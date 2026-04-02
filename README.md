# claude-code-statusline

A rich status line for [Claude Code](https://claude.ai/code) that shows model info, context usage, git branch, session cost, duration, effort level, and live rate-limit bars.

## Preview

```
Claude Sonnet 4.6  │  12%  (24k/200k)  $0.08  │  my-project (main)  │  5m  │  default

5h  ●●○○○○○○○○  18%  (3h 42m) → 6:30pm
7d  ●●●●○○○○○○  40%  (2d 14h) → apr 9, 6:30pm
```

## What it shows

**Line 1**
- Model display name
- Context window usage — percentage + token count, color-coded (green → orange → yellow → red)
- Session cost (when available)
- Current directory name + git branch (with `*` when dirty)
- Session duration
- Effort level (`default` / `high` / `low`)

**Line 2**
- 5-hour rate limit bar + time left until reset
- 7-day rate limit bar + time left until reset
- Extra usage credits (when enabled on your account)

## Requirements

- `bash` 4+
- `jq`
- `curl`
- macOS or Linux

## Install

```bash
bash install.sh
```

Then add to `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash \"$HOME/.claude/statusline.sh\""
  }
}
```

Restart Claude Code to apply.

## Rate limit display

The script fetches usage from `https://api.anthropic.com/api/oauth/usage` using your stored Claude Code OAuth token. Results are cached in `/tmp/claude/statusline-usage-cache.json` for 60 seconds to avoid excessive API calls.

Works automatically if you're logged in to Claude Code via OAuth (the default). No API key needed.

## Customization

### Custom project labels

By default the status line shows the current directory name. To map paths to custom labels, create `~/.config/claude-statusline/labels` with one `pattern=label` entry per line:

```
my-api=api
my-frontend=ui
my-shared-lib=shared
```

Then add this to `statusline.sh` in the working directory section:

```bash
labels_file="$HOME/.config/claude-statusline/labels"
if [ -f "$labels_file" ]; then
    while IFS='=' read -r pattern label; do
        [[ "$cwd" == *"$pattern"* ]] && dirname="$label" && break
    done < "$labels_file"
fi
```

### Service health indicator

To add a health check for a local service (e.g. a database, vector store, or dev server), add before the output section:

```bash
service_up=false
if curl -sf --max-time 1 "http://localhost:YOUR_PORT/health" >/dev/null 2>&1; then
    service_up=true
fi

if $service_up; then
    service_indicator="${green}service ●${reset}"
else
    service_indicator="${dim}service ○${reset}"
fi
```

Then prepend `$service_indicator${sep}` to `$rate_lines`.

## License

MIT
