# claude-code-statusline

A rich status line for [Claude Code](https://claude.ai/code) — model info, context usage, cache efficiency, session cost, git status, rate-limit bars, battery, memory, and more.

## Preview

```
Claude Sonnet 4.6  │  12% (24k/200k) cache:45%  $0.08 ($0.03/1k)  │  my-project (main 3~ ↑1 2h)  │  15m 12msg  │  default

5h  ●●○○○○○○○○   18%  (3h 42m) → 6:30pm
7d  ●●●●○○○○○○   40%  (2d 14h) → apr 9, 6:30pm

bat 87%  │  mem 6.2gb free  │  net ●  │  2:34pm
```

## What it shows

**Line 1 — Session**
| Field | Description |
|---|---|
| Model name | Color-coded by tier: cyan = Haiku, blue = Sonnet, magenta = Opus |
| Context % | Usage vs window size, color-coded green → orange → yellow → red |
| Cache hit rate | `cache_read / total_tokens` — higher = cheaper, faster responses |
| Session cost | Total `$` spent this session |
| Cost per 1k tokens | Efficiency indicator for the session |
| Directory | Current working directory name |
| Git branch | Branch name with dirty file count (`3~`), ahead/behind (`↑1↓0`), last commit age (`2h`) |
| Session duration | How long the current session has been running |
| Message count | Number of messages in the session |
| Effort level | `default` / `high` / `low` |
| Thinking | `thinking` label shown when extended thinking is active |
| Permissions | `!perms` warning shown when `bypassPermissions` is enabled |

**Line 2 — Rate limits**
| Field | Description |
|---|---|
| 5h bar | 5-hour usage bar with % and time until reset |
| 7d bar | 7-day usage bar with % and date/time until reset |
| Extra | Monthly extra usage credits (shown only when enabled) |

**Line 3 — System**
| Field | Description |
|---|---|
| Battery | Level with color warning at ≤40% (yellow) and ≤20% (red). Hidden on desktop/server. |
| Memory | Free RAM (macOS: free + inactive pages; Linux: MemAvailable) |
| Internet | `●` up / `○` down — pings 1.1.1.1, cached 30s |
| Local time | Current time |

## Requirements

- `bash` 4+
- `jq`
- `curl`
- macOS or Linux

## Install

```bash
bash install.sh
```

`install.sh` copies `statusline.sh` to `~/.claude/statusline.sh` and automatically patches `~/.claude/settings.json` with the required `statusLine` config. Restart Claude Code to apply.

### Manual settings.json entry

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash \"$HOME/.claude/statusline.sh\""
  }
}
```

## How rate limits work

The script fetches live usage from `https://api.anthropic.com/api/oauth/usage` using the OAuth token stored by Claude Code. Results are cached in `/tmp/claude/statusline-usage-cache.json` for 60 seconds. Works automatically if you're logged in via OAuth — no API key needed.

## Customization

### Custom project labels

By default the status line shows the current directory name. To map paths to custom labels, create `~/.config/claude-statusline/labels` with one `pattern=label` entry per line:

```
my-api=api
my-frontend=ui
my-shared-lib=shared
```

Then add to the working directory section of `statusline.sh`:

```bash
labels_file="$HOME/.config/claude-statusline/labels"
if [ -f "$labels_file" ]; then
    while IFS='=' read -r pattern label; do
        [[ "$cwd" == *"$pattern"* ]] && dirname="$label" && break
    done < "$labels_file"
fi
```

### Custom service health indicator

To add a health ping for a local service (database, dev server, etc.), add before the output section:

```bash
if curl -sf --max-time 1 "http://localhost:YOUR_PORT/health" >/dev/null 2>&1; then
    sys_parts+=("${green}myservice ●${reset}")
else
    sys_parts+=("${dim}myservice ○${reset}")
fi
```

## License

MIT
