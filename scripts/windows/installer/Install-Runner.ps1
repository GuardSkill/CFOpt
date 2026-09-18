param(
    [string]$RunnerName,
    [string]$InstallDir = "$env:ProgramData\CFOpt\runner-sc",
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'
if ($RunnerName -notmatch '^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$') {
    throw 'Runner name must contain 1-64 ASCII letters, digits, underscores or hyphens.'
}
$token = $env:CFOPT_REGISTRATION_TOKEN
if ([string]::IsNullOrWhiteSpace($token) -or $token -notmatch '^[A-Za-z0-9_\-]+$') {
    throw 'Enter a valid temporary GitHub runner registration token, not a personal access token.'
}
if ($token -match '^(ghp_|github_pat_)') { throw 'Personal access tokens are not accepted.' }
if ($ValidateOnly) { Write-Output 'Installer parameter validation passed.'; exit 0 }

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Administrator permission is required to install the Windows service.'
}
if (-not [Environment]::Is64BitOperatingSystem -or $env:PROCESSOR_ARCHITECTURE -eq 'ARM64') {
    throw 'This installer supports Windows x64 only.'
}
$git = Get-Command git.exe -ErrorAction SilentlyContinue
if (-not $git) {
    throw 'Git for Windows is required. Install it from https://git-scm.com/download/win, then run this installer again.'
}
$InstallDir = [IO.Path]::GetFullPath($InstallDir)
if (Test-Path -LiteralPath $InstallDir) {
    if (@(Get-ChildItem -LiteralPath $InstallDir -Force).Count -gt 0) {
        throw "Install directory is not empty: $InstallDir. Existing runners are never replaced automatically."
    }
}
New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$headers = @{ 'User-Agent' = 'CFOpt-Runner-Installer'; Accept = 'application/vnd.github+json' }
Write-Output 'Downloading the official GitHub Actions runner (Windows x64)...'
$release = Invoke-RestMethod -Headers $headers -Uri 'https://api.github.com/repos/actions/runner/releases/latest'
$assets = @($release.assets | Where-Object { $_.name -match '^actions-runner-win-x64-[0-9.]+\.zip$' })
if ($assets.Count -ne 1) { throw 'Could not find exactly one official Windows x64 runner archive.' }
$asset = $assets[0]
if ($asset.digest -notmatch '^sha256:([a-fA-F0-9]{64})$') {
    throw 'Official runner SHA256 digest is unavailable; refusing an unverified download.'
}
$expectedHash = $Matches[1]
$archive = Join-Path $InstallDir 'runner-download.zip'
Invoke-WebRequest -UseBasicParsing -Uri $asset.browser_download_url -OutFile $archive
if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne $expectedHash) {
    throw 'Runner archive SHA256 verification failed. Nothing has been registered.'
}
Write-Output 'SHA256 verified. Extracting the runner...'
Expand-Archive -LiteralPath $archive -DestinationPath $InstallDir
Remove-Item -LiteralPath $archive

# Grant the service identity access only to this dedicated installation directory.
& icacls.exe $InstallDir /grant '*S-1-5-20:(OI)(CI)M' /T /Q | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Could not grant NETWORK SERVICE access to the runner directory.' }
Push-Location $InstallDir
try {
    Write-Output 'Registering Sichuan CMCC runner and installing its Windows service...'
    & .\config.cmd --unattended --url 'https://github.com/GuardSkill/CFOpt' `
        --token $token --name $RunnerName --work '_work' `
        --labels 'cfopt,sichuan,cmcc' --runasservice `
        --windowslogonaccount 'NT AUTHORITY\NETWORK SERVICE' 2>&1 |
        ForEach-Object { Write-Output ($_.ToString().Replace($token, '[REDACTED]')) }
    if ($LASTEXITCODE -ne 0) { throw 'Runner registration failed. Obtain a fresh registration token. See the log above.' }
    $serviceFile = Join-Path $InstallDir '.service'
    if (-not (Test-Path -LiteralPath $serviceFile)) { throw 'Runner did not create a Windows service.' }
    $serviceName = (Get-Content -LiteralPath $serviceFile -Raw).Trim()
    Set-Service -Name $serviceName -StartupType Automatic
    $service = Get-Service -Name $serviceName
    if ($service.Status -ne 'Running') { Start-Service -Name $serviceName }
    Write-Output "Installation complete. Service: $serviceName"
    Write-Output 'Profile: Sichuan CMCC / Deyang; output: CMCC_SC.csv.'
    Write-Output 'The service starts at boot, even before login. Benchmarking requires a GitHub Actions job.'
    Write-Output 'Ask the repository owner to run: Actions > Update Sichuan CMCC CSV > Run workflow.'
}
finally {
    Pop-Location
    Remove-Item Env:\CFOPT_REGISTRATION_TOKEN -ErrorAction SilentlyContinue
    $token = $null
}
