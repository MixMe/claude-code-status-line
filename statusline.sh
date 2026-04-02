#!/bin/bash
set -f

input=$(cat)

if [ -z "$input" ]; then
    printf "Claude"
    exit 0
fi

# ── Colors ────────────────────────────────────────────
blue='\033[38;2;0;153;255m'
orange='\033[38;2;255;176;85m'
green='\033[38;2;0;175;80m'
cyan='\033[38;2;86;182;194m'
red='\033[38;2;255;85;85m'
yellow='\033[38;2;230;200;0m'
white='\033[38;2;220;220;220m'
magenta='\033[38;2;180;140;255m'
dim='\033[2m'
reset='\033[0m'

sep=" ${dim}│${reset} "

# ── Helpers ───────────────────────────────────────────
format_tokens() {
    local num=$1
    if [ "$num" -ge 1000000 ]; then
        awk "BEGIN {printf \"%.1fm\", $num / 1000000}"
    elif [ "$num" -ge 1000 ]; then
        awk "BEGIN {printf \"%.0fk\", $num / 1000}"
    else
        printf "%d" "$num"
    fi
}

color_for_pct() {
    local pct=$1
    if [ "$pct" -ge 90 ]; then printf "$red"
    elif [ "$pct" -ge 70 ]; then printf "$yellow"
    elif [ "$pct" -ge 50 ]; then printf "$orange"
    else printf "$green"
    fi
}

build_bar() {
    local pct=$1
    local width=${2:-10}
    [ "$pct" -lt 0 ] 2>/dev/null && pct=0
    [ "$pct" -gt 100 ] 2>/dev/null && pct=100

    local filled=$(( pct * width / 100 ))
    local empty=$(( width - filled ))
    local bar_color
    bar_color=$(color_for_pct "$pct")

    local filled_str="" empty_str=""
    for ((i=0; i<filled; i++)); do filled_str+="●"; done
    for ((i=0; i<empty; i++)); do empty_str+="○"; done

    printf "${bar_color}${filled_str}${dim}${empty_str}${reset}"
}

iso_to_epoch() {
    local iso_str="$1"
    local epoch

    # GNU date (Linux)
    epoch=$(date -d "${iso_str}" +%s 2>/dev/null)
    [ -n "$epoch" ] && { echo "$epoch"; return 0; }

    # BSD date (macOS)
    local stripped="${iso_str%%.*}"
    local is_utc=false
    [[ "$iso_str" == *Z* ]] || [[ "$iso_str" == *+00:00* ]] && is_utc=true
    stripped="${stripped%%Z}"
    stripped="${stripped%%+*}"
    stripped="${stripped%%-[0-9][0-9]:[0-9][0-9]}"
    if $is_utc; then
        epoch=$(TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%S" "$stripped" +%s 2>/dev/null)
    else
        epoch=$(date -j -f "%Y-%m-%dT%H:%M:%S" "$stripped" +%s 2>/dev/null)
    fi
    [ -n "$epoch" ] && { echo "$epoch"; return 0; }

    return 1
}

format_reset_time() {
    local iso_str="$1"
    local style="${2:-date}"
    [ -z "$iso_str" ] || [ "$iso_str" = "null" ] && return

    local epoch
    epoch=$(iso_to_epoch "$iso_str")
    [ -z "$epoch" ] && return

    local result=""
    case "$style" in
        time)
            result=$(date -j -r "$epoch" +"%l:%M%p" 2>/dev/null | sed 's/^ //; s/\.//g' | tr '[:upper:]' '[:lower:]')
            [ -z "$result" ] && result=$(date -d "@$epoch" +"%l:%M%P" 2>/dev/null | sed 's/^ //; s/\.//g')
            ;;
        datetime)
            result=$(date -j -r "$epoch" +"%b %-d, %l:%M%p" 2>/dev/null | sed 's/  / /g; s/^ //; s/\.//g' | tr '[:upper:]' '[:lower:]')
            [ -z "$result" ] && result=$(date -d "@$epoch" +"%b %-d, %l:%M%P" 2>/dev/null | sed 's/  / /g; s/^ //; s/\.//g')
            ;;
        *)
            result=$(date -j -r "$epoch" +"%b %-d" 2>/dev/null | tr '[:upper:]' '[:lower:]')
            [ -z "$result" ] && result=$(date -d "@$epoch" +"%b %-d" 2>/dev/null)
            ;;
    esac
    printf "%s" "$result"
}

