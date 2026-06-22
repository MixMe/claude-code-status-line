#!/bin/bash
set -e

# claude-code-statusline uninstaller.
# Reverses install.sh: removes the statusLine entry from settings.json, deletes
# the installed script, clears caches, and removes the config directory.
# Pass --keep-config to preserve ~/.config/claude-statusline/config.

TARGET="$HOME/.claude/statusline.sh"
SETTINGS="$HOME/.claude/settings.json"
CONFIG_DIR="$HOME/.config/claude-statusline"
TMPDIR="${TMPDIR:-${TMP:-${TEMP:-/tmp}}}"
CACHE_DIR="$TMPDIR/claude"

have() { command -v "$1" >/dev/null 2>&1; }

KEEP_CONFIG=false
[ "$1" = "--keep-config" ] && KEEP_CONFIG=true

echo "claude-code-statusline uninstaller"
echo ""

# ── 1. Remove the statusLine entry from settings.json (portable) ──
# Only the statusLine key is touched — every other setting is preserved.
if [ -f "$SETTINGS" ]; then
    if have jq; then
        if jq -e '.statusLine' "$SETTINGS" >/dev/null 2>&1; then
            tmp=$(mktemp)
            jq 'del(.statusLine)' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
            echo "Removed statusLine from $SETTINGS"
        else
            echo "No statusLine entry in settings.json"
        fi
    elif have python3; then
        python3 -c '
import json, sys
path = sys.argv[1]
try:
    s = json.load(open(path))
except Exception:
    s = {}
if isinstance(s, dict) and "statusLine" in s:
    del s["statusLine"]
    open(path, "w").write(json.dumps(s, indent=2) + "\n")
    print("Removed statusLine from " + path)
else:
    print("No statusLine entry in settings.json")
' "$SETTINGS"
    elif have node; then
        node -e "
const fs=require('fs');const p=process.argv[1];
try{
  const s=JSON.parse(fs.readFileSync(p,'utf8'));
  if(s.statusLine){delete s.statusLine;fs.writeFileSync(p,JSON.stringify(s,null,2)+'\n');console.log('Removed statusLine from '+p);}
  else console.log('No statusLine entry in settings.json');
}catch(e){console.log('Could not edit '+p+' — remove the statusLine key manually');}
" "$SETTINGS" 2>/dev/null
    else
        echo "No jq / python3 / node found — remove the \"statusLine\" key from $SETTINGS manually."
    fi
else
    echo "No settings.json found — skipping"
fi

# ── 2. Remove the installed script ───────────────────
if [ -f "$TARGET" ]; then
    rm -f "$TARGET"
    echo "Removed $TARGET"
else
    echo "No installed script at $TARGET"
fi

# ── 3. Clear caches ──────────────────────────────────
if ls "$CACHE_DIR"/statusline-* >/dev/null 2>&1 || [ -f "$CACHE_DIR/net-cache" ]; then
    rm -f "$CACHE_DIR"/statusline-* "$CACHE_DIR/net-cache" 2>/dev/null || true
    echo "Cleared caches in $CACHE_DIR"
fi

# ── 4. Remove config directory ───────────────────────
if [ -d "$CONFIG_DIR" ]; then
    if $KEEP_CONFIG; then
        echo "Kept config at $CONFIG_DIR (--keep-config)"
    else
        rm -rf "$CONFIG_DIR"
        echo "Removed $CONFIG_DIR"
    fi
fi

echo ""
echo "Uninstalled. Restart Claude Code to apply."
