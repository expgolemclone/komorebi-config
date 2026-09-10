#requires -Version 7.0

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true
$allPassed = $true
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..\..")).Path
$restartPath = Join-Path $repoRoot "scripts\restart.ps1"
$whkdConfigPath = Join-Path $repoRoot "whkdrc"
$komorebicPath = (Get-Command komorebic -ErrorAction Stop).Source
$whkdPath = (Get-Command whkd -ErrorAction Stop).Source

Write-Host "=== restart.ps1 integration test ===" -ForegroundColor Cyan

$nightLightServiceBefore = Get-CimInstance `
    -ClassName Win32_Service `
    -Filter "Name='DisplayEnhancementService'"
if (-not $nightLightServiceBefore) {
    Write-Host "FAIL: DisplayEnhancementService was not found" -ForegroundColor Red
    exit 1
}
$nightLightProcessIdBefore = [uint32]$nightLightServiceBefore.ProcessId

$runningProcesses = Get-Process -Name @("komorebi", "komorebi-bar", "whkd") -ErrorAction SilentlyContinue
if ($runningProcesses) {
    Stop-Process -Id $runningProcesses.Id -Force
}

$whkdArguments = "-c `"$whkdConfigPath`""
$orphanedWhkd = Start-Process `
    -FilePath $whkdPath `
    -ArgumentList $whkdArguments `
    -WindowStyle Hidden `
    -PassThru
Start-Sleep -Milliseconds 500
if ($orphanedWhkd.HasExited) {
    Write-Host "FAIL: failed to prepare an orphaned whkd process" -ForegroundColor Red
    exit 1
}
Write-Host "Prepared orphaned whkd process: $($orphanedWhkd.Id)" -ForegroundColor Cyan

try {
    & $restartPath
} catch {
    Write-Host "FAIL: restart.ps1 failed: $_" -ForegroundColor Red
    exit 1
}

$expectedProcesses = @("komorebi", "whkd")
foreach ($name in $expectedProcesses) {
    $processes = @(Get-Process -Name $name -ErrorAction SilentlyContinue)
    if ($processes.Count -eq 1) {
        Write-Host "PASS: exactly one $name process is running" -ForegroundColor Green
    } else {
        Write-Host "FAIL: expected one $name process, found $($processes.Count)" -ForegroundColor Red
        $allPassed = $false
    }
}

$barProcesses = @(Get-Process -Name "komorebi-bar" -ErrorAction SilentlyContinue)
if ($barProcesses.Count -eq 0) {
    Write-Host "PASS: komorebi-bar is not running" -ForegroundColor Green
} else {
    Write-Host "FAIL: komorebi-bar is running" -ForegroundColor Red
    $allPassed = $false
}

$nightLightServiceAfter = Get-CimInstance `
    -ClassName Win32_Service `
    -Filter "Name='DisplayEnhancementService'"
$nightLightProcessIdAfter = [uint32]$nightLightServiceAfter.ProcessId
if ($nightLightServiceAfter.State -ne "Running" -or $nightLightProcessIdAfter -eq 0) {
    Write-Host `
        "FAIL: DisplayEnhancementService is not running after restart.ps1" `
        -ForegroundColor Red
    $allPassed = $false
} elseif (
    $nightLightProcessIdBefore -ne 0 -and
    $nightLightProcessIdAfter -eq $nightLightProcessIdBefore
) {
    Write-Host `
        "FAIL: DisplayEnhancementService process ID did not change" `
        -ForegroundColor Red
    $allPassed = $false
} else {
    Write-Host `
        "PASS: DisplayEnhancementService restarted and is running" `
        -ForegroundColor Green
}

$whkdProcess = Get-Process -Name whkd -ErrorAction SilentlyContinue
if (-not $whkdProcess -or $whkdProcess.MainWindowHandle -ne 0) {
    Write-Host "FAIL: whkd does not run without a visible window" -ForegroundColor Red
    $allPassed = $false
} else {
    Write-Host "PASS: whkd has no visible window" -ForegroundColor Green
}

$state = & $komorebicPath state | ConvertFrom-Json
foreach ($monitor in $state.monitors.elements) {
    $workspaces = @($monitor.workspaces.elements)
    if ($workspaces.Count -ne 1) {
        Write-Host "FAIL: monitor has $($workspaces.Count) workspaces" -ForegroundColor Red
        $allPassed = $false
        continue
    }

    $width = [int]$monitor.size.right
    $height = [int]$monitor.size.bottom
    if ($width -gt $height) {
        $expectedLayout = "Columns"
    } else {
        $expectedLayout = "Rows"
    }

    if ($workspaces[0].layout.Default -ne $expectedLayout) {
        Write-Host "FAIL: workspace layout is $($workspaces[0].layout.Default), expected $expectedLayout for ${width}x${height}" -ForegroundColor Red
        $allPassed = $false
    } else {
        Write-Host "PASS: ${width}x${height} monitor uses $expectedLayout" -ForegroundColor Green
    }
}

if (-not $allPassed) {
    exit 1
}

Write-Host "ALL TESTS PASSED" -ForegroundColor Green
exit 0
