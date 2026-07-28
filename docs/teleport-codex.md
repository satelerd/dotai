# Teleport for Codex — design note

> **Status: implemented and VALIDATED.** `dotai tp --harness codex`
> moves the newest Codex rollout for the current cwd. Grounded against
> codex-cli 0.142.5 and revalidated against 0.146.0 (bundled in ChatGPT.app):
> the format below held,
> and the open question is answered — **resume is global by UUID** (a session
> absent from `session_index.jsonl` still resumes from any cwd; the index only
> tracks named threads). A **real round-trip** placed a rollout with its
> `session_meta` cwd rewritten and `codex exec resume <uuid>` recalled a
> pre-teleport marker from conversation memory. e2e scenario L covers the
> pipeline in the Docker sandbox. The target needs Codex installed and logged
> in; teleport resolves a compatible binary from PATH or the Codex.app /
> ChatGPT.app bundles.

## Goal

`dotai tp` already moves a live **Claude Code** conversation between machines. Do the
same for **Codex** (OpenAI's CLI). The repo handling (URL match → clone/worktree,
uncommitted patch, untracked, local-commit bundle, `--into`) is reused **unchanged**;
only finding / packaging / placing / resuming the session is Codex-specific.

## Confirmed format (real sessions, 2026-06-23)

- **Rollouts:** `~/.codex/sessions/YYYY/MM/DD/rollout-<ISO-ts>-<uuid>.jsonl`
- Each line is `{ "timestamp", "type", "payload" }`. Types seen: `session_meta`
  (first line), then `event_msg` / `response_item` (the turns).
- **The cwd lives in ONE place:** the first line's `payload.cwd`
  (e.g. `/Users/sat/code/Pump Up`). `payload.id` == the UUID == the filename's uuid.
- Contrast with Claude: there is **no per-line cwd**, and the session is keyed by
  **UUID in the filename**, not by an encoded-cwd project dir. So there's no
  path-encoding trap like the one that bit Claude — likely simpler.

## The one open question — ANSWERED (2026-07-01)

`codex resume` locates a session **by UUID globally**: a rollout dropped under
`~/.codex/sessions/YYYY/MM/DD/` resumes from any cwd, without touching
`session_index.jsonl` (that index only tracks named threads from the desktop
app). Verified empirically on codex-cli 0.142.5: created a session via
`codex exec`, confirmed its uuid was absent from the index, resumed it from a
different directory, and it recalled the conversation.

## Implementation sketch

1. **send** (`--harness codex`): find the rollout for the current cwd, or use a
   full `--session <uuid>` and take its recorded cwd as the source of truth.
   Capture a complete JSONL snapshot, stage it with the existing repo payload,
   and ship.
2. **receive**: place the rollout under `~/.codex/sessions/YYYY/MM/DD/` on the
   target, require exactly one matching `session_meta`, rewrite **only**
   `payload.cwd` to the worktree path, then print the resolved
   `codex resume <uuid>` command. Reuse clone/worktree as-is.
3. **skill**: detect `$CODEX_THREAD_ID` and pass the full UUID without guessing.
4. **tests**: use a captured-format rollout fixture; cover placement, strict
   metadata validation, no-clobber, and execution through an app-bundled Codex
   binary that is intentionally absent from PATH.

## Test plan (real, end-to-end)

- **codex + auth on the mini:** install and log in to Codex on the mini.
- Teleport a throwaway Codex session MacBook→mini with a unique marker; run
  `codex resume <uuid>` on the mini; confirm it resumes carrying the marker. Same bar
  Claude teleport met.
