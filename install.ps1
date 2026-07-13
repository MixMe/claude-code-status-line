# claude-code-statusline installer for Windows PowerShell
$ErrorActionPreference = "Stop"

$RepoRaw = "https://raw.githubusercontent.com/MixMe/claude-code-status-line/main"
$ClaudeDir = "$env:USERPROFILE\.claude"
$Target = "$ClaudeDir\statusline.sh"
$Settings = "$ClaudeDir\settings.json"
$ConfigDir = "$env:USERPROFILE\.config\claude-statusline"
$ConfigFile = "$ConfigDir\config"

# ── Download statusline.sh ───────────────────────────
New-Item -ItemType Directory -Force -Path $ClaudeDir | Out-Null
New-Item -ItemType Directory -Force -Path $ConfigDir | Out-Null

Write-Host "Downloading statusline.sh..."
Invoke-WebRequest -Uri "$RepoRaw/statusline.sh" -OutFile $Target -UseBasicParsing

$Version = (Select-String -Path $Target -Pattern '^VERSION="(.+)"' | ForEach-Object { $_.Matches.Groups[1].Value })
if (-not $Version) { $Version = "unknown" }

Write-Host ""
Write-Host "claude-code-statusline v$Version" -ForegroundColor Cyan
Write-Host ""

# ── Load existing config ──────────────────────────────
# .Trim() strips a stray \r left by configs written with CRLF by older
# installer versions.
$TimeFormat = "12h"
$StatuslineMode = "full"
if (Test-Path $ConfigFile) {
    $existing = (Select-String -Path $ConfigFile -Pattern '^TIME_FORMAT=(.+)' | ForEach-Object { $_.Matches.Groups[1].Value.Trim() })
    if ($existing) { $TimeFormat = $existing }
    $existing = (Select-String -Path $ConfigFile -Pattern '^STATUSLINE_MODE=(.+)' | ForEach-Object { $_.Matches.Groups[1].Value.Trim() })
    if ($existing) { $StatuslineMode = $existing }
}

# ── Generic interactive selector ──────────────────────
# PowerShell port of install.sh's select_option: arrow keys / j,k / 1..9 to
# move, Enter to confirm, q to keep current. The current value is
# pre-highlighted (matches the macOS installer — no manual typing). Returns
# the chosen value; falls back to keeping the current value when there is no
# interactive console (piped install, CI), mirroring the macOS `has_tty` skip.
function Select-Option {
    param(
        [string]$Prompt,
        [int]$InitialIndex,
        [string[]]$Labels,
        [string[]]$Values
    )
    $n = $Labels.Count
    $selected = $InitialIndex
    if ($selected -lt 0 -or $selected -ge $n) { $selected = 0 }

    # No interactive console → keep current selection (ReadKey would throw).
    if ([Console]::IsInputRedirected) { return $Values[$selected] }

    Write-Host $Prompt
    try {
        $startTop = [Console]::CursorTop
        [Console]::CursorVisible = $false

        $render = {
            [Console]::SetCursorPosition(0, $startTop)
            for ($i = 0; $i -lt $n; $i++) {
                if ($i -eq $selected) {
                    Write-Host ("  > " + $Labels[$i]).PadRight(72) -ForegroundColor Cyan
                } else {
                    Write-Host ("    " + $Labels[$i]).PadRight(72) -ForegroundColor DarkGray
                }
            }
        }

        & $render
        while ($true) {
            $key = [Console]::ReadKey($true)
            $k = $key.Key
            if ($k -eq 'Enter' -or $k -eq 'Q') { break }
            elseif ($k -eq 'UpArrow' -or $k -eq 'LeftArrow' -or $k -eq 'K') { $selected = ($selected - 1 + $n) % $n }
            elseif ($k -eq 'DownArrow' -or $k -eq 'RightArrow' -or $k -eq 'J') { $selected = ($selected + 1) % $n }
            elseif ([char]::IsDigit($key.KeyChar) -and $key.KeyChar -ne '0') {
                $idx = [int]::Parse([string]$key.KeyChar) - 1
                if ($idx -lt $n) { $selected = $idx }
            }
            & $render
        }
    } catch {
        # Any console/cursor limitation → silently keep the current selection.
    } finally {
        try { [Console]::CursorVisible = $true } catch { }
    }
    return $Values[$selected]
}

# ── Time format ───────────────────────────────────────
$fmtInitial = if ($TimeFormat -eq "24h") { 1 } else { 0 }
$TimeFormat = Select-Option "Select time format (arrow keys / j,k / 1,2, Enter to confirm):" `
    $fmtInitial `
    @("12-hour  (2:34pm)", "24-hour  (14:34)") `
    @("12h", "24h")

# ── Statusline mode ───────────────────────────────────
$modeInitial = if ($StatuslineMode -eq "compact") { 1 } else { 0 }
$StatuslineMode = Select-Option "Select statusline mode (arrow keys / j,k / 1,2, Enter to confirm):" `
    $modeInitial `
    @("full     (multi-line: context, rate-limit bars, system info)", "compact  (single line: model, context, rate-limit remainders)") `
    @("full", "compact")

# The config is consumed by a bash script (Git Bash), so it MUST be written
# with LF line endings and no BOM. PowerShell's Set-Content default (CRLF)
# made the values read as "24h\r" / "compact\r" in bash, so string
# comparisons never matched — that is exactly the bug this avoids.
[IO.File]::WriteAllText($ConfigFile, "TIME_FORMAT=$TimeFormat`nSTATUSLINE_MODE=$StatuslineMode`n")
Write-Host "Time format: $TimeFormat"
Write-Host "Statusline mode: $StatuslineMode"

# ── Clear stale caches ────────────────────────────────
# Git Bash resolves its temp dir from TMP/TEMP, i.e. the Windows temp dir.
$CacheDir = Join-Path $env:TEMP "claude"
if (Test-Path $CacheDir) {
    Remove-Item -Force -ErrorAction SilentlyContinue `
        "$CacheDir\statusline-usage-cache.json", "$CacheDir\statusline-extra-cache.json", `
        "$CacheDir\statusline-extra.lock", "$CacheDir\statusline-update-cache"
}

# ── Patch settings.json ───────────────────────────────
$StatusLineValue = @{
    type = "command"
    command = 'bash "$HOME/.claude/statusline.sh"'
}

if (-not (Test-Path $Settings)) {
    @{ statusLine = $StatusLineValue } | ConvertTo-Json -Depth 3 | Set-Content $Settings
    Write-Host "Created $Settings"
} else {
    $settingsObj = Get-Content $Settings -Raw | ConvertFrom-Json
    if ($null -eq $settingsObj.statusLine) {
        $settingsObj | Add-Member -NotePropertyName "statusLine" -NotePropertyValue $StatusLineValue
        $settingsObj | ConvertTo-Json -Depth 3 | Set-Content $Settings
        Write-Host "Updated $Settings"
    } else {
        Write-Host "statusLine already configured"
    }
}

Write-Host ""
Write-Host "Installed v$Version. Restart Claude Code to apply." -ForegroundColor Green
