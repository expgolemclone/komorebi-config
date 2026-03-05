# test-auto-distribute.ps1
# auto-distribute.ps1 and restart.ps1 validation tests

$ErrorCount = 0
$PassCount = 0

function Test-Check {
    param([string]$Name, [bool]$Condition, [string]$Message)
    if ($Condition) {
        Write-Host "[PASS] $Name" -ForegroundColor Green
        $script:PassCount++
    } else {
        Write-Host "[FAIL] $Name - $Message" -ForegroundColor Red
        $script:ErrorCount++
    }
}

Write-Host "=== auto-distribute.ps1 tests ===" -ForegroundColor Cyan
Write-Host ""

# Test 1: file exists
$scriptPath = "$PSScriptRoot\auto-distribute.ps1"
Test-Check "File exists" (Test-Path $scriptPath) "auto-distribute.ps1 not found"

# Test 2: no syntax errors
$syntaxErrors = $null
$tokens = $null
[System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$syntaxErrors) | Out-Null
Test-Check "Syntax check" ($syntaxErrors.Count -eq 0) "Syntax errors: $($syntaxErrors | ForEach-Object { $_.Message })"

# Test 3: required keywords present
$content = Get-Content $scriptPath -Raw -Encoding UTF8

Test-Check "subscribe-pipe call" ($content -match "subscribe-pipe") "subscribe-pipe call missing"
Test-Check "unsubscribe-pipe call" ($content -match "unsubscribe-pipe") "unsubscribe-pipe call missing"
Test-Check "Manage event filter" ($content -match 'Manage') "Manage event filter missing"
Test-Check "komorebic state call" ($content -match "komorebic state") "komorebic state call missing"
Test-Check "move-to-workspace call" ($content -match "move-to-workspace") "move-to-workspace call missing"
# komorebi is the client; our script must create the pipe as a server
Test-Check "NamedPipeServerStream usage" ($content -match "NamedPipeServerStream") "Named Pipe server missing"
Test-Check "JSON parse" ($content -match "ConvertFrom-Json") "ConvertFrom-Json call missing"

# Test 4: move condition logic
Test-Check "Move condition: container count >= 2" ($content -match '\$currentCount\s*-ge\s*2') "currentCount >= 2 condition missing"
Test-Check "Move condition: different workspace" ($content -match '\$minIdx\s*-ne\s*\$focusedIdx') "minIdx -ne focusedIdx condition missing"

# Test 4b: UTF-8 encoding is set (required for parsing komorebic state with Japanese titles)
Test-Check "UTF-8 OutputEncoding" ($content -match 'OutputEncoding.*UTF8') "UTF-8 OutputEncoding setting missing"

# Test 5: restart.ps1 changes
Write-Host ""
Write-Host "=== restart.ps1 tests ===" -ForegroundColor Cyan
Write-Host ""

$restartPath = "$PSScriptRoot\restart.ps1"
$restartContent = Get-Content $restartPath -Raw -Encoding UTF8

Test-Check "restart.ps1: background launch" ($restartContent -match "auto-distribute") "auto-distribute launch missing"
Test-Check "restart.ps1: hidden window" ($restartContent -match "Hidden.*auto-distribute|auto-distribute.*Hidden") "WindowStyle Hidden launch missing"
# pwsh (PowerShell 7) is required for reliable JSON parsing of large komorebic state
Test-Check "restart.ps1: uses pwsh" ($restartContent -match "Start-Process pwsh.*auto-distribute") "should use pwsh instead of powershell"
# The stop logic spans multiple lines, so use (?s) to make '.' match newlines too
Test-Check "restart.ps1: stop process" ($restartContent -match "(?s)auto-distribute.*Stop-Process") "auto-distribute stop process missing"

# Test 6: restart.ps1 syntax check
$restartErrors = $null
$restartTokens = $null
[System.Management.Automation.Language.Parser]::ParseFile($restartPath, [ref]$restartTokens, [ref]$restartErrors) | Out-Null
Test-Check "restart.ps1: syntax check" ($restartErrors.Count -eq 0) "Syntax errors: $($restartErrors | ForEach-Object { $_.Message })"

# Summary
Write-Host ""
Write-Host "=== Results ===" -ForegroundColor Cyan
Write-Host "PASS: $PassCount / $($PassCount + $ErrorCount)" -ForegroundColor $(if ($ErrorCount -eq 0) { 'Green' } else { 'Yellow' })
if ($ErrorCount -gt 0) {
    Write-Host "FAIL: $ErrorCount test(s) failed" -ForegroundColor Red
    exit 1
} else {
    Write-Host "All tests passed!" -ForegroundColor Green
    exit 0
}
