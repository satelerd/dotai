#!/bin/bash

# Read JSON input from stdin
input=$(cat)

# Colors (ANSI 256)
RESET="\033[0m"
BOLD="\033[1m"

# Colors
CYAN="\033[38;5;81m"
PURPLE="\033[38;5;141m"
GRAY="\033[38;5;245m"
BLUE="\033[38;5;75m"
GREEN="\033[38;5;82m"
RED="\033[38;5;203m"

# Context colors
CTX_GREEN="\033[38;5;82m"
CTX_YELLOW="\033[38;5;220m"
CTX_ORANGE="\033[38;5;208m"
CTX_RED="\033[38;5;196m"

# Extract info
model=$(echo "$input" | jq -r '.model.display_name // .model.id // "unknown"')
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // "."')

# Shorten model name
case "$model" in
  *"opus"*|*"Opus"*) model_short="opus" ;;
  *"sonnet"*|*"Sonnet"*) model_short="sonnet" ;;
  *"haiku"*|*"Haiku"*) model_short="haiku" ;;
  *) model_short="claude" ;;
esac

# Calculate context usage
# Note: JSON only has message tokens. We add estimated overhead for:
# - System prompt (~4k), System tools (~15k), MCP tools (~26k), Memory files (~1k)
# - Partial autocompact buffer
# Total overhead: ~70k (adjust if your MCP setup differs)
# Feature request: https://github.com/anthropics/claude-code/issues/16524
CONTEXT_OVERHEAD=70000

usage=$(echo "$input" | jq '.context_window.current_usage // empty')
size=$(echo "$input" | jq '.context_window.context_window_size // 200000')

if [ -n "$usage" ] && [ "$usage" != "null" ]; then
    input_tokens=$(echo "$usage" | jq '.input_tokens // 0')
    cache_create=$(echo "$usage" | jq '.cache_creation_input_tokens // 0')
    cache_read=$(echo "$usage" | jq '.cache_read_input_tokens // 0')
    messages=$((input_tokens + cache_create + cache_read))
    current=$((messages + CONTEXT_OVERHEAD))
    if [ "$size" -gt 0 ]; then
        pct=$((current * 100 / size))
    else
        pct=0
    fi
else
    pct=0
fi

# Session-relative percentage calculation
# Store initial context value per session and calculate relative progress
max_pct=80  # autocompact threshold
max_tokens=$((size * max_pct / 100))

# Use transcript_path as session identifier
session_id=$(echo "$input" | jq -r '.transcript_path // ""' | md5 2>/dev/null || echo "$input" | jq -r '.transcript_path // ""' | md5sum 2>/dev/null | cut -d' ' -f1)
cache_dir="/tmp/claude-statusline"
mkdir -p "$cache_dir" 2>/dev/null

if [ -n "$session_id" ]; then
    cache_file="$cache_dir/$session_id"

    # Store initial context value on first run of this session
    if [ ! -f "$cache_file" ]; then
        echo "$current" > "$cache_file"
    fi

    initial_tokens=$(cat "$cache_file" 2>/dev/null || echo "$current")

    # Calculate session-relative percentage
    # 0% = initial context, 100% = max (autocompact threshold)
    available_range=$((max_tokens - initial_tokens))
    used_range=$((current - initial_tokens))

    if [ "$available_range" -gt 0 ] && [ "$used_range" -ge 0 ]; then
        pct_scaled=$((used_range * 100 / available_range))
        [ "$pct_scaled" -gt 100 ] && pct_scaled=100
        [ "$pct_scaled" -lt 0 ] && pct_scaled=0
    else
        pct_scaled=0
    fi
else
    # Fallback to absolute percentage if no session id
    if [ "$pct" -ge "$max_pct" ]; then
        pct_scaled=100
    else
        pct_scaled=$((pct * 100 / max_pct))
    fi
fi

# Smooth gradient colors (ANSI 256)
# 0-15%: bright green (46)
# 15-30%: green (82)
# 30-45%: lime (118)
# 45-55%: yellow-green (154)
# 55-65%: yellow (220)
# 65-75%: orange (214)
# 75-85%: dark orange (208)
# 85-95%: red-orange (202)
# 95-100%: red (196)

if [ "$pct_scaled" -lt 15 ]; then
    ctx_color="\033[38;5;46m"
elif [ "$pct_scaled" -lt 30 ]; then
    ctx_color="\033[38;5;82m"
elif [ "$pct_scaled" -lt 45 ]; then
    ctx_color="\033[38;5;118m"
elif [ "$pct_scaled" -lt 55 ]; then
    ctx_color="\033[38;5;154m"
elif [ "$pct_scaled" -lt 65 ]; then
    ctx_color="\033[38;5;220m"
elif [ "$pct_scaled" -lt 75 ]; then
    ctx_color="\033[38;5;214m"
