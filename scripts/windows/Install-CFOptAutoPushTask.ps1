param(
    [string]$Owner = "GuardSkill",
    [string]$Repo = "CFOpt",
    [string]$Branch = "main",
    [string]$WorkDir = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) ".cfopt-work"),
    [string]$BaseUrl = "",
    [string]$ScriptUrl = "",
    [string]$ScriptPath = "",
    [string]$CfstReleaseApiUrl = "https://api.github.com/repos/XIU2/CloudflareSpeedTest/releases/latest",
    [string]$CfstAssetName = "cfst_windows_amd64.zip",
    [string]$CfstPath = "",
    [string]$TaskName = "CFOpt Auto Push",
    [string]$DailyAt = "03:30",
    [int]$StartupDelayMinutes = 2,
    [switch]$SkipDownloads
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($BaseUrl)) {
    $BaseUrl = "https://raw.githubusercontent.com/$Owner/$Repo/$Branch"
}
if ([string]::IsNullOrWhiteSpace($ScriptUrl)) {
    $ScriptUrl = "$BaseUrl/scripts/windows/Invoke-CFOptAutoPush.ps1"
}
if ([string]::IsNullOrWhiteSpace($ScriptPath)) {
    $ScriptPath = Join-Path $WorkDir "Invoke-CFOptAutoPush.ps1"
}
if ([string]::IsNullOrWhiteSpace($CfstPath)) {
    $CfstPath = Join-Path $WorkDir "cfst.exe"
}

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null

function Save-RemoteFile {
    param(
        [string]$Url,
        [string]$Path
    )

    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }

    Invoke-WebRequest -Uri $Url -OutFile $Path -UseBasicParsing -Headers @{ "User-Agent" = "CFOptInstaller" }
}

function Install-Cfst {
    if (Test-Path -LiteralPath $CfstPath) {
        return
    }

    Write-Host "Downloading cfst binary from latest CloudflareSpeedTest release"
    $release = Invoke-RestMethod -Uri $CfstReleaseApiUrl -Headers @{ "User-Agent" = "CFOptInstaller" }
    $asset = @($release.assets | Where-Object { $_.name -eq $CfstAssetName } | Select-Object -First 1)
    if (-not $asset) {
        throw "Could not find release asset '$CfstAssetName' from $CfstReleaseApiUrl"
    }

    $zipPath = Join-Path $WorkDir $CfstAssetName
    $extractPath = Join-Path $WorkDir "cfst-download"
    if (Test-Path -LiteralPath $extractPath) {
        Remove-Item -LiteralPath $extractPath -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $extractPath | Out-Null

    Save-RemoteFile -Url $asset.browser_download_url -Path $zipPath
    Expand-Archive -LiteralPath $zipPath -DestinationPath $extractPath -Force

    $downloadedCfst = Get-ChildItem -LiteralPath $extractPath -Recurse -File -Filter "cfst.exe" | Select-Object -First 1
    if (-not $downloadedCfst) {
        throw "Downloaded archive did not contain cfst.exe: $zipPath"
    }

    Copy-Item -LiteralPath $downloadedCfst.FullName -Destination $CfstPath -Force
}

if (-not $SkipDownloads) {
    Write-Host "Downloading CFOpt Windows runner to $ScriptPath"
    Save-RemoteFile -Url $ScriptUrl -Path $ScriptPath
    Install-Cfst
}

if (-not (Test-Path -LiteralPath $ScriptPath)) {
    throw "Main script not found: $ScriptPath"
}
if (-not (Test-Path -LiteralPath $CfstPath)) {
    throw "cfst executable not found: $CfstPath"
}

$powershell = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$argument = "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`" -WorkDir `"$WorkDir`" -CfstPath `"$CfstPath`" -AutoDetectNetworkIsp"

$action = New-ScheduledTaskAction -Execute $powershell -Argument $argument -WorkingDirectory $repoRoot
$dailyTrigger = New-ScheduledTaskTrigger -Once -At ([datetime]::Parse($DailyAt))
$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$logonTrigger = New-ScheduledTaskTrigger -AtLogOn -User $currentUser
$logonTrigger.Delay = "PT${StartupDelayMinutes}M"
$principal = New-ScheduledTaskPrincipal -UserId $currentUser -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -MultipleInstances IgnoreNew `
    -ExecutionTimeLimit (New-TimeSpan -Hours 6)

try {
    Register-ScheduledTask `
        -TaskName $TaskName `
        -Action $action `
        -Trigger @($dailyTrigger, $logonTrigger) `
        -Principal $principal `
        -Settings $settings `
        -Force `
        -Description "CFOpt daily rolling retest at ${DailyAt}: detect the direct ISP, update the Chengdu Mobile or Telecom CSV, and upload qualified nodes." | Out-Null
}
catch {
    Write-Warning "Task Scheduler cmdlets could not install the logon trigger; falling back to a daily current-user task: $($_.Exception.Message)"
    $taskCommand = "powershell.exe $argument"
    if ($taskCommand.Length -gt 261) {
        throw "Fallback task command exceeds the schtasks.exe 261-character limit."
    }
    & schtasks.exe /Create /TN $TaskName /TR $taskCommand /SC DAILY /ST $DailyAt /RL LIMITED /F | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "schtasks.exe fallback failed with exit code $LASTEXITCODE."
    }
}

Write-Host "Scheduled task installed: $TaskName"
Write-Host "It will run daily at $DailyAt and, when permitted, at logon after $StartupDelayMinutes minute(s)."
Write-Host "Script path: $ScriptPath"
Write-Host "Work dir: $WorkDir"
Write-Host "cfst path: $CfstPath"
