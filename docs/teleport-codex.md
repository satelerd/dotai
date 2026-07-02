# Teleport for Codex — design note

> **Status: implemented and VALIDATED (2026-07-01).** `dotai tp --harness codex`
> moves the newest Codex rollout for the current cwd. Grounded against
> codex-cli 0.142.5 (bundled in Codex.app) on the mini: the format below held,
> and the open question is answered — **resume is global by UUID** (a session
> absent from `session_index.jsonl` still resumes from any cwd; the index only
> tracks named threads). A **real round-trip** placed a rollout with its
> `session_meta` cwd rewritten and `codex exec resume <uuid>` recalled a
> pre-teleport marker from conversation memory. e2e scenario L covers the
> pipeline in the Docker sandbox. Requirement: the target needs codex
> installed and logged in.

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

1. **send** (`--harness codex`): find the rollout for the current cwd (newest, or
   `--session <uuid>`), stage it with the existing repo payload, ship.
2. **receive**: place the rollout under `~/.codex/sessions/YYYY/MM/DD/` on the
   target, rewrite **only** `payload.cwd` on the first line to the worktree path,
   then print the real `codex resume <uuid>` command. Reuse clone/worktree as-is.
3. **skill**: add a Codex detection path (today it asserts `$CLAUDE_CODE_SESSION_ID`).
4. **tests**: add a Codex scenario using a captured real rollout fixture; assert
   placement against where `codex resume` actually looks — **not** against our own
   placement function (the non-circular lesson from the Claude encoding bug).

## Test plan (real, end-to-end)

- **codex + auth on the mini:** install codex on the mini and **copy
  `~/.codex/auth.json` from the MacBook** (decided 2026-06-23) so resume can run.
- Teleport a throwaway Codex session MacBook→mini with a secret token; run
  `codex resume <uuid>` on the mini; confirm it resumes carrying the token. Same bar
  Claude teleport met.

## Where to start next session

Grounding is done (format, cwd location, session id, rollout path). Pending: the
resume-lookup mechanism (above), then implement + validate end-to-end. Start here.