elif [ "$pct_scaled" -lt 85 ]; then
    ctx_color="\033[38;5;208m"
elif [ "$pct_scaled" -lt 95 ]; then
    ctx_color="\033[38;5;202m"
else
    ctx_color="\033[38;5;196m"
fi

# Get session cost
cost=$(echo "$input" | jq -r '.cost.total_cost_usd // 0' 2>/dev/null)
if [ -z "$cost" ] || [ "$cost" = "null" ] || [ "$cost" = "0" ]; then
    cost_display="\$0.00"
else
    cost_display="\$$(printf '%.2f' "$cost")"
fi

# Get directory name
dir_name=$(basename "$cwd")

# Get git info
git_info=""
git_changes=""
if git -C "$cwd" rev-parse --git-dir > /dev/null 2>&1; then
    branch=$(git -C "$cwd" --no-optional-locks branch --show-current 2>/dev/null)
    [ -z "$branch" ] && branch="detached"

    if ! git -C "$cwd" --no-optional-locks diff-index --quiet HEAD -- 2>/dev/null; then
        git_status="*"
    else
        git_status=""
    fi
    git_info="${branch}${git_status}"

    # Get insertions/deletions
    diff_stats=$(git -C "$cwd" --no-optional-locks diff --shortstat 2>/dev/null)
    if [ -n "$diff_stats" ]; then
        insertions=$(echo "$diff_stats" | grep -oE '[0-9]+ insertion' | grep -oE '[0-9]+' || echo "0")
        deletions=$(echo "$diff_stats" | grep -oE '[0-9]+ deletion' | grep -oE '[0-9]+' || echo "0")
        [ -z "$insertions" ] && insertions="0"
        [ -z "$deletions" ] && deletions="0"
        git_changes="+${insertions} -${deletions}"
    fi
fi

# Build progress bar (10 chars) - using scaled percentage
filled=$((pct_scaled / 10))
[ "$filled" -gt 10 ] && filled=10
empty=$((10 - filled))
bar=""
for ((i=0; i<filled; i++)); do bar+="█"; done
for ((i=0; i<empty; i++)); do bar+="░"; done

# Get session duration from cost.total_duration_ms
duration_ms=$(echo "$input" | jq -r '.cost.total_duration_ms // 0' 2>/dev/null)
if [ -n "$duration_ms" ] && [ "$duration_ms" != "null" ] && [ "$duration_ms" != "0" ]; then
    elapsed=$((duration_ms / 1000))
    mins=$((elapsed / 60))
    secs=$((elapsed % 60))
    if [ "$mins" -gt 0 ]; then
        session_time="${mins}m${secs}s"
    else
        session_time="${secs}s"
    fi
else
    session_time=""
fi

# Count messages and tool calls from transcript
transcript_path=$(echo "$input" | jq -r '.transcript_path // ""' 2>/dev/null)
tool_count=0
msg_count=0
if [ -n "$transcript_path" ] && [ -f "$transcript_path" ]; then
    tool_count=$(grep -o '"type":"tool_use"' "$transcript_path" 2>/dev/null | wc -l | tr -d ' ')
    # Count only real user messages (type=user where content is a string, not array with tool_result)
    msg_count=$(jq -c 'select(.type == "user" and (.message.content | type) == "string")' "$transcript_path" 2>/dev/null | wc -l | tr -d ' ')
fi

# ═══════════════════════════════════════════════════════════════════
# LINE 1: dir on branch with model | +123 -45
# ═══════════════════════════════════════════════════════════════════

line1="${CYAN}${dir_name}${RESET}"

if [ -n "$git_info" ]; then
    line1="${line1} ${GRAY}on${RESET} ${PURPLE}${git_info}${RESET}"
fi

line1="${line1} ${GRAY}with${RESET} ${BLUE}${model_short}${RESET}"

if [ -n "$git_changes" ]; then
    line1="${line1}  ${GRAY}|${RESET}  ${GREEN}+${insertions}${RESET} ${RED}-${deletions}${RESET}"
fi

# ═══════════════════════════════════════════════════════════════════
# LINE 2: 5m23s | 42t | $1.23 | ████████░░ 64%
# ═══════════════════════════════════════════════════════════════════

line2=""

if [ -n "$session_time" ]; then
    line2="${GRAY}${session_time}${RESET}  ${GRAY}|${RESET}  "
fi

# Add message and tool count (Xm Xt)
line2="${line2}${CYAN}${msg_count}m ${tool_count}t${RESET}  ${GRAY}|${RESET}  "

line2="${line2}${GREEN}${cost_display}${RESET}  ${GRAY}|${RESET}  ${ctx_color}${bar} ${pct_scaled}%${RESET}"

# Output
printf "%b\n" "$line1"
printf "%b" "$line2"
