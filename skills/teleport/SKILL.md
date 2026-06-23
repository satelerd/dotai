---
name: teleport
description: Move THIS live Claude Code conversation to another machine and keep working there. Trigger when the user says "teleport yourself / this session to the mini", "send this conversation to <host>", "I'm closing the lid, move this to my server", or asks to continue the same thread on a different computer. Packages the current session + repo state (committed + uncommitted + untracked + local-only commits), clones or worktrees the repo on the target, and prints the command to resume the same thread there (optionally inside tmux). Reads the target host from .dotai.conf when present — does not ask for or invent one.
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

Then it places the transcript and pre-accepts the trust dialog. By default it
just prints the `claude -r` command to resume; pass `--tmux` to land the session
in a **tmux** session you can reattach from your phone over mosh.

## How to run it

1. **Confirm this is Claude Code.** The session id is in the environment:
   ```bash
   echo "${CLAUDE_CODE_SESSION_ID:?not a Claude Code session}"
   ```
   (Codex isn't supported yet — teleport will say so.)

2. **Run from the repo where this conversation is happening** (the cwd Claude
   was launched in). Teleport finds the session under that directory's project
   folder. If you `cd`'d elsewhere, go back to the repo root first.

3. **Resolve the target host — don't ask if you don't have to, and NEVER invent one.**
   First check for a configured host:
   ```bash
   cat ./.dotai.conf "$HOME/.dotai.conf" 2>/dev/null | grep DOTAI_TP_HOST
   ```
   Then, in order:
   - If the user named a **full** host (`user@host`), use exactly that.
   - Else if `.dotai.conf` has `DOTAI_TP_HOST`, **run `dotai tp` with NO host argument** —
     the script reads it for you. Don't pass a host, don't ask.
   - Only if there is **neither** a user-named host **nor** a `DOTAI_TP_HOST`, ask for one.

   **Never build a host yourself.** Do not take a hostname from Tailscale / mDNS / ssh config
   and prepend the *local* username — the remote user is almost never the same (`sat@mini-sat`
   fails when the mini's user is `minisat`). The full `user@host` comes from the config or from
   what the user literally typed — nowhere else.

4. **Locate dotai and send**, passing this exact session so there's no guessing.
   Omit the host when it comes from `.dotai.conf`:
   ```bash
   DOTAI="$(command -v dotai || echo "$HOME/code/dotai/dotai")"
   "$DOTAI" tp --session "$CLAUDE_CODE_SESSION_ID"             # host from .dotai.conf
   # …or, ONLY if the user named one explicitly:
   "$DOTAI" tp user@host --session "$CLAUDE_CODE_SESSION_ID"
   ```
   By default it just places the session and prints the `claude -r` command to
   resume. Add `--tmux` only if the user asks for tmux (for mosh reattach).

   **Routing the destination.** By default the repo lands under `~/code` on the
   target. If the user says where it should go ("put it in my work folder"),
   add `--into <dir>`. Use a **bare name** — `--into work` lands it in `~/work`
   on the target — so a `~` or `$HOME` doesn't get expanded on the source by
   mistake. Absolute paths work too.

5. **Relay the output verbatim** — by default it prints the resume command:
   ```
   cd <target-path> && claude -r <session-id>   # on the target
   ```
   With `--tmux` it instead prints how to reattach:
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
