# claude-code-statusline

[![ShellCheck](https://github.com/MixMe/claude-code-status-line/actions/workflows/shellcheck.yml/badge.svg)](https://github.com/MixMe/claude-code-status-line/actions/workflows/shellcheck.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-1.6.2-blue.svg)](https://github.com/MixMe/claude-code-status-line/releases)
![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux%20%7C%20Windows-lightgrey)
![Dependencies](https://img.shields.io/badge/dependencies-zero-brightgreen)

A rich, zero-dependency status line for [Claude Code](https://claude.ai/code) — model info, context usage, rate-limit bars, git status, system metrics, and auto-update notifications.

## Preview

**Full mode** (default) — three-block layout with rate-limit bars and system info:

![preview full](preview-full.svg)

**Compact mode** — single line, terse, model plus credit remainders:

![preview compact](preview-compact.svg)

Switch between them at install time or any time via
`STATUSLINE_MODE=compact` / `STATUSLINE_MODE=full` in
`~/.config/claude-statusline/config`.

## Install / Update

One command — installs fresh or updates existing:

```bash
curl -fsSL https://raw.githubusercontent.com/MixMe/claude-code-status-line/main/install.sh | bash
```

Restart Claude Code to apply. No dependencies to install — the status line parses JSON with whichever of `jq`, `python3`, or `node` is already on your system, and falls back to a pure `awk` parser (always present wherever `bash` runs) if none are. It no longer requires Node — Claude Code's native install stopped bundling it.

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

One bar per category, dynamically discovered. The list always contains
`5-hour` and `7-day` (read from stdin, always present); every other row
is enumerated from `/api/oauth/usage` and rendered automatically — new
categories Anthropic adds in the future appear without a code change.

| Field | Description |
|---|---|
| 5-hour | 5-hour usage bar with reset time and countdown |
| 7-day | 7-day usage bar with reset date and countdown |
| sonnet / opus / ... | Per-model weekly sub-limits (Max plan only). Each `seven_day_*` field present in `/api/oauth/usage` becomes its own row, with the `seven_day_` prefix stripped. |
| extra | Monthly prepaid credits, shown when `extra_usage.is_enabled` is true. |
| codenames | Internal slots Anthropic ships before they have a public name (e.g. `omelette`, `iguana_necktie`) appear under their raw key so new limit types are visible the day they activate. |

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
- `bash` 3.2+, `curl`, plus the standard POSIX tools (`awk`, `sed`, `grep`, `date`) — all present by default on macOS, Linux, and Git Bash
- macOS, Linux, or Windows (WSL / Git Bash)

**JSON parsing** is automatic and degrades gracefully: the script picks the first of `jq` → `python3` / `python` → `node` that actually **works** — each candidate is executed as a probe, not merely found on `PATH`, so Windows' Microsoft Store `python.exe` / `python3.exe` stub aliases can never be mistaken for a real interpreter — and if none do, falls back to a built-in `awk` parser. Under the `awk` fallback the core line still renders (model, context, 5-hour, 7-day); only the `/api/oauth/usage` extras (per-model weekly limits and prepaid credits) are omitted, since that nested response needs a real JSON parser. For the full feature set, install any one of `jq` / `python3` / `node` (`jq` recommended — `brew install jq`, `apt install jq`).

> **Upgrading from ≤ v1.5.x and seeing `Claude | ctx 0% (0/200k)`?** Earlier versions hard-depended on `node`. When Claude Code switched to a native install (no bundled Node) — or after a Homebrew Node upgrade left `node` keg-only and off `PATH` — that dependency silently broke every field. v1.6.0 removes the hard Node dependency; re-run the installer (or `git pull`) to fix it.
>
> **Same blank line on Windows with v1.6.0?** That release's parser detection was fooled by Windows' Microsoft Store `python3` stub alias. v1.6.1 probes each candidate by executing it — re-run the installer to fix.

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/MixMe/claude-code-status-line/main/install.sh | bash -s -- --uninstall
```

Or, from a local clone:

```bash
bash uninstall.sh            # also: bash install.sh --uninstall
```

This removes the `statusLine` entry from `~/.claude/settings.json` (leaving every other setting intact), deletes `~/.claude/statusline.sh`, clears caches, and removes `~/.config/claude-statusline/`. Pass `--keep-config` to preserve your `config` file. Restart Claude Code to apply.

## Statusline modes

Two rendering modes, selected at install time and switchable via config:

- **full** (default) — three-block multi-line layout: session info, rate-limit bars, system metrics. What you see in the "Line 1 / Line 2 / Line 3" tables above.
- **compact** — single-line terse output: model, context (with absolute token counts), and rate-limit usage for every category present in the API response (5-hour, 7-day, Sonnet, Opus, extra, plus any future or codename slots Anthropic ships). Percentages use the **same semantic as full mode** (used, not remaining), so a given metric shows the exact same number in both layouts. Colour urgency tracks usage: green = low, red = near exhaustion.

Switch at any time by editing `~/.config/claude-statusline/config`:

```
STATUSLINE_MODE=compact
```

or re-run the installer and pick interactively.

## How rate limits work

The 5-hour and 7-day usage percentages are read directly from Claude Code's stdin JSON — **zero API calls**, always fresh on every render.

Every other rate-limit category (Sonnet weekly, Opus weekly, prepaid credits, future / codename slots) is fetched from the `/api/oauth/usage` endpoint and cached together:
- Single API call — every category comes out of one response
- Cached for 3 minutes
- Backs off 5 min on rate limit (429), 10 min on auth error
- Stale data shown with age indicator (max 10 min)
- Categories are enumerated dynamically: any non-null top-level field that matches one of the two known shapes (`{utilization, resets_at}` or `{is_enabled, monthly_limit, used_credits, currency}`) becomes its own row. Hardcoded "sonnet" / "extra" parsing was replaced in v1.5.0 so new limit types Anthropic ships are visible automatically.

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

### Time format and mode

The installer asks for time format and statusline mode interactively. To change later, edit `~/.config/claude-statusline/config`:

```
TIME_FORMAT=24h
STATUSLINE_MODE=compact
```

`TIME_FORMAT` accepts `12h` or `24h`. `STATUSLINE_MODE` accepts `full` or `compact`.

## Changelog

### v1.6.2
- **Fix: Windows numbers rendered raw and rate-limit time-left went missing** (e.g. `ctx 13% (0/1000000)` instead of `ctx 13% (0/1.0m)`, and `5h 39%` with no `2h 1m` reset countdown). When the JSON backend is Windows `python`, `print()` emits CRLF line endings, so every parsed value arrived with a trailing `\r`. That made `[ -ge ]` integer tests error out (so `format_tokens` printed the raw number instead of `1.0m`/`130k`), collapsed the `input_tokens + cache_*` context sum to `0`, and broke the reset-epoch math (so no time-left was shown). The stdin parse loop now strips a trailing `\r` from every value — the same defence the config reader already used.
- **`install.ps1` interactive picker brought to full parity with `install.sh`.** Time format and statusline mode are now chosen from an **arrow-key menu** (↑/↓/←/→, `j`/`k`, number keys, Enter to confirm), with the current value pre-highlighted — no more typing `12h` / `full` by hand. Falls back to keeping the current value when there is no interactive console (piped install / CI), mirroring the macOS `has_tty` skip.

### v1.6.1
- **Fix: Windows regression from v1.6.0 — status line collapsed to `Claude | ctx 0% (0/200k)`.** The v1.6.0 backend detection checked only that a command *exists* on `PATH`. Windows ships Microsoft Store "app execution alias" stubs (`python.exe` / `python3.exe` in `WindowsApps`) that sit on `PATH` even when Python is **not installed**; the stub won the `python3` detection slot ahead of a working `node`, every parse failed silently (stderr is suppressed by design), and all fields fell back to defaults. Every candidate is now **functionally probed** — actually executed against a tiny input — before being selected, so a broken tool can never shadow a working one. This also hardens the original macOS keg-only-node case the v1.6.0 change was aimed at.
- **`python` (without the `3`) added as a detection candidate** after `python3` — a real Windows Python install provides `python.exe`, not `python3.exe`.
- **Fix: `TIME_FORMAT=24h` ignored on Windows.** `install.ps1` wrote the config file with CRLF line endings, so bash read the value as `24h<CR>` and the `24h` comparison never matched. The installer now writes LF, and the statusline strips a stray `\r` when reading configs left behind by older installs.
- **`install.ps1` brought to parity with `install.sh`**: asks for statusline mode (`full` / `compact`), preserves both existing settings on re-install, clears stale caches.
- **`install.sh` patches `settings.json` via the same functional probing** (and gains the `python` candidate too).

### v1.6.0
- **Fix: status line went blank (`Claude | ctx 0% (0/200k)`) when Node left `PATH`.** Every field was parsed through `node`, so Claude Code's native install (which no longer bundles Node) — or a Homebrew `node` upgrade that left only a keg-only `node@NN` off `PATH` — silently zeroed out the entire line. The hard Node dependency is gone.
- **Portable JSON parsing with graceful degradation.** The script now detects the best available parser at runtime — `jq` → `python3` → `node` → `awk` — and routes every parse through it. The `awk` last resort is always present wherever `bash` runs, so the core line (model, context, 5-hour, 7-day) renders even with none of the three JSON runtimes installed; only the nested `/api/oauth/usage` extras (per-model weekly limits, prepaid credits) need a real JSON parser and are skipped under `awk`. This makes the "zero-dependency" promise genuinely true again.
- **`install.sh` no longer requires Node either** — it patches `settings.json` via the same `jq` / `python3` / `node` detection, and prints a manual snippet if none are present.
- **New uninstaller.** `uninstall.sh` (also `install.sh --uninstall`, or `curl … | bash -s -- --uninstall`) removes the `statusLine` key from `settings.json`, deletes the installed script, clears caches, and removes the config dir (`--keep-config` to preserve it). Closes the long-standing "there is no uninstall" gap.

### v1.5.0
- **Dynamic rate-limit discovery**: every non-null top-level field in the `/api/oauth/usage` response is now rendered as its own bar, so categories the previous parser ignored (`seven_day_opus`, `seven_day_omelette`, internal codename slots like `iguana_necktie`) are visible the moment Anthropic activates them. New limit types added in the future no longer need a code change to appear in the statusline.
- **Consistent label padding**: all rows in full mode now share the same label width — computed once across the whole set — so bars line up vertically regardless of which categories the API returned.
- **Compact mode covers everything too**: the single-line layout iterates the same record list as full mode, so any newly-discovered category appears in compact rendering as well, not just full.
- **Internals**: replaced the hardcoded `seven_day_sonnet` / `extra_usage` parser with a generic enumerator that classifies each field into one of two known shapes (`{utilization, resets_at}` for percentage bars, `{is_enabled, monthly_limit, used_credits, currency}` for credit bars). Anything else is silently skipped. The dropped `*_enabled` / `*_pct` / `*_used` / `*_limit` defaults are no longer referenced.

### v1.4.1
- **Fix: compact mode rate-limit percentages now match full mode**. v1.4.0 displayed compact-mode 5-hour / 7-day / Sonnet as *remaining* (100 − used) while `ctx` and full-mode bars continued to show *used*, which made identical metrics read as different numbers depending on layout (e.g. 7-day at 82% used appeared as `7d 18%` in compact but `82%` in full). All percentages are now used, consistently, in both modes.

### v1.4.0
- **Sonnet weekly sub-limit**: new third rate-limit line showing the Sonnet-specific weekly quota enforced on Max plans, parsed from the same `/api/oauth/usage` response already fetched for extra usage — no additional API calls. Silently hidden on non-Max plans.
- **Compact single-line mode**: opt-in single-line layout showing model, context (with absolute token counts), and credit remainders for 5-hour / 7-day / Sonnet / extra. Rate-limit percentages are shown as remaining, so the number reads as "how much budget I still have" while colour urgency still tracks usage. Full mode remains default and untouched; compact is strictly additive.
- **Interactive mode picker at install**: the installer now asks for `full` vs `compact` in addition to the existing time-format question, using the same arrow-key selector.
- **Fix: arrow-key selection on bash 3.2 (macOS default)**: the fractional `read -t 0.05` timeout in the interactive picker failed immediately on macOS' bundled bash 3.2 with "invalid timeout specification", silently swallowing arrow-key escape sequences so only the 1/2 hotkeys worked. Switched to integer `-t 1` which is supported on bash 3.2+.
- **Perf: fewer forks per render**: node invocations reduced from 4 to 2 per render by merging the Sonnet and extra-usage parsers into a single process and removing the has_extra caching gate. Git invocations reduced from 5 to 2 by replacing the `rev-parse` / `symbolic-ref` / `status --porcelain` / `rev-list --count --left-right` combo with a single `git status --porcelain=v2 --branch` that yields inside-work-tree, branch, ahead/behind and dirty count in one call.
- **Docs**: README now documents the two modes with separate preview images and expanded rate-limit explanation.

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
