#!/bin/bash

# Ultra-optimized statusline v3 - minimal subprocess spawning
# Strategy: ONE jq call extracts everything, pure bash for the rest

input=$(cat)
cache_dir="/tmp/claude-statusline"
[[ -d "$cache_dir" ]] || mkdir -p "$cache_dir"

# SINGLE jq call extracts all values with | delimiter
read_data=$(echo "$input" | jq -r '
  [
    (.model.display_name // .model.id // "unknown"),
    (.workspace.current_dir // .cwd // "."),
    ((.cost.total_cost_usd // 0) * 100 | floor),
    ((.cost.total_duration_ms // 0) | floor),
    (.context_window.current_usage.input_tokens // 0),
    (.context_window.current_usage.cache_creation_input_tokens // 0),
    (.context_window.current_usage.cache_read_input_tokens // 0),
    (.context_window.context_window_size // 200000),
    (.transcript_path // "")
  ] | join("|")
')

# Parse with IFS (no subprocess)
IFS='|' read -r model cwd cost duration_ms input_tokens cache_create cache_read ctx_size transcript_path <<< "$read_data"

# Model shortname with version (pure bash)
case "$model" in
    *[Oo]pus*4.6*|*[Oo]pus*4-6*) m="opus 4.6";;
    *[Oo]pus*4.5*|*[Oo]pus*4-5*) m="opus 4.5";;
    *[Oo]pus*4.1*|*[Oo]pus*4-1*) m="opus 4.1";;
    *[Oo]pus*4*) m="opus 4";;
    *[Oo]pus*) m="opus";;
    *[Ss]onnet*4.5*|*[Ss]onnet*4-5*) m="sonnet 4.5";;
    *[Ss]onnet*4*) m="sonnet 4";;
    *[Ss]onnet*3.7*|*[Ss]onnet*3-7*) m="sonnet 3.7";;
    *[Ss]onnet*3.5*|*[Ss]onnet*3-5*) m="sonnet 3.5";;
    *[Ss]onnet*) m="sonnet";;
    *[Hh]aiku*4.5*|*[Hh]aiku*4-5*) m="haiku 4.5";;
    *[Hh]aiku*3.5*|*[Hh]aiku*3-5*) m="haiku 3.5";;
    *[Hh]aiku*) m="haiku";;
    *) m="claude";;
esac

# Context calculation (pure bash math)
messages=$((input_tokens + cache_create + cache_read))
current=$((messages + 38000))
max_tokens=$((ctx_size * 77 / 100))

# Session tracking
if [[ -n "$transcript_path" ]]; then
    session_id="${transcript_path: -32}"
    session_id="${session_id//\//_}"
else
    session_id="default_$$"
fi
cache_file="$cache_dir/$session_id"

if [[ -f "$cache_file" ]]; then
    read initial < "$cache_file"
    ((current < initial)) && { echo "$current" > "$cache_file"; initial=$current; }
else
    echo "$current" > "$cache_file"
    initial=$current
fi

avail=$((max_tokens - initial))
used=$((current - initial))
if ((avail > 5000 && used >= 0)); then
    pct=$((used * 100 / avail))
elif ((avail <= 0)); then
    # Already over limit at session start
    pct=100
else
    pct=0
fi
((pct > 100)) && pct=100
((pct < 0)) && pct=0

# Color (cascading comparison)
((pct >= 95)) && c=196 || { ((pct >= 85)) && c=202 || { ((pct >= 75)) && c=208 || { ((pct >= 65)) && c=214 || { ((pct >= 55)) && c=220 || { ((pct >= 45)) && c=154 || { ((pct >= 30)) && c=118 || { ((pct >= 15)) && c=82 || c=46; }; }; }; }; }; }; }

# Cost display (pure bash)
((cost == 0)) && cost_str='$0.00' || printf -v cost_str '$%d.%02d' $((cost/100)) $((cost%100))

# Directory name (pure bash, handle trailing slash)
cwd="${cwd%/}"
dir="${cwd##*/}"

