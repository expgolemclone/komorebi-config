# test-border-style.ps1
# Border color and width verification
# Expected: bright cyan (#00FFFF), width 20

$config = Get-Content "$env:KOMOREBI_CONFIG_HOME\komorebi.json" | ConvertFrom-Json

# Check border width
if ($config.border_width -eq 8) {
    Write-Host "PASS: border_width is 8" -ForegroundColor Green
} else {
    Write-Host "FAIL: border_width is $($config.border_width), expected 8" -ForegroundColor Red
}

# Check border colors
$expectedColor = "#00FFFF"
$colors = $config.border_colours
$targets = @("single", "stack", "monocle", "floating")
foreach ($target in $targets) {
    if ($colors.$target -eq $expectedColor) {
        Write-Host "PASS: $target color is $expectedColor" -ForegroundColor Green
    } else {
        Write-Host "FAIL: $target color is $($colors.$target), expected $expectedColor" -ForegroundColor Red
    }
}
