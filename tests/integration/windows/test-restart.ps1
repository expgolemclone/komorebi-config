#requires -Version 7.0

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true
$allPassed = $true
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..\..")).Path
$restartPath = Join-Path $repoRoot "scripts\restart.ps1"
$whkdConfigPath = Join-Path $repoRoot "whkdrc"
$komorebicPath = (Get-Command komorebic -ErrorAction Stop).Source
$whkdPath = (Get-Command whkd -ErrorAction Stop).Source

function Get-NightLightDataSnapshot {
    $cloudStorePath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\CloudStore\Store\DefaultAccount\Cloud"
    $snapshotParts = @(
        Get-ChildItem -LiteralPath $cloudStorePath -Recurse -ErrorAction Stop |
            Where-Object { $_.Name -match "bluelightreduction" } |
            Sort-Object Name |
            ForEach-Object {
                $properties = Get-ItemProperty `
                    -LiteralPath $_.PSPath `
                    -ErrorAction Stop
                $data = $properties.Data
                if ($null -ne $data) {
                    "$($_.Name)=$([Convert]::ToHexString([byte[]]$data))"
                }
            }
    )

    return $snapshotParts -join "`n"
}

Write-Host "=== restart.ps1 integration test ===" -ForegroundColor Cyan

if (-not (Test-Path -LiteralPath $restartPath -PathType Leaf)) {
    Write-Host "FAIL: restart.ps1 was not found" -ForegroundColor Red
    exit 1
}
$restartTask = Get-ScheduledTask `
    -TaskName "komorebi" `
    -TaskPath "\" `
    -ErrorAction SilentlyContinue
if ($null -eq $restartTask) {
    Write-Host "FAIL: managed komorebi Scheduled Task was not found" -ForegroundColor Red
    exit 1
}
$taskInfoBefore = Get-ScheduledTaskInfo `
    -TaskName "komorebi" `
    -TaskPath "\" `
    -ErrorAction Stop

