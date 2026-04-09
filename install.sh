#!/bin/bash
set -e

REPO_RAW="https://raw.githubusercontent.com/MixMe/claude-code-status-line/main"
TARGET="$HOME/.claude/statusline.sh"
SETTINGS="$HOME/.claude/settings.json"
CONFIG_DIR="$HOME/.config/claude-statusline"
CONFIG_FILE="$CONFIG_DIR/config"

# ── Detect local vs remote mode ──────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}" 2>/dev/null)" && pwd 2>/dev/null)" || SCRIPT_DIR=""
LOCAL_SCRIPT="$SCRIPT_DIR/statusline.sh"

fetch_statusline() {
    if [ -n "$SCRIPT_DIR" ] && [ -f "$LOCAL_SCRIPT" ]; then
        cat "$LOCAL_SCRIPT"
    else
        curl -fsSL "$REPO_RAW/statusline.sh"
    fi
}

# ── Download and install ─────────────────────────────
mkdir -p "$HOME/.claude" "$CONFIG_DIR" /tmp/claude

statusline_content=$(fetch_statusline)
if [ -z "$statusline_content" ]; then
    echo "Error: failed to download statusline.sh" >&2
    exit 1
fi

echo "$statusline_content" > "$TARGET"
chmod +x "$TARGET"

VERSION=$(echo "$statusline_content" | grep '^VERSION=' | head -1 | cut -d'"' -f2)
[ -z "$VERSION" ] && VERSION="unknown"

echo "claude-code-statusline v${VERSION}"
echo ""

# ── Load existing config ─────────────────────────────
time_format="12h"
statusline_mode="full"
if [ -f "$CONFIG_FILE" ]; then
    existing=$(grep '^TIME_FORMAT=' "$CONFIG_FILE" 2>/dev/null | cut -d= -f2)
    [ -n "$existing" ] && time_format="$existing"
    existing=$(grep '^STATUSLINE_MODE=' "$CONFIG_FILE" 2>/dev/null | cut -d= -f2)
    [ -n "$existing" ] && statusline_mode="$existing"
fi

# Interactive prompt (skip if no tty available)
has_tty=false
(echo "" > /dev/tty) 2>/dev/null && has_tty=true

# ── Generic interactive selector ─────────────────────
# Usage: select_option <prompt> <initial_index> <label1> <value1> [<label2> <value2> ...]
# Result is returned via global SELECTED_VALUE.
#
# Supported keys: ↑/↓/←/→ arrow keys, j/k (vim), 1..9 (direct pick),
# Enter to confirm, q to abort with current selection.
#
# Integer `read -t 1` timeout is mandatory for bash 3.2 compatibility —
# see the bugfix commit that preceded this refactor.
select_option() {
    local prompt="$1"; shift
    local initial="$1"; shift
    local labels=() values=()
    while [ $# -ge 2 ]; do
        labels+=("$1")
        values+=("$2")
        shift 2
    done
    local n=${#labels[@]}
    local selected=$initial
    [ -z "$selected" ] && selected=0
    [ "$selected" -ge "$n" ] 2>/dev/null && selected=0
    [ "$selected" -lt 0 ] 2>/dev/null && selected=0

    _render_opts() {
        local i
        for ((i=0; i<n; i++)); do
            if [ "$i" -eq "$selected" ]; then
                printf '  \033[1;36m> %s\033[0m\n' "${labels[$i]}" > /dev/tty
            else
                printf '    \033[2m%s\033[0m\n' "${labels[$i]}" > /dev/tty
            fi
        done
    }

    printf '%s\n' "$prompt" > /dev/tty
    # Hide cursor during selection; always restore on exit.
    printf '\033[?25l' > /dev/tty
    trap 'printf "\033[?25h" > /dev/tty' EXIT INT TERM

    _render_opts

    local key rest
    while true; do
        IFS= read -rsn1 key </dev/tty 2>/dev/null || { key=""; break; }
        case "$key" in
            $'\x1b')
                IFS= read -rsn2 -t 1 rest </dev/tty 2>/dev/null || rest=""
                case "$rest" in
                    '[A'|'[D') selected=$(( (selected - 1 + n) % n )) ;;  # up / left
                    '[B'|'[C') selected=$(( (selected + 1) % n )) ;;      # down / right
                esac
                ;;
            'k'|'K') selected=$(( (selected - 1 + n) % n )) ;;
            'j'|'J') selected=$(( (selected + 1) % n )) ;;
            [1-9])
                local idx=$((key - 1))
                [ "$idx" -lt "$n" ] && selected=$idx
                ;;
            '')  break ;;  # Enter confirms
            'q'|'Q') break ;;
        esac
        # Move cursor up n lines and redraw options in place.
        printf '\033[%dA' "$n" > /dev/tty
        _render_opts
    done

    printf '\033[?25h' > /dev/tty
    trap - EXIT INT TERM

    SELECTED_VALUE="${values[$selected]}"
}

config_set() {
    local key="$1" value="$2"
    if [ -f "$CONFIG_FILE" ] && grep -q "^${key}=" "$CONFIG_FILE" 2>/dev/null; then
        local tmp; tmp=$(mktemp)
        sed "s|^${key}=.*|${key}=${value}|" "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
    else
        echo "${key}=${value}" >> "$CONFIG_FILE"
    fi
}

# ── Time format ───────────────────────────────────────
if $has_tty; then
    initial=0; [ "$time_format" = "24h" ] && initial=1
    select_option "Select time format (arrow keys / j,k / 1,2, Enter to confirm):" \
        "$initial" \
        "12-hour  (2:34pm)" "12h" \
        "24-hour  (14:34)"  "24h"
    time_format="$SELECTED_VALUE"
fi
config_set TIME_FORMAT "$time_format"
echo "Time format: ${time_format}"

# ── Statusline mode ──────────────────────────────────
if $has_tty; then
    initial=0; [ "$statusline_mode" = "compact" ] && initial=1
    select_option "Select statusline mode (arrow keys / j,k / 1,2, Enter to confirm):" \
        "$initial" \
        "full     (multi-line: context, rate-limit bars, system info)" "full" \
        "compact  (single line: model, context, rate-limit remainders)" "compact"
    statusline_mode="$SELECTED_VALUE"
fi
config_set STATUSLINE_MODE "$statusline_mode"
echo "Statusline mode: ${statusline_mode}"

# ── Clear stale caches ───────────────────────────────
TMPDIR="${TMPDIR:-${TMP:-${TEMP:-/tmp}}}"
rm -f "$TMPDIR/claude/statusline-usage-cache.json" "$TMPDIR/claude/statusline-extra-cache.json" \
      "$TMPDIR/claude/statusline-extra.lock" "$TMPDIR/claude/statusline-update-cache" 2>/dev/null

# ── Patch settings.json ───────────────────────────────
node -e "
const fs=require('fs');
const path='$SETTINGS';
const sl={type:'command',command:'bash \"\$HOME/.claude/statusline.sh\"'};
let settings={};
let action='';
if(fs.existsSync(path)){
  settings=JSON.parse(fs.readFileSync(path,'utf8'));
  if(settings.statusLine){action='exists'}
  else{settings.statusLine=sl;action='updated'}
}else{
  settings={statusLine:sl};action='created';
}
if(action!=='exists'){
  fs.writeFileSync(path,JSON.stringify(settings,null,2)+'\n');
}
console.log(action==='exists'?'statusLine already configured':
  action==='created'?'Created '+path:'Updated '+path);
" 2>/dev/null

echo ""
echo "Installed v${VERSION}. Restart Claude Code to apply."
