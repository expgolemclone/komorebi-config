#requires -Version 7.0

param(
    [string]$KomorebiBin,
    [string]$WhkdBin,
    [string]$AutoHotkeyPath,
    [switch]$RecoverDisplay
)

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-ElevatedRestart {
    param(
        [Parameter(Mandatory)]
        [string[]]$ArgumentList
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = Join-Path $PSHOME "pwsh.exe"
    $startInfo.UseShellExecute = $true
    $startInfo.Verb = "RunAs"
    foreach ($argument in $ArgumentList) {
        [void]$startInfo.ArgumentList.Add($argument)
    }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    Write-Host "Requesting administrator privileges for restart.ps1"

    try {
        if (-not $process.Start()) {
            throw "failed to start elevated restart.ps1"
        }

        $process.WaitForExit()
        if ($process.ExitCode -ne 0) {
            throw "elevated restart.ps1 failed with exit code $($process.ExitCode)"
        }
    } catch [System.ComponentModel.Win32Exception] {
        if ($_.Exception.NativeErrorCode -eq 1223) {
            throw "administrator elevation was canceled"
        }
        throw "failed to start elevated restart.ps1: $($_.Exception.Message)"
    } finally {
        $process.Dispose()
    }
}

function Enter-RestartLock {
    $mutex = [Threading.Mutex]::new(
        $false,
        "Local\komorebi-config-restart"
    )

    try {
        if (-not $mutex.WaitOne(0)) {
            $mutex.Dispose()
            return $null
        }
    } catch [Threading.AbandonedMutexException] {
        # The abandoned mutex is acquired by the current process.
    }

    return $mutex
}

function Invoke-NativeCommand {
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,

        [Parameter(Mandatory)]
        [string[]]$ArgumentList,

        [Parameter(Mandatory)]
        [string]$Operation,

        [Parameter(Mandatory)]
        [string]$CommandName,

        [int]$TimeoutMilliseconds = 10000
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $FilePath
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($argument in $ArgumentList) {
        [void]$startInfo.ArgumentList.Add($argument)
    }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    Write-Host "${CommandName}: $Operation"

    try {
        if (-not $process.Start()) {
            throw "failed to start $CommandName for $Operation"
        }

        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()

        if (-not $process.WaitForExit($TimeoutMilliseconds)) {
            $process.Kill($true)
            $process.WaitForExit()
            [void]$stdoutTask.GetAwaiter().GetResult()
            [void]$stderrTask.GetAwaiter().GetResult()
            $seconds = [Math]::Round($TimeoutMilliseconds / 1000, 1)
            throw "$CommandName $Operation timed out after $seconds seconds"
        }

        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()

        if ($process.ExitCode -ne 0) {
            $details = @()
            if (-not [string]::IsNullOrWhiteSpace($stdout)) {
                $details += "stdout: $($stdout.Trim())"
            }
            if (-not [string]::IsNullOrWhiteSpace($stderr)) {
                $details += "stderr: $($stderr.Trim())"
            }
            $suffix = if ($details.Count -eq 0) { "" } else { ": $($details -join ' | ')" }
            throw "$CommandName $Operation failed with exit code $($process.ExitCode)$suffix"
        }

        return $stdout.Trim()
    } finally {
        $process.Dispose()
    }
}

function Invoke-Komorebic {
    param(
        [Parameter(Mandatory)]
        [string]$KomorebicPath,

        [Parameter(Mandatory)]
        [string[]]$ArgumentList,

        [Parameter(Mandatory)]
        [string]$Operation,

        [int]$TimeoutMilliseconds = 10000
    )

    return Invoke-NativeCommand `
        -FilePath $KomorebicPath `
        -ArgumentList $ArgumentList `
        -Operation $Operation `
        -CommandName "komorebic" `
        -TimeoutMilliseconds $TimeoutMilliseconds
}

function Wait-KomorebiReady {
    param(
        [Parameter(Mandatory)]
        [string]$KomorebicPath,

        [int]$TimeoutMilliseconds = 15000
    )

    $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMilliseconds)
    $lastFailure = "no readiness probe was completed"
    do {
        if (-not (Get-Process -Name "komorebi" -ErrorAction SilentlyContinue)) {
            throw "komorebi exited before its IPC server became ready"
        }

        try {
            return Invoke-Komorebic `
                -KomorebicPath $KomorebicPath `
                -ArgumentList @("monitor-information") `
                -Operation "readiness probe" `
                -TimeoutMilliseconds 2000
        } catch {
            $lastFailure = $_.Exception.Message
        }

        Start-Sleep -Milliseconds 200
    } while ([DateTime]::UtcNow -lt $deadline)

    $seconds = [Math]::Round($TimeoutMilliseconds / 1000, 1)
    throw "komorebi IPC server did not become ready within $seconds seconds: $lastFailure"
}

function Restart-WindowsNightLight {
    param(
        [int]$TimeoutMilliseconds = 10000
    )

    # Restart-Service waits internally, so bound the entire operation in a child process.
    [void](Invoke-NativeCommand `
        -FilePath (Join-Path $PSHOME "pwsh.exe") `
        -ArgumentList @(
            "-NoProfile",
            "-NonInteractive",
            "-Command",
            "Restart-Service -Name DisplayEnhancementService -Force -ErrorAction Stop"
        ) `
        -Operation "restart Windows Night Light (DisplayEnhancementService)" `
        -CommandName "pwsh" `
        -TimeoutMilliseconds $TimeoutMilliseconds)
}