format_time_left() {
    local iso_str="$1"
    [ -z "$iso_str" ] || [ "$iso_str" = "null" ] && return

    local epoch
    epoch=$(iso_to_epoch "$iso_str")
    [ -z "$epoch" ] && return

    local now_epoch remaining
    now_epoch=$(date +%s)
    remaining=$(( epoch - now_epoch ))
    [ "$remaining" -le 0 ] && printf "now" && return

    if [ "$remaining" -ge 86400 ]; then
        local d=$(( remaining / 86400 ))
        local h=$(( (remaining % 86400) / 3600 ))
        [ "$h" -gt 0 ] && printf "${d}d ${h}h" || printf "${d}d"
    elif [ "$remaining" -ge 3600 ]; then
        local h=$(( remaining / 3600 ))
        local m=$(( (remaining % 3600) / 60 ))
        [ "$m" -gt 0 ] && printf "${h}h ${m}m" || printf "${h}h"
    else
        printf "%dm" $(( remaining / 60 ))
    fi
}

format_age() {
    local ts="$1"
    [ -z "$ts" ] && return
    local now age
    now=$(date +%s)
    age=$(( now - ts ))
    if [ "$age" -ge 86400 ]; then
        printf "%dd" $(( age / 86400 ))
    elif [ "$age" -ge 3600 ]; then
        printf "%dh" $(( age / 3600 ))
    elif [ "$age" -ge 60 ]; then
        printf "%dm" $(( age / 60 ))
    else
        printf "%ds" "$age"
    fi
}

mkdir -p /tmp/claude

# ── Parse JSON input ──────────────────────────────────
model_name=$(echo "$input" | jq -r '.model.display_name // "Claude"')

ctx_size=$(echo "$input" | jq -r '.context_window.context_window_size // 200000')
[ "$ctx_size" -eq 0 ] 2>/dev/null && ctx_size=200000

input_tokens=$(echo "$input" | jq -r '.context_window.current_usage.input_tokens // 0')
cache_create=$(echo "$input" | jq -r '.context_window.current_usage.cache_creation_input_tokens // 0')
cache_read=$(echo "$input" | jq -r '.context_window.current_usage.cache_read_input_tokens // 0')
ctx_used=$(( input_tokens + cache_create + cache_read ))

used_fmt=$(format_tokens "$ctx_used")
total_fmt=$(format_tokens "$ctx_size")

ctx_pct=0
[ "$ctx_size" -gt 0 ] && ctx_pct=$(( ctx_used * 100 / ctx_size ))

raw_cost=$(echo "$input" | jq -r '.cost_usd // empty')
msg_count=$(echo "$input" | jq -r 'if .messages then (.messages | length) else empty end' 2>/dev/null)

# ── Model tier color ──────────────────────────────────
model_color="$blue"
case "$model_name" in
    *Haiku*) model_color="$cyan" ;;
    *Sonnet*) model_color="$blue" ;;
    *Opus*)  model_color="$magenta" ;;
esac

# ── Cache hit rate ────────────────────────────────────
cache_hit_str=""
if [ "$ctx_used" -gt 0 ]; then
    cache_hit_pct=$(( cache_read * 100 / ctx_used ))
    cache_hit_str="${dim}cache:${cache_hit_pct}%${reset}"
fi

