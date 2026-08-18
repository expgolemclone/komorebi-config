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

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $KomorebicPath
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($argument in $ArgumentList) {
        [void]$startInfo.ArgumentList.Add($argument)
    }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    Write-Host "komorebic: $Operation"

    try {
        if (-not $process.Start()) {
            throw "failed to start komorebic for $Operation"
        }

        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()

        if (-not $process.WaitForExit($TimeoutMilliseconds)) {
            $process.Kill($true)
            $process.WaitForExit()
            [void]$stdoutTask.GetAwaiter().GetResult()
            [void]$stderrTask.GetAwaiter().GetResult()
            $seconds = [Math]::Round($TimeoutMilliseconds / 1000, 1)
            throw "komorebic $Operation timed out after $seconds seconds"
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
            throw "komorebic $Operation failed with exit code $($process.ExitCode)$suffix"
        }

        return $stdout.Trim()
    } finally {
        $process.Dispose()
    }
}

if (-not (Test-IsAdministrator)) {
    throw "restart.ps1 must be run from an elevated PowerShell 7 session"
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

Write-Host "=== Stopping komorebi ==="
$runningProcesses = Get-Process -Name $managedProcessNames -ErrorAction SilentlyContinue
$komorebiProcesses = @($runningProcesses | Where-Object Name -eq "komorebi")
if ($komorebiProcesses.Count -gt 1) {
    throw "multiple komorebi processes are running"
}

if ($komorebiProcesses.Count -eq 1) {
    [void](Invoke-Komorebic `
        -KomorebicPath $komorebicPath `
        -ArgumentList @("stop", "--whkd", "--bar") `
        -Operation "stop" `
        -TimeoutMilliseconds 10000)
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
        throw "komorebi processes did not stop within 10 seconds: $remaining"
    }
}

Write-Host "=== Cleaning runtime files ==="
$dataDirectory = Invoke-Komorebic `
    -KomorebicPath $komorebicPath `
    -ArgumentList @("data-directory") `
    -Operation "data-directory" `
    -TimeoutMilliseconds 10000
if (Test-Path -LiteralPath $dataDirectory -PathType Container) {
    Get-ChildItem -LiteralPath $dataDirectory -File -Filter "komorebi-bar-*" |
        Remove-Item -Force
}

Write-Host "=== Starting komorebi ==="
[void](Invoke-Komorebic `
    -KomorebicPath $komorebicPath `
    -ArgumentList @("start", "--config", $configPath, "--whkd", "--bar", "--clean-state") `
    -Operation "start" `
    -TimeoutMilliseconds 15000)

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
$monitorJson = Invoke-Komorebic `
    -KomorebicPath $komorebicPath `
    -ArgumentList @("monitor-information") `
    -Operation "monitor-information" `
    -TimeoutMilliseconds 10000
$monitors = @($monitorJson | ConvertFrom-Json)
if ($monitors.Count -eq 0) {
    throw "komorebi did not detect any monitors"
}

for ($monitorIndex = 0; $monitorIndex -lt $monitors.Count; $monitorIndex++) {
    [void](Invoke-Komorebic `
        -KomorebicPath $komorebicPath `
        -ArgumentList @("workspace-layout", [string]$monitorIndex, "0", "rows") `
        -Operation "workspace-layout monitor $monitorIndex workspace 0" `
        -TimeoutMilliseconds 10000)
}

Write-Host "=== Running processes ==="
Get-Process -Name $managedProcessNames | Format-Table Name, Id -AutoSize
Write-Host "Config home: $configRoot"
Write-Host "Detected monitors: $($monitors.Count)"