function Get-SingleHealthyDisplayAdapter {
    $displayAdapters = @(
        Get-PnpDevice `
            -Class "Display" `
            -PresentOnly `
            -Status "OK" `
            -ErrorAction Stop
    )
    if ($displayAdapters.Count -ne 1) {
        throw "expected exactly one healthy display adapter, found $($displayAdapters.Count)"
    }

    return $displayAdapters[0]
}

function Get-ActiveScreens {
    if (-not ("KomorebiPhysicalScreenCoordinates" -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class KomorebiPhysicalScreenCoordinates
{
    [DllImport("user32.dll", SetLastError = true)]
    public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
}
'@ -ErrorAction Stop
    }
    $previousDpiContext = [KomorebiPhysicalScreenCoordinates]::SetThreadDpiAwarenessContext([IntPtr](-4))
    if ($previousDpiContext -eq [IntPtr]::Zero) {
        $errorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        throw "failed to enable per-monitor DPI awareness: Win32 error $errorCode"
    }
    if (-not ("System.Windows.Forms.Screen" -as [type])) {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    }

    return [System.Windows.Forms.Screen]::AllScreens
}

function Get-ActiveScreenCount {
    return @(Get-ActiveScreens).Count
}

function Get-ActiveScreenGeometry {
    $screens = @(
        Get-ActiveScreens |
            ForEach-Object {
                $bounds = $_.Bounds
                "$($bounds.X),$($bounds.Y):$($bounds.Width)x$($bounds.Height)"
            } |
            Sort-Object
    )
    return $screens -join ";"
}

function Wait-DisplayPipelineReady {
    param(
        [Parameter(Mandatory)]
        [string]$DisplayAdapterInstanceId,

        [Parameter(Mandatory)]
        [int]$ExpectedScreenCount,

        [Parameter(Mandatory)]
        [string]$ExpectedScreenGeometry,

        [int]$TimeoutMilliseconds = 30000,

        [int]$RequiredStableSamples = 5
    )

    $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMilliseconds)
    $stableSamples = 0
    $lastAdapterStatus = "not found"
    $lastScreenCount = 0
    $lastScreenGeometry = ""

    do {
        $displayAdapter = Get-PnpDevice `
            -InstanceId $DisplayAdapterInstanceId `
            -ErrorAction SilentlyContinue
        if ($null -ne $displayAdapter) {
            $lastAdapterStatus = [string]$displayAdapter.Status
        } else {
            $lastAdapterStatus = "not found"
        }

        $lastScreenCount = Get-ActiveScreenCount
        $lastScreenGeometry = Get-ActiveScreenGeometry
        if (
            $null -ne $displayAdapter -and
            $displayAdapter.Present -and
            $displayAdapter.Status -eq "OK" -and
            $lastScreenCount -eq $ExpectedScreenCount -and
            $lastScreenGeometry -eq $ExpectedScreenGeometry
        ) {
            $stableSamples++
            if ($stableSamples -ge $RequiredStableSamples) {
                return
            }
        } else {
            $stableSamples = 0
        }

        Start-Sleep -Milliseconds 200
    } while ([DateTime]::UtcNow -lt $deadline)

    $seconds = [Math]::Round($TimeoutMilliseconds / 1000, 1)
    throw "display pipeline did not recover within $seconds seconds: adapter status $lastAdapterStatus, active screens $lastScreenCount/$ExpectedScreenCount, geometry $lastScreenGeometry/$ExpectedScreenGeometry"
}

