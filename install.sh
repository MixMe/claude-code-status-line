#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$HOME/.claude/statusline.sh"

cp "$SCRIPT_DIR/statusline.sh" "$TARGET"
chmod +x "$TARGET"

echo "Installed to $TARGET"
echo ""
echo "Add this to ~/.claude/settings.json:"
echo '{'
echo '  "statusLine": {'
echo '    "type": "command",'
echo '    "command": "bash \"$HOME/.claude/statusline.sh\""'
echo '  }'
echo '}'