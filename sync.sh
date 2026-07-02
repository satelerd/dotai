#!/usr/bin/env bash
#
# sync.sh — sync your Claude Code, Codex, and Cursor configs with this repo.
#
# Usage:
#   ./sync.sh push     Copy HOME -> repo (sanitizes secrets). Then scans.
#   ./sync.sh pull     Copy repo -> HOME (additive; sanitize files go to *.from-sync).
#   ./sync.sh status   Show diff between HOME and repo (no writes).
#   ./sync.sh scan     Scan the repo tree for secrets. Exits non-zero if found.
#
# Secrets never go into the repo: settings.json / config.toml / mcp.json are redacted on push.
# Re-inject real values from your secrets store after pull.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="$REPO_ROOT/manifest.txt"
HOME_DIR="${HOME}"

c_red=$'\033[31m'; c_grn=$'\033[32m'; c_yel=$'\033[33m'; c_blu=$'\033[34m'; c_dim=$'\033[2m'; c_rst=$'\033[0m'
info() { printf '%s%s%s\n' "$c_blu" "$*" "$c_rst"; }
ok()   { printf '%s%s%s\n' "$c_grn" "$*" "$c_rst"; }
warn() { printf '%s%s%s\n' "$c_yel" "$*" "$c_rst"; }
err()  { printf '%s%s%s\n' "$c_red" "$*" "$c_rst" >&2; }

RSYNC_EXCLUDES=(--exclude='.DS_Store' --exclude='.git' --exclude='.system' --exclude='node_modules' --exclude='__pycache__' --exclude='*.pyc')

# ---------------------------------------------------------------------------
# Secret sanitization.
# ---------------------------------------------------------------------------
sanitize_file() {
  local src="$1" dst="$2"
  mkdir -p "$(dirname "$dst")"
  case "$(basename "$src")" in
    settings*.json)
      # Redact any .env value whose key contains key/token/secret/password.
      jq '
        if has("env") then
          .env |= with_entries(
            if (.key | ascii_downcase | test("key|token|secret|password"))
            then .value = "__REDACTED__" else . end
          )
        else . end
      ' "$src" > "$dst"
      ;;
    mcp.json)
      # Cursor's global MCP config (~/.cursor/mcp.json). Redact secrets carried in
      # each server's env/headers, plus any secret-looking field on the server itself.
      jq '
        if has("mcpServers") then
          .mcpServers |= with_entries(
            .value |= (
              with_entries(
                if (.key | ascii_downcase | test("key|token|secret|password|auth"))
                   and (.value | type == "string")
                then .value = "__REDACTED__" else . end
              )
              | (if has("env") then .env |= with_entries(
                   if (.key | ascii_downcase | test("key|token|secret|password|auth"))
                   then .value = "__REDACTED__" else . end) else . end)
              | (if has("headers") then .headers |= with_entries(
                   if (.key | ascii_downcase | test("key|token|secret|password|auth"))
                   then .value = "__REDACTED__" else . end) else . end)
            )
          )
        else . end
      ' "$src" > "$dst"
      ;;
    config.toml)
      # Redact API keys embedded in MCP server headers and X-API-Key values.
      perl -pe '
        s/(sk_shapeup_)[A-Za-z0-9]+/${1}__REDACTED__/g;
        s/(svk_)[A-Za-z0-9_\-]+/${1}__REDACTED__/g;
        s/(sk_)[A-Za-z0-9]{20,}/${1}__REDACTED__/g;
        s/(X-API-Key\s*=\s*")[A-Fa-f0-9]{20,}/${1}__REDACTED__/g;
        s/(X-API-Key:\s*)[A-Fa-f0-9]{20,}/${1}__REDACTED__/g;
      ' "$src" > "$dst"
      ;;
    *)
      cp "$src" "$dst" ;;
  esac
}

# ---------------------------------------------------------------------------
# Secret scanner — safety net over the entire repo tree (excluding .git).
# Patterns are scoped to avoid false positives on bare git SHAs.
# ---------------------------------------------------------------------------
SECRET_PATTERNS=(
  'svk_[A-Za-z0-9_-]{12,}'
  'sk_shapeup_[A-Za-z0-9]{12,}'
  'sk_[A-Za-z0-9]{20,}'
  'X-API-Key[[:space:]]*[:=][[:space:]]*"?[A-Fa-f0-9]{20,}'
)

scan() {
  local found=0 pat
  for pat in "${SECRET_PATTERNS[@]}"; do
    if grep -rEn --binary-files=without-match \
        --exclude-dir='.git' "$pat" "$REPO_ROOT" 2>/dev/null; then
      found=1
    fi
  done
  if [[ "$found" -ne 0 ]]; then
    err "✗ Possible secrets found in the repo (see above). Do NOT commit."
    return 1
  fi
  ok "✓ Scan clean: no secrets detected in the repo tree."
}

