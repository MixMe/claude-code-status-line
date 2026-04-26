#!/bin/bash
# Disable pathname expansion (globbing) process-wide. The script has no
# intentional glob patterns anywhere — every `[A'|'[B'` inside case
# statements is quoted so globbing is irrelevant for correctness — but
# disabling it defensively prevents surprises if a future edit prints an
# unquoted value containing `*`, `?`, or `[` into a path-like context.
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

# claude-code-statusline v1.4.1
VERSION="1.4.1"
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
    v('exceeds_200k',   d.exceeds_200k_tokens ?? false);
    v('total_duration_ms', d.cost?.total_duration_ms ?? '');
    v('cwd',            d.workspace?.current_dir ?? d.cwd ?? '');
    v('five_pct',       d.rate_limits?.five_hour?.used_percentage ?? '');
    v('five_resets_epoch', d.rate_limits?.five_hour?.resets_at ?? '');
    v('seven_pct',      d.rate_limits?.seven_day?.used_percentage ?? '');
    v('seven_resets_epoch', d.rate_limits?.seven_day?.resets_at ?? '');
    v('effort',         s.effortLevel ?? 'default');
    v('thinking_setting', s.thinking ?? '');
    v('bypass_perms',   s.bypassPermissions ?? false);
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
ctx_pct=0 exceeds_200k=false total_duration_ms="" cwd=""
five_pct="" five_resets_epoch="" seven_pct="" seven_resets_epoch=""
effort="default" thinking_setting="" bypass_perms=false

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

# ── Cache hit rate ────────────────────────────────────
cache_hit_str=""
if [ "$ctx_used" -gt 0 ]; then
    cache_hit_pct=$(( cache_read * 100 / ctx_used ))
    cache_hit_str="${dim}cache:${cache_hit_pct}%${reset}"
fi

# ── Context overflow warning ─────────────────────────
ctx_warning=""
[ "$exceeds_200k" = "true" ] && ctx_warning="${red}long chat${reset}"

# ── Session duration ─────────────────────────────────
session_duration=""
if [ -n "$total_duration_ms" ]; then
    elapsed=$(( total_duration_ms / 1000 ))
    if [ "$elapsed" -ge 3600 ]; then
        session_duration="$(( elapsed / 3600 ))h $(( (elapsed % 3600) / 60 ))m"
    elif [ "$elapsed" -ge 60 ]; then
        session_duration="$(( elapsed / 60 ))m"
    else
        session_duration="${elapsed}s"
    fi
fi

# ── Effort + thinking + permissions ──────────────────
thinking_on=false
[ "$thinking_setting" = "true" ] || [ "$thinking_setting" = "enabled" ] && thinking_on=true

bypass_perms_on=false
[ "$bypass_perms" = "true" ] && bypass_perms_on=true

# ── Working directory & git ───────────────────────────
[ -z "$cwd" ] && cwd=$(pwd)
dirname=$(basename "$cwd")

git_branch=""
git_dirty_count=0
git_ahead=0
git_behind=0
git_commit_age=""

# Single `git status --porcelain=v2 --branch` call yields inside-work-tree
# check (exit code), branch name, upstream tracking and ahead/behind counts,
# and the file list for dirty count — replacing 4 separate git invocations.
# Porcelain v2 format has been stable since Git 2.11 (2016).
if git_status=$(git -C "$cwd" --no-optional-locks status --porcelain=v2 --branch 2>/dev/null); then
    while IFS= read -r gs_line; do
        case "$gs_line" in
            '# branch.head '*)
                git_branch="${gs_line#\# branch.head }"
                [ "$git_branch" = "(detached)" ] && git_branch=""
                ;;
            '# branch.ab '*)
                ab="${gs_line#\# branch.ab }"
                # Format: "+<ahead> -<behind>"
                gs_ahead="${ab%% *}"
                gs_behind="${ab##* }"
                git_ahead="${gs_ahead#+}"
                git_behind="${gs_behind#-}"
                ;;
        esac
    done <<< "$git_status"

    git_dirty_count=$(echo "$git_status" | awk '!/^#/ {n++} END {print n+0}')

    commit_ts=$(git -C "$cwd" log -1 --format="%ct" 2>/dev/null)
    [ -n "$commit_ts" ] && git_commit_age=$(format_age "$commit_ts")
