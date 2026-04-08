# ユーザー環境変数として永続的に設定（Windowsの「システム環境変数」に書き込む）
# こうすることで、このスクリプト以外から起動されたプロセス（whkd など）でも
# 設定ファイルの場所を見つけられるようになる
[System.Environment]::SetEnvironmentVariable("KOMOREBI_CONFIG_HOME", "$env:USERPROFILE\.config\komorebi", "User")
[System.Environment]::SetEnvironmentVariable("WHKD_CONFIG_HOME", "$env:USERPROFILE\.config\komorebi", "User")

# Low-level keyboard hook のタイムアウトを延長（デフォルト ~300ms → 5000ms）
# テキストボックスにフォーカスした際、IME などの処理でフックの応答が遅れると
# Windows がフックを無効化してしまう。タイムアウトを伸ばすことでこれを防ぐ。
# ※ 反映にはログオフ/再起動が必要な場合がある
Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "LowLevelHooksTimeout" -Value 5000 -Type DWord -Force

# 設定ファイルの場所を環境変数で指定（現セッション用）
$Env:KOMOREBI_CONFIG_HOME = "$env:USERPROFILE\.config\komorebi"
$Env:WHKD_CONFIG_HOME = "$env:USERPROFILE\.config\komorebi"

# komorebi と whkd の実行ファイルがあるフォルダを PATH に追加して、コマンドとして使えるようにする
$Env:Path = "C:\Program Files\komorebi\bin;C:\Program Files\whkd\bin;" + $Env:Path

# komorebi, whkd, bar を全て停止（komorebic stop で komorebi 本体に停止命令を送る）
komorebic stop 2>&1 | Out-Null
Stop-Process -Name whkd -Force -ErrorAction SilentlyContinue
Stop-Process -Name komorebi-bar -Force -ErrorAction SilentlyContinue
Stop-Process -Name komorebi -Force -ErrorAction SilentlyContinue
# distribute-windows.ps1 が動いている pwsh プロセスを探して停止する
# （再起動時に旧プロセスが残らないようにするため）
# pwsh.exe = PowerShell 7 のプロセス名
Get-CimInstance Win32_Process -Filter "Name='pwsh.exe'" |
    Where-Object { $_.CommandLine -like "*distribute-windows*" } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
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
# distribute-windows.ps1 をバックグラウンドで起動する
# 新しいウィンドウを空いているワークスペースへ自動振り分けするスクリプト
# pwsh (PowerShell 7) を使う理由: PS 5.1 では大きな JSON のパースに失敗するため
# -WindowStyle Hidden で窓を出さずに裏で動かす
Start-Process pwsh -ArgumentList "-ExecutionPolicy Bypass -File `"$PSScriptRoot\distribute-windows.ps1`"" -WindowStyle Hidden
Start-Sleep -Seconds 3

# 確認
$procs = Get-Process -Name komorebi, komorebi-bar, whkd -ErrorAction SilentlyContinue
Write-Host "=== Running processes ==="
$procs | Format-Table Name, Id -AutoSize
Write-Host "whkd config home: $Env:WHKD_CONFIG_HOME"
