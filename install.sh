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
    echo "Time format [12h = 2:34pm / 24h = 14:34] (current: ${time_format}):"
    printf "  Enter 12h or 24h, or press Enter to keep current: "
    input_fmt=""
    read -r input_fmt </dev/tty 2>/dev/null || input_fmt=""
    input_fmt=$(echo "$input_fmt" | tr -d '[:space:]')
    case "$input_fmt" in
        12h|24h) time_format="$input_fmt" ;;
        "") ;;
        *) echo "  Unknown value '${input_fmt}', keeping ${time_format}" ;;
    esac
fi

if [ -f "$CONFIG_FILE" ] && grep -q '^TIME_FORMAT=' "$CONFIG_FILE" 2>/dev/null; then
    tmp=$(mktemp)
    sed "s/^TIME_FORMAT=.*/TIME_FORMAT=${time_format}/" "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
else
    echo "TIME_FORMAT=${time_format}" >> "$CONFIG_FILE"
fi
echo "Time format: ${time_format}"

# ── Clear stale caches ───────────────────────────────
rm -f /tmp/claude/statusline-usage-cache.json /tmp/claude/statusline-extra-cache.json \
      /tmp/claude/statusline-extra.lock /tmp/claude/statusline-update-cache 2>/dev/null

# ── Patch settings.json ───────────────────────────────
STATUS_LINE_VALUE='{"type":"command","command":"bash \"$HOME/.claude/statusline.sh\""}'

if [ ! -f "$SETTINGS" ]; then
    echo "{\"statusLine\": $STATUS_LINE_VALUE}" | jq . > "$SETTINGS"
    echo "Created $SETTINGS"
elif jq -e '.statusLine' "$SETTINGS" >/dev/null 2>&1; then
    echo "statusLine already configured"
else
    tmp=$(mktemp)
    jq --argjson v "$STATUS_LINE_VALUE" '. + {statusLine: $v}' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
    echo "Updated $SETTINGS"
fi

echo ""
echo "Installed v${VERSION}. Restart Claude Code to apply."
