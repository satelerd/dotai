#!/bin/bash
# SmartVOC API - Base wrapper script
# Handles authentication, base URL, and HTTP requests
#
# Usage:
#   source smartvoc-api.sh
#   smartvoc_get "/get-all-smartvoc-clients"
#   smartvoc_post "/create-smartvoc-client" '{"clientName":"Test"}'
#   smartvoc_put "/update-smartvoc-client-details" '{"clientName":"Test",...}'

set -euo pipefail

SMARTVOC_API_URL="${SMARTVOC_API_URL:-https://ops.dev.smartvoc.ai}"
SMARTVOC_API_KEY="${SMARTVOC_API_KEY:-}"

if [ -z "$SMARTVOC_API_KEY" ]; then
  echo "ERROR: SMARTVOC_API_KEY environment variable is not set" >&2
  echo "Set it with: export SMARTVOC_API_KEY=your-api-key" >&2
  exit 1
fi

_smartvoc_request() {
  local method="$1"
  local endpoint="$2"
  local data="${3:-}"

  local response http_code body

  response=$(curl -s -w "\n%{http_code}" \
    -X "$method" \
    -H "X-API-Key: $SMARTVOC_API_KEY" \
    -H "Content-Type: application/json" \
    ${data:+-d "$data"} \
    "${SMARTVOC_API_URL}${endpoint}")

  http_code=$(echo "$response" | tail -1)
  body=$(echo "$response" | sed '$d')

  if [ "$http_code" -ge 400 ]; then
    echo "ERROR: HTTP $http_code" >&2
    echo "$body" >&2
    return 1
  fi

  echo "$body"
}

smartvoc_get() {
  _smartvoc_request GET "$1"
}

smartvoc_post() {
  _smartvoc_request POST "$1" "${2:-}"
}

smartvoc_put() {
  _smartvoc_request PUT "$1" "${2:-}"
}

# Pretty-print JSON if jq is available
smartvoc_format() {
  if command -v jq &>/dev/null; then
    jq .
  else
    cat
  fi
}