fi

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
    net_mtime=$(stat -f %m "$net_cache" 2>/dev/null || stat -c %Y "$net_cache" 2>/dev/null)
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
statusline_mode="full"
config_file="$HOME/.config/claude-statusline/config"
[ -f "$config_file" ] && {
    fmt=$(grep '^TIME_FORMAT=' "$config_file" 2>/dev/null | cut -d= -f2)
    [ -n "$fmt" ] && time_format="$fmt"
    mode=$(grep '^STATUSLINE_MODE=' "$config_file" 2>/dev/null | cut -d= -f2)
    [ -n "$mode" ] && statusline_mode="$mode"
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
[ -n "$ctx_warning" ] && line1+=" ${ctx_warning}"
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
fi
line1+="${sep}"
case "$effort" in
    high) line1+="${magenta}high${reset}" ;;
    low)  line1+="${dim}low${reset}" ;;
    *)    line1+="${dim}${effort}${reset}" ;;
esac
$thinking_on    && line1+=" ${cyan}thinking${reset}"
$bypass_perms_on && line1+=" ${red}!permissions${reset}"

# ── Rate limits: collect every category into rate_records[] ─
# stdin carries the standard 5-hour and 7-day slots; the API block below
# adds dynamic discovery of every other limit Anthropic returns. Rendering
# is deferred until both sources have populated the array, so that label
# padding stays consistent across all rows regardless of which categories
# were discovered. Each record is a single string with pipe-separated
# fields:
#     util|<label>|<pct>|<resets_epoch>
#     credits|<label>|<pct>|<used>|<limit>|<currency>
rate_records=()
bar_width=10

if [ -n "$five_pct" ]; then
    five_pct_int=$(printf "%.0f" "$five_pct" 2>/dev/null || echo "0")
    rate_records+=("util|5-hour|${five_pct_int}|${five_resets_epoch}")
fi

if [ -n "$seven_pct" ]; then
    seven_pct_int=$(printf "%.0f" "$seven_pct" 2>/dev/null || echo "0")
    rate_records+=("util|7-day|${seven_pct_int}|${seven_resets_epoch}")
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
    lock_mtime=$(stat -f %m "$extra_lock" 2>/dev/null || stat -c %Y "$extra_lock" 2>/dev/null)
    lock_age=$(( $(date +%s) - lock_mtime ))
    blocked_for=$(cat "$extra_lock" 2>/dev/null || echo "300")
    [ "$lock_age" -lt "$blocked_for" ] && locked=true
fi

extra_data=""
needs_extra_refresh=true
if [ -f "$extra_cache" ]; then
    extra_mtime=$(stat -f %m "$extra_cache" 2>/dev/null || stat -c %Y "$extra_cache" 2>/dev/null)
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
                # Cache every successful response unconditionally; the
                # consolidated parser below tolerates missing sections
                # (extra_usage / seven_day_sonnet may not exist on all plans)
                # and simply leaves the corresponding *_enabled flags false.
                extra_data="$response_body"
                tmp=$(mktemp "$CACHE_DIR/extra-XXXXXX")
                echo "$response_body" > "$tmp" && mv "$tmp" "$extra_cache"
                rm -f "$extra_lock" 2>/dev/null
                ;;
            429) echo "300" > "$extra_lock" ;;
            401|403) echo "600" > "$extra_lock" ;;
            *) echo "60" > "$extra_lock" ;;
        esac
    fi
    if [ -z "$extra_data" ] && [ -f "$extra_cache" ]; then
        extra_mtime=$(stat -f %m "$extra_cache" 2>/dev/null || stat -c %Y "$extra_cache" 2>/dev/null)
        extra_age=$(( $(date +%s) - extra_mtime ))
        [ "$extra_age" -lt 600 ] && extra_data=$(cat "$extra_cache" 2>/dev/null)
    fi
fi

