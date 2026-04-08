# test-startup-shortcut.ps1
# ショートカットが正しく作成されたか検証する

$shortcutPath = "$Env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\komorebi-restart.lnk"
$scriptPath = "$Env:USERPROFILE\.config\komorebi\scripts\restart.ps1"

# ショートカットが存在するか
if (-not (Test-Path $shortcutPath)) {
    Write-Host "FAIL: shortcut not found at $shortcutPath" -ForegroundColor Red
    exit 1
}

# ショートカットのプロパティを検証
$shell = New-Object -ComObject WScript.Shell
$lnk = $shell.CreateShortcut($shortcutPath)

# ターゲットが pwsh または powershell であること
if (($lnk.TargetPath -notlike "*pwsh*") -and ($lnk.TargetPath -notlike "*powershell*")) {
    Write-Host "FAIL: TargetPath is not pwsh/powershell: $($lnk.TargetPath)" -ForegroundColor Red
    exit 1
}

# 引数に restart.ps1 が含まれること
if ($lnk.Arguments -notlike "*restart.ps1*") {
    Write-Host "FAIL: Arguments do not contain restart.ps1: $($lnk.Arguments)" -ForegroundColor Red
    exit 1
}

# WindowStyle が 7 (最小化) であること
if ($lnk.WindowStyle -ne 7) {
    Write-Host "FAIL: WindowStyle is $($lnk.WindowStyle), expected 7 (Minimized)" -ForegroundColor Red
    exit 1
}

Write-Host "PASS: startup shortcut is correctly configured" -ForegroundColor Green
Write-Host "  Path: $shortcutPath"
Write-Host "  Target: $($lnk.TargetPath)"
Write-Host "  Arguments: $($lnk.Arguments)"
Write-Host "  WindowStyle: $($lnk.WindowStyle)"
