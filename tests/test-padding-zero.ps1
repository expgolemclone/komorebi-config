# test-padding-zero.ps1
# komorebi.json の padding（余白）が 0 に設定されているかチェックするテスト
# padding が 0 だと、ウィンドウが画面の端ギリギリまで広がる

# 設定ファイル（komorebi.json）を読み込んで、PowerShell のオブジェクトに変換する
$configPath = "$env:KOMOREBI_CONFIG_HOME/komorebi.json"
$config = Get-Content $configPath -Raw | ConvertFrom-Json

# workspace_padding = 画面の端とウィンドウの間の余白
$workspacePadding = $config.default_workspace_padding
# container_padding = ウィンドウ同士の間の余白
$containerPadding = $config.default_container_padding

# テスト結果を追跡するフラグ（最初は合格 = $true にしておく）
$pass = $true

# workspace_padding が 0 でなければ失敗
if ($workspacePadding -ne 0) {
    Write-Host "FAIL: default_workspace_padding = $workspacePadding (expected 0)" -ForegroundColor Red
    $pass = $false
}

# container_padding が 0 でなければ失敗
if ($containerPadding -ne 0) {
    Write-Host "FAIL: default_container_padding = $containerPadding (expected 0)" -ForegroundColor Red
    $pass = $false
}

# 両方 0 なら合格
if ($pass) {
    Write-Host "PASS: padding is 0 - windows will use maximum screen space" -ForegroundColor Green
}
