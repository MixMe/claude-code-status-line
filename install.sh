#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$HOME/.claude/statusline.sh"
SETTINGS="$HOME/.claude/settings.json"
CONFIG_DIR="$HOME/.config/claude-statusline"
CONFIG_FILE="$CONFIG_DIR/config"

# ── Time format ───────────────────────────────────────
time_format="12h"
if [ -f "$CONFIG_FILE" ]; then
    existing=$(grep '^TIME_FORMAT=' "$CONFIG_FILE" 2>/dev/null | cut -d= -f2)
    [ -n "$existing" ] && time_format="$existing"
fi

echo "Time format [12h = 2:34pm / 24h = 14:34] (current: ${time_format}):"
printf "  Enter 12h or 24h, or press Enter to keep current: "
read -r input_fmt </dev/tty
input_fmt=$(echo "$input_fmt" | tr -d '[:space:]')
case "$input_fmt" in
    12h|24h) time_format="$input_fmt" ;;
    "") ;;  # keep current
    *) echo "  Unknown value '${input_fmt}', keeping ${time_format}" ;;
esac

mkdir -p "$CONFIG_DIR"
if [ -f "$CONFIG_FILE" ]; then
    # update existing entry or append
    if grep -q '^TIME_FORMAT=' "$CONFIG_FILE" 2>/dev/null; then
        tmp=$(mktemp)
        sed "s/^TIME_FORMAT=.*/TIME_FORMAT=${time_format}/" "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
    else
        echo "TIME_FORMAT=${time_format}" >> "$CONFIG_FILE"
    fi
else
    echo "TIME_FORMAT=${time_format}" > "$CONFIG_FILE"
fi
echo "Time format set to: ${time_format}"
echo ""

# ── Copy statusline script ────────────────────────────
mkdir -p "$HOME/.claude"
cp "$SCRIPT_DIR/statusline.sh" "$TARGET"
chmod +x "$TARGET"
echo "Installed $TARGET"

# ── Patch settings.json ───────────────────────────────
STATUS_LINE_VALUE='{"type":"command","command":"bash \"$HOME/.claude/statusline.sh\""}'

if [ ! -f "$SETTINGS" ]; then
    echo "{\"statusLine\": $STATUS_LINE_VALUE}" | jq . > "$SETTINGS"
    echo "Created $SETTINGS"
elif jq -e '.statusLine' "$SETTINGS" >/dev/null 2>&1; then
    echo "statusLine already set in $SETTINGS — skipping (edit manually to change)"
else
    tmp=$(mktemp)
    jq --argjson v "$STATUS_LINE_VALUE" '. + {statusLine: $v}' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
    echo "Updated $SETTINGS"
fi

echo ""
echo "Done. Restart Claude Code to apply."
