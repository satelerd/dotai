# dotai

> dotfiles for your AI harness (Claude Code, Codex)

A lightweight sync system for your **Claude Code** (`~/.claude`) and **Codex** (`~/.codex`) configs: skills, prompts, hooks, statusline, rules, keybindings, and plugin manifests.

**Goal:** fork this repo, run one command to back up your setup, and restore everything on a new machine in minutes.

It also bundles **[teleport](#teleport)** — move a *live* Claude Code conversation (full history + the repo it lives in) to another machine and pick it up there.

## How it works

```
 Machine A                  GitHub                      Machine B
 ~/.claude  ──── push ────▶ dotai repo ──── pull ────▶  ~/.claude
 ~/.codex                                               ~/.codex
```

`manifest.txt` declares exactly what moves. API keys are redacted on push and arrive as `*.from-sync` on pull, so your live files are never overwritten.

## Teleport

Beyond syncing configs, dotai can move a **live conversation** to another machine. The classic case: you're working in Claude Code on your laptop, you close the lid, and the *same thread* — full history plus the repo it lives in — lands on your Mac mini, ready to resume. One command:

```bash
dotai tp me@mini          # send THIS conversation to another machine
```

It carries the session transcript, the repo (cloned or worktree'd on the target), your uncommitted changes, and even local-only commits. Full mechanics in [Teleport in depth](#teleport-in-depth) below.

## Quick start

### 1. Fork and clone

```bash
git clone https://github.com/YOUR_USERNAME/dotai ~/code/dotai
cd ~/code/dotai
git config core.hooksPath hooks   # enables the pre-commit secret scanner
```

### 2. Back up your configs

```bash
./sync.sh push
git diff                          # review what changed
git add -A && git commit -m "sync $(date +%F)"
git push
```

### 3. Restore on a new machine

```bash
# Prerequisites
brew install jq rsync

# Clone your repo
git clone https://github.com/YOUR_USERNAME/dotai ~/code/dotai
cd ~/code/dotai
git config core.hooksPath hooks

# Apply configs
./sync.sh pull
```

After pull:
1. Files with secrets land as `*.from-sync` (e.g. `settings.json.from-sync`). Review them, inject your real API keys from your secrets store, and rename to the real filename.
2. Reinstall plugins: Claude Code auto-installs them on next launch when `enabledPlugins` is set.
3. Install any skill/hook dependencies (e.g. `jq`, `rsync`, tool-specific CLIs).

### 4. Teleport a live conversation

From inside the repo where the conversation is happening:

```bash
dotai tp me@mini                 # HOST defaults to DOTAI_TP_HOST in .dotai.conf
dotai tp me@mini --into work     # land the repo under ~/work on the target
dotai tp me@mini --tmux          # land it inside tmux for mosh reattach
```

It prints the `claude -r …` command to continue the same thread on the target (or, with `--tmux`, the `tmux attach` line).

## Commands

| Command | What it does |
|---|---|
| `./sync.sh push` | `HOME → repo`. Sanitizes secrets, then runs the scanner. |
| `./sync.sh pull` | `repo → HOME`. Additive, never deletes your local files. |
| `./sync.sh status` | Shows what differs between HOME and the repo. No writes. |
| `./sync.sh scan` | Scans the repo tree for secrets. Exits non-zero if found. |
| `dotai tp [HOST]` | Teleport the current Claude Code conversation to HOST. |

## Security model

- `settings.json` and `config.toml` are **never stored with real values**. On `push`, secret-looking env values are replaced with `__REDACTED__`.
- A secret scanner runs as a `pre-commit` hook and as the last step of every `push`. It aborts if it finds a pattern matching known secret formats.
- `.gitignore` blocks the raw config files (`settings.json`, `config.toml`) so an accidental `git add -A` can't leak them.
- Real secrets live in your secrets store (1Password, a private repo, etc.) and are never touched by dotai.

## What gets synced

Defined in `manifest.txt`. Add or remove entries to match your setup.

| Tool | Synced | Not synced |
|---|---|---|
| Claude Code | `CLAUDE.md`, `skills/`, `claude-hooks/`, `statusline*.sh`, `settings.*.json` (redacted), plugin manifests, `settings.local.json` | history, sessions, projects, todos, caches, `auth.json`, `settings.json` (raw) |
| Codex | `AGENTS.md`, `codex-skills/`, `codex-hooks/`, `codex-rules/`, `codex-keybindings.json`, `config.toml` (redacted) | memories (they have their own git), history |

Plugin **content** is not vendored; it lives in its marketplace repo with `autoUpdate`. Only the manifest that reinstalls them is synced.

## Teleport in depth

`dotai tp` moves the **current Claude Code conversation** — full history plus the repo it lives in — to another machine, ready to resume.

```bash
# from inside the repo where the conversation is happening
dotai tp me@mini                 # HOST defaults to DOTAI_TP_HOST in .dotai.conf
dotai tp me@mini --into work     # land it under ~/work on the target
dotai tp me@mini --tmux          # land it inside tmux (default: just prints `claude -r`)
```

By default the repo lands under `~/code` on the target. `--into <dir>` routes it elsewhere — a **bare name** like `work` is taken relative to the target's home (`~/work`), so a stray `~` on the source can't point it at the wrong path; absolute paths are used as-is.

What travels: the session transcript, the repo's origin URL + branch + HEAD, your uncommitted patch, untracked files, **and a bundle of local-only commits** (so a HEAD you never pushed still resolves on the target).

How the repo lands on the target — matched **by remote URL, not folder name**:

| On the target | What happens |
|---|---|
| Repo not cloned yet | Clones into `$DOTAI_TP_BASE/<repo>` and works there. |
| Repo already cloned | Carves a dedicated **git worktree** on a fresh `tp/<stamp>` branch under `$DOTAI_TP_BASE/.tp/<repo>/`. The existing checkout is **never touched**, so work in progress isn't obstructed. |

Everything is additive: it refuses to overwrite an existing session (no-clobber) and never modifies the target's working checkout. Config lives in `.dotai.conf` (`DOTAI_TP_HOST`, `DOTAI_TP_BASE`, `DOTAI_TP_TMUX`). v1 is Claude Code only.

**tmux is opt-in.** By default teleport just places the session and prints the `claude -r` command. Pass `--tmux` (or set `DOTAI_TP_TMUX=1` in `.dotai.conf` for a machine that always wants it) to land the session inside a tmux session you can reattach from your phone over mosh.

**Let an agent teleport itself.** The `teleport` skill lets Claude move its own session when you ask ("teleport yourself to the mini") — it reads `$CLAUDE_CODE_SESSION_ID` and runs the send for you.

**Tests:** `tests/run.sh` spins up a throwaway Docker sandbox and runs the e2e suite (real ssh/rsync/git, never your `$HOME`): fresh clone, worktree-on-existing, URL matching, local-commit-via-bundle, the combined worktree+bundle path, and the no-clobber guard.

**Known limits**

- The Docker suite verifies the **mechanics** (transport, clone, worktree, bundle, transcript placement). It does **not** prove `claude -r` reopens the same thread — that needs one real laptop→mini run (teleport, resume, confirm it continues).
- URL matching scans **one level** (`$DOTAI_TP_BASE/*/`). A nested layout (`~/code/<namespace>/<repo>`) won't match, so teleport would clone a duplicate instead of worktree-ing the real one.
- **No automatic cleanup** of teleport worktrees. They pile up under `$DOTAI_TP_BASE/.tp/<repo>/` on `tp/<stamp>` branches. To prune:
  ```bash
  rm -rf ~/code/.tp/<repo>/<stamp> && git -C ~/code/<repo> worktree prune
  ```

## Setting up on a new machine (with the dotai-setup skill)

If you have the `dotai-setup` skill installed, you can ask Claude Code to set up a remote machine over SSH:

> "Use dotai-setup to apply my configs to `user@host`"

Claude will inspect the remote machine, compare it with your dotai repo, ask about secrets, merge `settings.local.json` carefully, and apply everything via rsync/scp.
