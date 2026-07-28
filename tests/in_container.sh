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
  rm -rf "$HOME/code" "$HOME/work" "$HOME/origins" "$HOME/.claude/projects" "$HOME/.codex" "$HOME/.cache/dotai-tp"
  rm -f /tmp/fake-codex-invocations
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

tmux_alive(){ if tmux ls 2>/dev/null | grep -q '^tp-'; then ok "tmux session is live"; else no "no live tmux session"; fi; }

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
hd "H · pushed HEAD → no full-history bundle in the payload (regression)"
# Regression for the stall bug: `git bundle create … HEAD` (no --not --remotes)
# packed the repo's ENTIRE history — every blob — into the payload, ballooning to
# hundreds of MB on a real repo and dragging the transfer to a crawl. With HEAD
# already on origin the local-only range is empty, so NO bundle must be produced.
# The big blob below would make a full-history bundle fat and obvious; we assert
# the real payload the engine rsynced to the target carries no commits.bundle.
reset_all; init_origin hotel
git clone -q "$ORIGIN_URL" "$HOME/work/hotel"
( cd "$HOME/work/hotel"
  head -c 300000 /dev/urandom > big.bin                          # ~300KB blob…
  git add big.bin; git commit -qm "big blob"; git push -q origin HEAD:main )  # …pushed → HEAD on origin
( cd "$HOME/work/hotel"; echo "wip-h" >> README.md )             # only uncommitted, no local commit
make_session "$HOME/work/hotel" "$SID"
send "$HOME/work/hotel" "$SID" >/dev/null 2>&1 || no "H send failed"
H_BUNDLE="$(ls "$HOME"/.cache/dotai-tp/*/commits.bundle 2>/dev/null | head -1)"
[[ -z "$H_BUNDLE" ]] && ok "no commits.bundle in payload (pushed HEAD → empty range)" \
  || no "full-history bundle leaked: $(du -h "$H_BUNDLE" 2>/dev/null | cut -f1)"
WD="$HOME/code/hotel"                                            # receive still resolves HEAD via origin
[[ "$(git -C "$WD" rev-parse HEAD 2>/dev/null)" == "$(git -C "$HOME/work/hotel" rev-parse HEAD)" ]] \
  && ok "target HEAD resolved via origin (no bundle needed)" || no "target HEAD mismatch without bundle"

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
hd "K · cursor harness → session dir travels, lands under the new cwd hash"
# Plumbing test: packaging, transfer, placement, no-clobber. The chats-bucket
# hash itself is exercised through the REAL cursor_hash_cwd on both sides, so
# this is circular on the hash rule — grounding that rule against a real
# cursor-agent session is a separate, on-machine check (same story as test U).
reset_all; init_origin kilo
rm -rf "$HOME/.cursor"
chash(){ "$TP" _cursor_hash "$1"; }
CSID="22222222-2222-2222-2222-222222222222"
git clone -q "$ORIGIN_URL" "$HOME/work/kilo"
( cd "$HOME/work/kilo"; echo "edit-k" >> README.md )
SRC_CD="$HOME/.cursor/chats/$(chash "$HOME/work/kilo")/$CSID"
mkdir -p "$SRC_CD"
head -c 4096 /dev/urandom > "$SRC_CD/store.db"    # opaque payload: must travel byte-identical
( cd "$HOME/work/kilo" && "$TP" send "$HOST" --session "$CSID" --harness cursor ) >/dev/null 2>&1 || no "K send failed"
WD="$HOME/code/kilo"
[[ -d "$WD/.git" ]] && ok "repo cloned at $WD" || no "no clone at $WD"
bytematch "$HOME/work/kilo" "$WD" "K"
DSTD="$HOME/.cursor/chats/$(chash "$WD")/$CSID"
[[ -f "$DSTD/store.db" ]] && ok "cursor session placed under the new cwd's bucket" || no "session dir missing: $DSTD"
cmp -s "$SRC_CD/store.db" "$DSTD/store.db" && ok "store.db byte-identical" || no "store.db differs after transfer"
# no-clobber (mirrors E): outside git the workdir is deterministic, so the same
# session sent twice lands on the SAME bucket — the second must be refused.
mkdir -p "$HOME/work/kilo2"; echo "note" > "$HOME/work/kilo2/note.txt"
SRC2="$HOME/.cursor/chats/$(chash "$HOME/work/kilo2")/$CSID"
mkdir -p "$SRC2"; head -c 512 /dev/urandom > "$SRC2/store.db"
( cd "$HOME/work/kilo2" && "$TP" send "$HOST" --session "$CSID" --harness cursor ) >/dev/null 2>&1 \
  && ok "1st placement (no-URL) ok" || no "1st cursor placement failed"
