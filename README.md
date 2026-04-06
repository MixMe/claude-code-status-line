# claude-code-statusline

[![ShellCheck](https://github.com/MixMe/claude-code-status-line/actions/workflows/shellcheck.yml/badge.svg)](https://github.com/MixMe/claude-code-status-line/actions/workflows/shellcheck.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-1.3.0-blue.svg)](https://github.com/MixMe/claude-code-status-line/releases)
![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux%20%7C%20Windows-lightgrey)
![Dependencies](https://img.shields.io/badge/dependencies-zero-brightgreen)

A rich, zero-dependency status line for [Claude Code](https://claude.ai/code) — model info, context usage, rate-limit bars, git status, system metrics, and auto-update notifications.

## Preview

**Compact mode** — single line:

![compact](preview-compact.png)

**Flex mode** — line + rate bars + system info:

![flex](preview-flex.png)

## Install / Update

One command — installs fresh or updates existing:

```bash
curl -fsSL https://raw.githubusercontent.com/MixMe/claude-code-status-line/main/install.sh | bash
```

Restart Claude Code to apply. No dependencies to install — uses `node` that ships with Claude Code.

**Windows (PowerShell):**

```powershell
irm https://raw.githubusercontent.com/MixMe/claude-code-status-line/main/install.ps1 | iex
```

Also works in WSL or [Git Bash](https://git-scm.com/downloads/win) with the `curl | bash` command above.

## What it shows

**Line 1 — Session**
| Field | Description |
|---|---|
| Model name | Color-coded: cyan = Haiku, blue = Sonnet, magenta = Opus |
| Context % | Usage bar with color gradient (green -> orange -> yellow -> red) |
| Cache hit | `cache_read / total_tokens` — higher = faster responses |
| Long chat | Red warning when context exceeds 200k tokens |
| Directory | Current working directory |
| Git | Branch, dirty count (`3~`), ahead/behind (`↑1↓0`), last commit age |
| Duration | Session time elapsed |
| Effort | `default` / `high` / `low` |
| Thinking | Shown when extended thinking is active |
| !perms | Warning when `bypassPermissions` is enabled |

**Line 2 — Rate limits**
| Field | Description |
|---|---|
| 5h | 5-hour usage bar with reset time and countdown |
| 7d | 7-day usage bar with reset date and countdown |
| extra | Monthly extra credits (shown only when enabled) |

**Line 3 — System**
| Field | Description |
|---|---|
| Battery | Color warning at ≤40% / ≤20%. Hidden on desktop. |
| Memory | Free RAM |
| Internet | Connectivity indicator, cached 30s |
| Time | Local clock |
| Update | Notification when newer version is available |

## Requirements

- Claude Code v2.1.80+
- `bash` 4+, `curl`
- macOS, Linux, or Windows (WSL / Git Bash)

## How rate limits work

Rate limits (5h and 7d) are read directly from Claude Code's stdin JSON — **zero API calls**, always fresh.

**Extra usage** (monthly credits) is fetched from the API with smart caching:
- Cached for 3 minutes
- Backs off 5 min on rate limit (429), 10 min on auth error
- Stale data shown with age indicator (max 10 min)

## Customization

### Custom project labels

Map directory paths to short labels. Create `~/.config/claude-statusline/labels`:

```
my-api=api
my-frontend=ui
```

Add to the working directory section of `statusline.sh`:

```bash
labels_file="$HOME/.config/claude-statusline/labels"
if [ -f "$labels_file" ]; then
    while IFS='=' read -r pattern label; do
        [[ "$cwd" == *"$pattern"* ]] && dirname="$label" && break
    done < "$labels_file"
fi
```

### Service health indicator

Add a health check for local services (database, dev server, etc.):

```bash
if curl -sf --max-time 1 "http://localhost:YOUR_PORT/health" >/dev/null 2>&1; then
    sys_parts+=("${green}myservice ●${reset}")
else
    sys_parts+=("${dim}myservice ○${reset}")
fi
```

### Time format

The installer asks for 12h/24h preference. To change later, edit `~/.config/claude-statusline/config`:

```
TIME_FORMAT=24h
```

## Changelog

### v1.3.0
- **Locale fix**: force `LC_NUMERIC=C` and `LC_TIME=C` so `printf`/`awk` parse JSON floats (e.g. `28.5`) and `date` outputs English month names on locales like `ru_RU.UTF-8` / `de_DE.UTF-8` / `fr_FR.UTF-8` (common on Fedora). Fixes broken 5-hour / 7-day progress blocks.
- **English-only labels, no abbreviations**: `bat` → `battery`, `mem` → `memory`, `net` → `network`, `5h` → `5-hour`, `7d` → `7-day`, `!perms` → `!permissions`, `gb`/`mb` → `GB`/`MB`.
- **Interactive time-format picker**: `install.sh` now uses an arrow-key selector (↑/↓, j/k, 1/2, Enter) instead of typing `12h`/`24h`. Cursor restored on Ctrl+C via `trap`.
- **Windows support**: PowerShell installer (`install.ps1`), Git Bash compatibility, credential path fallbacks.
- **ShellCheck clean**: all SC2059 / SC2154 warnings fixed.

### v1.2.0
- **Zero dependencies**: replaced `jq` with `node` (ships with Claude Code). Nothing to install.
- **Single node call**: parses stdin JSON + settings.json in one process (was ~20 `jq` calls).

### v1.1.0
- **stdin-first rate limits**: reads from Claude Code stdin, no API polling.
- **Rate-limit backoff**: lock file prevents API hammering on 429.
- **Long chat warning**: shown when context exceeds 200k tokens.
- **Auto-update check**: daily GitHub check with notification.
- **One-command install**: `curl | bash` for all platforms.

### v1.0.0
- Initial release: model, context, cost, git, rate limits, battery, memory, network.

## License

MIT
