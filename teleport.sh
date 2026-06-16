#!/usr/bin/env bash
#
# teleport.sh — move a live AI-harness conversation from this machine to another.
#
# The classic case: you're working in Claude Code on your laptop, you have to
# leave, you close the lid. Run `dotai tp` and the *same conversation* (full
# history) plus the repo it lives in lands on your other machine (e.g. a Mac
# mini), ready to resume — optionally inside a tmux session you can reattach to
# from your phone over mosh.
#
# Usage:
#   teleport.sh send    [HOST] [--session ID] [--harness claude] [--no-tmux]
#   teleport.sh receive <payload-dir>            # internal: runs on the target
#
# v1 supports Claude Code only (Codex detection prints a friendly "not yet").
# The transcript is the deliverable; repo state is best-effort.
#
# Config (gitignored .dotai.conf in the repo root, or ~/.dotai.conf):
#   DOTAI_TP_HOST="user@host"     # ssh target (Tailscale name/IP works)
#   DOTAI_TP_BASE="$HOME/code"    # where repos get cloned on the target
#   DOTAI_TP_TMUX=1               # 1 = land the session inside tmux on target

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

c_red=$'\033[31m'; c_grn=$'\033[32m'; c_yel=$'\033[33m'; c_blu=$'\033[34m'; c_dim=$'\033[2m'; c_rst=$'\033[0m'
info() { printf '%s%s%s\n' "$c_blu" "$*" "$c_rst"; }
ok()   { printf '%s%s%s\n' "$c_grn" "$*" "$c_rst"; }
warn() { printf '%s%s%s\n' "$c_yel" "$*" "$c_rst" >&2; }
err()  { printf '%s%s%s\n' "$c_red" "$*" "$c_rst" >&2; }
die()  { err "$*"; exit 1; }

# Load config (first match wins): repo .dotai.conf, then ~/.dotai.conf.
for cfg in "$REPO_ROOT/.dotai.conf" "$HOME/.dotai.conf"; do
  # shellcheck disable=SC1090
  [[ -f "$cfg" ]] && { source "$cfg"; break; }
done
: "${DOTAI_TP_HOST:=}"
: "${DOTAI_TP_BASE:=$HOME/code}"
: "${DOTAI_TP_TMUX:=1}"

need() { command -v "$1" >/dev/null 2>&1 || die "Missing dependency: $1"; }

# realpath that works even if the path is a symlink (macOS /tmp -> /private/tmp).
realpath_p() { python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$1"; }

# Claude Code encodes a project dir as its resolved cwd with every "/" -> "-".
encode_cwd() { printf '%s' "$(realpath_p "$1")" | sed 's:/:-:g'; }

# ===========================================================================
# SEND  (runs on the source machine, e.g. the laptop)
# ===========================================================================
cmd_send() {
  need python3; need rsync; need ssh; need git
  local host="" session="" harness="claude" use_tmux="$DOTAI_TP_TMUX"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --session) session="$2"; shift 2 ;;
      --harness) harness="$2"; shift 2 ;;
      --no-tmux) use_tmux=0; shift ;;
      --tmux)    use_tmux=1; shift ;;
      -*) die "Unknown flag: $1" ;;
      *) host="$1"; shift ;;
    esac
  done
  [[ -z "$host" ]] && host="$DOTAI_TP_HOST"
  [[ -z "$host" ]] && die "No target host. Pass one (dotai tp send user@host) or set DOTAI_TP_HOST in .dotai.conf"

  if [[ "$harness" == "codex" ]]; then
    die "Codex teleport isn't supported yet (v1 is Claude Code only). Tracked as a follow-up."
  fi
  [[ "$harness" != "claude" ]] && die "Unknown harness: $harness (only 'claude' in v1)"

  local cwd; cwd="$(realpath_p "$PWD")"
  local proj_dir="$HOME/.claude/projects/$(encode_cwd "$cwd")"
  [[ -d "$proj_dir" ]] || die "No Claude Code sessions for this directory ($cwd).\n  Are you in the repo where the conversation happened?"

  # Pick the session: explicit --session, else the most recently modified one.
  if [[ -z "$session" ]]; then
    session="$(ls -t "$proj_dir"/*.jsonl 2>/dev/null | head -1 | xargs -I{} basename {} .jsonl)"
    [[ -z "$session" ]] && die "No .jsonl sessions found in $proj_dir"
  fi
  local sfile="$proj_dir/$session.jsonl"
  [[ -f "$sfile" ]] || die "Session not found: $sfile"

  info "▶ Teleporting session ${session:0:8}… from $cwd"

  # ---- Repo state (best-effort) ----------------------------------------
  local in_git=0 url="" branch="" head="" repo_name="" toplevel=""
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    in_git=1
    toplevel="$(git rev-parse --show-toplevel)"
    repo_name="$(basename "$toplevel")"
    branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo HEAD)"
    head="$(git rev-parse HEAD 2>/dev/null || echo '')"
    url="$(git remote get-url origin 2>/dev/null || echo '')"
    [[ -z "$url" ]] && warn "  · no 'origin' remote — target won't be able to clone; transcript still moves."
  else
    warn "  · not a git repo — moving the transcript only."
    repo_name="$(basename "$cwd")"
  fi

  # ---- Stage payload OUTSIDE the repo (transcripts can hold secrets) ----
  local stage; stage="$(mktemp -d "${TMPDIR:-/tmp}/dotai-tp.XXXXXX")"
  # guard with :- so the EXIT trap is safe under `set -u` after the local goes out of scope
  trap 'rm -rf "${stage:-}"' EXIT
  cp "$sfile" "$stage/session.jsonl"
  cp "$REPO_ROOT/teleport.sh" "$stage/teleport.sh"   # self-contained receiver

  local has_patch=false has_untracked=false
  if [[ "$in_git" == 1 ]]; then
    if git diff HEAD --binary > "$stage/uncommitted.patch" 2>/dev/null && [[ -s "$stage/uncommitted.patch" ]]; then
      has_patch=true
    else rm -f "$stage/uncommitted.patch"; fi
    # Untracked (respecting .gitignore)
    if git ls-files --others --exclude-standard -z | grep -qz .; then
      git ls-files --others --exclude-standard -z \
        | tar --null -czf "$stage/untracked.tar.gz" -T - 2>/dev/null && has_untracked=true
    fi
  fi

  python3 - "$stage/tp.json" "$harness" "$session" "$cwd" "$url" "$branch" "$head" "$repo_name" "$has_patch" "$has_untracked" <<'PY'
