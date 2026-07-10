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

# ── Time format ───────────────────────────────────────
$input_fmt = Read-Host "Time format [12h = 2:34pm / 24h = 14:34] (current: $TimeFormat). Enter 12h or 24h, or press Enter to keep"
$input_fmt = $input_fmt.Trim()
if ($input_fmt -eq "12h" -or $input_fmt -eq "24h") {
    $TimeFormat = $input_fmt
} elseif ($input_fmt -ne "") {
    Write-Host "  Unknown value '$input_fmt', keeping $TimeFormat"
}

# ── Statusline mode ───────────────────────────────────
$input_mode = Read-Host "Statusline mode [full = multi-line / compact = single line] (current: $StatuslineMode). Enter full or compact, or press Enter to keep"
$input_mode = $input_mode.Trim()
if ($input_mode -eq "full" -or $input_mode -eq "compact") {
    $StatuslineMode = $input_mode
} elseif ($input_mode -ne "") {
    Write-Host "  Unknown value '$input_mode', keeping $StatuslineMode"
}

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
