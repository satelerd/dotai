#!/bin/bash

CLAUDE_DIR="$HOME/.claude"

current_mode() {
  if [ -f "$CLAUDE_DIR/settings.json" ]; then
    if grep -q '"CLAUDE_CODE_USE_BEDROCK"' "$CLAUDE_DIR/settings.json" 2>/dev/null; then
      echo "bedrock"
    else
      echo "pro"
    fi
  else
    echo "none"
  fi
}

case "$1" in
  pro)
    cp "$CLAUDE_DIR/settings.pro.json" "$CLAUDE_DIR/settings.json"
    echo "✅ Switched to Claude Pro subscription mode"
    echo "   (asegúrate de estar logueado: 'claude' → /login)"
    ;;
  bedrock)
    cp "$CLAUDE_DIR/settings.bedrock.json" "$CLAUDE_DIR/settings.json"
    echo "💳 Switched to Bedrock API mode"
    ;;
  status|"")
    echo "Current mode: $(current_mode)"
    echo "Usage: claude-mode [pro|bedrock|status]"
    ;;
  *)
    echo "Unknown mode: $1"
    echo "Usage: claude-mode [pro|bedrock|status]"
    exit 1
    ;;
esac
