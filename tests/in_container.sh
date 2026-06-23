#!/usr/bin/env bash
# teleport e2e — runs inside the sandbox container as user `tester`.
# Source and target are this same machine (ssh to self): the full path runs for
# real — packaging, ssh, rsync, receive (clone / worktree / bundle), transcript
# placement, tmux. Asserts behaviour, not just "it ran".
set -u

TP=/opt/dotai/teleport.sh
HOST=tester@localhost
export DOTAI_TP_BASE="$HOME/code"
export DOTAI_TP_TMUX=1   # tmux default is now OFF; force it on so these scenarios exercise the tmux path
export GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"

PASS=0; FAIL=0
ok(){ printf '   \033[32m✓\033[0m %s\n' "$*"; PASS=$((PASS+1)); }
no(){ printf '   \033[31m✗\033[0m %s\n' "$*"; FAIL=$((FAIL+1)); }
hd(){ printf '\n\033[1m── %s ──\033[0m\n' "$*"; }

rp(){   python3 -c 'import os,sys;print(os.path.realpath(sys.argv[1]))' "$1"; }
enc(){  "$TP" _encode "$1"; }   # use the REAL encode_cwd (anchored by test U below), not a copy of the rule

reset_all(){
  tmux kill-server >/dev/null 2>&1 || true
  rm -rf "$HOME/code" "$HOME/work" "$HOME/origins" "$HOME/.claude/projects" "$HOME/.cache/dotai-tp"
  mkdir -p "$HOME/code" "$HOME/work"
}

# init_origin <name>  → sets ORIGIN_URL to a seeded bare repo (commit "C0").
init_origin(){
  local n="$1"
  local o="$HOME/origins/$n.git"
  local t
  rm -rf "$o"; mkdir -p "$HOME/origins"
  git init -q --bare "$o"
  t="$(mktemp -d)"
  git clone -q "tester@localhost:$o" "$t" 2>/dev/null   # empty-repo warning is expected
  ( cd "$t"; echo "# $n" > README.md; echo "base" > base.txt
    git add -A; git commit -qm C0; git push -q origin HEAD:main )
  rm -rf "$t"
  ORIGIN_URL="tester@localhost:$o"
}

# make_session <dir> <sid>  → fake Claude transcript anchored at dir's realpath.
# Line 2 carries the old cwd inside PROSE on purpose: the receiver must rewrite
# only the structured `cwd` field, never blanket-replace text.
make_session(){
  local dir="$1" sid="$2" pd rpdir
  pd="$HOME/.claude/projects/$(enc "$dir")"; rpdir="$(rp "$dir")"
  mkdir -p "$pd"
  python3 - "$pd/$sid.jsonl" "$rpdir" <<'PY'
import json, sys
f, cwd = sys.argv[1], sys.argv[2]
with open(f, "w") as o:
    o.write(json.dumps({"type": "summary", "cwd": cwd}) + "\n")
    o.write(json.dumps({"type": "user", "cwd": cwd,
                        "message": {"content": f"I am working in {cwd}"}}) + "\n")
    o.write(json.dumps({"type": "assistant", "cwd": cwd}) + "\n")
PY
}

send(){ ( cd "$1" && "$TP" send "$HOST" --session "$2" ); }   # <repo-dir> <sid>

# bytematch <src> <dst> <label> — working trees identical ignoring git metadata.
bytematch(){
  if diff -r --exclude=.git "$1" "$2" >/dev/null 2>&1; then ok "$3 working tree byte-matches source"
  else no "$3 working tree DIFFERS from source"; diff -r --exclude=.git "$1" "$2" 2>&1 | head -8; fi
}

# transcript_ok <workdir> <sid> <srcdir>
transcript_ok(){
  local wd="$1" sid="$2" src="$3" f
  f="$HOME/.claude/projects/$(enc "$wd")/$sid.jsonl"
  [[ -f "$f" ]] || { no "transcript not placed at $f"; return; }
  if python3 -c 'import json,sys;rows=[json.loads(l) for l in open(sys.argv[1]) if l.strip()];sys.exit(0 if all(r.get("cwd")==sys.argv[2] for r in rows if "cwd" in r) else 1)' "$f" "$(rp "$wd")"; then
    ok "transcript cwd rewritten → $(rp "$wd")"
  else no "transcript cwd not fully rewritten"; fi
  if grep -q "I am working in $(rp "$src")" "$f"; then ok "prose untouched (no blanket path replace)"
  else no "prose was mangled (blanket replace)"; fi
}

tmux_alive(){ if tmux ls 2>/dev/null | grep -q '^tp-'; then ok "tmux session is live (claude -r …)"; else no "no live tmux session"; fi; }

SID="11111111-1111-1111-1111-111111111111"

