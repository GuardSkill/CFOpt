$ErrorActionPreference = "Stop"

$rootDir = Split-Path -Parent $PSScriptRoot
$runnerPath = Join-Path $rootDir "scripts\windows\Invoke-CFOptAutoPush.ps1"
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("cfopt-tcp-precheck-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $tempDir | Out-Null

$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, 0)
$listener.Start(256)
$listenerPort = ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port

try {
    $selectedPath = Join-Path $tempDir "selected.txt"
    $mapPath = Join-Path $tempDir "map.csv"
    $logPath = Join-Path $tempDir "precheck.log"
    $selected = [System.Collections.Generic.List[string]]::new()
    $map = [System.Collections.Generic.List[string]]::new()
    foreach ($index in 1..121) {
        $ip = "127.0.0.$index"
        $selected.Add($ip)
        $map.Add("$ip,DE,ip.zip")
    }
    $selected.Add("192.0.2.1")
    $map.Add("192.0.2.1,DE,ip.zip")
    $map.Add("192.0.2.1,DE,previous")
    [System.IO.File]::WriteAllLines($selectedPath, $selected, [System.Text.Encoding]::ASCII)
    [System.IO.File]::WriteAllLines($mapPath, $map, [System.Text.Encoding]::ASCII)

    $env:CFOPT_SOURCE_ONLY = "1"
    . $runnerPath
    $script:WorkDir = $tempDir
    $script:logFile = $logPath
    $script:TcpPrecheckEnabled = $true
    $script:TcpPrecheckMinCandidates = 120
    $script:TcpPrecheckTimeoutMs = 200
    $script:TcpPrecheckThreads = 32
    $script:TcpPrecheckMaxCandidates = 80
    Invoke-TcpPrecheck -Port $listenerPort -SelectedIpPath $selectedPath -MapPath $mapPath

    $result = @(Get-Content -LiteralPath $selectedPath)
    if ($result.Count -ne 81) {
        throw "Expected 80 new candidates and one previous candidate, got $($result.Count)."
    }
    if (-not ($result -contains "192.0.2.1")) {
        throw "Previous candidate was removed by TCP precheck."
    }
    if (-not ((Get-Content -LiteralPath $logPath -Raw) -match "TCP precheck input=122 connected=121 kept_new=80 kept_previous=1 elapsed_ms=")) {
        throw "TCP precheck metrics were not logged."
    }

    $runnerText = Get-Content -LiteralPath $runnerPath -Raw
    $functionText = [regex]::Match($runnerText, 'function Invoke-TcpPrecheck[\s\S]*?\r?\n}').Value
    if ([string]::IsNullOrWhiteSpace($functionText)) {
        throw "Invoke-TcpPrecheck function was not found."
    }
    if ($functionText.ToCharArray() | Where-Object { [int]$_ -gt 127 } | Select-Object -First 1) {
        throw "Invoke-TcpPrecheck must contain ASCII characters only."
    }

    Write-Host "Windows script tests passed."
}
finally {
    $env:CFOPT_SOURCE_ONLY = $null
    $listener.Stop()
    Remove-Item -LiteralPath $tempDir -Recurse -Force
}