# ── Session cost + cost per 1k tokens ────────────────
session_cost=""
cost_per_k=""
if [ -n "$raw_cost" ] && [ "$raw_cost" != "null" ]; then
    session_cost=$(awk "BEGIN {printf \"\$%.2f\", $raw_cost}")
    if [ "$ctx_used" -gt 1000 ]; then
        cost_per_k=$(awk "BEGIN {printf \"\$%.3f/1k\", $raw_cost / $ctx_used * 1000}")
    fi
fi

# ── Session duration ──────────────────────────────────
session_duration=""
session_start=$(echo "$input" | jq -r '.session.start_time // empty')
if [ -n "$session_start" ] && [ "$session_start" != "null" ]; then
    start_epoch=$(iso_to_epoch "$session_start")
    if [ -n "$start_epoch" ]; then
        now_epoch=$(date +%s)
        elapsed=$(( now_epoch - start_epoch ))
        if [ "$elapsed" -ge 3600 ]; then
            session_duration="$(( elapsed / 3600 ))h$(( (elapsed % 3600) / 60 ))m"
        elif [ "$elapsed" -ge 60 ]; then
            session_duration="$(( elapsed / 60 ))m"
        else
            session_duration="${elapsed}s"
        fi
    fi
fi

# ── Effort + thinking + permissions ──────────────────
settings_path="$HOME/.claude/settings.json"
effort="default"
thinking_on=false
bypass_perms=false

if [ -f "$settings_path" ]; then
    effort=$(jq -r '.effortLevel // "default"' "$settings_path" 2>/dev/null)
    t=$(jq -r '.thinking // empty' "$settings_path" 2>/dev/null)
    [ "$t" = "true" ] || [ "$t" = "enabled" ] && thinking_on=true
    bp=$(jq -r '.bypassPermissions // false' "$settings_path" 2>/dev/null)
    [ "$bp" = "true" ] && bypass_perms=true
fi
# also check JSON input for thinking
t2=$(echo "$input" | jq -r '.thinking.enabled // empty' 2>/dev/null)
[ "$t2" = "true" ] && thinking_on=true

# ── Working directory & git ───────────────────────────
cwd=$(echo "$input" | jq -r '.cwd // ""')
[ -z "$cwd" ] || [ "$cwd" = "null" ] && cwd=$(pwd)
dirname=$(basename "$cwd")

git_branch=""
git_dirty_count=0
git_ahead=0
git_behind=0
git_commit_age=""

if git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git_branch=$(git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null)

    git_dirty_count=$(git -C "$cwd" --no-optional-locks status --porcelain 2>/dev/null | wc -l | tr -d ' ')

    ab=$(git -C "$cwd" rev-list --count --left-right "@{upstream}...HEAD" 2>/dev/null)
    if [ -n "$ab" ]; then
        git_behind=$(echo "$ab" | awk '{print $1}')
        git_ahead=$(echo "$ab" | awk '{print $2}')
    fi

    commit_ts=$(git -C "$cwd" log -1 --format="%ct" 2>/dev/null)
    [ -n "$commit_ts" ] && git_commit_age=$(format_age "$commit_ts")
fi

# ── Battery ───────────────────────────────────────────
battery_str=""
batt_pct=""

# macOS
batt_raw=$(pmset -g batt 2>/dev/null | grep -Eo '[0-9]+%' | head -1)
[ -n "$batt_raw" ] && batt_pct="${batt_raw%\%}"

# Linux fallback
if [ -z "$batt_pct" ]; then
    for bat in /sys/class/power_supply/BAT{0,1,2}; do
        [ -f "$bat/capacity" ] && batt_pct=$(cat "$bat/capacity") && break
    done
fi

if [ -n "$batt_pct" ]; then
    if [ "$batt_pct" -le 20 ]; then
        battery_str="${red}bat ${batt_pct}%${reset}"
    elif [ "$batt_pct" -le 40 ]; then
        battery_str="${yellow}bat ${batt_pct}%${reset}"
    else
        battery_str="${dim}bat ${batt_pct}%${reset}"
    fi
