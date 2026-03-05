# ユーザー環境変数として永続的に設定（Windowsの「システム環境変数」に書き込む）
# こうすることで、このスクリプト以外から起動されたプロセス（whkd など）でも
# 設定ファイルの場所を見つけられるようになる
[System.Environment]::SetEnvironmentVariable("KOMOREBI_CONFIG_HOME", "C:\Users\0000250059\.config\komorebi", "User")
[System.Environment]::SetEnvironmentVariable("WHKD_CONFIG_HOME", "C:\Users\0000250059\.config\komorebi", "User")

# Low-level keyboard hook のタイムアウトを延長（デフォルト ~300ms → 5000ms）
# テキストボックスにフォーカスした際、IME などの処理でフックの応答が遅れると
# Windows がフックを無効化してしまう。タイムアウトを伸ばすことでこれを防ぐ。
# ※ 反映にはログオフ/再起動が必要な場合がある
Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "LowLevelHooksTimeout" -Value 5000 -Type DWord -Force

# 設定ファイルの場所を環境変数で指定（現セッション用）
$Env:KOMOREBI_CONFIG_HOME = "C:\Users\0000250059\.config\komorebi"
$Env:WHKD_CONFIG_HOME = "C:\Users\0000250059\.config\komorebi"

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
# komorebi（ウィンドウマネージャー）、komorebi-bar（ステータスバー）、
# whkd（キーボードショートカット）を komorebic コマンドで一括起動する。
# --whkd と --bar オプションをつけると、komorebi が whkd と bar も一緒に立ち上げてくれる。
# whkd の設定ファイルの場所（WHKD_CONFIG_HOME）は上の方でユーザーレベル環境変数として
# Windows に永続保存してあるので、komorebic 経由で起動しても whkd が設定を見つけられる。
komorebic start --whkd --bar 2>&1
Start-Sleep -Seconds 3

# 確認
$procs = Get-Process -Name komorebi, komorebi-bar, whkd -ErrorAction SilentlyContinue
Write-Host "=== Running processes ==="
$procs | Format-Table Name, Id -AutoSize
Write-Host "whkd config home: $Env:WHKD_CONFIG_HOME"
