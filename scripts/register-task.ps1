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
$komorebicPath = (Get-Command komorebic -ErrorAction Stop).Source
$barPath = (Get-Command komorebi-bar -ErrorAction Stop).Source
$whkdPath = (Get-Command whkd -ErrorAction Stop).Source
$komorebiBin = Split-Path -Path $komorebicPath -Parent
$barBin = Split-Path -Path $barPath -Parent
$whkdBin = Split-Path -Path $whkdPath -Parent
if ($barBin -ne $komorebiBin) {
    throw "komorebic and komorebi-bar must be installed in the same directory"
}
$autoHotkeyInstallLocation = Get-ItemPropertyValue `
    -LiteralPath "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\AutoHotkey" `
    -Name "InstallLocation" `
    -ErrorAction Stop
$autoHotkeyPath = Join-Path $autoHotkeyInstallLocation "v2\AutoHotkey64.exe"
if (-not (Test-Path -LiteralPath $autoHotkeyPath -PathType Leaf)) {
    throw "AutoHotkey v2 executable was not found: $autoHotkeyPath"
}
$userId = [Security.Principal.WindowsIdentity]::GetCurrent().Name

$action = New-ScheduledTaskAction `
    -Execute $pwshPath `
    -Argument ( `
        "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden " +
        "-File `"$restartPath`" " +
        "-KomorebiBin `"$komorebiBin`" " +
        "-WhkdBin `"$whkdBin`" " +
        "-AutoHotkeyPath `"$autoHotkeyPath`""
    )

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