fi

# ── Memory ────────────────────────────────────────────
mem_str=""

if command -v vm_stat >/dev/null 2>&1; then
    page_size=$(sysctl -n hw.pagesize 2>/dev/null || echo 4096)
    free_p=$(vm_stat 2>/dev/null | awk '/Pages free:/ {gsub(/\./, "", $3); print $3+0}')
    inactive_p=$(vm_stat 2>/dev/null | awk '/Pages inactive:/ {gsub(/\./, "", $3); print $3+0}')
    if [ -n "$free_p" ] && [ -n "$inactive_p" ]; then
        free_mb=$(( (free_p + inactive_p) * page_size / 1024 / 1024 ))
        if [ "$free_mb" -ge 1024 ]; then
            mem_str="${dim}mem $(awk "BEGIN {printf \"%.1fgb\", $free_mb/1024}") free${reset}"
        else
            mem_str="${dim}mem ${free_mb}mb free${reset}"
        fi
    fi
elif [ -f /proc/meminfo ]; then
    avail_kb=$(awk '/MemAvailable:/ {print $2}' /proc/meminfo)
    if [ -n "$avail_kb" ]; then
        if [ "$avail_kb" -ge 1048576 ]; then
            mem_str="${dim}mem $(awk "BEGIN {printf \"%.1fgb\", $avail_kb/1048576}") free${reset}"
        else
            mem_str="${dim}mem $(awk "BEGIN {printf \"%.0fmb\", $avail_kb/1024}") free${reset}"
        fi
    fi
fi

# ── Internet (cached 30s) ─────────────────────────────
net_cache="/tmp/claude/net-cache"
net_up=false
net_needs_refresh=true

if [ -f "$net_cache" ]; then
    net_mtime=$(stat -f %m "$net_cache" 2>/dev/null || stat -c %Y "$net_cache" 2>/dev/null)
    net_age=$(( $(date +%s) - net_mtime ))
    [ "$net_age" -lt 30 ] && net_needs_refresh=false && [ "$(cat "$net_cache")" = "up" ] && net_up=true
fi

if $net_needs_refresh; then
    if ping -c 1 -t 1 1.1.1.1 >/dev/null 2>&1 || ping -c 1 -W 1 1.1.1.1 >/dev/null 2>&1; then
        net_up=true; echo "up" > "$net_cache"
    else
        echo "down" > "$net_cache"
    fi
fi

if $net_up; then
    net_str="${dim}net ${green}●${reset}"
else
    net_str="${dim}net ${red}○${reset}"
fi

# ── Local time ────────────────────────────────────────
time_format="12h"
config_file="$HOME/.config/claude-statusline/config"
[ -f "$config_file" ] && {
    fmt=$(grep '^TIME_FORMAT=' "$config_file" 2>/dev/null | cut -d= -f2)
    [ -n "$fmt" ] && time_format="$fmt"
}

if [ "$time_format" = "24h" ]; then
    local_time=$(date +"%H:%M" 2>/dev/null)
else
    local_time=$(date +"%l:%M%p" 2>/dev/null | sed 's/^ //; s/\.//g' | tr '[:upper:]' '[:lower:]')
fi

# ── Build line 1 ─────────────────────────────────────
ctx_color=$(color_for_pct "$ctx_pct")

line1="${model_color}${model_name}${reset}"
line1+="${sep}"
line1+="${ctx_color}${ctx_pct}%${reset} ${dim}(${used_fmt}/${total_fmt})${reset}"
[ -n "$cache_hit_str" ] && line1+=" ${cache_hit_str}"
if [ -n "$session_cost" ]; then
    line1+=" ${dim}${session_cost}${reset}"
    [ -n "$cost_per_k" ] && line1+=" ${dim}(${cost_per_k})${reset}"