import json, sys
(_, out, harness, sid, cwd, url, branch, head, repo_name, has_patch, has_untracked) = sys.argv
json.dump({
    "version": 1, "harness": harness, "session_id": sid, "source_cwd": cwd,
    "repo": {"url": url, "branch": branch, "head": head,
             "has_patch": has_patch == "true", "has_untracked": has_untracked == "true"},
    "repo_name": repo_name,
}, open(out, "w"), indent=2)
PY

  # ---- Transfer + run receiver on the target ---------------------------
  local stamp remote
  stamp="$(date +%Y%m%d_%H%M%S)_$$"
  remote=".cache/dotai-tp/$stamp"
  info "▶ Sending to $host:~/$remote"
  ssh "$host" "mkdir -p \"\$HOME/$remote\""
  rsync -a "$stage"/ "$host:$remote/"
  echo
  # The receiver prints the resume instructions; we just relay its output.
  ssh "$host" "DOTAI_TP_TMUX=$use_tmux bash \"\$HOME/$remote/teleport.sh\" receive \"\$HOME/$remote\""
}

# ===========================================================================
# RECEIVE  (runs on the target machine, e.g. the mini)
# ===========================================================================
cmd_receive() {
  need python3; need git
  local payload="${1:-}"
  [[ -d "$payload" ]] || die "receive: payload dir not found: $payload"
  local man="$payload/tp.json"
  [[ -f "$man" ]] || die "receive: manifest missing: $man"

  # Pull manifest fields.
  eval "$(python3 - "$man" <<'PY'
import json, sys, shlex
d = json.load(open(sys.argv[1]))
r = d.get("repo", {})
def out(k, v): print(f'{k}={shlex.quote(str(v))}')
out("HARNESS", d.get("harness", "claude"))
out("SID", d.get("session_id", ""))
out("SRC_CWD", d.get("source_cwd", ""))
out("REPO_NAME", d.get("repo_name", ""))
out("URL", r.get("url", ""))
out("BRANCH", r.get("branch", ""))
out("HEAD", r.get("head", ""))
out("HAS_PATCH", "1" if r.get("has_patch") else "")
out("HAS_UNTRACKED", "1" if r.get("has_untracked") else "")
PY
)"

  [[ "$HARNESS" == "claude" ]] || die "receive: unsupported harness '$HARNESS'"

  local base; base="$(eval echo "${DOTAI_TP_BASE}")"
  local target="$base/$REPO_NAME"

  # ---- Repo: clone fresh, or reuse an existing checkout (never clobber) -
  if [[ -n "$URL" ]]; then
    if [[ ! -d "$target/.git" ]]; then
      info "▶ Cloning $URL → $target"
      mkdir -p "$base"
      git clone "$URL" "$target" >/dev/null 2>&1 || die "clone failed: $URL"
      ( cd "$target"
        git fetch origin >/dev/null 2>&1 || true
        git checkout "$BRANCH" >/dev/null 2>&1 || git checkout -b "$BRANCH" >/dev/null 2>&1 || true
        [[ -n "$HEAD" ]] && git reset --hard "$HEAD" >/dev/null 2>&1 || true
        if [[ -n "$HAS_PATCH" && -f "$payload/uncommitted.patch" ]]; then
          git apply --whitespace=nowarn "$payload/uncommitted.patch" 2>/dev/null \
            && ok "  · applied uncommitted changes" || warn "  · patch didn't apply cleanly (resolve manually): $payload/uncommitted.patch"
        fi
        [[ -n "$HAS_UNTRACKED" && -f "$payload/untracked.tar.gz" ]] && tar -xzf "$payload/untracked.tar.gz" -C "$target" 2>/dev/null && ok "  · restored untracked files"
      )
    else
      warn "▶ $target already exists — leaving it untouched (no clobber)."
      warn "  · Your local checkout is preserved. Carried patch (if any): $payload/uncommitted.patch"
    fi
  else
    target="$(eval echo "${DOTAI_TP_BASE}")/$REPO_NAME"
    mkdir -p "$target"
    warn "▶ No repo URL in payload — placing the transcript against $target only."
  fi

  local tcwd; tcwd="$(realpath_p "$target")"

  # ---- Place the transcript (additive; refuse to clobber) --------------
  local enc proj dst
  enc="$(encode_cwd "$tcwd")"
  proj="$HOME/.claude/projects/$enc"
  dst="$proj/$SID.jsonl"
  mkdir -p "$proj"
  if [[ -f "$dst" ]]; then
    die "A session with id $SID already exists on the target:\n  $dst\n  Refusing to overwrite (no clobber). Delete it first if you really want to replace it."
  fi
  python3 - "$payload/session.jsonl" "$dst" "$SRC_CWD" "$tcwd" <<'PY'
