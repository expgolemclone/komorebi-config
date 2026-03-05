# test-move-cursor-bottom-center.ps1
# Tests for move-cursor-bottom-center.ps1

$ErrorActionPreference = "Stop"
$configHome = $env:KOMOREBI_CONFIG_HOME
if (-not $configHome) { $configHome = "$env:USERPROFILE\.config\komorebi" }

$passed = 0
$failed = 0

function Assert-True($condition, $message) {
    if ($condition) {
        Write-Host "  PASS: $message" -ForegroundColor Green
        $script:passed++
    } else {
        Write-Host "  FAIL: $message" -ForegroundColor Red
        $script:failed++
    }
}

Write-Host ""
Write-Host "=== move-cursor-bottom-center tests ===" -ForegroundColor Cyan

# 1. Script file exists
$scriptPath = Join-Path $configHome "scripts\move-cursor-bottom-center.ps1"
Assert-True (Test-Path $scriptPath) "script file exists"

# 2. Script has no syntax errors
$parseErrors = $null
[System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$parseErrors)
Assert-True ($parseErrors.Count -eq 0) "script has no syntax errors"

# 3. Script contains required Win32 APIs
$content = Get-Content $scriptPath -Raw
Assert-True ($content -match "GetForegroundWindow") "contains GetForegroundWindow"
Assert-True ($content -match "GetWindowRect") "contains GetWindowRect"
Assert-True ($content -match "SetCursorPos") "contains SetCursorPos"

# 4. whkdrc has cursor move for all 4 directions
$whkdrc = Get-Content (Join-Path $configHome "whkdrc") -Raw
$directions = @("left", "down", "up", "right")
foreach ($dir in $directions) {
    $pattern = 'komorebic focus ' + $dir + '.*move-cursor-bottom-center'
    Assert-True ($whkdrc -match $pattern) "whkdrc: focus $dir chains cursor move"
}

# 5. komorebi.json has mouse_follows_focus disabled
$json = Get-Content (Join-Path $configHome "komorebi.json") -Raw | ConvertFrom-Json
Assert-True ($json.mouse_follows_focus -eq $false) "mouse_follows_focus is false"

# Summary
Write-Host ""
if ($failed -eq 0) { $color = "Green" } else { $color = "Red" }
Write-Host "--- Results: $passed passed, $failed failed ---" -ForegroundColor $color
if ($failed -gt 0) { exit 1 }