fi
line1+="${sep}"
line1+="${cyan}${dirname}${reset}"
if [ -n "$git_branch" ]; then
    git_info="${git_branch}"
    [ "$git_dirty_count" -gt 0 ] && git_info+=" ${red}${git_dirty_count}~${reset}${green}"
    sync_str=""
    [ "$git_ahead" -gt 0 ] && sync_str+="↑${git_ahead}"
    [ "$git_behind" -gt 0 ] && sync_str+="↓${git_behind}"
    [ -n "$sync_str" ] && git_info+=" ${dim}${sync_str}${reset}${green}"
    [ -n "$git_commit_age" ] && git_info+=" ${dim}${git_commit_age}${reset}${green}"
    line1+=" ${green}(${git_info})${reset}"
fi
if [ -n "$session_duration" ]; then
    line1+="${sep}${dim}${session_duration}${reset}"
    [ -n "$msg_count" ] && line1+=" ${dim}${msg_count}msg${reset}"
fi
line1+="${sep}"
case "$effort" in
    high) line1+="${magenta}high${reset}" ;;
    low)  line1+="${dim}low${reset}" ;;
    *)    line1+="${dim}${effort}${reset}" ;;
esac
$thinking_on  && line1+=" ${cyan}thinking${reset}"
$bypass_perms && line1+=" ${red}!perms${reset}"

# ── OAuth token ───────────────────────────────────────
get_oauth_token() {
    [ -n "$CLAUDE_CODE_OAUTH_TOKEN" ] && { echo "$CLAUDE_CODE_OAUTH_TOKEN"; return 0; }

    if command -v security >/dev/null 2>&1; then
        local blob
        blob=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null)
        if [ -n "$blob" ]; then
            local token
            token=$(echo "$blob" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
            [ -n "$token" ] && [ "$token" != "null" ] && { echo "$token"; return 0; }
        fi
    fi

    local creds_file="$HOME/.claude/.credentials.json"
    if [ -f "$creds_file" ]; then
        local token
        token=$(jq -r '.claudeAiOauth.accessToken // empty' "$creds_file" 2>/dev/null)
        [ -n "$token" ] && [ "$token" != "null" ] && { echo "$token"; return 0; }
    fi

    echo ""
}

# ── Usage API (cached 60s) ────────────────────────────
cache_file="/tmp/claude/statusline-usage-cache.json"
cache_max_age=60
needs_refresh=true
usage_data=""

if [ -f "$cache_file" ]; then
    cache_mtime=$(stat -f %m "$cache_file" 2>/dev/null || stat -c %Y "$cache_file" 2>/dev/null)
    cache_age=$(( $(date +%s) - cache_mtime ))
    [ "$cache_age" -lt "$cache_max_age" ] && needs_refresh=false && usage_data=$(cat "$cache_file" 2>/dev/null)
fi

