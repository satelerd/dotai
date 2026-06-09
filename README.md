# dotai

> dotfiles for your AI harness (Claude Code, Codex)

A lightweight sync system for your **Claude Code** (`~/.claude`) and **Codex** (`~/.codex`) configs: skills, prompts, hooks, statusline, rules, keybindings, and plugin manifests.

**Goal:** fork this repo, run one command to back up your setup, and restore everything on a new machine in minutes.

## How it works

```
 Machine A                  GitHub                      Machine B
 ~/.claude  ──── push ────▶ dotai repo ──── pull ────▶  ~/.claude
 ~/.codex                                               ~/.codex
```

`manifest.txt` declares exactly what moves. API keys are redacted on push and arrive as `*.from-sync` on pull, so your live files are never overwritten.

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

## Commands

| Command | What it does |
|---|---|
| `./sync.sh push` | `HOME → repo`. Sanitizes secrets, then runs the scanner. |
| `./sync.sh pull` | `repo → HOME`. Additive, never deletes your local files. |
| `./sync.sh status` | Shows what differs between HOME and the repo. No writes. |
| `./sync.sh scan` | Scans the repo tree for secrets. Exits non-zero if found. |

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

## Setting up on a new machine (with the dotai-setup skill)

If you have the `dotai-setup` skill installed, you can ask Claude Code to set up a remote machine over SSH:

> "Use dotai-setup to apply my configs to `user@host`"

Claude will inspect the remote machine, compare it with your dotai repo, ask about secrets, merge `settings.local.json` carefully, and apply everything via rsync/scp.