# Git - cached for 2s
git_info="" ins="" del=""
if [[ -d "$cwd/.git" ]]; then
    gc="$cache_dir/g_${cwd//\//_}"
    now=$(date +%s)

    if [[ -f "$gc" ]]; then
        read ct cb ci cd < "$gc"
        ((now - ct < 2)) && { git_info="$cb"; ins="$ci"; del="$cd"; }
    fi

    if [[ -z "$git_info" ]]; then
        git_info=$(git -C "$cwd" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null || echo "detached")
        git -C "$cwd" --no-optional-locks diff-index --quiet HEAD -- 2>/dev/null || {
            git_info+="*"
            ds=$(git -C "$cwd" --no-optional-locks diff --shortstat 2>/dev/null)
            [[ "$ds" =~ ([0-9]+)\ insertion ]] && ins="${BASH_REMATCH[1]}"
            [[ "$ds" =~ ([0-9]+)\ deletion ]] && del="${BASH_REMATCH[1]}"
        }
        echo "$now $git_info ${ins:-0} ${del:-0}" > "$gc"
    fi
fi

# Progress bar (lookup table)
bars=("░░░░░░░░░░" "█░░░░░░░░░" "██░░░░░░░░" "███░░░░░░░" "████░░░░░░" "█████░░░░░" "██████░░░░" "███████░░░" "████████░░" "█████████░" "██████████")
f=$((pct / 10)); ((f > 10)) && f=10; ((f < 0)) && f=0
bar="${bars[$f]}"

# Session time (pure bash)
st=""
if ((duration_ms > 0)); then
    e=$((duration_ms / 1000))
    mm=$((e / 60)); ss=$((e % 60))
    ((mm > 0)) && st="${mm}m${ss}s" || st="${ss}s"
fi

