#!/bin/bash
set -f

# Force C locale for numbers and dates. Output is English-only by design:
#   - LC_NUMERIC=C: bash/awk printf use strtod(), which on locales like
#     ru_RU.UTF-8, de_DE.UTF-8, fr_FR.UTF-8 expects `,` as decimal
#     separator and fails to parse JSON floats (e.g. 28.5) from Claude Code.
#   - LC_TIME=C: `date` outputs month/day names in English (nov, mon, ...)
#     instead of localized strings (нояб, пн, ...).
# LC_CTYPE is left alone so UTF-8 characters (bar glyphs, bullets) render
# correctly. LC_ALL is unset first because it overrides all LC_* per POSIX.
unset LC_ALL
export LC_NUMERIC=C LC_TIME=C

# mtime helper: GNU stat uses `-c %Y`, BSD stat uses `-f %m`. We must NOT
# fall back blindly — on Linux, `stat -f` means "display file system status"
# and succeeds with verbose stdout, corrupting arithmetic later. Detect once.
if stat -c %Y / >/dev/null 2>&1; then
    _mtime() { stat -c %Y "$1" 2>/dev/null; }
else
    _mtime() { stat -f %m "$1" 2>/dev/null; }
fi

# claude-code-statusline v1.3.0
VERSION="1.3.0"
REPO="MixMe/claude-code-status-line"

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
    if [ "$pct" -ge 90 ]; then printf '%b' "$red"
    elif [ "$pct" -ge 70 ]; then printf '%b' "$yellow"
    elif [ "$pct" -ge 50 ]; then printf '%b' "$orange"
    else printf '%b' "$green"
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

    printf '%b' "${bar_color}${filled_str}${dim}${empty_str}${reset}"
}

format_epoch_as_time() {
    local epoch="$1"
    local style="${2:-time}"
    [ -z "$epoch" ] || [ "$epoch" = "null" ] || [ "$epoch" = "0" ] && return

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
        date)
            result=$(date -j -r "$epoch" +"%b %-d" 2>/dev/null | tr '[:upper:]' '[:lower:]')
            [ -z "$result" ] && result=$(date -d "@$epoch" +"%b %-d" 2>/dev/null)
            ;;
    esac
    printf "%s" "$result"
}

