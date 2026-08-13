# 管理者権限がなければUACで再起動する
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

# ユーザー環境変数として永続的に設定（Windowsの「システム環境変数」に書き込む）
# こうすることで、このスクリプト以外から起動されたプロセス（whkd など）でも
# 設定ファイルの場所を見つけられるようになる
[System.Environment]::SetEnvironmentVariable("KOMOREBI_CONFIG_HOME", "$env:USERPROFILE\projects\komorebi-config", "User")
[System.Environment]::SetEnvironmentVariable("WHKD_CONFIG_HOME", "$env:USERPROFILE\projects\komorebi-config", "User")

# Low-level keyboard hook のタイムアウトを延長（デフォルト ~300ms → 5000ms）
# テキストボックスにフォーカスした際、IME などの処理でフックの応答が遅れると
# Windows がフックを無効化してしまう。タイムアウトを伸ばすことでこれを防ぐ。
# ※ 反映にはログオフ/再起動が必要な場合がある
Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "LowLevelHooksTimeout" -Value 5000 -Type DWord -Force

# 設定ファイルの場所を環境変数で指定（現セッション用）
$Env:KOMOREBI_CONFIG_HOME = "$env:USERPROFILE\projects\komorebi-config"
$Env:WHKD_CONFIG_HOME = "$env:USERPROFILE\projects\komorebi-config"

# komorebi と whkd の実行ファイルがあるフォルダを PATH に追加して、コマンドとして使えるようにする
$Env:Path = "C:\Program Files\komorebi\bin;C:\Program Files\whkd\bin;" + $Env:Path

# komorebi, whkd, bar を全て停止（komorebic stop で komorebi 本体に停止命令を送る）
komorebic stop 2>&1 | Out-Null
Stop-Process -Name whkd -Force -ErrorAction SilentlyContinue
Stop-Process -Name komorebi-bar -Force -ErrorAction SilentlyContinue
Stop-Process -Name komorebi -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3

# 残っていないか確認
$remaining = Get-Process -Name komorebi, komorebi-bar, whkd -ErrorAction SilentlyContinue
if ($remaining) {
    Write-Host "WARNING: processes still running:"
    $remaining | Format-Table Name, Id
}

# 再起動
# komorebi（ウィンドウマネージャー）と komorebi-bar（ステータスバー）を起動する。
# whkd（キーボードショートカット）は --whkd で一緒に起動すると
# コンソール窓が表示されてしまうので、別途 Start-Process で非表示起動する。
komorebic start --bar 2>&1
Start-Sleep -Seconds 1
# whkd を「ウィンドウを非表示」で起動する
# komorebic --whkd 経由だとコンソール窓が出てしまうので、
# Start-Process -WindowStyle Hidden を使って窓を出さずに起動する
Start-Process whkd -WindowStyle Hidden
Start-Sleep -Seconds 3

# 起動直後のデフォルト WS 0 は config のレイアウトが適用されないため強制設定
# komorebic state の JSON は巨大なため PS 5.1 では ConvertFrom-Json が失敗する
# モニター数は komorebi.json から取得する
$cfg = Get-Content "$Env:KOMOREBI_CONFIG_HOME\komorebi.json" -Raw | ConvertFrom-Json
for ($i = 0; $i -lt $cfg.monitors.Count; $i++) {
    komorebic workspace-layout $i 0 rows
}

# 確認
$procs = Get-Process -Name komorebi, komorebi-bar, whkd -ErrorAction SilentlyContinue
Write-Host "=== Running processes ==="
$procs | Format-Table Name, Id -AutoSize
Write-Host "whkd config home: $Env:WHKD_CONFIG_HOME"