if $needs_refresh; then
    token=$(get_oauth_token)
    if [ -n "$token" ] && [ "$token" != "null" ]; then
        response=$(curl -s --max-time 5 \
            -H "Accept: application/json" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer $token" \
            -H "anthropic-beta: oauth-2025-04-20" \
            -H "User-Agent: claude-code/2.1.34" \
            "https://api.anthropic.com/api/oauth/usage" 2>/dev/null)
        if [ -n "$response" ] && echo "$response" | jq -e '.five_hour' >/dev/null 2>&1; then
            usage_data="$response"
            echo "$response" > "$cache_file"
        fi
    fi
    [ -z "$usage_data" ] && [ -f "$cache_file" ] && usage_data=$(cat "$cache_file" 2>/dev/null)
fi

# ── Build line 2: Rate limits ─────────────────────────
rate_lines=""

if [ -n "$usage_data" ] && echo "$usage_data" | jq -e . >/dev/null 2>&1; then
    bar_width=10

    five_resets_at=$(echo "$usage_data" | jq -r '.five_hour.resets_at // empty')
    five_pct=$(echo "$usage_data" | jq -r '.five_hour.utilization // 0' | awk '{printf "%.0f", $1}')
    five_reset=$(format_reset_time "$five_resets_at" time)
    five_left=$(format_time_left "$five_resets_at")
    five_bar=$(build_bar "$five_pct" "$bar_width")
    five_color=$(color_for_pct "$five_pct")

    rate_lines+="${white}5h${reset}  ${five_bar} ${five_color}$(printf "%3d" "$five_pct")%${reset}"
    if [ -n "$five_left" ] && [ -n "$five_reset" ]; then
        rate_lines+=" ${dim}(${five_left})${reset} ${dim}→ ${reset}${white}${five_reset}${reset}"
    elif [ -n "$five_reset" ]; then
        rate_lines+=" ${dim}→ ${reset}${white}${five_reset}${reset}"
    fi

    seven_resets_at=$(echo "$usage_data" | jq -r '.seven_day.resets_at // empty')
    seven_pct=$(echo "$usage_data" | jq -r '.seven_day.utilization // 0' | awk '{printf "%.0f", $1}')
    seven_reset=$(format_reset_time "$seven_resets_at" datetime)
    seven_left=$(format_time_left "$seven_resets_at")
    seven_bar=$(build_bar "$seven_pct" "$bar_width")
    seven_color=$(color_for_pct "$seven_pct")

    rate_lines+="\n${white}7d${reset}  ${seven_bar} ${seven_color}$(printf "%3d" "$seven_pct")%${reset}"
    if [ -n "$seven_left" ] && [ -n "$seven_reset" ]; then
        rate_lines+=" ${dim}(${seven_left})${reset} ${dim}→ ${reset}${white}${seven_reset}${reset}"
    elif [ -n "$seven_reset" ]; then
        rate_lines+=" ${dim}→ ${reset}${white}${seven_reset}${reset}"
    fi

    extra_enabled=$(echo "$usage_data" | jq -r '.extra_usage.is_enabled // false')
    if [ "$extra_enabled" = "true" ]; then
        extra_pct=$(echo "$usage_data" | jq -r '.extra_usage.utilization // 0' | awk '{printf "%.0f", $1}')
        extra_used=$(echo "$usage_data" | jq -r '.extra_usage.used_credits // 0' | awk '{printf "%.2f", $1/100}')
        extra_limit=$(echo "$usage_data" | jq -r '.extra_usage.monthly_limit // 0' | awk '{printf "%.2f", $1/100}')
        extra_bar=$(build_bar "$extra_pct" "$bar_width")
        extra_color=$(color_for_pct "$extra_pct")

        extra_reset=$(date -v+1m -v1d +"%b %-d" 2>/dev/null | tr '[:upper:]' '[:lower:]')
        [ -z "$extra_reset" ] && extra_reset=$(date -d "$(date +%Y-%m-01) +1 month" +"%b %-d" 2>/dev/null | tr '[:upper:]' '[:lower:]')

        rate_lines+="\n${white}extra${reset}  ${extra_bar} ${extra_color}\$${extra_used}${dim}/${reset}${white}\$${extra_limit}${reset}"
        [ -n "$extra_reset" ] && rate_lines+=" ${dim}→ ${reset}${white}${extra_reset}${reset}"
    fi
fi

# ── Build line 3: System info ─────────────────────────
sys_parts=()
[ -n "$battery_str" ] && sys_parts+=("$battery_str")
[ -n "$mem_str" ]     && sys_parts+=("$mem_str")
[ -n "$net_str" ]     && sys_parts+=("$net_str")
[ -n "$local_time" ]  && sys_parts+=("${dim}${local_time}${reset}")

sys_line=""
for part in "${sys_parts[@]}"; do
    [ -n "$sys_line" ] && sys_line+="${sep}"
    sys_line+="${part}"
done

# ── Output ────────────────────────────────────────────
printf "%b" "$line1"
[ -n "$rate_lines" ] && printf "\n\n%b" "$rate_lines"
[ -n "$sys_line" ]   && printf "\n\n%b" "$sys_line"

exit 0