format_epoch_time_left() {
    local epoch="$1"
    [ -z "$epoch" ] || [ "$epoch" = "null" ] || [ "$epoch" = "0" ] && return

    local now_epoch remaining
    now_epoch=$(date +%s)
    remaining=$(( epoch - now_epoch ))
    [ "$remaining" -le 0 ] && printf "now" && return

    if [ "$remaining" -ge 86400 ]; then
        local d=$(( remaining / 86400 ))
        local h=$(( (remaining % 86400) / 3600 ))
        [ "$h" -gt 0 ] && printf '%s' "${d}d ${h}h" || printf '%s' "${d}d"
    elif [ "$remaining" -ge 3600 ]; then
        local h=$(( remaining / 3600 ))
        local m=$(( (remaining % 3600) / 60 ))
        [ "$m" -gt 0 ] && printf '%s' "${h}h ${m}m" || printf '%s' "${h}h"
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

# Shell-safe value escaper for node output
node_parse() {
    echo "$input" | node -e "
const fs=require('fs'),p=require('path');
let buf='';process.stdin.on('data',c=>buf+=c);process.stdin.on('end',()=>{
  try{
    const d=JSON.parse(buf);
    const home=process.env.HOME||process.env.USERPROFILE||'';
    const sf=p.join(home,'.claude','settings.json');
    let s={};
    try{s=JSON.parse(fs.readFileSync(sf,'utf8'))}catch{}
    const v=(k,val)=>{
      if(val===undefined||val===null) val='';
      console.log(k+'='+String(val));
    };
    v('model_name',     d.model?.display_name ?? 'Claude');
    v('ctx_size',       d.context_window?.context_window_size ?? 200000);
    v('input_tokens',   d.context_window?.current_usage?.input_tokens ?? 0);
    v('cache_create',   d.context_window?.current_usage?.cache_creation_input_tokens ?? 0);
    v('cache_read',     d.context_window?.current_usage?.cache_read_input_tokens ?? 0);
    v('ctx_pct',        d.context_window?.used_percentage ?? 0);
    v('five_pct',       d.rate_limits?.five_hour?.used_percentage ?? '');
    v('five_resets_epoch', d.rate_limits?.five_hour?.resets_at ?? '');
    v('seven_pct',      d.rate_limits?.seven_day?.used_percentage ?? '');
    v('seven_resets_epoch', d.rate_limits?.seven_day?.resets_at ?? '');
  }catch(e){process.stderr.write(e.message)}
});
"
}

TMPDIR="${TMPDIR:-${TMP:-${TEMP:-/tmp}}}"
CACHE_DIR="$TMPDIR/claude"
mkdir -p "$CACHE_DIR"

# ── Parse stdin + settings in one node call ──────────
# Defaults (shellcheck SC2154: variables assigned via declare)
model_name="Claude" ctx_size=200000 input_tokens=0 cache_create=0 cache_read=0
ctx_pct=0
five_pct="" five_resets_epoch="" seven_pct="" seven_resets_epoch=""

while IFS='=' read -r key val; do
    declare "$key=$val"
done < <(node_parse)

[ "$ctx_size" = "0" ] && ctx_size=200000

ctx_used=$(( input_tokens + cache_create + cache_read ))
used_fmt=$(format_tokens "$ctx_used")
total_fmt=$(format_tokens "$ctx_size")

# ── Model tier color ──────────────────────────────────
model_color="$blue"
case "$model_name" in
    *Haiku*) model_color="$cyan" ;;
    *Sonnet*) model_color="$blue" ;;
    *Opus*)  model_color="$magenta" ;;
esac

# ── Battery ───────────────────────────────────────────
battery_str=""
batt_pct=""

batt_raw=$(pmset -g batt 2>/dev/null | grep -Eo '[0-9]+%' | head -1)
[ -n "$batt_raw" ] && batt_pct="${batt_raw%\%}"

if [ -z "$batt_pct" ]; then
    for bat in /sys/class/power_supply/BAT{0,1,2}; do
        [ -f "$bat/capacity" ] && batt_pct=$(cat "$bat/capacity") && break
    done
fi

if [ -n "$batt_pct" ]; then
    if [ "$batt_pct" -le 20 ]; then
        battery_str="${red}battery ${batt_pct}%${reset}"
    elif [ "$batt_pct" -le 40 ]; then
        battery_str="${yellow}battery ${batt_pct}%${reset}"
    else
        battery_str="${dim}battery ${batt_pct}%${reset}"
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
            mem_str="${dim}memory $(awk "BEGIN {printf \"%.1fGB\", $free_mb/1024}") free${reset}"
        else
            mem_str="${dim}memory ${free_mb}MB free${reset}"
        fi
    fi
elif [ -f /proc/meminfo ]; then
    avail_kb=$(awk '/MemAvailable:/ {print $2}' /proc/meminfo)
    if [ -n "$avail_kb" ]; then
        if [ "$avail_kb" -ge 1048576 ]; then
            mem_str="${dim}memory $(awk "BEGIN {printf \"%.1fGB\", $avail_kb/1048576}") free${reset}"
        else
            mem_str="${dim}memory $(awk "BEGIN {printf \"%.0fMB\", $avail_kb/1024}") free${reset}"
        fi
    fi
fi

# ── Internet (cached 30s) ─────────────────────────────
net_cache="$CACHE_DIR/net-cache"
net_up=false
net_needs_refresh=true

if [ -f "$net_cache" ]; then
    net_mtime=$(_mtime "$net_cache")
    net_age=$(( $(date +%s) - net_mtime ))
    [ "$net_age" -lt 30 ] && net_needs_refresh=false && [ "$(cat "$net_cache")" = "up" ] && net_up=true