$displayAdapters = @(
    Get-PnpDevice `
        -Class "Display" `
        -PresentOnly `
        -Status "OK" `
        -ErrorAction Stop
)
if ($displayAdapters.Count -ne 1) {
    Write-Host `
        "FAIL: expected one healthy display adapter, found $($displayAdapters.Count)" `
        -ForegroundColor Red
    exit 1
}
$displayAdapter = $displayAdapters[0]
$displayAdapterArrivalBefore = (
    Get-PnpDeviceProperty `
        -InstanceId $displayAdapter.InstanceId `
        -KeyName "DEVPKEY_Device_LastArrivalDate" `
        -ErrorAction Stop
).Data
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class RestartTestPhysicalScreenCoordinates
{
    [DllImport("user32.dll", SetLastError = true)]
    public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
}
'@
if ([RestartTestPhysicalScreenCoordinates]::SetThreadDpiAwarenessContext([IntPtr](-4)) -eq [IntPtr]::Zero) {
    throw "failed to enable per-monitor DPI awareness"
}
Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
$activeScreenCountBefore = [System.Windows.Forms.Screen]::AllScreens.Count
$nightLightDataBefore = Get-NightLightDataSnapshot

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

Start-ScheduledTask `
    -TaskName "komorebi" `
    -TaskPath "\" `
    -ErrorAction Stop
$taskDeadline = [DateTime]::UtcNow.AddMinutes(2)
do {
    Start-Sleep -Milliseconds 500
    $restartTask = Get-ScheduledTask `
        -TaskName "komorebi" `
        -TaskPath "\" `
        -ErrorAction Stop
    $taskInfoAfter = Get-ScheduledTaskInfo `
        -TaskName "komorebi" `
        -TaskPath "\" `
        -ErrorAction Stop
    if (
        $restartTask.State -eq "Ready" -and
        $taskInfoAfter.LastRunTime -gt $taskInfoBefore.LastRunTime
    ) {
        break
    }
} while ([DateTime]::UtcNow -lt $taskDeadline)

if (
    $restartTask.State -ne "Ready" -or
    $taskInfoAfter.LastRunTime -le $taskInfoBefore.LastRunTime
) {
    Write-Host "FAIL: komorebi Scheduled Task did not finish" -ForegroundColor Red
    exit 1
}
if ($taskInfoAfter.LastTaskResult -ne 0) {
    Write-Host `
        "FAIL: restart.ps1 task failed with result $($taskInfoAfter.LastTaskResult)" `
        -ForegroundColor Red
    exit 1
}
Write-Host "PASS: restart.ps1 task completed successfully" -ForegroundColor Green

$displayAdapterAfter = Get-PnpDevice `
    -InstanceId $displayAdapter.InstanceId `
    -ErrorAction SilentlyContinue
$displayAdapterArrivalAfter = (
    Get-PnpDeviceProperty `
        -InstanceId $displayAdapter.InstanceId `
        -KeyName "DEVPKEY_Device_LastArrivalDate" `
        -ErrorAction Stop
).Data
if (
    $null -eq $displayAdapterAfter -or
    -not $displayAdapterAfter.Present -or
    $displayAdapterAfter.Status -ne "OK"
) {
    Write-Host "FAIL: display adapter did not return healthy" -ForegroundColor Red
    $allPassed = $false
}
elseif ($displayAdapterArrivalAfter -le $displayAdapterArrivalBefore) {
    Write-Host "FAIL: display adapter was not restarted" -ForegroundColor Red
    $allPassed = $false
}
else {
    Write-Host "PASS: display adapter restarted and is healthy" -ForegroundColor Green
}

$activeScreenCountAfter = [System.Windows.Forms.Screen]::AllScreens.Count
if ($activeScreenCountAfter -ne $activeScreenCountBefore) {
    Write-Host `
        "FAIL: active screens changed from $activeScreenCountBefore to $activeScreenCountAfter" `
        -ForegroundColor Red
    $allPassed = $false
}
else {
    Write-Host "PASS: all active screens returned" -ForegroundColor Green
}
if ([RestartTestPhysicalScreenCoordinates]::SetThreadDpiAwarenessContext([IntPtr](-4)) -eq [IntPtr]::Zero) {
    throw "failed to enable per-monitor DPI awareness"
}
$windowsScreenSizes = @(
    [System.Windows.Forms.Screen]::AllScreens |
        ForEach-Object { "$($_.Bounds.Width)x$($_.Bounds.Height)" } |
        Sort-Object
)

$nightLightDataAfter = Get-NightLightDataSnapshot
if ($nightLightDataAfter -cne $nightLightDataBefore) {
    Write-Host "FAIL: Night Light settings data changed" -ForegroundColor Red
    $allPassed = $false
}
else {
    Write-Host "PASS: Night Light settings data was preserved" -ForegroundColor Green
}

$expectedProcesses = @("komorebi", "whkd")
foreach ($name in $expectedProcesses) {
    $processes = @(Get-Process -Name $name -ErrorAction SilentlyContinue)
    if ($processes.Count -eq 1) {
        Write-Host "PASS: exactly one $name process is running" -ForegroundColor Green
    }
    else {
        Write-Host "FAIL: expected one $name process, found $($processes.Count)" -ForegroundColor Red
        $allPassed = $false
    }
}

$barProcesses = @(Get-Process -Name "komorebi-bar" -ErrorAction SilentlyContinue)
if ($barProcesses.Count -eq 0) {
    Write-Host "PASS: komorebi-bar is not running" -ForegroundColor Green
}
else {
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
}
elseif (
    $nightLightProcessIdBefore -ne 0 -and
    $nightLightProcessIdAfter -eq $nightLightProcessIdBefore
) {
    Write-Host `
        "FAIL: DisplayEnhancementService process ID did not change" `
        -ForegroundColor Red
    $allPassed = $false
}
else {
    Write-Host `
        "PASS: DisplayEnhancementService restarted and is running" `
        -ForegroundColor Green
}

$whkdProcess = Get-Process -Name whkd -ErrorAction SilentlyContinue
if (-not $whkdProcess -or $whkdProcess.MainWindowHandle -ne 0) {
    Write-Host "FAIL: whkd does not run without a visible window" -ForegroundColor Red
    $allPassed = $false
}
else {
    Write-Host "PASS: whkd has no visible window" -ForegroundColor Green
}

$state = & $komorebicPath state | ConvertFrom-Json
if ($state.monitors.elements.Count -ne $activeScreenCountBefore) {
    Write-Host `
        "FAIL: komorebi detected $($state.monitors.elements.Count) monitors, expected $activeScreenCountBefore" `
        -ForegroundColor Red
    $allPassed = $false
}
else {
    Write-Host "PASS: komorebi detected every active screen" -ForegroundColor Green
}
$komorebiScreenSizes = @(
    $state.monitors.elements |
        ForEach-Object { "$($_.size.right)x$($_.size.bottom)" } |
        Sort-Object
)
if (($komorebiScreenSizes -join ";") -ne ($windowsScreenSizes -join ";")) {
    Write-Host "FAIL: komorebi monitor sizes $($komorebiScreenSizes -join ', ') differ from Windows $($windowsScreenSizes -join ', ')" -ForegroundColor Red
    $allPassed = $false
} else {
    Write-Host "PASS: komorebi monitor sizes match Windows" -ForegroundColor Green
}
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
    }
    else {
        $expectedLayout = "Rows"
    }

    if ($workspaces[0].layout.Default -ne $expectedLayout) {
        Write-Host "FAIL: workspace layout is $($workspaces[0].layout.Default), expected $expectedLayout for ${width}x${height}" -ForegroundColor Red
        $allPassed = $false
    }
    else {
        Write-Host "PASS: ${width}x${height} monitor uses $expectedLayout" -ForegroundColor Green
    }
}

if (-not $allPassed) {
    exit 1
}

Write-Host "ALL TESTS PASSED" -ForegroundColor Green
exit 0
