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

    $script:extractDir = Join-Path $tempDir "extract"
    $portDir = Join-Path $script:extractDir "443"
    New-Item -ItemType Directory -Force -Path $portDir | Out-Null
    [System.IO.File]::WriteAllLines((Join-Path $portDir "DE.txt"), @("198.51.100.10"), [System.Text.Encoding]::ASCII)
    $previousEntry = [pscustomobject]@{ Ip = "198.51.100.10"; Port = 443; City = "DE" }
    $workItem = New-PortWorkItem -CurrentPort 443 -Vps789CtIps @() -CfBestIpCandidates @() -PreviousCsvEntries @($previousEntry) -SelectedCountries @("DE") -ScopeName "overlap" -IncludeVps789Ct $false
    $overlapMap = @(Get-Content -LiteralPath $workItem.MapPath)
    if (-not ($overlapMap -contains "198.51.100.10,DE,previous")) {
        throw "Overlapping previous candidate must be marked previous by the work-item builder."
    }

    $emptySelectedPath = Join-Path $tempDir "empty-selected.txt"
    $emptyMapPath = Join-Path $tempDir "empty-map.csv"
    $emptySelected = foreach ($index in 1..121) { "127.0.1.$index" }
    $emptyMap = foreach ($index in 1..121) { "127.0.1.$index,DE,ip.zip" }
    [System.IO.File]::WriteAllLines($emptySelectedPath, $emptySelected, [System.Text.Encoding]::ASCII)
    [System.IO.File]::WriteAllLines($emptyMapPath, $emptyMap, [System.Text.Encoding]::ASCII)
    Invoke-TcpPrecheck -Port 1 -SelectedIpPath $emptySelectedPath -MapPath $emptyMapPath
    $emptyWorkItem = [pscustomobject]@{ Port = 1; Scope = "focus-DE"; SelectedIpPath = $emptySelectedPath }
    $remainingWorkItems = @(Get-NonEmptyWorkItems -WorkItems @($emptyWorkItem))
    if ($remainingWorkItems.Count -ne 0) {
        throw "Empty TCP precheck work item must be removed before CFST."
    }
    if (-not ((Get-Content -LiteralPath $logPath -Raw) -match "Skipping empty TCP precheck work item")) {
        throw "Skipped empty TCP precheck work item was not logged."
    }

    $equalDuration = foreach ($index in 1..81) {
        [pscustomobject]@{ Ip = "203.0.113.$index"; City = "DE"; Source = "ip.zip"; ElapsedMs = 5; Ordinal = $index }
    }
    $equalDurationResult = @(Select-TcpPrecheckCandidates -Successful $equalDuration -MaxCandidates 80)
    if ($equalDurationResult.Count -ne 80 -or $equalDurationResult[0] -ne "203.0.113.1" -or $equalDurationResult[-1] -ne "203.0.113.80") {
        throw "Equal-duration TCP candidates must retain input order."
    }

    Write-Host "Windows script tests passed."
}
finally {
    $env:CFOPT_SOURCE_ONLY = $null
    $listener.Stop()
    Remove-Item -LiteralPath $tempDir -Recurse -Force
}
