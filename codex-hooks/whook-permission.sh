#!/bin/bash
# whook permission hook for Codex CLI
# Install: copy to ~/.codex/hooks/ && chmod +x
# Config: add to ~/.codex/hooks.json
if [ ! -f "$HOME/.whook-enabled" ]; then
  printf '{}'
  exit 0
fi
TOKEN=$(cat "$HOME/.whook-token" 2>/dev/null)
if [ -z "$TOKEN" ]; then
  printf '{}'
  exit 0
fi
WHOOK_URL="${WHOOK_URL:-https://whook.getsmartup.ai}"
request_body=$(cat)
codex_sandbox="${CODEX_SANDBOX:-unknown}"
whook_full_access="false"
case "$codex_sandbox" in
  *danger*|*full*)
    whook_full_access="true"
    ;;
esac

request_body=$(printf '%s' "$request_body" | python3 -c '
import json
import os
import sys

full_access = len(sys.argv) > 1 and sys.argv[1].lower() == "true"
raw = sys.stdin.read()
try:
    payload = json.loads(raw)
except Exception:
    sys.stdout.write(raw)
    raise SystemExit(0)

if isinstance(payload, dict):
    payload["whook_client"] = "codex"
    payload["whook_sandbox"] = os.environ.get("CODEX_SANDBOX", "unknown")
    payload["whook_full_access"] = full_access

sys.stdout.write(json.dumps(payload, separators=(",", ":")))
' "$whook_full_access")

response=$(curl -fsS -X POST "$WHOOK_URL/api/permission" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d "$request_body" 2>/dev/null)

status=$?
if [ $status -ne 0 ] || [ -z "$response" ]; then
  printf '{}'
  exit 0
fi

normalized=$(printf '%s' "$response" | python3 -c '
import json
import sys

def emit(obj):
    sys.stdout.write(json.dumps(obj, separators=(",", ":")))

try:
    data = json.load(sys.stdin)
except Exception:
    emit({})
    raise SystemExit(0)

if not isinstance(data, dict):
    emit({})
    raise SystemExit(0)

hso = data.get("hookSpecificOutput")
if not isinstance(hso, dict):
    emit({})
    raise SystemExit(0)

event_name = hso.get("hookEventName")
if event_name == "PreToolUse":
    if hso.get("permissionDecision") == "deny":
        emit({
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "deny",
                "permissionDecisionReason": hso.get("permissionDecisionReason") or "Denied in whook",
            }
        })
    else:
        emit({})
    raise SystemExit(0)

if event_name == "PermissionRequest":
    decision = hso.get("decision")
    behavior = decision.get("behavior") if isinstance(decision, dict) else None
    if behavior == "deny":
        emit({
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "deny",
                "permissionDecisionReason": decision.get("message") or "Denied in whook",
            }
        })
    else:
        emit({})
    raise SystemExit(0)

emit({})
')

printf '%s' "$normalized"
