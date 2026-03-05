# create-startup-shortcut.ps1
# Create a startup shortcut for komorebi with RunAs (admin) flag

$shortcutPath = "$Env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\komorebi-restart.lnk"
$scriptPath = "C:\Users\0000250059\.config\komorebi\scripts\restart.ps1"
$pwshPath = (Get-Command pwsh -ErrorAction Stop).Source

$shell = New-Object -ComObject WScript.Shell
$lnk = $shell.CreateShortcut($shortcutPath)
$lnk.TargetPath = $pwshPath
$lnk.Arguments = "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`""
$lnk.WindowStyle = 7  # Minimized
$lnk.Description = "komorebi auto-start on login (admin)"
$lnk.Save()

# Patch the .lnk binary to set RUNASADMIN flag (byte 0x15, bit 0x20)
# WScript.Shell COM does not expose this property
$bytes = [System.IO.File]::ReadAllBytes($shortcutPath)
$bytes[0x15] = $bytes[0x15] -bor 0x20
[System.IO.File]::WriteAllBytes($shortcutPath, $bytes)

Write-Host "Created startup shortcut with RunAs flag: $shortcutPath"
