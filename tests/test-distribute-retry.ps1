# test-distribute-retry.ps1
# distribute-windows.ps1 にエクスポネンシャルバックオフと最大リトライ数が実装されているか検証する

$scriptPath = "$PSScriptRoot\..\scripts\distribute-windows.ps1"
$content = Get-Content $scriptPath -Raw

$allPass = $true

# maxRetries 変数の存在
if ($content -match '\$maxRetries\s*=\s*\d+') {
    Write-Host "PASS: maxRetries variable is defined" -ForegroundColor Green
} else {
    Write-Host "FAIL: maxRetries variable not found" -ForegroundColor Red
    $allPass = $false
}

# retryCount のインクリメント
if ($content -match '\$retryCount\+\+') {
    Write-Host "PASS: retryCount is incremented" -ForegroundColor Green
} else {
    Write-Host "FAIL: retryCount increment not found" -ForegroundColor Red
    $allPass = $false
}

# エクスポネンシャルバックオフ (Pow) の存在
if ($content -match '\[Math\]::Pow') {
    Write-Host "PASS: exponential backoff (Math::Pow) is used" -ForegroundColor Green
} else {
    Write-Host "FAIL: exponential backoff not found" -ForegroundColor Red
    $allPass = $false
}

# 上限到達時の exit
if ($content -match 'exit\s+1') {
    Write-Host "PASS: script exits on max retries" -ForegroundColor Green
} else {
    Write-Host "FAIL: exit on max retries not found" -ForegroundColor Red
    $allPass = $false
}

# 接続成功時のリトライカウントリセット
if ($content -match '\$retryCount\s*=\s*0') {
    Write-Host "PASS: retryCount is reset on success" -ForegroundColor Green
} else {
    Write-Host "FAIL: retryCount reset not found" -ForegroundColor Red
    $allPass = $false
}

if ($allPass) {
    Write-Host "RESULT: PASS - distribute-windows retry logic is correct" -ForegroundColor Green
    exit 0
} else {
    Write-Host "RESULT: FAIL - distribute-windows retry logic has issues" -ForegroundColor Red
    exit 1
}
