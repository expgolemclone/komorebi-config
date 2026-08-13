#requires -Version 7.0

$ErrorActionPreference = "Stop"

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdministrator)) {
    $pwshPath = (Get-Command pwsh -ErrorAction Stop).Source
    $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    $elevatedProcess = Start-Process `
        -FilePath $pwshPath `
        -ArgumentList $arguments `
        -Verb RunAs `
        -Wait `
        -PassThru
    exit $elevatedProcess.ExitCode
}

$pwshPath = (Get-Command pwsh -ErrorAction Stop).Source
$restartPath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "restart.ps1")).Path
$userId = [Security.Principal.WindowsIdentity]::GetCurrent().Name

$action = New-ScheduledTaskAction `
    -Execute $pwshPath `
    -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$restartPath`""

$trigger = New-ScheduledTaskTrigger -AtLogOn -User $userId
$trigger.Delay = "PT30S"

$principal = New-ScheduledTaskPrincipal `
    -UserId $userId `
    -RunLevel Highest `
    -LogonType Interactive

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit ([TimeSpan]::Zero)

Register-ScheduledTask `
    -TaskName "komorebi" `
    -Action $action `
    -Trigger $trigger `
    -Principal $principal `
    -Settings $settings `
    -Description "Start komorebi from the registered configuration repository" `
    -Force

$legacyShortcutPath = Join-Path `
    $Env:APPDATA `
    "Microsoft\Windows\Start Menu\Programs\Startup\komorebi-restart.lnk"
if (Test-Path -LiteralPath $legacyShortcutPath -PathType Leaf) {
    Remove-Item -LiteralPath $legacyShortcutPath -Force
    Write-Host "Removed obsolete startup shortcut: $legacyShortcutPath"
}

Write-Host "Registered scheduled task 'komorebi' for: $restartPath"
