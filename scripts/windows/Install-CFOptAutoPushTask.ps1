param(
    [string]$ScriptPath = (Join-Path $PSScriptRoot "Invoke-CFOptAutoPush.ps1"),
    [string]$TaskName = "CFOpt Auto Push",
    [string]$DailyAt = "04:00",
    [int]$StartupDelayMinutes = 2
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $ScriptPath)) {
    throw "Main script not found: $ScriptPath"
}

$powershell = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$argument = "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`""

$action = New-ScheduledTaskAction -Execute $powershell -Argument $argument
$dailyTrigger = New-ScheduledTaskTrigger -Daily -At ([datetime]::Parse($DailyAt))
$startupTrigger = New-ScheduledTaskTrigger -AtStartup
$startupTrigger.Delay = "PT${StartupDelayMinutes}M"
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
    -Trigger @($dailyTrigger, $startupTrigger) `
    -Principal $principal `
    -Settings $settings `
    -Description "Daily CFOpt rolling retest: retest previous CSV nodes, replace weak rows, and upload CloudflareSpeedTest CSV." | Out-Null

Write-Host "Scheduled task installed: $TaskName"
Write-Host "It will run daily at $DailyAt and at startup after $StartupDelayMinutes minute(s). The main script enforces the 1-day interval."
