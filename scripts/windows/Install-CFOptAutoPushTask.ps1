param(
    [string]$ScriptPath = "C:\Users\GuardSkill\Documents\Codex\2026-06-27\ni\outputs\Invoke-CFOptAutoPush.ps1",
    [string]$TaskName = "CFOpt Auto Push",
    [int]$StartupDelayMinutes = 2
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $ScriptPath)) {
    throw "Main script not found: $ScriptPath"
}

$powershell = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$argument = "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`""

$action = New-ScheduledTaskAction -Execute $powershell -Argument $argument
$trigger = New-ScheduledTaskTrigger -AtStartup
$trigger.Delay = "PT${StartupDelayMinutes}M"
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -MultipleInstances IgnoreNew `
    -ExecutionTimeLimit (New-TimeSpan -Hours 6)

if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
}

Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $action `
    -Trigger $trigger `
    -Principal $principal `
    -Settings $settings `
    -Description "Download IP lists, run cfst, and push CloudflareSpeedTest.csv to GitHub every 6 days after startup." | Out-Null

Write-Host "Scheduled task installed: $TaskName"
Write-Host "It will run at startup after $StartupDelayMinutes minute(s). The main script enforces the 6-day interval."