fi

if $net_needs_refresh; then
    # macOS: -t = timeout, Linux: -W = timeout, Windows: -n = count, -w = timeout(ms)
    if ping -c 1 -t 1 1.1.1.1 >/dev/null 2>&1 \
    || ping -c 1 -W 1 1.1.1.1 >/dev/null 2>&1 \
    || ping -n 1 -w 1000 1.1.1.1 >/dev/null 2>&1; then
        net_up=true; echo "up" > "$net_cache"
    else
        echo "down" > "$net_cache"
    fi
fi

if $net_up; then
    net_str="${dim}network ${green}●${reset}"
else
    net_str="${dim}network ${red}○${reset}"
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

# ── Build compact line ───────────────────────────────
ctx_color=$(color_for_pct "$ctx_pct")

if $net_up; then
    net_dot="${green}●${reset}"
else
    net_dot="${red}●${reset}"
fi

line1=""
[ -n "$local_time" ] && line1+="${dim}${local_time}${reset}${sep}"
line1+="${net_dot}"
line1+="${sep}${model_color}${model_name}${reset}"
line1+="${sep}${ctx_color}${ctx_pct}%${reset} ${dim}(${used_fmt}/${total_fmt})${reset}"

# 5-hour segment
if [ -n "$five_pct" ]; then
    five_pct_int=$(printf "%.0f" "$five_pct" 2>/dev/null || echo "0")
    five_reset=$(format_epoch_as_time "$five_resets_epoch" time)
    five_color=$(color_for_pct "$five_pct_int")
    line1+="${sep}${white}5h${reset} ${five_color}${five_pct_int}%${reset}"
    [ -n "$five_reset" ] && line1+=" ${dim}${five_reset}${reset}"
fi

# 7-day segment
if [ -n "$seven_pct" ]; then
    seven_pct_int=$(printf "%.0f" "$seven_pct" 2>/dev/null || echo "0")
    seven_reset=$(format_epoch_as_time "$seven_resets_epoch" date)
    seven_color=$(color_for_pct "$seven_pct_int")
    line1+="${sep}${white}7d${reset} ${seven_color}${seven_pct_int}%${reset}"
    [ -n "$seven_reset" ] && line1+=" ${dim}${seven_reset}${reset}"
fi

# ── Rate limits: stdin-first (zero API calls) ────────
rate_lines=""
bar_width=10

if [ -n "$five_pct" ]; then
    five_pct_int=$(printf "%.0f" "$five_pct" 2>/dev/null || echo "0")
    five_reset=$(format_epoch_as_time "$five_resets_epoch" time)
    five_left=$(format_epoch_time_left "$five_resets_epoch")
    five_bar=$(build_bar "$five_pct_int" "$bar_width")
    five_color=$(color_for_pct "$five_pct_int")

    rate_lines+="${white}5-hour${reset}  ${five_bar} ${five_color}$(printf "%3d" "$five_pct_int")%${reset}"
    if [ -n "$five_reset" ]; then
        rate_lines+=" ${dim}-> ${reset}${white}${five_reset}${reset}"
        [ -n "$five_left" ] && rate_lines+=" ${dim}(${five_left})${reset}"
    fi
fi

if [ -n "$seven_pct" ]; then
    seven_pct_int=$(printf "%.0f" "$seven_pct" 2>/dev/null || echo "0")
    seven_reset=$(format_epoch_as_time "$seven_resets_epoch" datetime)
    seven_left=$(format_epoch_time_left "$seven_resets_epoch")
    seven_bar=$(build_bar "$seven_pct_int" "$bar_width")
    seven_color=$(color_for_pct "$seven_pct_int")

    [ -n "$rate_lines" ] && rate_lines+="\n"
    rate_lines+="${white}7-day${reset}   ${seven_bar} ${seven_color}$(printf "%3d" "$seven_pct_int")%${reset}"
    if [ -n "$seven_reset" ]; then
        rate_lines+=" ${dim}-> ${reset}${white}${seven_reset}${reset}"
        [ -n "$seven_left" ] && rate_lines+=" ${dim}(${seven_left})${reset}"
    fi