# ===========================================================================
hd "U · encode_cwd matches Claude Code's project-dir rule (NON-circular)"
# Expected value is HARDCODED — not computed from encode_cwd itself. Anchors the
# cwd->project-dir rule (every non-alnum char -> "-", runs NOT collapsed) to the
# real Claude Code behaviour, verified against an actual project dir. If this
# fails, a teleported session won't be found by `claude -r` on the target — which
# is exactly the bug the byte-for-byte e2e checks missed (they were circular).
u_got="$("$TP" _encode '/srv/x/code/.tp/my_repo/2026-06-22-2334')"
u_exp='-srv-x-code--tp-my-repo-2026-06-22-2334'
[ "$u_got" = "$u_exp" ] && ok "encode_cwd → $u_got" || no "encode_cwd MISMATCH: got '$u_got' want '$u_exp'"

# ===========================================================================
hd "A · fresh clone, pushed HEAD → clone into base and work there"
reset_all; init_origin alpha
git clone -q "$ORIGIN_URL" "$HOME/work/alpha"
( cd "$HOME/work/alpha"; echo "edit" >> README.md; echo "untracked" > extra.txt )
make_session "$HOME/work/alpha" "$SID"
send "$HOME/work/alpha" "$SID" >/dev/null 2>&1 || no "A send failed"
WD="$HOME/code/alpha"
[[ -d "$WD/.git" ]] && ok "fresh clone created at $WD" || no "no clone at $WD"
bytematch "$HOME/work/alpha" "$WD" "A"
transcript_ok "$WD" "$SID" "$HOME/work/alpha"
tmux_alive

# ===========================================================================
hd "B · repo already cloned → dedicated worktree, main checkout untouched"
reset_all; init_origin bravo
git clone -q "$ORIGIN_URL" "$HOME/code/bravo"          # pre-existing main checkout
M_HEAD="$(git -C "$HOME/code/bravo" rev-parse HEAD)"
M_BR="$(git -C "$HOME/code/bravo" rev-parse --abbrev-ref HEAD)"
git clone -q "$ORIGIN_URL" "$HOME/work/bravo"
( cd "$HOME/work/bravo"; echo "edit-b" >> README.md; echo "u-b" > extra.txt )
make_session "$HOME/work/bravo" "$SID"
send "$HOME/work/bravo" "$SID" >/dev/null 2>&1 || no "B send failed"
WT="$(ls -d "$HOME"/code/.tp/bravo/*/ 2>/dev/null | head -1)"; WT="${WT%/}"
[[ -n "$WT" && -e "$WT" ]] && ok "worktree carved at $WT" || no "no worktree under base/.tp/bravo"
# main must be pristine: same HEAD, same branch, clean status
[[ "$(git -C "$HOME/code/bravo" rev-parse HEAD)" == "$M_HEAD" ]] && ok "main HEAD unchanged" || no "main HEAD moved"
[[ "$(git -C "$HOME/code/bravo" rev-parse --abbrev-ref HEAD)" == "$M_BR" ]] && ok "main branch unchanged ($M_BR)" || no "main branch changed"
[[ -z "$(git -C "$HOME/code/bravo" status --porcelain)" ]] && ok "main working tree clean (not obstructed)" || no "main working tree dirty"
[[ -n "$WT" ]] && bytematch "$HOME/work/bravo" "$WT" "B"
[[ -n "$WT" ]] && transcript_ok "$WT" "$SID" "$HOME/work/bravo"
tmux_alive

# ===========================================================================
hd "C · existing clone has a different basename → match by URL, not name"
reset_all; init_origin charlie
git clone -q "$ORIGIN_URL" "$HOME/code/weird-name"     # same origin, other dir name
git clone -q "$ORIGIN_URL" "$HOME/work/charlie"
( cd "$HOME/work/charlie"; echo "edit-c" >> README.md )
make_session "$HOME/work/charlie" "$SID"
send "$HOME/work/charlie" "$SID" >/dev/null 2>&1 || no "C send failed"
[[ ! -e "$HOME/code/charlie" ]] && ok "no stray clone named after the repo" || no "stray clone base/charlie appeared"
WT="$(ls -d "$HOME"/code/.tp/charlie/*/ 2>/dev/null | head -1)"; WT="${WT%/}"
[[ -n "$WT" && -e "$WT" ]] && ok "worktree carved at $WT" || no "no worktree carved"
if [[ -n "$WT" ]] && git -C "$HOME/code/weird-name" worktree list 2>/dev/null | grep -qF "$(rp "$WT")"; then
  ok "worktree belongs to the URL-matched checkout (weird-name)"
else no "worktree not attached to weird-name"; fi
[[ -n "$WT" ]] && bytematch "$HOME/work/charlie" "$WT" "C"

# ===========================================================================
hd "D · local-only commit (not on origin) → travels via bundle"
reset_all; init_origin delta
git clone -q "$ORIGIN_URL" "$HOME/work/delta"
( cd "$HOME/work/delta"
  echo "feature" >> base.txt; git commit -qam "C1 local only"   # never pushed
  echo "wip" >> README.md; echo "u-d" > extra.txt )             # + uncommitted
