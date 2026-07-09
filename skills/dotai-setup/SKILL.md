---
name: dotai-setup
description: Apply your dotai configs to a new or existing machine. Inspects what Claude Code (and optionally Codex) already has installed, compares with your dotai repo, asks about machine-specific choices, then applies skills, hooks, CLAUDE.md, statusline, and settings — preserving any machine-specific overrides. Works locally or over SSH.
allowed-tools: Bash(ssh *) Bash(rsync *) Bash(scp *) Bash(jq *) Bash(python3 *) Bash(ls *) Bash(cat *) Bash(mkdir *)
---

# dotai-setup

Use this skill when you want to apply your dotai configs to a new or existing machine.

## Step 1 — Identify the target

Ask the user:
- **Local** (this machine) or **remote** (SSH)?
- If remote: SSH user and host (e.g. `user@192.168.1.10` or a Tailscale hostname).
- Is Codex installed on the target? (Skip codex entries if not.)

Define helpers based on the answer:

```bash
TARGET="user@host"   # or "" for local
run()  { [[ -z "$TARGET" ]] && bash -c "$1"          || ssh "$TARGET" "$1"; }
push() { [[ -z "$TARGET" ]] && cp -r "$1" "$2"       || scp -r "$1" "$TARGET:$2"; }
sync_dir() {
  # $1 = local source dir, $2 = remote dest dir
  [[ -z "$TARGET" ]] \
    && rsync -a --exclude='.DS_Store' --exclude='__pycache__/' --exclude='*.pyc' "$1/" "$2/" \
    || rsync -a --exclude='.DS_Store' --exclude='__pycache__/' --exclude='*.pyc' -e ssh "$1/" "$TARGET:$2/"
}
```

## Step 2 — Inventory the target

```bash
run "echo '=== ~/.claude ===' && ls ~/.claude/ 2>/dev/null || echo 'missing'"
run "echo '=== ~/.codex  ===' && ls ~/.codex/  2>/dev/null || echo 'missing'"
run "cat ~/.claude/settings.json      2>/dev/null || echo 'no settings.json'"
run "cat ~/.claude/settings.local.json 2>/dev/null || echo 'no settings.local.json'"
run "ls ~/.claude/skills/ 2>/dev/null || echo 'no skills'"
run "ls ~/.claude/hooks/  2>/dev/null || echo 'no hooks'"
```

Build a mental diff:
- What does the target **have** that should be preserved? (Machine-specific flags, permissions, existing skills.)
- What is the target **missing** from the dotai repo? (CLAUDE.md, skills, hooks, statusline, settings fields.)

## Step 3 — Ask about secrets

Before applying `settings.json`, ask:
1. Should the target have API keys (LLM providers, external services)?
2. If yes: where are the real values? (Secrets file, 1Password, manual paste.)

## Step 4 — Apply non-secret files

Apply these directly — no merging needed:

```bash
# CLAUDE.md
push ~/.claude/CLAUDE.md ~/.claude/CLAUDE.md

# skills (additive — don't use --delete unless user confirms)
sync_dir ~/.claude/skills ~/.claude/skills

# hooks
sync_dir ~/.claude/hooks ~/.claude/hooks

# statusline scripts (if they exist locally)
for f in statusline.sh statusline-v1.sh claude-mode.sh; do
  [[ -f ~/.claude/$f ]] && push ~/.claude/$f ~/.claude/$f
done
```

## Step 5 — Merge settings.json

**Never overwrite settings.json blindly.** Build a merged version:

1. Start from the dotai repo's sanitized settings as the base structure.
2. Inject real API key values the user confirmed in Step 3.
3. Preserve machine-specific flags from the target's existing `settings.json`:
   - `remoteControlAtStartup`, `agentPushNotifEnabled` — often intentional on server machines.
   - Any flags not in the dotai base.

```bash
# Read target's current settings
run "cat ~/.claude/settings.json" > /tmp/target_settings.json

# Build merged JSON with jq or python3, write to /tmp/merged_settings.json
# Then apply:
push /tmp/merged_settings.json ~/.claude/settings.json
```

## Step 6 — Merge settings.local.json

`settings.local.json` contains machine-specific Bash allow rules — **always merge, never replace**.

Combine:
- Target's existing `allow` array (keep as-is, it's machine-specific)
- Dotai repo's `allow` array entries that are missing from the target
- **Adapt hardcoded paths** to the target's username/home dir (e.g. `/Users/alice/` instead of `/Users/bob/`)

```bash
run "cat ~/.claude/settings.local.json" > /tmp/target_local.json
# Merge with python3 or jq, write to /tmp/merged_local.json
push /tmp/merged_local.json ~/.claude/settings.local.json
```

## Step 7 — Verify

```bash
run "ls ~/.claude/skills/ && echo '---' && ls ~/.claude/hooks/"
run "cat ~/.claude/settings.json | python3 -c \
  'import json,sys; d=json.load(sys.stdin); \
   print(\"plugins:\", list(d.get(\"enabledPlugins\",{}).keys())); \
   print(\"env keys:\", list(d.get(\"env\",{}).keys()))'"
```

Report to the user:
- What was copied.
- What was merged and how.
- Any manual steps remaining (e.g. install plugin marketplaces by opening Claude Code, install deps like `jq`/`rsync`).

## Notes

- Plugins listed in `enabledPlugins` are auto-installed by Claude Code on next launch — no manual step needed.
- If the target lacks `jq` or `rsync`, flag it — `sync.sh pull` needs both (`brew install jq rsync`).
- For Codex: apply `AGENTS.md`, `skills/`, `hooks/`, `rules/`, `keybindings.json` the same way. `config.toml` follows the same merge pattern as `settings.json`.
- `git config core.hooksPath hooks` must be run on the target if the dotai repo is cloned there — this setting doesn't survive a clone.