function Restart-DisplayAdapter {
    param(
        [Parameter(Mandatory)]
        [Microsoft.Management.Infrastructure.CimInstance]$DisplayAdapter,

        [Parameter(Mandatory)]
        [int]$ExpectedScreenCount,

        [Parameter(Mandatory)]
        [string]$ExpectedScreenGeometry,

        [int]$TimeoutMilliseconds = 60000
    )

    $pnputilPath = Join-Path $env:SystemRoot "System32\pnputil.exe"
    if (-not (Test-Path -LiteralPath $pnputilPath -PathType Leaf)) {
        throw "PnPUtil was not found: $pnputilPath"
    }

    [void](Invoke-NativeCommand `
        -FilePath $pnputilPath `
        -ArgumentList @("/restart-device", [string]$DisplayAdapter.InstanceId) `
        -Operation "restart display adapter $($DisplayAdapter.FriendlyName)" `
        -CommandName "pnputil" `
        -TimeoutMilliseconds $TimeoutMilliseconds)

    Wait-DisplayPipelineReady `
        -DisplayAdapterInstanceId $DisplayAdapter.InstanceId `
        -ExpectedScreenCount $ExpectedScreenCount `
        -ExpectedScreenGeometry $ExpectedScreenGeometry
}

$logDirectory = Join-Path $env:LOCALAPPDATA 'komorebi'
New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
Start-Transcript -LiteralPath (Join-Path $logDirectory 'restart.log') -Append -Force | Out-Null
try {
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

if (-not (Test-IsAdministrator)) {
    $elevatedArguments = [System.Collections.Generic.List[string]]::new()
    foreach ($argument in @(
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        $PSCommandPath
    )) {
        $elevatedArguments.Add($argument)
    }
    if ($hasKomorebiBin) {
        foreach ($argument in @(
            "-KomorebiBin",
            $KomorebiBin,
            "-WhkdBin",
            $WhkdBin,
            "-AutoHotkeyPath",
            $AutoHotkeyPath
        )) {
            $elevatedArguments.Add($argument)
        }
    }

    if ($RecoverDisplay) {
        $elevatedArguments.Add('-RecoverDisplay')
    }
    Invoke-ElevatedRestart -ArgumentList $elevatedArguments.ToArray()
    return
}

$restartLock = Enter-RestartLock
if ($null -eq $restartLock) {
    Write-Host "Another restart.ps1 instance is already running"
    return
}

try {
Import-Module (Join-Path $HOME 'local-repository-map/repository-map.psm1')
$configRoot = Get-LocalRepositoryPath 'expgolemclone/komorebi-config'
$configPath = Join-Path $configRoot "komorebi.json"
$whkdConfigPath = Join-Path $configRoot "whkdrc"
foreach ($requiredFile in @($configPath, $whkdConfigPath)) {
    if (-not (Test-Path -LiteralPath $requiredFile -PathType Leaf)) {
        throw "required configuration file was not found: $requiredFile"
    }
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
Get-Command whkd -ErrorAction Stop | Out-Null
if ($RecoverDisplay) {
    $displayAdapter = Get-SingleHealthyDisplayAdapter
}
$activeScreenCount = Get-ActiveScreenCount
if ($activeScreenCount -le 0) {
    throw "Windows did not report any active screens"
}
$activeScreenGeometry = Get-ActiveScreenGeometry

$Env:KOMOREBI_CONFIG_HOME = $configRoot
$Env:WHKD_CONFIG_HOME = $configRoot
$Env:KOMOREBI_AUTOHOTKEY = $AutoHotkeyPath

Set-ItemProperty `
    -Path "HKCU:\Control Panel\Desktop" `
    -Name "LowLevelHooksTimeout" `
    -Value 1000 `
    -Type DWord `
    -Force

$processNamesToStop = @("komorebi", "komorebi-bar", "whkd")
$managedProcessNames = @("komorebi", "whkd")

Write-Host "=== Stopping komorebi ==="
$runningProcesses = @(Get-Process -Name $processNamesToStop -ErrorAction SilentlyContinue)
if ($runningProcesses.Count -ne 0) {
    $runningNames = ($runningProcesses.Name | Sort-Object -Unique) -join ", "
    Write-Host "Stopping managed processes: $runningNames"
    Stop-Process -Id $runningProcesses.Id -Force
}

if ($runningProcesses.Count -ne 0) {
    $stopDeadline = [DateTime]::UtcNow.AddSeconds(10)
    do {
        $runningProcesses = Get-Process -Name $processNamesToStop -ErrorAction SilentlyContinue
        if (-not $runningProcesses) {
            break
        }
        Start-Sleep -Milliseconds 200
    } while ([DateTime]::UtcNow -lt $stopDeadline)

    if ($runningProcesses) {
        $remaining = ($runningProcesses.Name | Sort-Object -Unique) -join ", "
        throw "komorebi processes did not stop within 10 seconds: $remaining"
    }
}

if ($RecoverDisplay) {
    Write-Host "=== Restarting display adapter ==="
    Restart-DisplayAdapter `
        -DisplayAdapter $displayAdapter `
        -ExpectedScreenCount $activeScreenCount `
        -ExpectedScreenGeometry $activeScreenGeometry

    Write-Host "=== Restarting Windows Night Light ==="
    Restart-WindowsNightLight
}

Write-Host "=== Starting komorebi ==="
# Use the upstream background launcher rather than a detached CreateNoWindow process.
# The latter can fail komorebi's AllowSetForegroundWindow startup check.
# KOMOREBI_CONFIG_HOME is authoritative. Passing --config also makes this upstream
# version invoke komorebi-bar --aliases, which creates an unwanted bar config.
$startOutput = Invoke-Komorebic `
    -KomorebicPath $komorebicPath `
    -ArgumentList @("start", "--clean-state", "--whkd") `
    -Operation "start komorebi" `
    -TimeoutMilliseconds 15000
Write-Host $startOutput

Write-Host "=== Waiting for komorebi ==="
$monitorJson = Wait-KomorebiReady -KomorebicPath $komorebicPath

Write-Host "=== Waiting for managed processes ==="
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
    throw "komorebi processes did not start within 15 seconds: $($missingProcesses -join ', ')"
}

Write-Host "=== Applying workspace layouts ==="
$monitors = @($monitorJson | ConvertFrom-Json)
if ($monitors.Count -eq 0) {
    throw "komorebi did not detect any monitors"
}
if ($monitors.Count -ne $activeScreenCount) {
    throw "komorebi detected $($monitors.Count) monitors, expected $activeScreenCount"
}
$windowsScreenSizes = @(
    Get-ActiveScreens |
        ForEach-Object { "$($_.Bounds.Width)x$($_.Bounds.Height)" } |
        Sort-Object
)
$komorebiScreenSizes = @(
    $monitors |
        ForEach-Object { "$($_.size.right)x$($_.size.bottom)" } |
        Sort-Object
)
if (($windowsScreenSizes -join ";") -ne ($komorebiScreenSizes -join ";")) {
    throw "komorebi monitor sizes $($komorebiScreenSizes -join ', ') do not match Windows screens $($windowsScreenSizes -join ', ')"
}

for ($monitorIndex = 0; $monitorIndex -lt $monitors.Count; $monitorIndex++) {
    $monitor = $monitors[$monitorIndex]
    $width = [int]$monitor.size.right
    $height = [int]$monitor.size.bottom

    if ($width -le 0 -or $height -le 0) {
        throw "monitor $monitorIndex has invalid dimensions: ${width}x${height}"
    }

    if ($width -gt $height) {
        $layout = "columns"
    } else {
        $layout = "rows"
    }

    Write-Host "Monitor $monitorIndex`: ${width}x${height} -> $layout"
    [void](Invoke-Komorebic `
        -KomorebicPath $komorebicPath `
        -ArgumentList @("workspace-layout", [string]$monitorIndex, "0", $layout) `
        -Operation "workspace-layout monitor $monitorIndex workspace 0 -> $layout" `
        -TimeoutMilliseconds 10000)
}

Write-Host "=== Running processes ==="
Get-Process -Name $managedProcessNames | Format-Table Name, Id -AutoSize
Write-Host "Config home: $configRoot"
Write-Host "Detected monitors: $($monitors.Count)"
} finally {
    $restartLock.ReleaseMutex()
    $restartLock.Dispose()
}
} catch {
    # Handoff tasks use NUL output handles; keep failures in the application transcript.
    Write-Host ($_ | Out-String)
    Write-Host $_.ScriptStackTrace
    throw
} finally {
    Stop-Transcript | Out-Null
}
