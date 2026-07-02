# Teleport for Cursor — design note

> **Status: NOT implemented, deferred (2026-07-01).** Config sync for Cursor
> (`~/.cursor/mcp.json`) and fainder search over Cursor both ship today. Teleport
> is out of scope for now because Cursor has no clean "resume this exact
> conversation" entrypoint for the surface people actually use (the GUI chat).
> This note records the grounding so a future session can pick it up without
> re-discovering the walls.

## What "teleport" needs

`dotai tp` moves a live conversation between machines by (1) copying a
self-contained transcript, (2) rewriting its `cwd`, and (3) printing a CLI command
that resumes *that exact conversation* (`claude -r <id>`, `codex resume <uuid>`).
The repo handling (URL match → clone/worktree, patch, untracked, local-commit
bundle, `--into`) is harness-agnostic and reused unchanged. The only harness-
specific parts are **find / package / place / resume** the session.

For Cursor, step (3) is the wall — and it differs by surface.

## Cursor has two conversation surfaces (confirmed 2026-07-01)

1. **GUI chat (composers)** — what you use inside the Cursor app, and what
   [fainder](https://github.com/satelerd/fainder) indexes. Stored as JSON blobs
   **inside a per-workspace SQLite DB**:
   `~/Library/Application Support/Cursor/User/workspaceStorage/<hash>/state.vscdb`,
   under keys `composer.composerData`, `aiService.prompts`, `aiService.generations`.
   There is **no CLI to resume a specific chat**. `cursor <folder>` only opens the
   workspace; it does not drop you back into a thread. fainder's "resume command"
   for Cursor is exactly that folder-open, by necessity.

2. **`cursor-agent` CLI** — the terminal agent. It **does** resume by id:
   `cursor-agent --resume <chatId>` (also `agent ls`, `agent resume`, `--continue`).
   But it's a **separate store** from the GUI chat (the Cursor forum confirms
   "Agent CLI resume shows chats but Cursor app history does not"). Storage path on
   disk is **not documented** — must be grounded on a machine that has it.

## The wish vs. the walls

The wish (sat, 2026-07-01): "sometimes I'm in Cursor on the MacBook and want to
move it to the Mac mini and keep going **in the Cursor app**." That targets
surface #1 (GUI), which is the hard one:

- **No resume entrypoint.** Even with the data moved, nothing reopens the thread.
- **Injecting into `state.vscdb` is invasive and fragile.** You'd have to
  reconstruct the target's workspace `<hash>`, write rows into Cursor's live DB
  (Cursor must be closed), and match a schema that changes across versions. This
  breaks dotai's "additive, never clobber" posture. **Do not attempt this as a
  first pass.**

Surface #2 (`cursor-agent` CLI) is the tractable teleport — it has a real
resume-by-id command — but it's a different UX than the app chat, so it only
satisfies the wish partially.

## If/when we implement (start here)

Ground on a machine that has Cursor (the MacBook Pro), the same bar Codex met:

1. **Pick the surface.** For a real, non-fragile teleport, target `cursor-agent`
   CLI sessions, not the GUI DB.
2. **Ground the storage.** Find where `cursor-agent` keeps sessions (likely under
   `~/.cursor/` or an XDG config dir). Confirm the on-disk format and whether
   `--resume <id>` looks up globally or is tied to cwd (decides whether dropping a
   file in place is enough, or an index must be touched). Same open question that
   Codex had.
3. **Reuse the repo pipeline** unchanged; add Cursor find/package/place/resume.
4. **Non-circular test.** Assert placement against where `cursor-agent --resume`
   actually looks — not against our own placement function (the lesson from the
   Claude encoding bug).
5. **Two-machine reality.** A round-trip demo needs `cursor-agent` installed on
   *both* machines. The Mac mini has no Cursor today.

## What ships now instead

- **Config sync:** `~/.cursor/mcp.json` (global MCP servers), secrets in
  `env`/`headers` redacted on push, `mcp.json.from-sync` on pull. See `manifest.txt`.
- **Search & reopen:** fainder finds any Cursor conversation and gives you the
  command to open its workspace. That covers "find the thread again" — just not a
  live cross-machine hand-off of the GUI chat.