S_HEAD="$(git -C "$HOME/work/delta" rev-parse HEAD)"
make_session "$HOME/work/delta" "$SID"
send "$HOME/work/delta" "$SID" >/dev/null 2>&1 || no "D send failed"
WD="$HOME/code/delta"
[[ -d "$WD/.git" ]] && ok "fresh clone created at $WD" || no "no clone at $WD"
D_HEAD="$(git -C "$WD" rev-parse HEAD 2>/dev/null || echo none)"
[[ "$D_HEAD" == "$S_HEAD" ]] && ok "target HEAD == local-only commit ${S_HEAD:0:8} (bundle worked)" || no "HEAD mismatch: $D_HEAD vs $S_HEAD"
bytematch "$HOME/work/delta" "$WD" "D"

# ===========================================================================
hd "F · repo already cloned AND HEAD is local-only → worktree off bundled commit"
# The flagship real case: you've worked on the mini's checkout before, now you
# close the laptop lid with unpushed commits. Crosses worktree + bundle.
reset_all; init_origin foxtrot
git clone -q "$ORIGIN_URL" "$HOME/code/foxtrot"        # pre-existing main checkout @ C0
F_MHEAD="$(git -C "$HOME/code/foxtrot" rev-parse HEAD)"
git clone -q "$ORIGIN_URL" "$HOME/work/foxtrot"
( cd "$HOME/work/foxtrot"
  echo "feature-f" >> base.txt; git commit -qam "C1 local only"   # never pushed
  echo "wip-f" >> README.md; echo "u-f" > extra.txt )             # + uncommitted
F_SHEAD="$(git -C "$HOME/work/foxtrot" rev-parse HEAD)"
make_session "$HOME/work/foxtrot" "$SID"
send "$HOME/work/foxtrot" "$SID" >/dev/null 2>&1 || no "F send failed"
WT="$(ls -d "$HOME"/code/.tp/foxtrot/*/ 2>/dev/null | head -1)"; WT="${WT%/}"
[[ -n "$WT" && -e "$WT" ]] && ok "worktree carved at $WT" || no "no worktree carved"
F_WHEAD="$([[ -n "$WT" ]] && git -C "$WT" rev-parse HEAD 2>/dev/null || echo none)"
[[ "$F_WHEAD" == "$F_SHEAD" ]] && ok "worktree HEAD == local-only commit ${F_SHEAD:0:8} (bundle into existing clone worked)" || no "worktree HEAD mismatch: $F_WHEAD vs $F_SHEAD"
[[ "$(git -C "$HOME/code/foxtrot" rev-parse HEAD)" == "$F_MHEAD" ]] && ok "main HEAD unchanged" || no "main HEAD moved"
[[ -z "$(git -C "$HOME/code/foxtrot" status --porcelain)" ]] && ok "main working tree clean (not obstructed)" || no "main working tree dirty"
[[ -n "$WT" ]] && bytematch "$HOME/work/foxtrot" "$WT" "F"

# ===========================================================================
hd "G · --into <name> routes to a custom base, relative to target home"
reset_all; init_origin golf
git clone -q "$ORIGIN_URL" "$HOME/work/golf"
( cd "$HOME/work/golf"; echo "edit-g" >> README.md; echo "u-g" > extra.txt )
make_session "$HOME/work/golf" "$SID"
( cd "$HOME/work/golf" && "$TP" send "$HOST" --session "$SID" --into projects ) >/dev/null 2>&1 || no "G send failed"
WD="$HOME/projects/golf"
[[ -d "$WD/.git" ]] && ok "repo landed under ~/projects (bare name → target \$HOME)" || no "repo not under ~/projects"
[[ ! -e "$HOME/code/golf" ]] && ok "default base ~/code left untouched" || no "leaked into ~/code"
bytematch "$HOME/work/golf" "$WD" "G"
transcript_ok "$WD" "$SID" "$HOME/work/golf"

# ===========================================================================
hd "E · no git repo + same session twice → no-clobber guard holds"
reset_all
mkdir -p "$HOME/work/echo"; echo "note" > "$HOME/work/echo/note.txt"   # not a repo
make_session "$HOME/work/echo" "$SID"
send "$HOME/work/echo" "$SID" >/dev/null 2>&1 && ok "1st placement (no-URL) ok" || no "1st placement failed"
DST="$HOME/.claude/projects/$(enc "$HOME/code/echo")/$SID.jsonl"
SUM_BEFORE="$(md5sum "$DST" 2>/dev/null | cut -d' ' -f1)"
if send "$HOME/work/echo" "$SID" >/dev/null 2>&1; then no "2nd placement should have been refused"
else ok "2nd placement refused (no-clobber)"; fi
[[ "$(md5sum "$DST" 2>/dev/null | cut -d' ' -f1)" == "$SUM_BEFORE" ]] && ok "existing transcript left intact" || no "existing transcript was modified"

# ===========================================================================
printf '\n\033[1m═══ %d passed · %d failed ═══\033[0m\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
