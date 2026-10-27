param(
    [string]$WorkDir = (Join-Path $PSScriptRoot '..\..\.cfopt-work\proxyip-refresh'),
    [double]$ProbeTimeout = 1.5
)

$ErrorActionPreference = 'Stop'
$sourceOnlyBefore = $env:CFOPT_SOURCE_ONLY
try {
    New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
    $env:CFOPT_SOURCE_ONLY = '1'
    . (Join-Path $PSScriptRoot 'Invoke-CFOptAutoPush.ps1') -WorkDir $WorkDir `
        -CfstPath (Join-Path $WorkDir 'unused-cfst.exe') -ProxyipBestTimeout $ProbeTimeout
    # Never upload a stale file after a generation failure.
    if (Test-Path -LiteralPath $proxyipBestPath) { Remove-Item -LiteralPath $proxyipBestPath }
    New-ProxyipBestFile
    if (-not (Test-Path -LiteralPath $proxyipBestPath)) { throw 'ProxyIP generation did not produce a fresh file.' }
    $lines = @(Get-Content -LiteralPath $proxyipBestPath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($lines.Count -lt 10) { throw "ProxyIP publication blocked: only $($lines.Count) validated entries; minimum 10." }
    Publish-FileToGitHub -LocalPath $proxyipBestPath -UploadTargetPath $ProxyipBestTargetPath
    Write-Log "Independent ProxyIP refresh published $($lines.Count) validated entries."
}
finally {
    $env:CFOPT_SOURCE_ONLY = $sourceOnlyBefore
}
