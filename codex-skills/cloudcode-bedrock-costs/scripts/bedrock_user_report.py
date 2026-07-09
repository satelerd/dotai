#!/usr/bin/env python3
"""
Local-only Cloud Code cost analyzer.

Reads Claude local transcripts under ~/.claude/projects (or custom --claude-root),
estimates Bedrock cost from token usage, and produces JSON/CSV/HTML/PDF outputs.
No AWS CLI calls.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import os
import re
import subprocess
from collections import Counter, defaultdict
from dataclasses import dataclass
from datetime import UTC, date, datetime, timedelta
from html import escape
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Tuple


DEFAULT_RATES_PER_MTOK = {
    "haiku": {"input": 1.0, "output": 5.0},
    "sonnet": {"input": 3.0, "output": 15.0},
    "opus": {"input": 15.0, "output": 75.0},
    "other": {"input": 3.0, "output": 15.0},
}

CACHE_WRITE_MULTIPLIER = 1.25
CACHE_READ_MULTIPLIER = 0.10

MODEL_ALIAS_RULES = [
    ("claude-haiku", "haiku"),
    ("claude-sonnet", "sonnet"),
    ("claude-opus", "opus"),
]

COLORS = {
    "cost": "#f39c4a",
    "input": "#3b82f6",
    "output": "#8b5cf6",
    "cache_write": "#ef4444",
    "cache_read": "#22c55e",
    "haiku": "#22c55e",
    "sonnet": "#8b5cf6",
    "opus": "#f59e0b",
    "other": "#94a3b8",
}

PLAN_BENCHMARKS = {
    "cloud_code_pro_20": {
        "label": "Cloud Code Pro ($20)",
        "vendor": "Anthropic",
        "fiveHourPromptRange": [10, 40],
        "weeklyHoursRange": [40, 80],
        "source": "https://support.anthropic.com/es/articles/8324991-about-claude-pro-plans",
    },
    "codex_plus_20": {
        "label": "Codex Plus ($20)",
        "vendor": "OpenAI",
        "fiveHourPromptRange": [30, 150],
        "weeklyHoursRange": None,
        "source": "https://help.openai.com/en/articles/11750701-what-are-the-rate-limits-for-codex",
    },
}


@dataclass
class UsageRecord:
    day: str
    timestamp: str
    session_id: str
    message_id: str
    model: str
    model_family: str
    cwd: str
    workspace: str
    project_bucket: str
    input_tokens: int
    output_tokens: int
    cache_write_tokens: int
    cache_read_tokens: int
    invocations: int
    estimated_cost_usd: float
    estimated_no_cache_cost_usd: float


# ---------- Utility ----------


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Local Cloud Code Bedrock cost analysis from local transcript files.")
    p.add_argument("--claude-root", default="~/.claude", help="Root Claude folder that contains projects/. Default: ~/.claude")
    p.add_argument(
        "--output-dir",
        default="./data/target/local_cloudcode_costs",
        help="Output directory for JSON/CSV/HTML/PDF. Default: ./data/target/local_cloudcode_costs",
    )
    p.add_argument("--from-date", default=None, help="Inclusive start date YYYY-MM-DD")
    p.add_argument("--to-date", default=None, help="Exclusive end date YYYY-MM-DD")
    p.add_argument(
        "--workspace-filter",
        default=None,
        help="Optional case-insensitive substring filter over cwd/workspace (example: core-admin).",
    )
    p.add_argument(
        "--include-non-bedrock",
        action="store_true",
        help="Include messages that do not have Bedrock markers (msg_bdrk_/toolu_bdrk_).",
    )
    p.add_argument(
        "--top-n",
        type=int,
        default=10,
        help="Top N rows for model/workspace/session tables. Default: 10",
    )
    p.add_argument(
        "--chrome-path",
        default=None,
        help="Optional explicit Chrome/Chromium binary path for PDF rendering.",
    )
    return p.parse_args()


def parse_iso_day(ts: str) -> Optional[str]:
    if not ts:
        return None
    raw = ts.replace("Z", "+00:00")
    try:
        return datetime.fromisoformat(raw).date().isoformat()
    except ValueError:
        return None


def parse_iso_datetime(ts: str) -> Optional[datetime]:
    if not ts:
        return None
    raw = ts.replace("Z", "+00:00")
    try:
        dt = datetime.fromisoformat(raw)
    except ValueError:
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=UTC)
    return dt.astimezone(UTC)


def parse_day_str(d: Optional[str]) -> Optional[date]:
    if not d:
        return None
    return date.fromisoformat(d)


def model_family(model: str) -> str:
    m = (model or "").lower()
    for needle, family in MODEL_ALIAS_RULES:
        if needle in m:
            return family
    return "other"


def is_bedrock_message(message_id: str, model: str, content: Any) -> bool:
    mid = (message_id or "").lower()
    mdl = (model or "").lower()
    if mid.startswith("msg_bdrk_"):
        return True
    if "bedrock" in mdl:
        return True
    if isinstance(content, list):
        for chunk in content:
            if isinstance(chunk, dict):
                cid = str(chunk.get("id") or "").lower()
                if cid.startswith("toolu_bdrk_"):
                    return True
    return False


def estimate_cost(
    family: str,
    input_tokens: int,
    output_tokens: int,
    cache_write_tokens: int,
    cache_read_tokens: int,
) -> Tuple[float, float]:
    rates = DEFAULT_RATES_PER_MTOK.get(family, DEFAULT_RATES_PER_MTOK["other"])
    in_rate = rates["input"]
    out_rate = rates["output"]

    with_cache = (
        (input_tokens * in_rate)
        + (output_tokens * out_rate)
        + (cache_write_tokens * in_rate * CACHE_WRITE_MULTIPLIER)
        + (cache_read_tokens * in_rate * CACHE_READ_MULTIPLIER)
    ) / 1_000_000.0

    no_cache = (
        ((input_tokens + cache_write_tokens + cache_read_tokens) * in_rate)
        + (output_tokens * out_rate)
    ) / 1_000_000.0

    return with_cache, no_cache


def clean_workspace(cwd: str, fallback_bucket: str) -> str:
    if cwd:
        cwd = cwd.rstrip("/")
        name = Path(cwd).name.strip()
        if name:
            return name
    return fallback_bucket or "unknown"


def discover_files(projects_root: Path) -> List[Path]:
    if not projects_root.exists():
        return []
    return sorted(projects_root.rglob("*.jsonl"))


# ---------- Parsing ----------


def parse_records(
    claude_root: Path,
    from_date: Optional[date],
    to_date: Optional[date],
    include_non_bedrock: bool,
    workspace_filter: Optional[str],
) -> Tuple[List[UsageRecord], Dict[str, Any]]:
    projects_root = claude_root / "projects"
    files = discover_files(projects_root)

    records: List[UsageRecord] = []
    seen_keys: set[str] = set()

    stats = {
        "files_scanned": len(files),
        "raw_usage_rows": 0,
        "kept_unique_rows": 0,
        "duplicate_rows_dropped": 0,
        "invalid_rows": 0,
        "filtered_by_date": 0,
        "filtered_by_workspace": 0,
        "filtered_non_bedrock": 0,
    }

    ws_filter = (workspace_filter or "").lower().strip()

    for fp in files:
        project_bucket = fp.relative_to(projects_root).parts[0] if fp.exists() else "unknown"
        try:
            with fp.open("r", encoding="utf-8", errors="ignore") as f:
                for line in f:
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        obj = json.loads(line)
                    except Exception:
                        stats["invalid_rows"] += 1
                        continue

                    if obj.get("type") != "assistant":
                        continue

                    msg = obj.get("message")
                    if not isinstance(msg, dict):
                        continue

                    usage = msg.get("usage")
                    if not isinstance(usage, dict):
                        continue

                    stats["raw_usage_rows"] += 1

                    session_id = str(obj.get("sessionId") or "")
                    msg_id = str(msg.get("id") or obj.get("requestId") or obj.get("uuid") or "")
                    dedupe_key = f"{session_id}::{msg_id}"
                    if dedupe_key in seen_keys:
                        stats["duplicate_rows_dropped"] += 1
                        continue
                    seen_keys.add(dedupe_key)

                    ts = str(obj.get("timestamp") or "")
                    day = parse_iso_day(ts)
                    if not day:
                        stats["invalid_rows"] += 1
                        continue

                    day_obj = date.fromisoformat(day)
                    if from_date and day_obj < from_date:
                        stats["filtered_by_date"] += 1
                        continue
                    if to_date and day_obj >= to_date:
                        stats["filtered_by_date"] += 1
                        continue

                    model = str(msg.get("model") or "unknown")
                    content = msg.get("content")
                    if not include_non_bedrock and not is_bedrock_message(msg_id, model, content):
                        stats["filtered_non_bedrock"] += 1
                        continue

                    cwd = str(obj.get("cwd") or "")
                    workspace = clean_workspace(cwd, project_bucket)

                    if ws_filter:
                        target = f"{cwd} {workspace} {project_bucket}".lower()
                        if ws_filter not in target:
                            stats["filtered_by_workspace"] += 1
                            continue

                    in_tok = int(usage.get("input_tokens") or 0)
                    out_tok = int(usage.get("output_tokens") or 0)
                    cwr_tok = int(usage.get("cache_creation_input_tokens") or 0)
                    crd_tok = int(usage.get("cache_read_input_tokens") or 0)

                    family = model_family(model)
                    est_cost, est_no_cache = estimate_cost(family, in_tok, out_tok, cwr_tok, crd_tok)

                    records.append(
                        UsageRecord(
                            day=day,
                            timestamp=ts,
                            session_id=session_id,
                            message_id=msg_id,
                            model=model,
                            model_family=family,
                            cwd=cwd,
                            workspace=workspace,
                            project_bucket=project_bucket,
                            input_tokens=in_tok,
                            output_tokens=out_tok,
                            cache_write_tokens=cwr_tok,
                            cache_read_tokens=crd_tok,
                            invocations=1,
                            estimated_cost_usd=est_cost,
                            estimated_no_cache_cost_usd=est_no_cache,
                        )
                    )
                    stats["kept_unique_rows"] += 1
        except Exception:
            stats["invalid_rows"] += 1

    return records, stats


# ---------- Aggregation ----------


def _rolling_window_counts(event_times: List[datetime], window: timedelta) -> List[int]:
    counts: List[int] = []
    left = 0
    for right, ts in enumerate(event_times):
        while left <= right and ts - event_times[left] > window:
            left += 1
        counts.append(right - left + 1)
    return counts


def _exceedance_stats(counts: List[int], threshold: int) -> Dict[str, int]:
    points = 0
    periods = 0
    in_period = False
    for c in counts:
        if c > threshold:
            points += 1
            if not in_period:
                periods += 1
                in_period = True
        else:
            in_period = False
    return {"points": points, "periods": periods}


def _format_week_key(dt: datetime) -> str:
    iso = dt.isocalendar()
    return f"{iso.year}-W{iso.week:02d}"


def _build_subscription_pressure(
    records: List[UsageRecord], event_times: List[datetime], event_costs: List[float]
) -> Dict[str, Any]:
    if not event_times:
        return {
            "rolling5h": {"maxInvocations": 0, "labels": [], "counts": []},
            "fiveHourBuckets": [],
            "weekly": [],
            "planAnalysis": {},
        }

    window = timedelta(hours=5)
    rolling_counts = _rolling_window_counts(event_times, window)
    max_rolling = max(rolling_counts) if rolling_counts else 0
    rolling_labels = [t.strftime("%m-%d %H:%M") for t in event_times]

    start = event_times[0]
    buckets: Dict[int, Dict[str, Any]] = defaultdict(lambda: {"invocations": 0, "cost": 0.0})
    for ts, c in zip(event_times, event_costs):
        idx = int((ts - start).total_seconds() // (5 * 3600))
        buckets[idx]["invocations"] += 1
        buckets[idx]["cost"] += c
    bucket_rows = []
    for idx in sorted(buckets.keys()):
        b_start = start + timedelta(hours=5 * idx)
        b_end = b_start + timedelta(hours=5)
        bucket_rows.append(
            {
                "start": b_start.isoformat().replace("+00:00", "Z"),
                "end": b_end.isoformat().replace("+00:00", "Z"),
                "label": b_start.strftime("%m-%d %Hh"),
                "invocations": int(buckets[idx]["invocations"]),
                "cost": round(float(buckets[idx]["cost"]), 8),
            }
        )

    week_data: Dict[str, Dict[str, Any]] = {}
    for ts, c in zip(event_times, event_costs):
        wk = _format_week_key(ts)
        if wk not in week_data:
            week_data[wk] = {"week": wk, "invocations": 0, "cost": 0.0}
        week_data[wk]["invocations"] += 1
        week_data[wk]["cost"] += c
    weekly = []
    for wk in sorted(week_data.keys()):
        item = week_data[wk]
        inv = int(item["invocations"])
        weekly.append(
            {
                "week": wk,
                "invocations": inv,
                "cost": round(float(item["cost"]), 8),
                "hoursNeededAt10": round(inv / 10.0 * 5.0, 2),
                "hoursNeededAt40": round(inv / 40.0 * 5.0, 2),
                "hoursNeededAt30": round(inv / 30.0 * 5.0, 2),
                "hoursNeededAt150": round(inv / 150.0 * 5.0, 2),
            }
        )

    plan_analysis: Dict[str, Any] = {}
    for plan_key, cfg in PLAN_BENCHMARKS.items():
        low, high = cfg["fiveHourPromptRange"]
        low_ex = _exceedance_stats(rolling_counts, low)
        high_ex = _exceedance_stats(rolling_counts, high)

        row: Dict[str, Any] = {
            "label": cfg["label"],
            "vendor": cfg["vendor"],
            "fiveHourPromptRange": cfg["fiveHourPromptRange"],
            "source": cfg["source"],
            "maxRolling5hInvocations": max_rolling,
            "exceedLowThreshold": low_ex,
            "exceedHighThreshold": high_ex,
        }

        if cfg["weeklyHoursRange"]:
            w_low, w_high = cfg["weeklyHoursRange"]
            weeks_above_low = 0
            weeks_above_high = 0
            for w in weekly:
                hours_optimistic = w["invocations"] / float(high) * 5.0
                if hours_optimistic > w_low:
                    weeks_above_low += 1
                if hours_optimistic > w_high:
                    weeks_above_high += 1
            row["weeklyHoursRange"] = cfg["weeklyHoursRange"]
            row["weeksAboveWeeklyLow"] = weeks_above_low
            row["weeksAboveWeeklyHigh"] = weeks_above_high
        else:
            proxy_weekly_limit = int((24 / 5) * 7 * low)
            weeks_above_proxy = sum(1 for w in weekly if w["invocations"] > proxy_weekly_limit)
            row["weeklyHoursRange"] = None
            row["weeklyCapKnown"] = False
            row["proxyWeeklyInvocationsAtLow5h"] = proxy_weekly_limit
            row["weeksAboveProxyWeeklyInvocations"] = weeks_above_proxy

        plan_analysis[plan_key] = row

    return {
        "rolling5h": {
            "maxInvocations": max_rolling,
            "labels": rolling_labels,
            "counts": rolling_counts,
        },
        "fiveHourBuckets": bucket_rows,
        "weekly": weekly,
        "planAnalysis": plan_analysis,
    }


def summarize(records: List[UsageRecord], top_n: int) -> Dict[str, Any]:
    if not records:
        return {
            "window": {"start": None, "endExclusive": None, "days": 0},
            "totals": {},
            "daily": [],
            "models": [],
            "workspaces": [],
            "sessions": [],
            "subscriptionPressure": {
                "rolling5h": {"maxInvocations": 0, "labels": [], "counts": []},
                "fiveHourBuckets": [],
                "weekly": [],
                "planAnalysis": {},
            },
        }

    records = sorted(records, key=lambda r: (r.day, r.timestamp, r.session_id, r.message_id))
    days = sorted({r.day for r in records})
    event_times = [
        parse_iso_datetime(r.timestamp) or datetime.fromisoformat(f"{r.day}T00:00:00+00:00") for r in records
    ]
    event_costs = [float(r.estimated_cost_usd) for r in records]

    total_cost = sum(r.estimated_cost_usd for r in records)
    total_no_cache = sum(r.estimated_no_cache_cost_usd for r in records)
    total_in = sum(r.input_tokens for r in records)
    total_out = sum(r.output_tokens for r in records)
    total_cw = sum(r.cache_write_tokens for r in records)
    total_cr = sum(r.cache_read_tokens for r in records)
    total_inv = sum(r.invocations for r in records)

    by_day: Dict[str, Dict[str, float]] = defaultdict(lambda: defaultdict(float))
    by_model: Dict[str, Dict[str, float]] = defaultdict(lambda: defaultdict(float))
    by_workspace: Dict[str, Dict[str, float]] = defaultdict(lambda: defaultdict(float))
    by_session: Dict[str, Dict[str, Any]] = {}
    day_model_cost: Dict[str, Dict[str, float]] = defaultdict(lambda: defaultdict(float))

    for r in records:
        d = by_day[r.day]
        d["cost"] += r.estimated_cost_usd
        d["cost_no_cache"] += r.estimated_no_cache_cost_usd
        d["input_tokens"] += r.input_tokens
        d["output_tokens"] += r.output_tokens
        d["cache_write_tokens"] += r.cache_write_tokens
        d["cache_read_tokens"] += r.cache_read_tokens
        d["invocations"] += r.invocations

        m = by_model[r.model]
        m["cost"] += r.estimated_cost_usd
        m["invocations"] += r.invocations
        m["input_tokens"] += r.input_tokens
        m["output_tokens"] += r.output_tokens
        m["cache_write_tokens"] += r.cache_write_tokens
        m["cache_read_tokens"] += r.cache_read_tokens

        w = by_workspace[r.workspace]
        w["cost"] += r.estimated_cost_usd
        w["invocations"] += r.invocations
        w["input_tokens"] += r.input_tokens + r.cache_write_tokens + r.cache_read_tokens
        w["output_tokens"] += r.output_tokens

        sid = r.session_id or "unknown"
        if sid not in by_session:
            by_session[sid] = {
                "sessionId": sid,
                "workspace": r.workspace,
                "projectBucket": r.project_bucket,
                "firstDay": r.day,
                "lastDay": r.day,
                "models": Counter(),
                "cost": 0.0,
                "invocations": 0,
                "tokens": 0,
            }
        s = by_session[sid]
        s["cost"] += r.estimated_cost_usd
        s["invocations"] += r.invocations
        s["tokens"] += (r.input_tokens + r.output_tokens + r.cache_write_tokens + r.cache_read_tokens)
        s["firstDay"] = min(s["firstDay"], r.day)
        s["lastDay"] = max(s["lastDay"], r.day)
        s["models"][r.model] += r.estimated_cost_usd

        day_model_cost[r.day][r.model] += r.estimated_cost_usd

    daily = []
    for d in days:
        row = by_day[d]
        daily.append(
            {
                "day": d,
                "cost": round(row["cost"], 8),
                "costNoCache": round(row["cost_no_cache"], 8),
                "cacheSavings": round(row["cost_no_cache"] - row["cost"], 8),
                "inputTokens": int(row["input_tokens"]),
                "outputTokens": int(row["output_tokens"]),
                "cacheWriteTokens": int(row["cache_write_tokens"]),
                "cacheReadTokens": int(row["cache_read_tokens"]),
                "invocations": int(row["invocations"]),
            }
        )

    models = []
    for model, agg in by_model.items():
        family = model_family(model)
        models.append(
            {
                "model": model,
                "family": family,
                "cost": round(agg["cost"], 8),
                "invocations": int(agg["invocations"]),
                "inputTokens": int(agg["input_tokens"]),
                "outputTokens": int(agg["output_tokens"]),
                "cacheWriteTokens": int(agg["cache_write_tokens"]),
                "cacheReadTokens": int(agg["cache_read_tokens"]),
            }
        )
    models.sort(key=lambda x: x["cost"], reverse=True)

    workspaces = []
    for ws, agg in by_workspace.items():
        workspaces.append(
            {
                "workspace": ws,
                "cost": round(agg["cost"], 8),
                "invocations": int(agg["invocations"]),
                "inputLikeTokens": int(agg["input_tokens"]),
                "outputTokens": int(agg["output_tokens"]),
            }
        )
    workspaces.sort(key=lambda x: x["cost"], reverse=True)

    sessions = []
    for sid, agg in by_session.items():
        top_model = ""
        if agg["models"]:
            top_model = agg["models"].most_common(1)[0][0]
        sessions.append(
            {
                "sessionId": sid,
                "workspace": agg["workspace"],
                "projectBucket": agg["projectBucket"],
                "firstDay": agg["firstDay"],
                "lastDay": agg["lastDay"],
                "cost": round(agg["cost"], 8),
                "invocations": int(agg["invocations"]),
                "tokens": int(agg["tokens"]),
                "topModel": top_model,
            }
        )
    sessions.sort(key=lambda x: x["cost"], reverse=True)

    top_model_daily_names = [m["model"] for m in models[:4]]
    day_model_series = {m: [] for m in top_model_daily_names}
    day_model_other = []
    for d in days:
        total_day = 0.0
        top_sum = 0.0
        dm = day_model_cost[d]
        for model, cost in dm.items():
            total_day += cost
            if model in day_model_series:
                top_sum += cost
        for model in top_model_daily_names:
            day_model_series[model].append(round(dm.get(model, 0.0), 8))
        day_model_other.append(round(max(total_day - top_sum, 0.0), 8))

    subscription_pressure = _build_subscription_pressure(records, event_times, event_costs)

    return {
        "window": {
            "start": days[0],
            "endExclusive": (date.fromisoformat(days[-1]).isoformat()),
            "days": len(days),
        },
        "totals": {
            "estimatedCostUsd": round(total_cost, 8),
            "estimatedCostNoCacheUsd": round(total_no_cache, 8),
            "estimatedCacheSavingsUsd": round(total_no_cache - total_cost, 8),
            "invocations": int(total_inv),
            "inputTokens": int(total_in),
            "outputTokens": int(total_out),
            "cacheWriteTokens": int(total_cw),
            "cacheReadTokens": int(total_cr),
            "allTokens": int(total_in + total_out + total_cw + total_cr),
        },
        "daily": daily,
        "models": models,
        "workspaces": workspaces,
        "sessions": sessions[: max(top_n * 3, 30)],
        "dailyTopModelSeries": {
            "labels": days,
            "series": day_model_series,
            "other": day_model_other,
        },
        "subscriptionPressure": subscription_pressure,
    }


# ---------- SVG rendering ----------


def fmt_usd(v: float) -> str:
    return f"${v:,.2f}"


def fmt_int(v: int) -> str:
    return f"{v:,}"


def _nice_tick(v: float) -> float:
    if v <= 0:
        return 1.0
    exp = math.floor(math.log10(v))
    f = v / (10 ** exp)
    if f < 1.5:
        nf = 1.0
    elif f < 3.0:
        nf = 2.0
    elif f < 7.0:
        nf = 5.0
    else:
        nf = 10.0
    return nf * (10 ** exp)


def svg_line_chart(
    labels: List[str],
    series: List[Tuple[str, List[float], str]],
    width: int = 1120,
    height: int = 360,
    y_prefix: str = "$",
    y_decimals: int = 0,
    area_for_first: bool = False,
) -> str:
    margin_left, margin_right, margin_top, margin_bottom = 72, 20, 20, 44
    plot_w = width - margin_left - margin_right
    plot_h = height - margin_top - margin_bottom

    if not labels:
        return '<svg viewBox="0 0 1120 360" width="100%" height="360"><text x="16" y="24" fill="#64748b">No data</text></svg>'

    n = len(labels)
    max_y = 0.0
    for _, vals, _ in series:
        if vals:
            max_y = max(max_y, max(vals))
    max_y = max(max_y, 1.0)
    y_top = _nice_tick(max_y * 1.1)

    def x_of(i: int) -> float:
        if n <= 1:
            return margin_left + plot_w / 2
        return margin_left + (plot_w * i / (n - 1))

    def y_of(v: float) -> float:
        return margin_top + plot_h - (v / y_top) * plot_h

    parts = [f'<svg viewBox="0 0 {width} {height}" width="100%" height="{height}" role="img" aria-label="line-chart">']

    for i in range(6):
        yv = y_top * i / 5
        y = y_of(yv)
        parts.append(f'<line x1="{margin_left}" y1="{y:.2f}" x2="{width - margin_right}" y2="{y:.2f}" stroke="#e2e8f0" stroke-width="1"/>')
        ytxt = f"{y_prefix}{yv:,.{y_decimals}f}"
        parts.append(f'<text x="{margin_left - 8}" y="{y + 4:.2f}" text-anchor="end" font-size="11" fill="#64748b">{escape(ytxt)}</text>')

    tick_count = min(8, n)
    step = max(1, math.ceil(n / tick_count))
    for i in range(0, n, step):
        x = x_of(i)
        parts.append(f'<line x1="{x:.2f}" y1="{margin_top}" x2="{x:.2f}" y2="{height - margin_bottom}" stroke="#f1f5f9" stroke-width="1"/>')
        lbl = labels[i]
        parts.append(f'<text x="{x:.2f}" y="{height - 14}" text-anchor="middle" font-size="10" fill="#64748b">{escape(lbl)}</text>')

    for idx, (name, vals, color) in enumerate(series):
        if not vals:
            continue
        pts = " ".join(f"{x_of(i):.2f},{y_of(v):.2f}" for i, v in enumerate(vals))
        if idx == 0 and area_for_first:
            area_pts = f"{x_of(0):.2f},{y_of(0):.2f} " + pts + f" {x_of(n-1):.2f},{y_of(0):.2f}"
            parts.append(f'<polygon points="{area_pts}" fill="{color}" fill-opacity="0.14"/>')
        parts.append(f'<polyline points="{pts}" fill="none" stroke="{color}" stroke-width="2.4"/>')

    legend_x = margin_left
    legend_y = 14
    for name, _, color in series:
        parts.append(f'<rect x="{legend_x}" y="{legend_y - 8}" width="10" height="10" rx="2" fill="{color}"/>')
        parts.append(f'<text x="{legend_x + 14}" y="{legend_y}" font-size="11" fill="#334155">{escape(name)}</text>')
        legend_x += 14 + len(name) * 7 + 16

    parts.append('</svg>')
    return "".join(parts)


def svg_stacked_bar_chart(
    labels: List[str],
    series: List[Tuple[str, List[float], str]],
    width: int = 1120,
    height: int = 360,
    y_prefix: str = "$",
    y_decimals: int = 0,
) -> str:
    margin_left, margin_right, margin_top, margin_bottom = 72, 20, 20, 64
    plot_w = width - margin_left - margin_right
    plot_h = height - margin_top - margin_bottom

    if not labels:
        return '<svg viewBox="0 0 1120 360" width="100%" height="360"><text x="16" y="24" fill="#64748b">No data</text></svg>'

    n = len(labels)
    totals = [0.0] * n
    for _, vals, _ in series:
        for i, v in enumerate(vals[:n]):
            totals[i] += v
    max_y = max(max(totals), 1.0)
    y_top = _nice_tick(max_y * 1.15)

    bar_w = max(4.0, min(40.0, plot_w / max(n * 1.6, 1)))
    gap = bar_w * 0.6
    total_cluster_w = n * bar_w + (n - 1) * gap
    x_start = margin_left + max((plot_w - total_cluster_w) / 2, 0)

    def y_of(v: float) -> float:
        return margin_top + plot_h - (v / y_top) * plot_h

    parts = [f'<svg viewBox="0 0 {width} {height}" width="100%" height="{height}" role="img" aria-label="stacked-bar-chart">']

    for i in range(6):
        yv = y_top * i / 5
        y = y_of(yv)
        parts.append(f'<line x1="{margin_left}" y1="{y:.2f}" x2="{width - margin_right}" y2="{y:.2f}" stroke="#e2e8f0" stroke-width="1"/>')
        ytxt = f"{y_prefix}{yv:,.{y_decimals}f}"
        parts.append(f'<text x="{margin_left - 8}" y="{y + 4:.2f}" text-anchor="end" font-size="11" fill="#64748b">{escape(ytxt)}</text>')

    for i in range(n):
        x = x_start + i * (bar_w + gap)
        base = 0.0
        for _, vals, color in series:
            v = vals[i] if i < len(vals) else 0.0
            if v <= 0:
                continue
            y1 = y_of(base)
            y2 = y_of(base + v)
            h = y1 - y2
            parts.append(f'<rect x="{x:.2f}" y="{y2:.2f}" width="{bar_w:.2f}" height="{h:.2f}" fill="{color}"/>')
            base += v

    tick_count = min(10, n)
    step = max(1, math.ceil(n / tick_count))
    for i in range(0, n, step):
        x = x_start + i * (bar_w + gap) + bar_w / 2
        parts.append(f'<text x="{x:.2f}" y="{height - 22}" text-anchor="middle" font-size="10" fill="#64748b">{escape(labels[i])}</text>')

    legend_x = margin_left
    legend_y = height - 6
    for name, _, color in series:
        parts.append(f'<rect x="{legend_x}" y="{legend_y - 10}" width="10" height="10" rx="2" fill="{color}"/>')
        parts.append(f'<text x="{legend_x + 14}" y="{legend_y - 1}" font-size="11" fill="#334155">{escape(name)}</text>')
        legend_x += 14 + len(name) * 7 + 18

    parts.append("</svg>")
    return "".join(parts)


# ---------- Output ----------


def write_csv(path: Path, rows: List[Dict[str, Any]], fields: List[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        for r in rows:
            w.writerow({k: r.get(k) for k in fields})


def build_html_report(summary: Dict[str, Any], metadata: Dict[str, Any], output_html: Path, top_n: int) -> None:
    totals = summary["totals"]
    daily = summary["daily"]
    models = summary["models"]
    workspaces = summary["workspaces"]
    sessions = summary["sessions"]
    subscription = summary.get("subscriptionPressure") or {}

    labels = [d["day"] for d in daily]
    daily_cost = [float(d["cost"]) for d in daily]

    def _downsample(lbls: List[str], values_list: List[List[float]], max_points: int = 72) -> Tuple[List[str], List[List[float]]]:
        if len(lbls) <= max_points:
            return lbls, values_list
        step = int(math.ceil(len(lbls) / max_points))
        idxs = list(range(0, len(lbls), step))
        return [lbls[i] for i in idxs], [[vals[i] for i in idxs] for vals in values_list]

    line_daily_cost = svg_line_chart(
        labels,
        [("Estimated Cost (USD)", daily_cost, COLORS["cost"])],
        area_for_first=True,
        y_prefix="$",
        y_decimals=0,
    )

    line_tokens = svg_line_chart(
        labels,
        [
            ("Input", [float(d["inputTokens"]) for d in daily], COLORS["input"]),
            ("Output", [float(d["outputTokens"]) for d in daily], COLORS["output"]),
            ("Cache Read", [float(d["cacheReadTokens"]) for d in daily], COLORS["cache_read"]),
            ("Cache Write", [float(d["cacheWriteTokens"]) for d in daily], COLORS["cache_write"]),
        ],
        area_for_first=False,
        y_prefix="",
        y_decimals=0,
    )

    model_top = models[:top_n]
    model_labels = [m["model"].replace("claude-", "")[:22] for m in model_top]
    model_series = [("Cost", [float(m["cost"]) for m in model_top], COLORS["cost"])]
    model_bars = svg_stacked_bar_chart(model_labels, model_series, y_prefix="$", y_decimals=0)

    ws_top = workspaces[:top_n]
    ws_labels = [w["workspace"][:22] for w in ws_top]
    ws_series = [("Cost", [float(w["cost"]) for w in ws_top], "#0ea5e9")]
    ws_bars = svg_stacked_bar_chart(ws_labels, ws_series, y_prefix="$", y_decimals=0)

    dm = summary.get("dailyTopModelSeries") or {}
    dm_labels = dm.get("labels") or []
    dm_series_data = dm.get("series") or {}
    dm_other = dm.get("other") or []
    dm_series = []
    color_by_family = {
        "haiku": COLORS["haiku"],
        "sonnet": COLORS["sonnet"],
        "opus": COLORS["opus"],
        "other": COLORS["other"],
    }
    for name, vals in dm_series_data.items():
        fam = model_family(name)
        dm_series.append((name.replace("claude-", "")[:24], [float(v) for v in vals], color_by_family[fam]))
    if dm_other:
        dm_series.append(("other", [float(v) for v in dm_other], COLORS["other"]))
    daily_model_bars = svg_stacked_bar_chart(dm_labels, dm_series, y_prefix="$", y_decimals=0)

    fiveh = subscription.get("fiveHourBuckets") or []
    fiveh_labels = [b["label"] for b in fiveh]
    fiveh_counts = [float(b["invocations"]) for b in fiveh]
    fiveh_labels_s, fiveh_values_s = _downsample(
        fiveh_labels,
        [
            fiveh_counts,
            [10.0] * len(fiveh_counts),
            [40.0] * len(fiveh_counts),
            [30.0] * len(fiveh_counts),
            [150.0] * len(fiveh_counts),
        ],
        max_points=84,
    )
    line_5h_limits = svg_line_chart(
        fiveh_labels_s,
        [
            ("Observed invocations / 5h", fiveh_values_s[0], "#0ea5e9"),
            ("Cloud Code Pro low (10)", fiveh_values_s[1], "#22c55e"),
            ("Cloud Code Pro high (40)", fiveh_values_s[2], "#16a34a"),
            ("Codex Plus low (30)", fiveh_values_s[3], "#f59e0b"),
            ("Codex Plus high (150)", fiveh_values_s[4], "#ef4444"),
        ],
        y_prefix="",
        y_decimals=0,
    )

    weekly = subscription.get("weekly") or []
    weekly_labels = [w["week"] for w in weekly]
    weekly_hours_cc = [float(w["hoursNeededAt40"]) for w in weekly]
    weekly_hours_codex = [float(w["hoursNeededAt150"]) for w in weekly]
    weekly_line = svg_line_chart(
        weekly_labels,
        [
            ("Cloud Code hours eq. (40 prompts/5h)", weekly_hours_cc, "#16a34a"),
            ("Codex hours eq. (150 prompts/5h)", weekly_hours_codex, "#f59e0b"),
            ("Cloud Code weekly low (40h)", [40.0] * len(weekly_labels), "#0ea5e9"),
            ("Cloud Code weekly high (80h)", [80.0] * len(weekly_labels), "#3b82f6"),
        ],
        y_prefix="",
        y_decimals=0,
    )

    # Executive insights
    top_model = model_top[0] if model_top else None
    top_workspace = ws_top[0] if ws_top else None
    cache_savings = totals.get("estimatedCacheSavingsUsd", 0.0)
    cache_pct = (cache_savings / totals["estimatedCostNoCacheUsd"] * 100) if totals.get("estimatedCostNoCacheUsd") else 0.0
    sub_plan = subscription.get("planAnalysis", {})
    cc_plan = sub_plan.get("cloud_code_pro_20") or {}
    codex_plan = sub_plan.get("codex_plus_20") or {}

    insights = [
        f"Costo estimado total local: {fmt_usd(totals['estimatedCostUsd'])} en {fmt_int(totals['invocations'])} invocaciones.",
        f"Tokens observados (input+output+cache): {fmt_int(totals['allTokens'])}.",
        f"Ahorro estimado por cache: {fmt_usd(cache_savings)} ({cache_pct:.1f}% vs escenario sin cache).",
    ]
    if top_model:
        share = (top_model["cost"] / totals["estimatedCostUsd"] * 100) if totals["estimatedCostUsd"] else 0.0
        insights.append(f"Modelo líder: {top_model['model']} con {fmt_usd(top_model['cost'])} ({share:.1f}% del costo).")
    if top_workspace:
        share = (top_workspace["cost"] / totals["estimatedCostUsd"] * 100) if totals["estimatedCostUsd"] else 0.0
        insights.append(f"Workspace líder: {top_workspace['workspace']} con {fmt_usd(top_workspace['cost'])} ({share:.1f}% del costo).")
    if cc_plan:
        insights.append(
            "Cloud Code Pro ($20): "
            + f"{cc_plan.get('exceedLowThreshold', {}).get('periods', 0)} periodos >10 prompts/5h, "
            + f"{cc_plan.get('exceedHighThreshold', {}).get('periods', 0)} periodos >40 prompts/5h."
        )
    if codex_plan:
        insights.append(
            "Codex Plus ($20): "
            + f"{codex_plan.get('exceedLowThreshold', {}).get('periods', 0)} periodos >30 prompts/5h, "
            + f"{codex_plan.get('exceedHighThreshold', {}).get('periods', 0)} periodos >150 prompts/5h."
        )

    sessions_rows = "".join(
        "<tr>"
        + f"<td>{escape(s['workspace'])}</td>"
        + f"<td>{escape(s['firstDay'])}</td>"
        + f"<td>{escape(s['lastDay'])}</td>"
        + f"<td>{fmt_usd(float(s['cost']))}</td>"
        + f"<td>{fmt_int(int(s['invocations']))}</td>"
        + f"<td>{fmt_int(int(s['tokens']))}</td>"
        + f"<td>{escape(s['topModel'] or '-')}</td>"
        + "</tr>"
        for s in sessions[:top_n]
    )

    model_rows = "".join(
        "<tr>"
        + f"<td>{escape(m['model'])}</td>"
        + f"<td>{escape(m['family'])}</td>"
        + f"<td>{fmt_usd(float(m['cost']))}</td>"
        + f"<td>{fmt_int(int(m['invocations']))}</td>"
        + f"<td>{fmt_int(int(m['inputTokens'] + m['outputTokens'] + m['cacheWriteTokens'] + m['cacheReadTokens']))}</td>"
        + "</tr>"
        for m in model_top
    )

    ws_rows = "".join(
        "<tr>"
        + f"<td>{escape(w['workspace'])}</td>"
        + f"<td>{fmt_usd(float(w['cost']))}</td>"
        + f"<td>{fmt_int(int(w['invocations']))}</td>"
        + f"<td>{fmt_int(int(w['inputLikeTokens'] + w['outputTokens']))}</td>"
        + "</tr>"
        for w in ws_top
    )

    plan_rows = []
    for plan_key in ["cloud_code_pro_20", "codex_plus_20"]:
        p = sub_plan.get(plan_key)
        if not p:
            continue
        weekly_note = "-"
        if p.get("weeklyHoursRange"):
            weekly_note = (
                f"weeks > {p['weeklyHoursRange'][0]}h: {p.get('weeksAboveWeeklyLow', 0)} | "
                f"weeks > {p['weeklyHoursRange'][1]}h: {p.get('weeksAboveWeeklyHigh', 0)}"
            )
        elif p.get("weeklyCapKnown") is False:
            weekly_note = (
                "OpenAI no publica cap semanal exacto. "
                + f"Proxy (>{p.get('proxyWeeklyInvocationsAtLow5h', 0)} inv/sem): {p.get('weeksAboveProxyWeeklyInvocations', 0)} semanas."
            )
        plan_rows.append(
            "<tr>"
            + f"<td>{escape(p.get('label', plan_key))}</td>"
            + f"<td>{escape(str(p.get('fiveHourPromptRange')))}</td>"
            + f"<td>{fmt_int(int(p.get('maxRolling5hInvocations', 0)))}</td>"
            + f"<td>{fmt_int(int((p.get('exceedLowThreshold') or {}).get('periods', 0)))}</td>"
            + f"<td>{fmt_int(int((p.get('exceedHighThreshold') or {}).get('periods', 0)))}</td>"
            + f"<td>{escape(weekly_note)}</td>"
            + "</tr>"
        )
    plan_rows_html = "".join(plan_rows)

    weekly_rows = "".join(
        "<tr>"
        + f"<td>{escape(w['week'])}</td>"
        + f"<td>{fmt_int(int(w['invocations']))}</td>"
        + f"<td>{fmt_usd(float(w['cost']))}</td>"
        + f"<td>{w['hoursNeededAt40']:.1f}h</td>"
        + f"<td>{w['hoursNeededAt150']:.1f}h</td>"
        + "</tr>"
        for w in weekly
    )

    html = f"""<!doctype html>
