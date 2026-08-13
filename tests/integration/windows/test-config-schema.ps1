#requires -Version 7.0

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..\..")).Path
$komorebiConfigPath = Join-Path $repoRoot "komorebi.json"
$barConfigPath = Join-Path $repoRoot "komorebi.bar.json"
$komorebicPath = (Get-Command komorebic -ErrorAction Stop).Source
$barPath = (Get-Command komorebi-bar -ErrorAction Stop).Source

$versionOutput = @(& $komorebicPath --version)
if ($versionOutput[0] -notmatch '^komorebic (?<Version>\d+\.\d+\.\d+)$') {
    throw "failed to determine the installed komorebi version"
}
$version = $Matches.Version

$komorebiConfig = Get-Content -LiteralPath $komorebiConfigPath -Raw | ConvertFrom-Json
$barConfig = Get-Content -LiteralPath $barConfigPath -Raw | ConvertFrom-Json
$expectedKomorebiSchema = "https://raw.githubusercontent.com/LGUG2Z/komorebi/v$version/schema.json"
$expectedBarSchema = "https://raw.githubusercontent.com/LGUG2Z/komorebi/v$version/schema.bar.json"
if ($komorebiConfig.'$schema' -ne $expectedKomorebiSchema) {
    throw "komorebi.json schema does not match installed version $version"
}
if ($barConfig.'$schema' -ne $expectedBarSchema) {
    throw "komorebi.bar.json schema does not match installed version $version"
}

$komorebiSchema = (& $komorebicPath static-config-schema) -join "`n"
$barSchema = (& $barPath --schema) -join "`n"
$komorebiJson = Get-Content -LiteralPath $komorebiConfigPath -Raw
$barJson = Get-Content -LiteralPath $barConfigPath -Raw
if (-not (Test-Json -Json $komorebiJson -Schema $komorebiSchema)) {
    throw "komorebi.json does not match the installed schema"
}
if (-not (Test-Json -Json $barJson -Schema $barSchema)) {
    throw "komorebi.bar.json does not match the installed schema"
}

$installedFonts = @(& $barPath --fonts)
if ($barConfig.font_family -notin $installedFonts) {
    throw "configured bar font is not installed: $($barConfig.font_family)"
}

& $komorebicPath check -k $komorebiConfigPath
Write-Host "PASS: configs match komorebi $version and the configured font is installed" -ForegroundColor Green
exit 0