if [ -n "$extra_data" ]; then
    # Dynamic discovery: enumerate every non-null top-level field in
    # /api/oauth/usage and classify each into one of two known shapes.
    # Anything else is silently skipped. five_hour and seven_day are
    # excluded here because both are already populated from stdin above
    # — including them would render duplicate rows. New limit types added
    # by Anthropic in the future appear in the statusline automatically
    # without code changes; this replaced a hardcoded parser that ignored
    # seven_day_opus, seven_day_omelette, and similar codename slots
    # entirely.
    api_records=$(echo "$extra_data" | node -e "
let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>{
  try{
    const j=JSON.parse(d);
    const skip=new Set(['five_hour','seven_day']);
    for(const [key,val] of Object.entries(j)){
      if(skip.has(key)||val==null||typeof val!=='object')continue;
      // Strip the seven_day_ prefix so 'seven_day_opus' renders as 'opus';
      // map the special-cased extra_usage to the historical 'extra' label.
      const label=key==='extra_usage'?'extra':key.replace(/^seven_day_/,'');
      // Pattern A — utilization + resets_at (sonnet/opus/cowork/...).
      if(typeof val.utilization==='number' && 'resets_at' in val){
        const pct=Math.round(val.utilization||0);
        const r=val.resets_at?Math.floor(new Date(val.resets_at).getTime()/1000):'';
        console.log('util|'+label+'|'+pct+'|'+r);
      }
      // Pattern B — prepaid credits (extra_usage shape).
      else if(val.is_enabled===true && typeof val.monthly_limit==='number'){
        const pct=Math.round(val.utilization||0);
        const used=(val.used_credits/100).toFixed(2);
        const lim=(val.monthly_limit/100).toFixed(2);
        const cur=val.currency||'USD';
        console.log('credits|'+label+'|'+pct+'|'+used+'|'+lim+'|'+cur);
      }
    }
  }catch(e){}
})" 2>/dev/null)
    if [ -n "$api_records" ]; then
        while IFS= read -r api_line; do
            [ -n "$api_line" ] && rate_records+=("$api_line")
        done <<EOF
$api_records
EOF
    fi
fi

# ── Render rate_records[] → rate_lines (full mode) ────────
rate_lines=""
if [ "${#rate_records[@]}" -gt 0 ]; then
    # Compute label padding once across every row so bars line up
    # vertically regardless of which categories the API returned.
    label_pad=5
    for rec in "${rate_records[@]}"; do
        rec_lbl=${rec#*|}; rec_lbl=${rec_lbl%%|*}
        rec_n=${#rec_lbl}
        [ "$rec_n" -gt "$label_pad" ] && label_pad="$rec_n"
    done

    for rec in "${rate_records[@]}"; do
        IFS='|' read -r kind lbl f3 f4 f5 f6 <<< "$rec"
        case "$kind" in
            util)
                pct="$f3"; epoch="$f4"
                bar=$(build_bar "$pct" "$bar_width")
                color=$(color_for_pct "$pct")
                lbl_padded=$(printf "%-${label_pad}s" "$lbl")
                [ -n "$rate_lines" ] && rate_lines+="\n"
                rate_lines+="${white}${lbl_padded}${reset}  ${bar} ${color}$(printf "%3d" "$pct")%${reset}"
                if [ -n "$epoch" ]; then
                    # 5-hour resets within the day so a bare time looks fine;
                    # everything else can span days, so include the date.
                    if [ "$lbl" = "5-hour" ]; then
                        reset_str=$(format_epoch_as_time "$epoch" time)
                    else
                        reset_str=$(format_epoch_as_time "$epoch" datetime)
                    fi
                    [ -n "$reset_str" ] && rate_lines+=" ${dim}-> ${reset}${white}${reset_str}${reset}"
                    time_left=$(format_epoch_time_left "$epoch")
                    [ -n "$time_left" ] && rate_lines+=" ${dim}(${time_left})${reset}"
                fi
                ;;
            credits)
                pct="$f3"; used="$f4"; lim="$f5"; cur="$f6"
                bar=$(build_bar "$pct" "$bar_width")
                color=$(color_for_pct "$pct")
                lbl_padded=$(printf "%-${label_pad}s" "$lbl")
                # USD displays as $; other currencies print the code.
                if [ "$cur" = "USD" ]; then
                    sym='$'
                else
                    sym="${cur} "
                fi
                # Prepaid credits reset on the 1st of the next month.
                reset_str=$(date -v+1m -v1d +"%b %-d" 2>/dev/null | tr '[:upper:]' '[:lower:]')
                [ -z "$reset_str" ] && reset_str=$(date -d "$(date +%Y-%m-01) +1 month" +"%b %-d" 2>/dev/null | tr '[:upper:]' '[:lower:]')
                [ -n "$rate_lines" ] && rate_lines+="\n"
                rate_lines+="${white}${lbl_padded}${reset}  ${bar} ${color}${sym}${used}${dim}/${reset}${white}${sym}${lim}${reset}"
                [ -n "$reset_str" ] && rate_lines+=" ${dim}-> ${reset}${white}${reset_str}${reset}"
                if [ -f "$extra_cache" ]; then
                    cache_mtime=$(stat -f %m "$extra_cache" 2>/dev/null || stat -c %Y "$extra_cache" 2>/dev/null)
                    cache_age=$(( $(date +%s) - cache_mtime ))
                    if [ "$cache_age" -gt "$extra_max_age" ]; then
                        stale_age=$(format_age "$cache_mtime")
                        rate_lines+=" ${dim}(${stale_age} ago)${reset}"
                    fi
                fi
                ;;
        esac
    done
