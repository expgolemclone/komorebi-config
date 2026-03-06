# create-startup-shortcut.ps1
# shell:startup に komorebi 自動起動用のショートカットを作成する

$shortcutPath = "$Env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\komorebi-restart.lnk"
$scriptPath = "C:\Users\0000250059\.config\komorebi\scripts\restart.ps1"
$pwshPath = (Get-Command pwsh -ErrorAction Stop).Source

$shell = New-Object -ComObject WScript.Shell
$lnk = $shell.CreateShortcut($shortcutPath)
$lnk.TargetPath = $pwshPath
$lnk.Arguments = "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`""
$lnk.WindowStyle = 7  # 最小化
$lnk.Description = "komorebi auto-start on login"
$lnk.Save()

Write-Host "Created startup shortcut: $shortcutPath"
