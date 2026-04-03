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

# ── Time format ───────────────────────────────────────
$TimeFormat = "12h"
if (Test-Path $ConfigFile) {
    $existing = (Select-String -Path $ConfigFile -Pattern '^TIME_FORMAT=(.+)' | ForEach-Object { $_.Matches.Groups[1].Value })
    if ($existing) { $TimeFormat = $existing }
}

$input_fmt = Read-Host "Time format [12h = 2:34pm / 24h = 14:34] (current: $TimeFormat). Enter 12h or 24h, or press Enter to keep"
$input_fmt = $input_fmt.Trim()
if ($input_fmt -eq "12h" -or $input_fmt -eq "24h") {
    $TimeFormat = $input_fmt
} elseif ($input_fmt -ne "") {
    Write-Host "  Unknown value '$input_fmt', keeping $TimeFormat"
}

Set-Content -Path $ConfigFile -Value "TIME_FORMAT=$TimeFormat"
Write-Host "Time format: $TimeFormat"

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
