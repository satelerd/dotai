#!/usr/bin/env python3
"""
Lists all Claude Code projects with conversation metadata.
Reads ~/.claude/projects/ and extracts session info from sessions-index.json files.
Also checks projects without index by counting JSONL files directly.

Output: JSON to stdout with project list and stats.
"""

import json
import os
import sys
from datetime import datetime
from pathlib import Path

CLAUDE_DIR = Path.home() / ".claude"
PROJECTS_DIR = CLAUDE_DIR / "projects"
SETTINGS_FILE = CLAUDE_DIR / "settings.json"


def get_retention_days():
    """Read cleanupPeriodDays from settings.json."""
    if not SETTINGS_FILE.exists():
        return None
    try:
        settings = json.loads(SETTINGS_FILE.read_text())
        return settings.get("cleanupPeriodDays")
    except (json.JSONDecodeError, OSError):
        return None


def decode_project_path(dirname):
    """Convert project directory name back to original path.
    e.g. '-Users-sat-SmartUp-core' -> '/Users/sat/SmartUp/core'
    """
    if dirname.startswith("-"):
        return "/" + dirname[1:].replace("-", "/")
    return dirname


def get_jsonl_files(project_dir):
    """List all JSONL conversation files in a project directory."""
    return list(project_dir.glob("*.jsonl"))


def get_project_info(project_dir):
    """Extract project metadata from sessions-index.json or raw JSONL files."""
    dirname = project_dir.name
    original_path = None
    sessions = []

    index_file = project_dir / "sessions-index.json"
    if index_file.exists():
        try:
            index = json.loads(index_file.read_text())
            entries = index.get("entries", [])
            original_path = index.get("originalPath")

            for entry in entries:
                sessions.append({
                    "sessionId": entry.get("sessionId"),
                    "firstPrompt": (entry.get("firstPrompt") or "")[:200],
                    "summary": entry.get("summary"),
                    "messageCount": entry.get("messageCount", 0),
                    "created": entry.get("created"),
                    "modified": entry.get("modified"),
                    "gitBranch": entry.get("gitBranch"),
                    "isSidechain": entry.get("isSidechain", False),
                })
        except (json.JSONDecodeError, OSError):
            pass

    # Also check for JSONL files not in the index
    jsonl_files = get_jsonl_files(project_dir)
    indexed_ids = {s["sessionId"] for s in sessions}

    for jf in jsonl_files:
        session_id = jf.stem
        if session_id not in indexed_ids:
            stat = jf.stat()
            sessions.append({
                "sessionId": session_id,
                "firstPrompt": "",
                "summary": None,
                "messageCount": None,
                "created": datetime.fromtimestamp(stat.st_ctime).isoformat() + "Z",
                "modified": datetime.fromtimestamp(stat.st_mtime).isoformat() + "Z",
                "gitBranch": None,
                "isSidechain": False,
            })

    if not sessions:
        return None

    if not original_path:
        original_path = decode_project_path(dirname)

    # Calculate date range
    dates = []
    for s in sessions:
        if s.get("created"):
            try:
                dates.append(s["created"][:10])
            except (TypeError, IndexError):
                pass
        if s.get("modified"):
            try:
                dates.append(s["modified"][:10])
            except (TypeError, IndexError):
                pass

    date_range = None
    if dates:
        dates.sort()
        date_range = {"from": dates[0], "to": dates[-1]}

    total_messages = sum(s.get("messageCount") or 0 for s in sessions)

    # Calculate total size of JSONL files
    total_size_bytes = sum(jf.stat().st_size for jf in jsonl_files)

    return {
        "dirName": dirname,
        "originalPath": original_path,
        "sessionCount": len(sessions),
        "totalMessages": total_messages,
        "totalSizeBytes": total_size_bytes,
        "totalSizeMB": round(total_size_bytes / (1024 * 1024), 2),
        "dateRange": date_range,
        "hasIndex": index_file.exists(),
        "sessions": sessions,
    }


def main():
    if not PROJECTS_DIR.exists():
        print(json.dumps({"error": "No projects directory found", "projects": []}))
        sys.exit(1)

    projects = []
    for item in sorted(PROJECTS_DIR.iterdir()):
        if not item.is_dir():
            continue
        info = get_project_info(item)
        if info:
            projects.append(info)

    retention_days = get_retention_days()

    output = {
        "claudeDir": str(CLAUDE_DIR),
        "projectsDir": str(PROJECTS_DIR),
        "retentionDays": retention_days,
        "retentionStatus": (
            "not_set" if retention_days is None
            else "low" if retention_days < 365
            else "ok"
        ),
        "totalProjects": len(projects),
        "totalSessions": sum(p["sessionCount"] for p in projects),
        "totalMessages": sum(p["totalMessages"] for p in projects),
        "totalSizeMB": round(sum(p["totalSizeBytes"] for p in projects) / (1024 * 1024), 2),
        "projects": projects,
    }

    print(json.dumps(output, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
