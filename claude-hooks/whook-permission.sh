#!/bin/bash
if [ ! -f "$HOME/.whook-enabled" ]; then exit 0; fi
TOKEN=$(cat "$HOME/.whook-token" 2>/dev/null)
if [ -z "$TOKEN" ]; then exit 0; fi
curl -s -X POST https://whook.getsmartup.ai/api/permission \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d "$(cat)"
