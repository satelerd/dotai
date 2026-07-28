---
name: teleport
description: Move THIS live Claude Code or Codex conversation to another machine and keep working there. Trigger when the user asks to teleport this session to the mini, send the conversation to another host, close the laptop and move to a server, or continue the same thread on a different computer. Packages the current session plus repo state, clones or worktrees the repo on the target, and prints the exact resume command. Reads the target host from .dotai.conf when present.
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

Then it places the session in the target harness's native store. By default it
prints the exact `claude -r` or `codex resume` command; pass `--tmux` to start
the resumed session inside tmux.

## How to run it

1. **Detect the current harness and full session id.**

   Claude Code:
   ```bash
   test -n "${CLAUDE_CODE_SESSION_ID:-}"
   ```

   Codex:
   ```bash
   test -n "${CODEX_THREAD_ID:-}"
   ```

   Use the matching variable verbatim. Never guess or shorten the id. With a
   Codex UUID, teleport reads the session's recorded cwd and packages the
   correct repo even if the shell command runs from another directory.

2. **Resolve the target host through the engine; do not re-derive it.**
   The engine (`teleport.sh`) already loads `DOTAI_TP_HOST` from `.dotai.conf` next to
   the script, then from `$HOME`. **Do not grep for the config yourself** — you'd look in
   the working directory (where the conversation lives, e.g. some product repo) and miss the
   config that sits next to `dotai`, get a false "no host", and wrongly start asking. Instead:
   - If the user named a **full** host (`user@host`), pass exactly that.
   - Otherwise, **run `dotai tp` with NO host argument** and let the engine resolve it.
   - Only if the engine itself fails with **"No target host"**, ask the user for a `user@host`
     and re-run with it.

   **Never build a host yourself.** Do not take a hostname from Tailscale / mDNS / ssh config
   and prepend the *local* username — the remote user is almost never the same (`sat@mini-sat`
   fails when the mini's user is `minisat`). The full `user@host` comes from the config (via
   the engine) or from what the user literally typed — nowhere else.

3. **Locate dotai and send the exact session.** Omit the host when it comes
   from `.dotai.conf`:
   ```bash
   DOTAI="$(command -v dotai || echo "$HOME/code/dotai/dotai")"
   if [ -n "${CODEX_THREAD_ID:-}" ]; then
     "$DOTAI" tp --harness codex --session "$CODEX_THREAD_ID"
   else
     "$DOTAI" tp --harness claude --session "${CLAUDE_CODE_SESSION_ID:?}"
   fi
   ```

   If the user explicitly named a full `user@host`, place it immediately after
   `tp`. Add `--tmux` only when the user requests tmux.

   **Routing the destination.** By default the repo lands under `~/code` on the
   target. If the user says where it should go ("put it in my work folder"),
   add `--into <dir>`. Use a **bare name** — `--into work` lands it in `~/work`
   on the target — so a `~` or `$HOME` doesn't get expanded on the source by
   mistake. Absolute paths work too.

4. **Relay the output verbatim.** It prints the target path and native resume
   command:
   ```
   cd <target-path> && claude -r <session-id>
   cd <target-path> && /resolved/path/codex resume <session-id>
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
- **Target harness required.** Codex teleport resolves a CLI that actually
  supports `resume`, including the binary bundled in Codex.app or ChatGPT.app,
  and stops before placing anything if none exists. The target must be logged in.

## Safety

Teleport is additive and non-destructive by design: it never overwrites another
session, never touches the target's existing checkout (it worktrees instead),
and stages the payload outside the repo. You may run it without extra
confirmation when the user asks to teleport. Do **not** delete the source
session or the local checkout afterward.