# ---------------------------------------------------------------------------
# Iterate the manifest, calling a callback for each valid entry.
#   callback MODE HOME_ABS REPO_ABS HOME_REL REPO_REL
# ---------------------------------------------------------------------------
for_each_entry() {
  local cb="$1"
  while read -r mode home_rel repo_rel _rest; do
    [[ -z "${mode:-}" || "$mode" == \#* ]] && continue
    [[ -z "${home_rel:-}" || -z "${repo_rel:-}" ]] && continue
    "$cb" "$mode" "$HOME_DIR/$home_rel" "$REPO_ROOT/$repo_rel" "$home_rel" "$repo_rel"
  done < "$MANIFEST"
}

# ---------------------------------------------------------------------------
# push: HOME -> repo
# ---------------------------------------------------------------------------
_push_entry() {
  local mode="$1" home_abs="$2" repo_abs="$3" home_rel="$4"
  if [[ ! -e "$home_abs" ]]; then
    warn "  · skipped (not in HOME): $home_rel"; return 0
  fi
  case "$mode" in
    sanitize)
      sanitize_file "$home_abs" "$repo_abs"
      printf '  %s↻ sanitize%s %s\n' "$c_dim" "$c_rst" "$home_rel"
      ;;
    sync)
      if [[ -d "$home_abs" ]]; then
        mkdir -p "$repo_abs"
        rsync -a --delete "${RSYNC_EXCLUDES[@]}" "$home_abs/" "$repo_abs/"
      else
        mkdir -p "$(dirname "$repo_abs")"
        cp "$home_abs" "$repo_abs"
      fi
      printf '  %s→ copy    %s %s\n' "$c_dim" "$c_rst" "$home_rel"
      ;;
    *) warn "  · unknown mode '$mode' for $home_rel" ;;
  esac
}

push() {
  info "push: HOME -> repo (sanitizing secrets)"
  for_each_entry _push_entry
  echo
  scan
  echo
  ok "Done. Review with: git -C \"$REPO_ROOT\" status && git -C \"$REPO_ROOT\" diff"
  info "When happy:  git -C \"$REPO_ROOT\" add -A && git -C \"$REPO_ROOT\" commit -m 'sync'"
}

# ---------------------------------------------------------------------------
# pull: repo -> HOME (additive; never deletes; sanitize -> *.from-sync)
# ---------------------------------------------------------------------------
_pull_entry() {
  local mode="$1" home_abs="$2" repo_abs="$3" home_rel="$4"
  if [[ ! -e "$repo_abs" ]]; then
    warn "  · skipped (not in repo): $home_rel"; return 0
  fi
  case "$mode" in
    sanitize)
      local target="${home_abs}.from-sync"
      mkdir -p "$(dirname "$target")"
      cp "$repo_abs" "$target"
      printf '  %s⇣ template%s %s.from-sync  %s(review and merge your secrets)%s\n' \
        "$c_dim" "$c_rst" "$home_rel" "$c_yel" "$c_rst"
      ;;
    sync)
      if [[ -d "$repo_abs" ]]; then
        mkdir -p "$home_abs"
        rsync -a "${RSYNC_EXCLUDES[@]}" "$repo_abs/" "$home_abs/"
      else
        mkdir -p "$(dirname "$home_abs")"
        cp "$repo_abs" "$home_abs"
      fi
      printf '  %s← copy    %s %s\n' "$c_dim" "$c_rst" "$home_rel"
      ;;
    *) warn "  · unknown mode '$mode' for $home_rel" ;;
  esac
}

pull() {
  info "pull: repo -> HOME (additive; secret files go to *.from-sync)"
  for_each_entry _pull_entry
  echo
  warn "Remember to re-inject secrets into settings.json / config.toml / mcp.json from your secrets store."
}

# ---------------------------------------------------------------------------
# status: diff HOME vs repo (no writes)
# ---------------------------------------------------------------------------
_status_entry() {
  local mode="$1" home_abs="$2" repo_abs="$3" home_rel="$4"
  [[ ! -e "$home_abs" ]] && { warn "  · repo only:  $home_rel"; return 0; }
  [[ ! -e "$repo_abs" ]] && { warn "  · HOME only:  $home_rel (not yet pushed)"; return 0; }
  local tmp=""
  if [[ "$mode" == "sanitize" ]]; then
    tmp="$(mktemp)"; sanitize_file "$home_abs" "$tmp"
    if diff -q "$tmp" "$repo_abs" >/dev/null 2>&1; then
      printf '  %s= same%s     %s %s(sanitized)%s\n' "$c_grn" "$c_rst" "$home_rel" "$c_dim" "$c_rst"
    else
      printf '  %s≠ differs%s  %s %s(sanitized)%s\n' "$c_yel" "$c_rst" "$home_rel" "$c_dim" "$c_rst"
    fi
    rm -f "$tmp"; return 0
  fi
  if diff -qr "${RSYNC_EXCLUDES[@]/--exclude=/--exclude }" "$home_abs" "$repo_abs" >/dev/null 2>&1 \
     || diff -qr "$home_abs" "$repo_abs" >/dev/null 2>&1; then
    printf '  %s= same%s     %s\n' "$c_grn" "$c_rst" "$home_rel"
  else
    printf '  %s≠ differs%s  %s\n' "$c_yel" "$c_rst" "$home_rel"
  fi
}

status() {
  info "status: comparing HOME vs repo (no changes made)"
  for_each_entry _status_entry
}

# ---------------------------------------------------------------------------
main() {
  command -v jq    >/dev/null || { err "Missing 'jq' (brew install jq)"; exit 1; }
  command -v rsync >/dev/null || { err "Missing 'rsync'"; exit 1; }
  case "${1:-}" in
    push)   push ;;
    pull)   pull ;;
    status) status ;;
    scan)   scan ;;
    *) cat <<EOF
sync.sh — sync Claude Code, Codex, and Cursor configs with this repo.

  ./sync.sh push     HOME -> repo (sanitizes secrets, then scans)
  ./sync.sh pull     repo -> HOME (additive; secrets -> *.from-sync)
  ./sync.sh status   diff HOME vs repo (no writes)
  ./sync.sh scan     scan repo for secrets (safety net)
EOF
      exit 1 ;;
  esac
}
main "$@"