fi

# ── Extra usage: API with rate-limit backoff (cached 180s) ─
get_oauth_token() {
    [ -n "$CLAUDE_CODE_OAUTH_TOKEN" ] && { echo "$CLAUDE_CODE_OAUTH_TOKEN"; return 0; }

    if command -v security >/dev/null 2>&1; then
        local blob
        blob=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null)
        if [ -n "$blob" ]; then
            local token
            token=$(echo "$blob" | node -e "let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>{try{console.log(JSON.parse(d).claudeAiOauth?.accessToken??'')}catch{console.log('')}})" 2>/dev/null)
            [ -n "$token" ] && { echo "$token"; return 0; }
        fi
    fi

    local home_dir="${HOME:-$USERPROFILE}"
    local creds_file="$home_dir/.claude/.credentials.json"
    if [ -f "$creds_file" ]; then
        local token
        token=$(node -e "try{console.log(JSON.parse(require('fs').readFileSync(process.argv[1],'utf8')).claudeAiOauth?.accessToken??'')}catch{console.log('')}" "$creds_file" 2>/dev/null)
        [ -n "$token" ] && { echo "$token"; return 0; }
    fi

    echo ""
}

extra_cache="$CACHE_DIR/statusline-extra-cache.json"
extra_lock="$CACHE_DIR/statusline-extra.lock"
extra_max_age=180

# Check lock file (rate-limit backoff)
locked=false
if [ -f "$extra_lock" ]; then
    lock_mtime=$(_mtime "$extra_lock")
    lock_age=$(( $(date +%s) - lock_mtime ))
    blocked_for=$(cat "$extra_lock" 2>/dev/null || echo "300")
    [ "$lock_age" -lt "$blocked_for" ] && locked=true
fi

extra_data=""
needs_extra_refresh=true
if [ -f "$extra_cache" ]; then
    extra_mtime=$(_mtime "$extra_cache")
    extra_age=$(( $(date +%s) - extra_mtime ))
    if [ "$extra_age" -lt "$extra_max_age" ]; then
        needs_extra_refresh=false
        extra_data=$(cat "$extra_cache" 2>/dev/null)
    fi
fi

if $needs_extra_refresh && ! $locked; then
    token=$(get_oauth_token)
    if [ -n "$token" ]; then
        http_response=$(curl -s -w "\n__HTTP_CODE__%{http_code}" --max-time 5 \
            -H "Accept: application/json" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer $token" \
            -H "anthropic-beta: oauth-2025-04-20" \
            "https://api.anthropic.com/api/oauth/usage" 2>/dev/null)

        http_code=$(echo "$http_response" | tail -1 | sed 's/__HTTP_CODE__//')
        response_body=$(echo "$http_response" | sed '$d')

        case "$http_code" in
            200)
                has_extra=$(echo "$response_body" | node -e "let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>{try{console.log(JSON.parse(d).extra_usage?'yes':'no')}catch{console.log('no')}})" 2>/dev/null)
                if [ "$has_extra" = "yes" ]; then
                    extra_data="$response_body"
                    tmp=$(mktemp "$CACHE_DIR/extra-XXXXXX")
                    echo "$response_body" > "$tmp" && mv "$tmp" "$extra_cache"
                    rm -f "$extra_lock" 2>/dev/null
                fi
                ;;
            429) echo "300" > "$extra_lock" ;;
            401|403) echo "600" > "$extra_lock" ;;
            *) echo "60" > "$extra_lock" ;;
        esac
    fi
    if [ -z "$extra_data" ] && [ -f "$extra_cache" ]; then
        extra_mtime=$(_mtime "$extra_cache")
        extra_age=$(( $(date +%s) - extra_mtime ))
        [ "$extra_age" -lt 600 ] && extra_data=$(cat "$extra_cache" 2>/dev/null)
    fi
