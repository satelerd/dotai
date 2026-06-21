---
name: teleport
description: Move THIS live Claude Code conversation to another machine and keep working there. Trigger when the user says "teleport yourself / this session to the mini", "send this conversation to <host>", "I'm closing the lid, move this to my server", or asks to continue the same thread on a different computer. Packages the current session + repo state (committed + uncommitted + untracked + local-only commits), clones or worktrees the repo on the target, and lands the session in tmux for mosh reattach.
allowed-tools: Bash(dotai *) Bash(*/dotai *) Bash(*/teleport.sh *) Bash(ssh *) Bash(git *) Bash(cat *) Bash(ls *)
---

# teleport

Use this when the user wants the **current conversation** to continue on another
machine (the classic case: working on the laptop, closing the lid, resume on the
Mac mini). You — the agent running this session — package yourself and send it.

## What it moves

- The **live transcript** of this session (full history, a snapshot).
- The **repo state**: origin URL, branch, HEAD, uncommitted patch, untracked
  files, **and a bundle of local-only commits** (so commits not yet pushed
  travel too).

On the target the repo is matched **by remote URL**, not by folder name:
- **Not cloned there yet** → it clones into `~/code/<repo>` and works there.
- **Already cloned there** → it carves a **dedicated git worktree** on a fresh
  `tp/<stamp>` branch under `~/code/.tp/<repo>/`. The existing checkout is never
  touched, so work in progress on the target isn't obstructed.

Then it places the transcript, pre-accepts the trust dialog, and (default) lands
the session in a **tmux** session you can reattach from your phone over mosh.

## How to run it

1. **Confirm this is Claude Code.** The session id is in the environment:
   ```bash
   echo "${CLAUDE_CODE_SESSION_ID:?not a Claude Code session}"
   ```
   (Codex isn't supported yet — teleport will say so.)

2. **Run from the repo where this conversation is happening** (the cwd Claude
   was launched in). Teleport finds the session under that directory's project
   folder. If you `cd`'d elsewhere, go back to the repo root first.

3. **Pick the target host.** Use the host the user names (`user@host`).
   Otherwise it falls back to `DOTAI_TP_HOST` in `.dotai.conf`. A Tailscale
   hostname or IP works well as the target.

4. **Locate dotai and send**, passing this exact session so there's no guessing:
   ```bash
   DOTAI="$(command -v dotai || echo "$HOME/code/dotai/dotai")"
   "$DOTAI" tp <host> --session "$CLAUDE_CODE_SESSION_ID"
   ```
   Add `--no-tmux` if the user just wants the session placed (prints the
   `claude -r` command instead of starting tmux).

   **Routing the destination.** By default the repo lands under `~/code` on the
   target. If the user says where it should go ("put it in my work folder"),
   add `--into <dir>`. Use a **bare name** — `--into work` lands it in `~/work`
   on the target — so a `~` or `$HOME` doesn't get expanded on the source by
   mistake. Absolute paths work too.

5. **Relay the output verbatim** — it prints how to reattach:
   ```
   tmux attach -t tp-<repo>           # on the target
   mosh <host> -- tmux attach -t tp-<repo>   # from your phone
   ```

## Limits — state these, don't try to "fix" them

- **The snapshot is slightly stale.** The transcript is copied mid-turn, so the
  turn where you ran teleport (and this confirmation) won't be in the moved
  copy. That's expected.
- **This session keeps running here.** Teleport never kills the source — you now
  have the thread on both machines. Tell the user to continue on the target and
  let this one go (or `/exit`).
- **No-clobber.** If a session with the same id already exists at the target
  location, teleport refuses rather than overwrite. Nothing is destroyed.
- **Private repos** must be reachable from the target (its own credentials). If
  the clone can't authenticate there, the transcript still moves.

## Safety

Teleport is additive and non-destructive by design: it never overwrites another
session, never touches the target's existing checkout (it worktrees instead),
and stages the payload outside the repo. You may run it without extra
confirmation when the user asks to teleport. Do **not** delete the source
session or the local checkout afterward.
