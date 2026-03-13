# test-bar-widgets.ps1
# komorebi.bar.json の全ウィジェットが enable: true であることを検証する
# （無効なウィジェットは設定から削除する運用のため）

$configPath = "$PSScriptRoot\..\komorebi.bar.json"
$config = Get-Content $configPath | ConvertFrom-Json

$allPass = $true

foreach ($widget in $config.left_widgets) {
    $name = ($widget.PSObject.Properties | Select-Object -First 1).Name
    $inner = $widget.$name
    if ($inner.PSObject.Properties.Name -contains "enable" -and -not $inner.enable) {
        Write-Host "FAIL: left_widgets.$name has enable=false (should be removed)" -ForegroundColor Red
        $allPass = $false
    }
}

foreach ($widget in $config.right_widgets) {
    $name = ($widget.PSObject.Properties | Select-Object -First 1).Name
    $inner = $widget.$name
    if ($inner.PSObject.Properties.Name -contains "enable" -and -not $inner.enable) {
        Write-Host "FAIL: right_widgets.$name has enable=false (should be removed)" -ForegroundColor Red
        $allPass = $false
    }
}

if ($allPass) {
    Write-Host "PASS: all widgets in bar config are enabled" -ForegroundColor Green
    exit 0
} else {
    exit 1
}
