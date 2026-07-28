# Teleport for Codex — design note

> **Status: GROUNDED, ready to implement (2026-06-23).** The session format was
> confirmed against real Codex sessions on the MacBook. Implementation + a real
> end-to-end test are the next-session task. The bar is the same Claude teleport
> met: a real laptop→mini run that actually resumes.

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

## The one open question (confirm FIRST when implementing)

How does `codex resume` locate a session — by UUID globally (scans
`~/.codex/sessions/`) or tied to the cwd? This decides whether dropping the rollout
file in place is enough, or whether an index/registry must be touched. Confirm with
`codex resume --help` (needs `node` on PATH — the bun shim failed over headless SSH;
run it in a login shell or via `/opt/homebrew/bin/codex`).

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