<html lang=\"en\">
<head>
<meta charset=\"utf-8\" />
<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\" />
<title>Local Bedrock Cost Intelligence</title>
<style>
  :root {{
    --bg: #f8fafc;
    --card: #ffffff;
    --text: #0f172a;
    --muted: #64748b;
    --border: #dbe4ee;
    --accent: #4f46e5;
  }}
  * {{ box-sizing: border-box; }}
  body {{ margin: 0; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; color: var(--text); background: var(--bg); }}
  .page {{ width: 297mm; min-height: 209mm; margin: 0 auto; padding: 10mm; page-break-after: always; }}
  .page:last-child {{ page-break-after: auto; }}
  .header {{ display: flex; justify-content: space-between; align-items: flex-start; gap: 20px; margin-bottom: 12px; }}
  h1 {{ margin: 0; font-size: 26px; color: #4338ca; }}
  h2 {{ margin: 0 0 6px; font-size: 20px; color: #4338ca; }}
  h3 {{ margin: 0 0 8px; font-size: 16px; color: #4338ca; }}
  .muted {{ color: var(--muted); font-size: 13px; }}
  .kpis {{ display: grid; grid-template-columns: repeat(5, 1fr); gap: 8px; margin: 10px 0 14px; }}
  .kpi {{ border: 1px solid var(--border); background: var(--card); border-radius: 10px; padding: 10px; }}
  .kpi .label {{ color: var(--muted); font-size: 11px; text-transform: uppercase; letter-spacing: .03em; }}
  .kpi .value {{ color: #4338ca; font-size: 28px; font-weight: 700; line-height: 1.15; margin-top: 4px; }}
  .card {{ border: 1px solid var(--border); background: var(--card); border-radius: 12px; padding: 10px; margin-bottom: 10px; }}
  .grid-2 {{ display: grid; grid-template-columns: 1fr 1fr; gap: 10px; }}
  .insights {{ margin: 0; padding-left: 18px; line-height: 1.5; font-size: 14px; }}
  table {{ width: 100%; border-collapse: collapse; font-size: 12px; }}
  th, td {{ border-top: 1px solid #e5e7eb; padding: 7px 6px; text-align: left; vertical-align: top; }}
  th {{ color: #334155; background: #f8fafc; font-weight: 700; }}
  .small {{ font-size: 11px; color: var(--muted); }}
  @media print {{
    body {{ background: #fff; }}
    .page {{ margin: 0; width: auto; min-height: auto; }}
  }}
</style>
</head>
<body>
  <section class=\"page\">
    <div class=\"header\">
      <div>
        <h1>Local Bedrock Cost Intelligence</h1>
        <div class=\"muted\">Device-level report from Claude local transcripts</div>
      </div>
      <div class=\"small\" style=\"text-align:right\">
        Generated: {escape(metadata['generatedAt'])}<br/>
        Source: {escape(metadata['claudeRoot'])}<br/>
        Window: {escape(metadata['window'])}<br/>
        Filter: {escape(metadata['workspaceFilter'])}
      </div>
    </div>

    <div class=\"kpis\">
      <div class=\"kpi\"><div class=\"label\">Estimated Cost</div><div class=\"value\">{fmt_usd(totals['estimatedCostUsd'])}</div></div>
      <div class=\"kpi\"><div class=\"label\">Invocations</div><div class=\"value\">{fmt_int(totals['invocations'])}</div></div>
      <div class=\"kpi\"><div class=\"label\">All Tokens</div><div class=\"value\">{fmt_int(totals['allTokens'])}</div></div>
      <div class=\"kpi\"><div class=\"label\">Cache Savings</div><div class=\"value\">{fmt_usd(totals['estimatedCacheSavingsUsd'])}</div></div>
      <div class=\"kpi\"><div class=\"label\">Days</div><div class=\"value\">{fmt_int(summary['window']['days'])}</div></div>
    </div>

    <div class=\"card\">
      <h3>Daily Estimated Spend (USD)</h3>
      {line_daily_cost}
    </div>

    <div class=\"card\">
      <h3>Daily Token Mix (Input / Output / Cache)</h3>
      {line_tokens}
    </div>
  </section>

  <section class=\"page\">
    <div class=\"grid-2\">
      <div class=\"card\">
        <h3>Top Models by Estimated Cost</h3>
        {model_bars}
      </div>
      <div class=\"card\">
        <h3>Top Workspaces by Estimated Cost</h3>
        {ws_bars}
      </div>
    </div>

    <div class=\"card\">
      <h3>Daily Cost Drivers by Model (Top models + Other)</h3>
      {daily_model_bars}
    </div>

    <div class=\"grid-2\">
      <div class=\"card\">
        <h3>Model Summary (Top {top_n})</h3>
        <table>
          <thead><tr><th>Model</th><th>Family</th><th>Estimated Cost</th><th>Invocations</th><th>Tokens</th></tr></thead>
          <tbody>{model_rows}</tbody>
        </table>
      </div>
      <div class=\"card\">
        <h3>Workspace Summary (Top {top_n})</h3>
        <table>
          <thead><tr><th>Workspace</th><th>Estimated Cost</th><th>Invocations</th><th>Tokens</th></tr></thead>
          <tbody>{ws_rows}</tbody>
        </table>
      </div>
    </div>
  </section>

  <section class=\"page\">
    <div class=\"card\">
      <h2>Plan Pressure (5h + Weekly)</h2>
      <p class=\"small\">
        Comparamos tu uso observado con referencias públicas de planes de USD 20. Es una correlación aproximada para gestión interna, no validación de billing.
      </p>
    </div>

    <div class=\"card\">
      <h3>Invocations in 5h Windows vs Plan Ranges</h3>
      {line_5h_limits}
    </div>

    <div class=\"card\">
      <h3>Weekly Equivalent Hours (Optimistic Throughput)</h3>
      {weekly_line}
    </div>

    <div class=\"card\">
      <h3>Plan Limit Correlation</h3>
      <table>
        <thead>
          <tr><th>Plan</th><th>5h range</th><th>Max rolling 5h</th><th>Periods &gt; low</th><th>Periods &gt; high</th><th>Weekly pressure</th></tr>
        </thead>
        <tbody>{plan_rows_html}</tbody>
      </table>
      <p class=\"small\">
        Sources:
        Cloud Code Pro: <a href=\"{escape(PLAN_BENCHMARKS['cloud_code_pro_20']['source'])}\">{escape(PLAN_BENCHMARKS['cloud_code_pro_20']['source'])}</a>.
        Codex Plus: <a href=\"{escape(PLAN_BENCHMARKS['codex_plus_20']['source'])}\">{escape(PLAN_BENCHMARKS['codex_plus_20']['source'])}</a>.
      </p>
    </div>

    <div class=\"card\">
      <h3>Weekly Breakdown</h3>
      <table>
        <thead>
          <tr><th>Week</th><th>Invocations</th><th>Estimated Cost</th><th>Cloud Code h eq (40/5h)</th><th>Codex h eq (150/5h)</th></tr>
        </thead>
        <tbody>{weekly_rows}</tbody>
      </table>
    </div>
  </section>

  <section class=\"page\">
    <div class=\"card\">
      <h2>Executive Insights</h2>
      <ul class=\"insights\">{''.join(f'<li>{escape(x)}</li>' for x in insights)}</ul>
      <p class=\"small\" style=\"margin-top:10px\">
        Metodología: costo estimado desde tokens locales (`input`, `output`, `cache write`, `cache read`) por invocación deduplicada.
        Pricing por familia de modelo (Haiku/Sonnet/Opus) y multiplicadores de cache (write=1.25x input, read=0.10x input).
        Este reporte es analítico y puede diferir de facturación exacta por ajustes de precio/región/impuestos.
      </p>
    </div>

    <div class=\"card\">
      <h3>Top Sessions by Estimated Cost</h3>
      <table>
        <thead>
          <tr>
            <th>Workspace</th><th>First Day</th><th>Last Day</th><th>Estimated Cost</th><th>Invocations</th><th>Tokens</th><th>Top Model</th>
          </tr>
        </thead>
        <tbody>{sessions_rows}</tbody>
      </table>
    </div>

    <div class=\"card\">
      <h3>Coverage and Data Quality</h3>
      <table>
        <tbody>
          <tr><th>Files scanned</th><td>{fmt_int(int(metadata['stats']['files_scanned']))}</td></tr>
          <tr><th>Raw usage rows</th><td>{fmt_int(int(metadata['stats']['raw_usage_rows']))}</td></tr>
          <tr><th>Duplicates dropped</th><td>{fmt_int(int(metadata['stats']['duplicate_rows_dropped']))}</td></tr>
          <tr><th>Kept unique rows</th><td>{fmt_int(int(metadata['stats']['kept_unique_rows']))}</td></tr>
          <tr><th>Filtered non-bedrock</th><td>{fmt_int(int(metadata['stats']['filtered_non_bedrock']))}</td></tr>
          <tr><th>Filtered by date</th><td>{fmt_int(int(metadata['stats']['filtered_by_date']))}</td></tr>
          <tr><th>Filtered by workspace</th><td>{fmt_int(int(metadata['stats']['filtered_by_workspace']))}</td></tr>
          <tr><th>Invalid rows</th><td>{fmt_int(int(metadata['stats']['invalid_rows']))}</td></tr>
        </tbody>
      </table>
    </div>
  </section>
</body>
</html>
"""

    output_html.parent.mkdir(parents=True, exist_ok=True)
    output_html.write_text(html, encoding="utf-8")


def detect_chrome(explicit: Optional[str]) -> Optional[str]:
    candidates = []
    if explicit:
        candidates.append(explicit)
    candidates.extend(
        [
            "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
            "/Applications/Chromium.app/Contents/MacOS/Chromium",
            "google-chrome",
            "chromium",
            "chromium-browser",
        ]
    )

    for c in candidates:
        if os.path.isabs(c):
            if Path(c).exists():
                return c
        else:
            p = shutil_which(c)
            if p:
                return p
    return None


def shutil_which(cmd: str) -> Optional[str]:
    paths = os.environ.get("PATH", "").split(os.pathsep)
    for p in paths:
        candidate = Path(p) / cmd
        if candidate.exists() and os.access(candidate, os.X_OK):
            return str(candidate)
    return None


def render_pdf(html_path: Path, pdf_path: Path, chrome_path: Optional[str]) -> Tuple[bool, str]:
    chrome = detect_chrome(chrome_path)
    if not chrome:
        return False, "Chrome/Chromium not found. HTML generated, PDF skipped."

    pdf_path.parent.mkdir(parents=True, exist_ok=True)
    uri = html_path.resolve().as_uri()

    for headless_flag in ["--headless=new", "--headless"]:
        cmd = [
            chrome,
            headless_flag,
            "--disable-gpu",
            "--no-sandbox",
            "--run-all-compositor-stages-before-draw",
            "--virtual-time-budget=12000",
            "--print-to-pdf-no-header",
            f"--print-to-pdf={str(pdf_path)}",
            uri,
        ]
        try:
            p = subprocess.run(cmd, text=True, capture_output=True)
            if p.returncode == 0 and pdf_path.exists() and pdf_path.stat().st_size > 1024:
                return True, f"PDF rendered with {chrome}"
        except Exception:
            pass

    return False, "Failed to render PDF with Chrome/Chromium."


def write_outputs(
    output_dir: Path,
    summary: Dict[str, Any],
    metadata: Dict[str, Any],
    top_n: int,
    chrome_path: Optional[str],
) -> Dict[str, str]:
    output_dir.mkdir(parents=True, exist_ok=True)

    json_path = output_dir / "local_bedrock_cost_intelligence.json"
    csv_daily = output_dir / "local_daily.csv"
    csv_models = output_dir / "local_models.csv"
    csv_workspaces = output_dir / "local_workspaces.csv"
    csv_sessions = output_dir / "local_sessions.csv"
    csv_fiveh = output_dir / "local_five_hour_windows.csv"
    csv_weekly = output_dir / "local_weekly_pressure.csv"
    html_path = output_dir / "local_bedrock_cost_report.html"
    pdf_path = output_dir / "local_bedrock_cost_report.pdf"

    payload = {
        "meta": metadata,
        "summary": summary,
    }
    json_path.write_text(json.dumps(payload, indent=2), encoding="utf-8")

    write_csv(
        csv_daily,
        summary.get("daily", []),
        [
            "day",
            "cost",
            "costNoCache",
            "cacheSavings",
            "inputTokens",
            "outputTokens",
            "cacheWriteTokens",
            "cacheReadTokens",
            "invocations",
        ],
    )
    write_csv(
        csv_models,
        summary.get("models", []),
        [
            "model",
            "family",
            "cost",
            "invocations",
            "inputTokens",
            "outputTokens",
            "cacheWriteTokens",
            "cacheReadTokens",
        ],
    )
    write_csv(
        csv_workspaces,
        summary.get("workspaces", []),
        ["workspace", "cost", "invocations", "inputLikeTokens", "outputTokens"],
    )
    write_csv(
        csv_sessions,
        summary.get("sessions", []),
        ["sessionId", "workspace", "projectBucket", "firstDay", "lastDay", "cost", "invocations", "tokens", "topModel"],
    )
    write_csv(
        csv_fiveh,
        (summary.get("subscriptionPressure") or {}).get("fiveHourBuckets", []),
        ["start", "end", "label", "invocations", "cost"],
    )
    write_csv(
        csv_weekly,
        (summary.get("subscriptionPressure") or {}).get("weekly", []),
        ["week", "invocations", "cost", "hoursNeededAt10", "hoursNeededAt40", "hoursNeededAt30", "hoursNeededAt150"],
    )

    build_html_report(summary, metadata, html_path, top_n=top_n)
    ok, msg = render_pdf(html_path, pdf_path, chrome_path=chrome_path)

    out = {
        "json": str(json_path),
        "csv_daily": str(csv_daily),
        "csv_models": str(csv_models),
        "csv_workspaces": str(csv_workspaces),
        "csv_sessions": str(csv_sessions),
        "csv_fiveh": str(csv_fiveh),
        "csv_weekly": str(csv_weekly),
        "html": str(html_path),
        "pdf": str(pdf_path) if ok else "",
        "pdf_status": msg,
    }
    return out


def main() -> None:
    args = parse_args()
    claude_root = Path(args.claude_root).expanduser().resolve()
    output_dir = Path(args.output_dir).expanduser().resolve()

    from_date = parse_day_str(args.from_date)
    to_date = parse_day_str(args.to_date)

    records, parse_stats = parse_records(
        claude_root=claude_root,
        from_date=from_date,
        to_date=to_date,
        include_non_bedrock=args.include_non_bedrock,
        workspace_filter=args.workspace_filter,
    )

    summary = summarize(records, top_n=args.top_n)

    win = summary.get("window", {})
    window_text = f"{win.get('start') or '-'} -> {win.get('endExclusive') or '-'}"

    metadata = {
        "generatedAt": datetime.now(UTC).isoformat(timespec="seconds").replace("+00:00", "Z"),
        "claudeRoot": str(claude_root),
        "window": window_text,
        "workspaceFilter": args.workspace_filter or "(none)",
        "includeNonBedrock": bool(args.include_non_bedrock),
        "pricingUsdPerMToken": DEFAULT_RATES_PER_MTOK,
        "cacheMultipliers": {
            "write": CACHE_WRITE_MULTIPLIER,
            "read": CACHE_READ_MULTIPLIER,
        },
        "planBenchmarks": PLAN_BENCHMARKS,
        "planBenchmarksRetrievedAt": "2026-02-16",
        "stats": parse_stats,
    }

    outputs = write_outputs(
        output_dir=output_dir,
        summary=summary,
        metadata=metadata,
        top_n=args.top_n,
        chrome_path=args.chrome_path,
    )

    totals = summary.get("totals", {})
    sp = summary.get("subscriptionPressure", {})
    plans = sp.get("planAnalysis", {})
    cc = plans.get("cloud_code_pro_20", {})
    cx = plans.get("codex_plus_20", {})
    print("[local-skill] Completed")
    print(f"[local-skill] Source: {claude_root}")
    print(f"[local-skill] Records: {parse_stats.get('kept_unique_rows', 0)} unique of {parse_stats.get('raw_usage_rows', 0)} raw usage rows")
    print(f"[local-skill] Estimated cost: {fmt_usd(float(totals.get('estimatedCostUsd', 0.0)))}")
    print(f"[local-skill] Invocations: {fmt_int(int(totals.get('invocations', 0)))}")
    print(f"[local-skill] Tokens: {fmt_int(int(totals.get('allTokens', 0)))}")
    print(f"[local-skill] Cache savings: {fmt_usd(float(totals.get('estimatedCacheSavingsUsd', 0.0)))}")
    if cc:
        print(
            "[local-skill] Cloud Code Pro 5h exceed periods: "
            + f">{cc.get('fiveHourPromptRange', [0,0])[0]} => {((cc.get('exceedLowThreshold') or {}).get('periods', 0))}, "
            + f">{cc.get('fiveHourPromptRange', [0,0])[1]} => {((cc.get('exceedHighThreshold') or {}).get('periods', 0))}"
        )
    if cx:
        print(
            "[local-skill] Codex Plus 5h exceed periods: "
            + f">{cx.get('fiveHourPromptRange', [0,0])[0]} => {((cx.get('exceedLowThreshold') or {}).get('periods', 0))}, "
            + f">{cx.get('fiveHourPromptRange', [0,0])[1]} => {((cx.get('exceedHighThreshold') or {}).get('periods', 0))}"
        )
    print(f"[local-skill] JSON: {outputs['json']}")
    print(f"[local-skill] HTML: {outputs['html']}")
    if outputs["pdf"]:
        print(f"[local-skill] PDF: {outputs['pdf']}")
    else:
        print(f"[local-skill] PDF: not generated ({outputs['pdf_status']})")


if __name__ == "__main__":
    main()
