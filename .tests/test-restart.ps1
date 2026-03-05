# test-restart.ps1
# restart.ps1 の変更が正しく動作するかテストするスクリプト
# テスト項目:
#   1. restart.ps1 が正常に実行できる
#   2. komorebi, komorebi-bar, whkd の3プロセスが全て起動している
#   3. whkd のウィンドウが非表示になっている（MainWindowHandle が 0 = 窓なし）

$ErrorActionPreference = "Stop"
$allPassed = $true

Write-Host "`n=== restart.ps1 test ===" -ForegroundColor Cyan

# --- Test 1: restart.ps1 を実行 ---
Write-Host "`n[Test 1] restart.ps1 を実行..." -ForegroundColor Yellow
try {
    # テストファイルは .tests/ にあるので、親フォルダの scripts/ を参照する
    & "$PSScriptRoot\..\scripts\restart.ps1"
    Write-Host "  PASS: restart.ps1 が正常に実行された" -ForegroundColor Green
} catch {
    Write-Host "  FAIL: restart.ps1 の実行に失敗: $_" -ForegroundColor Red
    $allPassed = $false
    exit 1
}

Start-Sleep -Seconds 2

# --- Test 2: 3つのプロセスが起動しているか ---
Write-Host "`n[Test 2] komorebi, komorebi-bar, whkd が起動しているか確認..." -ForegroundColor Yellow
$expectedProcesses = @("komorebi", "komorebi-bar", "whkd")
foreach ($name in $expectedProcesses) {
    $proc = Get-Process -Name $name -ErrorAction SilentlyContinue
    if ($proc) {
        Write-Host "  PASS: $name が起動している (PID: $($proc.Id))" -ForegroundColor Green
    } else {
        Write-Host "  FAIL: $name が起動していない" -ForegroundColor Red
        $allPassed = $false
    }
}

# --- Test 3: whkd のウィンドウが非表示か ---
Write-Host "`n[Test 3] whkd のウィンドウが非表示か確認..." -ForegroundColor Yellow
$whkdProc = Get-Process -Name whkd -ErrorAction SilentlyContinue
if ($whkdProc) {
    # MainWindowHandle が 0 なら、目に見えるウィンドウを持っていない
    if ($whkdProc.MainWindowHandle -eq 0) {
        Write-Host "  PASS: whkd のウィンドウは非表示 (MainWindowHandle = 0)" -ForegroundColor Green
    } else {
        Write-Host "  FAIL: whkd のウィンドウが表示されている (MainWindowHandle = $($whkdProc.MainWindowHandle))" -ForegroundColor Red
        $allPassed = $false
    }
} else {
    Write-Host "  SKIP: whkd が起動していないためスキップ" -ForegroundColor Yellow
    $allPassed = $false
}

# --- 結果 ---
Write-Host "`n=== Result ===" -ForegroundColor Cyan
if ($allPassed) {
    Write-Host "ALL TESTS PASSED" -ForegroundColor Green
} else {
    Write-Host "SOME TESTS FAILED" -ForegroundColor Red
}
