#requires -Version 7.0

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true
$allPassed = $true
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..\..")).Path
$restartPath = Join-Path $repoRoot "scripts\restart.ps1"

Write-Host "=== restart.ps1 integration test ===" -ForegroundColor Cyan

try {
    & $restartPath
} catch {
    Write-Host "FAIL: restart.ps1 failed: $_" -ForegroundColor Red
    exit 1
}

$expectedProcesses = @("komorebi", "komorebi-bar", "whkd")
foreach ($name in $expectedProcesses) {
    $process = Get-Process -Name $name -ErrorAction SilentlyContinue
    if ($process) {
        Write-Host "PASS: $name is running" -ForegroundColor Green
    } else {
        Write-Host "FAIL: $name is not running" -ForegroundColor Red
        $allPassed = $false
    }
}

$whkdProcess = Get-Process -Name whkd -ErrorAction SilentlyContinue
if (-not $whkdProcess -or $whkdProcess.MainWindowHandle -ne 0) {
    Write-Host "FAIL: whkd does not run without a visible window" -ForegroundColor Red
    $allPassed = $false
} else {
    Write-Host "PASS: whkd has no visible window" -ForegroundColor Green
}

$komorebicPath = (Get-Command komorebic -ErrorAction Stop).Source
$state = & $komorebicPath state | ConvertFrom-Json
foreach ($monitor in $state.monitors.elements) {
    $workspaces = @($monitor.workspaces.elements)
    if ($workspaces.Count -ne 1) {
        Write-Host "FAIL: monitor has $($workspaces.Count) workspaces" -ForegroundColor Red
        $allPassed = $false
        continue
    }
    if ($workspaces[0].layout.Default -ne "Rows") {
        Write-Host "FAIL: workspace layout is not Rows" -ForegroundColor Red
        $allPassed = $false
    }
}

if (-not $allPassed) {
    exit 1
}

Write-Host "ALL TESTS PASSED" -ForegroundColor Green
exit 0