# Transcript - sync first time, async updates
msg=0 tool=0 combo=0 err=false
if [[ -n "$transcript_path" && -f "$transcript_path" ]]; then
    tc="$cache_dir/${session_id}_c"
    sz=$(stat -f%z "$transcript_path" 2>/dev/null || stat -c%s "$transcript_path" 2>/dev/null)

    do_count() {
        local t=$(grep -c '"type":"tool_use"' "$transcript_path" 2>/dev/null || echo 0)
        local m=$(jq -c 'select(.type=="user" and (.message.content|type)=="string")' "$transcript_path" 2>/dev/null | wc -l | tr -d ' ')
        local combo_info=$(tail -50 "$transcript_path" 2>/dev/null | jq -s '
            [.[]|select(.type=="user")|.message.content|select(type=="array")|.[]|select(.type=="tool_result")]
            | reverse | {
                streak: (reduce .[] as $r ({n:0,stop:false}; if .stop then . elif ($r.is_error//false) then .stop=true else .n+=1 end) | .n),
                recent_err: ((.[0].is_error//false) and length>0)
            }' 2>/dev/null)
        local co=$(echo "$combo_info" | jq -r '.streak//0')
        local re=$([[ $(echo "$combo_info" | jq -r '.recent_err') == "true" ]] && echo 1 || echo 0)
        echo "$sz ${m:-0} ${t:-0} ${co:-0} ${re:-0}"
    }

    if [[ -f "$tc" ]]; then
        read csz cmsg ctool ccombo cerr < "$tc"
        if [[ "$csz" == "$sz" ]]; then
            # Cache is fresh
            msg=$cmsg; tool=$ctool; combo=$ccombo
            [[ "$cerr" == "1" ]] && err=true
        else
            # Cache exists but stale - use old values, update async
            msg=$cmsg; tool=$ctool; combo=$ccombo
            [[ "$cerr" == "1" ]] && err=true
            ( do_count > "$tc" ) &
        fi
    else
        # No cache - do sync count (first time)
        read csz msg tool combo cerr <<< "$(do_count)"
        echo "$csz $msg $tool $combo $cerr" > "$tc"
        [[ "$cerr" == "1" ]] && err=true
    fi
fi

# Kaomoji
$err && kao="(；′⌒\`)" || { ((combo>=15)) && kao="(ノ≧∀≦)ノ" || { ((combo>=10)) && kao="(ノ≧∀≦)ノ" || { ((combo>=5)) && kao="(๑˃ᴗ˂)ﻭ" || { ((pct>=95)) && kao="(×_×;)" || { ((pct>=85)) && kao="(－.－) zzZ" || { ((pct>=70)) && kao="(´-ω-\`)" || { ((pct>=50)) && kao="(´･ω･\`)" || { ((pct<10)) && kao="(•̀ᴗ•́)و" || kao="( ´ω\` )"; }; }; }; }; }; }; }; }

# Kubectl context - cached for 5s
k8s_ctx=""
k8s_ns=""
k8s_cloud=""
kc="$cache_dir/kubectl_ctx"
now=$(date +%s)

if [[ -f "$kc" ]]; then
    read kct kctx kns kcloud < "$kc"
    ((now - kct < 5)) && { k8s_ctx="$kctx"; k8s_ns="$kns"; k8s_cloud="$kcloud"; }
fi

if [[ -z "$k8s_ctx" ]]; then
    k8s_raw=$(kubectl config current-context 2>/dev/null || echo "")
    if [[ -n "$k8s_raw" ]]; then
        # Format kubectl context
        if [[ "$k8s_raw" == *"arn:aws:eks"* ]]; then
            # Extract cluster name from AWS ARN
            cluster_name="${k8s_raw##*/}"
            k8s_ctx="aws/$cluster_name"
            k8s_cloud="aws"
        elif [[ "$k8s_raw" == *"azure"* || "$k8s_raw" == *"aks"* || "$k8s_raw" == Smart-server* ]]; then
            # Azure context - use raw name for Smart-server contexts
            k8s_ctx="az/$k8s_raw"
            k8s_cloud="az"
        else
            # Keep original for other contexts
            k8s_ctx="$k8s_raw"
            k8s_cloud="other"
        fi

        # Get namespace
        k8s_ns=$(kubectl config view --minify -o jsonpath='{..namespace}' 2>/dev/null || echo "")
        [[ -z "$k8s_ns" ]] && k8s_ns="default"
    fi
    echo "$now $k8s_ctx $k8s_ns $k8s_cloud" > "$kc"
fi

# Output - Line 1: {directory} on {branch}  |  +X -Y  |  {kaomoji}
R='\033[0m'
printf '\033[38;5;75m%s\033[0m' "$dir"
[[ -n "$git_info" ]] && printf ' \033[38;5;245mon\033[0m \033[38;5;141m%s\033[0m' "$git_info"
printf '  \033[38;5;245m|\033[0m  '
[[ -n "$ins" || -n "$del" ]] && printf '\033[38;5;82m+%s\033[0m \033[38;5;203m-%s\033[0m' "${ins:-0}" "${del:-0}" || printf '\033[38;5;82m+0\033[0m \033[38;5;203m-0\033[0m'
printf '  \033[38;5;245m|\033[0m  \033[38;5;245m%s\033[0m\n' "$kao"

# Line 2: {aws|az}/{cluster}  |  ns:{namespace}  |  {model}
# Colors: AWS=208 (orange), Azure=39 (blue), Other=220 (yellow)
if [[ -n "$k8s_ctx" ]]; then
    case "$k8s_cloud" in aws) k8s_color=173;; az) k8s_color=39;; *) k8s_color=220;; esac
    printf '\033[38;5;%sm%s\033[0m  \033[38;5;245m|\033[0m  ' "$k8s_color" "$k8s_ctx"
fi
[[ -n "$k8s_ns" ]] && printf '\033[38;5;245mns:%s\033[0m  \033[38;5;245m|\033[0m  ' "$k8s_ns"
printf '\033[38;5;173m%s\033[0m\n' "$m"

# Line 3: {time}  |  {messages}m {tools}t  |  {cost}  |  {bar} {percentage}
[[ -n "$st" ]] && printf '\033[38;5;245m%s\033[0m  \033[38;5;245m|\033[0m  ' "$st"
printf '\033[38;5;245m%sm %st\033[0m  \033[38;5;245m|\033[0m  ' "$msg" "$tool"
printf '\033[38;5;82m%s\033[0m  \033[38;5;245m|\033[0m  \033[38;5;%sm%s %s%%\033[0m' "$cost_str" "$c" "$bar" "$pct"
