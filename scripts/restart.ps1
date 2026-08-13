#requires -Version 7.0

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

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

$configRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$configPath = Join-Path $configRoot "komorebi.json"
if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
    throw "komorebi.json was not found: $configPath"
}

$komorebicPath = (Get-Command komorebic -ErrorAction Stop).Source

[System.Environment]::SetEnvironmentVariable("KOMOREBI_CONFIG_HOME", $configRoot, "User")
[System.Environment]::SetEnvironmentVariable("WHKD_CONFIG_HOME", $configRoot, "User")
$Env:KOMOREBI_CONFIG_HOME = $configRoot
$Env:WHKD_CONFIG_HOME = $configRoot

Set-ItemProperty `
    -Path "HKCU:\Control Panel\Desktop" `
    -Name "LowLevelHooksTimeout" `
    -Value 5000 `
    -Type DWord `
    -Force

$managedProcessNames = @("komorebi", "komorebi-bar", "whkd")
$runningProcesses = Get-Process -Name $managedProcessNames -ErrorAction SilentlyContinue
if ($runningProcesses) {
    & $komorebicPath stop --whkd --bar

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
