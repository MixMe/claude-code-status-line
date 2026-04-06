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

# ── Time format ───────────────────────────────────────
time_format="12h"
if [ -f "$CONFIG_FILE" ]; then
    existing=$(grep '^TIME_FORMAT=' "$CONFIG_FILE" 2>/dev/null | cut -d= -f2)
    [ -n "$existing" ] && time_format="$existing"
fi

# Interactive prompt (skip if no tty available)
has_tty=false
(echo "" > /dev/tty) 2>/dev/null && has_tty=true

if $has_tty; then
    # Interactive selector: arrow keys (↑/↓), j/k, 1/2 to switch, Enter to confirm.
    # Options are redrawn in place using ANSI cursor-up escapes.
    options_label=("12-hour  (2:34pm)" "24-hour  (14:34)")
    options_value=("12h" "24h")
    selected=0
    [ "$time_format" = "24h" ] && selected=1

    render_options() {
        local i
        for i in 0 1; do
            if [ "$i" -eq "$selected" ]; then
                printf '  \033[1;36m> %s\033[0m\n' "${options_label[$i]}" > /dev/tty
            else
                printf '    \033[2m%s\033[0m\n' "${options_label[$i]}" > /dev/tty
            fi
        done
    }

    printf 'Select time format (use arrow keys or 1/2, Enter to confirm):\n' > /dev/tty
    # Hide cursor during selection; always restore on exit.
    printf '\033[?25l' > /dev/tty
    trap 'printf "\033[?25h" > /dev/tty' EXIT INT TERM

    render_options

    while true; do
        IFS= read -rsn1 key </dev/tty 2>/dev/null || { key=""; break; }
        case "$key" in
            $'\x1b')
                # Escape sequence: read the remaining two bytes of an arrow key.
                IFS= read -rsn2 -t 0.05 rest </dev/tty 2>/dev/null || rest=""
                case "$rest" in
                    '[A'|'[D') selected=0 ;;  # up / left
                    '[B'|'[C') selected=1 ;;  # down / right
                esac
                ;;
            '1') selected=0 ;;
            '2') selected=1 ;;
            'k'|'K') selected=0 ;;
            'j'|'J') selected=1 ;;
            '')  break ;;  # Enter confirms
            'q'|'Q') break ;;
        esac
        # Move cursor up 2 lines and redraw both options in place.
        printf '\033[2A' > /dev/tty
        render_options
    done

    printf '\033[?25h' > /dev/tty
    trap - EXIT INT TERM

    time_format="${options_value[$selected]}"
fi

if [ -f "$CONFIG_FILE" ] && grep -q '^TIME_FORMAT=' "$CONFIG_FILE" 2>/dev/null; then
    tmp=$(mktemp)
    sed "s/^TIME_FORMAT=.*/TIME_FORMAT=${time_format}/" "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
else
    echo "TIME_FORMAT=${time_format}" >> "$CONFIG_FILE"
fi
echo "Time format: ${time_format}"

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