import json, sys
src, dst, old, new = sys.argv[1:5]
n = 0
with open(src) as f, open(dst, "w") as o:
    for line in f:
        line = line.rstrip("\n")
        if not line:
            continue
        try:
            d = json.loads(line)
        except Exception:
            o.write(line + "\n"); continue
        # Rewrite ONLY the structured cwd field — never blanket-replace prose.
        if d.get("cwd") == old:
            d["cwd"] = new; n += 1
        o.write(json.dumps(d) + "\n")
print(f"  · transcript placed ({n} cwd refs rewritten)")
PY

  # ---- Pre-accept the trust dialog for this dir (additive merge) --------
  python3 - "$HOME/.claude.json" "$tcwd" <<'PY' 2>/dev/null || true
import json, sys
p, cwd = sys.argv[1], sys.argv[2]
try:
    d = json.load(open(p))
except Exception:
    sys.exit(0)
projs = d.setdefault("projects", {})
entry = projs.setdefault(cwd, {})
if not entry.get("hasTrustDialogAccepted"):
    entry["hasTrustDialogAccepted"] = True
    json.dump(d, open(p, "w"), indent=2)
PY

  # ---- Optionally land it in tmux for mosh reattach --------------------
  echo
  ok "✓ Session ${SID:0:8}… ready on this machine."
  local resume="cd $(printf '%q' "$tcwd") && claude -r $SID"
  if [[ "${DOTAI_TP_TMUX:-1}" == "1" ]] && command -v tmux >/dev/null 2>&1; then
    local sess="tp-$REPO_NAME"
    if tmux has-session -t "$sess" 2>/dev/null; then sess="tp-$REPO_NAME-$(date +%H%M%S)"; fi
    tmux new-session -d -s "$sess" -c "$tcwd" "claude -r $SID"
    ok "  Running in tmux session: $sess"
    echo "  Reattach here:        tmux attach -t $sess"
    echo "  From your phone:      mosh <thishost> -- tmux attach -t $sess"
  else
    echo "  Resume with:          $resume"
  fi
}

# ===========================================================================
main() {
  local sub="${1:-}"; shift || true
  case "$sub" in
    send)    cmd_send "$@" ;;
    receive) cmd_receive "$@" ;;
    *) cat <<EOF
teleport.sh — move a live AI conversation to another machine.

  teleport.sh send [HOST] [--session ID] [--no-tmux]
      Package the current Claude Code session + repo state and send it.
      HOST defaults to DOTAI_TP_HOST from .dotai.conf.

  teleport.sh receive <payload-dir>
      (internal) Runs on the target; clones the repo and places the session.

Run from inside the repo where the conversation is happening.
EOF
      exit 1 ;;
  esac
}
main "$@"
