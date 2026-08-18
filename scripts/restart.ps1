#requires -Version 7.0

param(
    [string]$KomorebiBin,
    [string]$WhkdBin,
    [string]$AutoHotkeyPath
)

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

$hasKomorebiBin = -not [string]::IsNullOrWhiteSpace($KomorebiBin)
$hasWhkdBin = -not [string]::IsNullOrWhiteSpace($WhkdBin)
$hasAutoHotkeyPath = -not [string]::IsNullOrWhiteSpace($AutoHotkeyPath)
$explicitCommandPaths = @($hasKomorebiBin, $hasWhkdBin, $hasAutoHotkeyPath)
if ($explicitCommandPaths -contains $true -and $explicitCommandPaths -contains $false) {
    throw "KomorebiBin, WhkdBin, and AutoHotkeyPath must be provided together"
}
if ($hasKomorebiBin) {
    foreach ($commandDirectory in @($KomorebiBin, $WhkdBin)) {
        if (-not (Test-Path -LiteralPath $commandDirectory -PathType Container)) {
            throw "command directory was not found: $commandDirectory"
        }
    }
    $Env:PATH = "$KomorebiBin;$WhkdBin;$Env:PATH"
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Stop-KomorebiGracefully {
    param(
        [Parameter(Mandatory)]
        [string]$KomorebicPath
    )

    $stopProcess = Start-Process `
        -FilePath $KomorebicPath `
        -ArgumentList @("stop", "--whkd", "--bar") `
        -NoNewWindow `
        -PassThru

    try {
        if (-not $stopProcess.WaitForExit(10000)) {
            $stopProcess.Kill($true)
            $stopProcess.WaitForExit()
            throw "komorebic stop timed out after 10 seconds"
        }
        if ($stopProcess.ExitCode -ne 0) {
            throw "komorebic stop failed with exit code $($stopProcess.ExitCode)"
        }
    } finally {
        $stopProcess.Dispose()
    }
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

$configRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$configPath = Join-Path $configRoot "komorebi.json"
if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
    throw "komorebi.json was not found: $configPath"
}
if (-not $hasAutoHotkeyPath) {
    $autoHotkeyInstallLocation = Get-ItemPropertyValue `
        -LiteralPath "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\AutoHotkey" `
        -Name "InstallLocation" `
        -ErrorAction Stop
    $AutoHotkeyPath = Join-Path $autoHotkeyInstallLocation "v2\AutoHotkey64.exe"
}
if (-not (Test-Path -LiteralPath $AutoHotkeyPath -PathType Leaf)) {
    throw "AutoHotkey v2 executable was not found: $AutoHotkeyPath"
}

$komorebicPath = (Get-Command komorebic -ErrorAction Stop).Source
(Get-Command komorebi-bar -ErrorAction Stop) | Out-Null
(Get-Command whkd -ErrorAction Stop) | Out-Null

[System.Environment]::SetEnvironmentVariable("KOMOREBI_CONFIG_HOME", $configRoot, "User")
[System.Environment]::SetEnvironmentVariable("WHKD_CONFIG_HOME", $configRoot, "User")
[System.Environment]::SetEnvironmentVariable("KOMOREBI_AUTOHOTKEY", $AutoHotkeyPath, "User")
$Env:KOMOREBI_CONFIG_HOME = $configRoot
$Env:WHKD_CONFIG_HOME = $configRoot
$Env:KOMOREBI_AUTOHOTKEY = $AutoHotkeyPath

Set-ItemProperty `
    -Path "HKCU:\Control Panel\Desktop" `
    -Name "LowLevelHooksTimeout" `
    -Value 1000 `
    -Type DWord `
    -Force

$managedProcessNames = @("komorebi", "komorebi-bar", "whkd")
$runningProcesses = Get-Process -Name $managedProcessNames -ErrorAction SilentlyContinue
$komorebiProcesses = @($runningProcesses | Where-Object Name -eq "komorebi")
if ($komorebiProcesses.Count -gt 1) {
    throw "multiple komorebi processes are running"
}

if ($komorebiProcesses.Count -eq 1) {
    Stop-KomorebiGracefully -KomorebicPath $komorebicPath
} else {
    $orphanedHelpers = @(
        $runningProcesses | Where-Object Name -in @("komorebi-bar", "whkd")
    )
    if ($orphanedHelpers.Count -ne 0) {
        $orphanedNames = ($orphanedHelpers.Name | Sort-Object -Unique) -join ", "
        Write-Host "Stopping orphaned helper processes: $orphanedNames"
        Stop-Process -Id $orphanedHelpers.Id -Force
    }
}

if ($runningProcesses) {
    $stopDeadline = [DateTime]::UtcNow.AddSeconds(10)
    do {
        $runningProcesses = Get-Process -Name $managedProcessNames -ErrorAction SilentlyContinue
        if (-not $runningProcesses) {
            break
        }
        Start-Sleep -Milliseconds 200
    } while ([DateTime]::UtcNow -lt $stopDeadline)

    if ($runningProcesses) {
        $remaining = ($runningProcesses.Name | Sort-Object -Unique) -join ", "
        throw "komorebi processes did not stop: $remaining"
    }
}

$dataDirectory = (& $komorebicPath data-directory).Trim()
if (Test-Path -LiteralPath $dataDirectory -PathType Container) {
    Get-ChildItem -LiteralPath $dataDirectory -File -Filter "komorebi-bar-*" |
        Remove-Item -Force
}

& $komorebicPath start --config $configPath --whkd --bar --clean-state

$startDeadline = [DateTime]::UtcNow.AddSeconds(15)
do {
    $runningProcesses = Get-Process -Name $managedProcessNames -ErrorAction SilentlyContinue
    $runningNames = @($runningProcesses.Name | Sort-Object -Unique)
    $missingProcesses = @($managedProcessNames | Where-Object { $_ -notin $runningNames })
    if ($missingProcesses.Count -eq 0) {
        break
    }
    Start-Sleep -Milliseconds 200
} while ([DateTime]::UtcNow -lt $startDeadline)

if ($missingProcesses.Count -ne 0) {
    throw "komorebi processes did not start: $($missingProcesses -join ', ')"
}

$monitors = @((& $komorebicPath monitor-information | ConvertFrom-Json))
if ($monitors.Count -eq 0) {
    throw "komorebi did not detect any monitors"
}

for ($monitorIndex = 0; $monitorIndex -lt $monitors.Count; $monitorIndex++) {
    & $komorebicPath workspace-layout $monitorIndex 0 rows
}

Write-Host "=== Running processes ==="
Get-Process -Name $managedProcessNames | Format-Table Name, Id -AutoSize
Write-Host "Config home: $configRoot"
Write-Host "Detected monitors: $($monitors.Count)"