fi

# ── Update check (cached 24h) ────────────────────────
update_str=""
update_cache="$CACHE_DIR/statusline-update-cache"
update_max_age=86400

update_needs_check=true
if [ -f "$update_cache" ]; then
    update_mtime=$(stat -f %m "$update_cache" 2>/dev/null || stat -c %Y "$update_cache" 2>/dev/null)
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
if [ "$statusline_mode" = "compact" ]; then
    # Single-line terse output: model, context, and rate-limit usage.
    # All percentages are shown as USED — same semantic as full mode — so
    # a given metric shows the exact same number in both layouts. Colour
    # urgency still tracks usage (green = low, red = near exhaustion).
    # rate_records[] is populated above from stdin (5-hour, 7-day) and
    # /api/oauth/usage (sonnet, opus, omelette, extra, ...) — every row
    # discovered in the API response is rendered here too, so new limit
    # types appear in compact mode without code changes.
    compact_line="${model_color}${model_name}${reset}"
    compact_line+="${sep}${ctx_color}ctx ${ctx_pct}%${reset} ${dim}(${used_fmt}/${total_fmt})${reset}"

    for rec in "${rate_records[@]}"; do
        IFS='|' read -r kind lbl f3 f4 f5 f6 <<< "$rec"
        # Tighten labels for the well-known long ones; everything else
        # (sonnet / opus / omelette / extra / future codenames) stays as-is.
        case "$lbl" in
            5-hour) clbl="5h" ;;
            7-day)  clbl="7d" ;;
            *)      clbl="$lbl" ;;
        esac
        case "$kind" in
            util)
                pct="$f3"; epoch="$f4"
                color=$(color_for_pct "$pct")
                compact_line+="${sep}${color}${clbl} ${pct}%${reset}"
                if [ -n "$epoch" ]; then
                    time_left=$(format_epoch_time_left "$epoch")
                    [ -n "$time_left" ] && compact_line+=" ${dim}${time_left}${reset}"
                fi
                ;;
            credits)
                pct="$f3"; used="$f4"; lim="$f5"; cur="$f6"
                color=$(color_for_pct "$pct")
                if [ "$cur" = "USD" ]; then sym='$'; else sym="${cur} "; fi
                compact_line+="${sep}${white}${clbl}${reset} ${color}${sym}${used}${dim}/${reset}${white}${sym}${lim}${reset}"
                ;;
        esac
    done

    printf "%b" "$compact_line"
    exit 0
fi

printf "%b" "$line1"
[ -n "$rate_lines" ] && printf "\n\n%b" "$rate_lines"
[ -n "$sys_line" ]   && printf "\n\n%b" "$sys_line"

exit 0