DST2="$HOME/.cursor/chats/$(chash "$HOME/code/kilo2")/$CSID/store.db"
SUM2="$(md5sum "$DST2" 2>/dev/null | cut -d' ' -f1)"
if ( cd "$HOME/work/kilo2" && "$TP" send "$HOST" --session "$CSID" --harness cursor ) >/dev/null 2>&1; then
  no "2nd cursor placement should have been refused"
else ok "2nd placement refused (cursor no-clobber)"; fi
[[ "$(md5sum "$DST2" 2>/dev/null | cut -d' ' -f1)" == "$SUM2" ]] && ok "existing store.db left intact" || no "existing store.db was modified"

# ===========================================================================
hd "L · codex harness → rollout travels, session_meta cwd rewritten, no-clobber"
# In the sandbox source and target share \$HOME, and a codex rollout lands at
# the SAME path it came from (sessions/YYYY/MM/DD/<basename>) — so a full send
# to self MUST be refused by the no-clobber guard. The source command runs from
# a DIFFERENT cwd to prove an explicit UUID uses session_meta.cwd as truth.
# Placement + rewrite are then asserted by running receive against a payload,
# including the app-bundled Codex fallback and actual tmux resume invocation.
reset_all; init_origin lima
CXSID="33333333-3333-3333-3333-333333333333"
CXBASE="rollout-2026-07-01T12-00-00-$CXSID.jsonl"
git clone -q "$ORIGIN_URL" "$HOME/work/lima"
make_codex_session(){   # <dir> — fake rollout anchored at dir's realpath
  local rpdir; rpdir="$(rp "$1")"
  mkdir -p "$HOME/.codex/sessions/2026/07/01"
  python3 - "$HOME/.codex/sessions/2026/07/01/$CXBASE" "$rpdir" "$CXSID" <<'PY'
import json, sys
f, cwd, sid = sys.argv[1:4]
with open(f, "w") as o:
    o.write(json.dumps({"timestamp": "t0", "type": "session_meta",
                        "payload": {"id": sid, "cwd": cwd, "cli_version": "test"}}) + "\n")
    o.write(json.dumps({"timestamp": "t1", "type": "event_msg",
                        "payload": {"content": f"I am working in {cwd}"}}) + "\n")
PY
}
make_codex_session "$HOME/work/lima"
CXSRC="$HOME/.codex/sessions/2026/07/01/$CXBASE"
CXSUM="$(md5sum "$CXSRC" | cut -d' ' -f1)"
if ( cd "$HOME/work" && "$TP" send "$HOST" --session "$CXSID" --harness codex ) >/dev/null 2>&1; then
  no "send-to-self should have been refused (same rollout path)"
else ok "send-to-self refused (codex no-clobber over the full ssh path)"; fi
[[ "$(md5sum "$CXSRC" | cut -d' ' -f1)" == "$CXSUM" ]] && ok "original rollout left intact" || no "original rollout was modified"
CXMAN="$(ls -t "$HOME"/.cache/dotai-tp/*/tp.json 2>/dev/null | head -1)"
if python3 -c 'import json,os,sys;d=json.load(open(sys.argv[1]));sys.exit(0 if d["session_id"]==sys.argv[2] and d["source_cwd"]==os.path.realpath(sys.argv[3]) else 1)' "$CXMAN" "$CXSID" "$HOME/work/lima"; then
  ok "explicit UUID canonicalized and session_meta cwd used as source truth"
