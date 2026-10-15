#requires -Version 7.0

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..\..")).Path
$komorebiConfigPath = Join-Path $repoRoot "komorebi.json"
$komorebicPath = (Get-Command komorebic -ErrorAction Stop).Source

$versionOutput = @(& $komorebicPath --version)
if ($versionOutput[0] -notmatch '^komorebic (?<Version>\d+\.\d+\.\d+)$') {
    throw "failed to determine the installed komorebi version"
}
$version = $Matches.Version

$komorebiConfig = Get-Content -LiteralPath $komorebiConfigPath -Raw | ConvertFrom-Json
$expectedKomorebiSchema = "https://raw.githubusercontent.com/LGUG2Z/komorebi/v$version/schema.json"
if ($komorebiConfig.'$schema' -ne $expectedKomorebiSchema) {
    throw "komorebi.json schema does not match installed version $version"
}

$komorebiSchema = (& $komorebicPath static-config-schema) -join "`n"
$komorebiJson = Get-Content -LiteralPath $komorebiConfigPath -Raw
if (-not (Test-Json -Json $komorebiJson -Schema $komorebiSchema)) {
    throw "komorebi.json does not match the installed schema"
}

& $komorebicPath check -k $komorebiConfigPath
Write-Host "PASS: config matches komorebi $version" -ForegroundColor Green
exit 0
