$action = New-ScheduledTaskAction `
    -Execute "C:\Program Files\PowerShell\7\pwsh.exe" `
    -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File ""C:\Users\0000250059\.config\komorebi\scripts\restart.ps1"""

$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$trigger.Delay = "PT30S"  # Wait 30s after logon for profile/filesystem to be ready

$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -RunLevel Highest -LogonType Interactive

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit (New-TimeSpan -Seconds 0)

Register-ScheduledTask `
    -TaskName "komorebi" `
    -Action $action `
    -Trigger $trigger `
    -Principal $principal `
    -Settings $settings `
    -Description "Start komorebi with admin privileges" `
    -Force

Write-Host "Task registered successfully"