else no "explicit UUID used the invoking shell cwd or wrong session id"; fi
if ( cd "$HOME/work" && "$TP" send "$HOST" --session "${CXSID:0:8}" --harness codex ) >/dev/null 2>&1; then
  no "partial Codex UUID should have been rejected"
else ok "partial Codex UUID rejected"; fi
# Now the real-target shape: payload in hand, original gone, receive places it.
PAY="$(mktemp -d)"
mv "$CXSRC" "$PAY/$CXBASE"
cp "$TP" "$PAY/teleport.sh"
python3 - "$PAY/tp.json" "$(rp "$HOME/work/lima")" "$CXSID" <<'PY'
import json, sys
out, src_cwd, sid = sys.argv[1:4]
json.dump({"version": 1, "harness": "codex", "session_id": sid, "source_cwd": src_cwd,
           "repo": {"url": "", "branch": "", "head": "", "has_patch": False,
                    "has_untracked": False, "has_bundle": False},
           "repo_name": "lima"}, open(out, "w"))
PY
bash "$PAY/teleport.sh" receive "$PAY" >/dev/null 2>&1 || no "L receive failed"
CXDST="$HOME/.codex/sessions/2026/07/01/$CXBASE"
[[ -f "$CXDST" ]] && ok "rollout placed under sessions/YYYY/MM/DD" || no "rollout not placed at $CXDST"
if python3 -c 'import json,sys;d=json.loads(open(sys.argv[1]).readline());sys.exit(0 if d["payload"]["cwd"]==sys.argv[2] else 1)' "$CXDST" "$(rp "$HOME/code/lima")"; then
  ok "session_meta cwd rewritten → $(rp "$HOME/code/lima")"
else no "session_meta cwd not rewritten"; fi
grep -q "I am working in $(rp "$HOME/work/lima")" "$CXDST" && ok "prose untouched (no blanket path replace)" || no "prose was mangled"
grep -q "^resume $CXSID$" /tmp/fake-codex-invocations 2>/dev/null \
  && ok "app-bundled Codex fallback launched resume with the full UUID" \
  || no "Codex resume was not launched through the app-bundled binary"
tmux_alive
if bash "$PAY/teleport.sh" receive "$PAY" >/dev/null 2>&1; then no "2nd receive should have been refused"
else ok "2nd receive refused (codex no-clobber)"; fi

# Strict metadata guard: a payload whose manifest cwd disagrees with
# session_meta must fail without leaving a destination rollout.
BADSID="44444444-4444-4444-4444-444444444444"
BADBASE="rollout-2026-07-01T12-30-00-$BADSID.jsonl"
BADPAY="$(mktemp -d)"
python3 - "$BADPAY/$BADBASE" "$(rp "$HOME/work/lima")" "$BADSID" <<'PY'
import json, sys
path, cwd, sid = sys.argv[1:4]
with open(path, "w") as out:
    out.write(json.dumps({"timestamp": "t0", "type": "session_meta",
                          "payload": {"id": sid, "cwd": cwd}}) + "\n")
PY
cp "$TP" "$BADPAY/teleport.sh"
python3 - "$BADPAY/tp.json" "$HOME/work/not-lima" "$BADSID" <<'PY'
import json, sys
out, wrong_cwd, sid = sys.argv[1:4]
json.dump({"version": 1, "harness": "codex", "session_id": sid, "source_cwd": wrong_cwd,
           "repo": {"url": "", "branch": "", "head": "", "has_patch": False,
                    "has_untracked": False, "has_bundle": False},
           "repo_name": "lima-bad"}, open(out, "w"))
PY
if bash "$BADPAY/teleport.sh" receive "$BADPAY" >/dev/null 2>&1; then
  no "mismatched session_meta cwd should have failed"
else ok "mismatched session_meta cwd rejected"; fi
[[ ! -e "$HOME/.codex/sessions/2026/07/01/$BADBASE" ]] \
  && ok "failed metadata validation left no rollout behind" \
  || no "failed metadata validation left a rollout behind"
rm -rf "$BADPAY"
rm -rf "$PAY"

# ===========================================================================
printf '\n\033[1m═══ %d passed · %d failed ═══\033[0m\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
