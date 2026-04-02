#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$HOME/.claude/statusline.sh"
SETTINGS="$HOME/.claude/settings.json"

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