fi

if [ -n "$extra_data" ]; then
    extra_enabled=false extra_pct=0 extra_used="0.00" extra_limit="0.00"
    eval "$(echo "$extra_data" | node -e "
let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>{
  try{
    const j=JSON.parse(d).extra_usage;
    if(!j||!j.is_enabled){console.log('extra_enabled=false');return}
    console.log('extra_enabled=true');
    console.log('extra_pct='+Math.round(j.utilization??0));
    console.log('extra_used='+(j.used_credits/100).toFixed(2));
    console.log('extra_limit='+(j.monthly_limit/100).toFixed(2));
  }catch{console.log('extra_enabled=false')}
})" 2>/dev/null)"

    if [ "$extra_enabled" = "true" ]; then
        extra_bar=$(build_bar "$extra_pct" "$bar_width")
        extra_color=$(color_for_pct "$extra_pct")

        extra_reset=$(date -v+1m -v1d +"%b %-d" 2>/dev/null | tr '[:upper:]' '[:lower:]')
        [ -z "$extra_reset" ] && extra_reset=$(date -d "$(date +%Y-%m-01) +1 month" +"%b %-d" 2>/dev/null | tr '[:upper:]' '[:lower:]')

        [ -n "$rate_lines" ] && rate_lines+="\n"
        rate_lines+="${white}extra${reset}  ${extra_bar} ${extra_color}\$${extra_used}${dim}/${reset}${white}\$${extra_limit}${reset}"
        [ -n "$extra_reset" ] && rate_lines+=" ${dim}-> ${reset}${white}${extra_reset}${reset}"

        if [ -f "$extra_cache" ]; then
            extra_mtime=$(_mtime "$extra_cache")
            extra_age=$(( $(date +%s) - extra_mtime ))
            if [ "$extra_age" -gt "$extra_max_age" ]; then
                stale_age=$(format_age "$extra_mtime")
                rate_lines+=" ${dim}(${stale_age} ago)${reset}"
            fi
        fi
    fi
fi

# ── Update check (cached 24h) ────────────────────────
update_str=""
update_cache="$CACHE_DIR/statusline-update-cache"
update_max_age=86400

update_needs_check=true
if [ -f "$update_cache" ]; then
    update_mtime=$(_mtime "$update_cache")
    update_age=$(( $(date +%s) - update_mtime ))
    [ "$update_age" -lt "$update_max_age" ] && update_needs_check=false
fi

if $update_needs_check; then
    latest_tag=$(curl -s --max-time 3 \
        "https://api.github.com/repos/${REPO}/releases/latest" 2>/dev/null \
        | node -e "let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>{try{console.log(JSON.parse(d).tag_name??'')}catch{console.log('')}})" 2>/dev/null)
    if [ -n "$latest_tag" ]; then
        latest_ver="${latest_tag#v}"
        echo "$latest_ver" > "$update_cache"
    fi
fi

if [ -f "$update_cache" ]; then
    latest_ver=$(cat "$update_cache" 2>/dev/null)
    if [ -n "$latest_ver" ] && [ "$latest_ver" != "$VERSION" ]; then
        update_str="${yellow}update ${latest_ver}${reset}"
    fi
fi

# ── Build line 3: System info ─────────────────────────
sys_parts=()
[ -n "$battery_str" ] && sys_parts+=("$battery_str")
[ -n "$mem_str" ]     && sys_parts+=("$mem_str")
[ -n "$net_str" ]     && sys_parts+=("$net_str")
[ -n "$local_time" ]  && sys_parts+=("${dim}${local_time}${reset}")
[ -n "$update_str" ]  && sys_parts+=("$update_str")

sys_line=""
for part in "${sys_parts[@]}"; do
    [ -n "$sys_line" ] && sys_line+="${sep}"
    sys_line+="${part}"
done

# ── Output ────────────────────────────────────────────
printf "%b" "$line1"

exit 0
