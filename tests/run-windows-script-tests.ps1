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
    if ($FocusCountries -ne "SG,HK,JP,KR,US,DE,GB") {
        throw "US must have a dedicated default focus scope."
    }
    $floors = ConvertFrom-CountryMinSpeedMap -Value $CountryMinSpeedMBPerSec -AllowedCountries $Countries
    if ($floors.Count -ne 4 -or $floors["JP"] -ne 10 -or $floors["US"] -ne 5 -or $floors["KR"] -ne 3 -or $floors["HK"] -ne 2) {
        throw "Unexpected default country speed floors."
    }
    if ((ConvertFrom-CountryMinSpeedMap -Value "" -AllowedCountries $Countries).Count -ne 0) {
        throw "An empty country speed floor map must disable the feature."
    }
    foreach ($bad in @("JP", "JP=x", "JP=-1", "JP=1,JP=2", "ZZ=1")) {
        try {
            ConvertFrom-CountryMinSpeedMap -Value $bad -AllowedCountries $Countries | Out-Null
            throw "Invalid map was accepted: $bad"
        }
        catch {
            if ($_.Exception.Message -eq "Invalid map was accepted: $bad") { throw }
        }
    }
    $candidateProfile = @($IpZipSamplePercent, $IpZipCountryMinCandidates, $IpZipCountryMaxCandidates, $CfBestIpPerCountryLimit, $Vps789CtLimit, $TcpPrecheckMaxCandidates) -join ","
    if ($candidateProfile -ne "40,40,320,400,100,30") {
        throw "Expected expanded candidate defaults 40,40,320,400,100,30; got $candidateProfile."
    }
    $profile = @($CfstLatencyTestCount, $CfstDownloadTestCount, $CfstDownloadTestTime, $FocusCfstDownloadTestCount, $FocusCfstDownloadTestTime) -join ","
    if ($profile -ne "2,10,4,10,4") {
        throw "Expected fast CFST defaults 2,10,4,10,4; got $profile."
    }
    $allArgs = @(Get-CfstArguments -Item ([pscustomobject]@{ Scope = "all"; Port = 443; SelectedIpPath = "all.txt"; CsvPath = "all.csv" })) -join " "
    $focusArgs = @(Get-CfstArguments -Item ([pscustomobject]@{ Scope = "focus-DE"; Port = 443; SelectedIpPath = "focus.txt"; CsvPath = "focus.csv" })) -join " "
    if ($allArgs -notmatch '(?:^| )-t 2 -dn 10 -dt 4(?: |$)' -or $focusArgs -notmatch '(?:^| )-t 2 -dn 10 -dt 4(?: |$)') {
        throw "Windows all and focus scopes must build the fast CFST argument profile."
    }
    if ((Get-PositiveTcpPrecheckValue -Value 0 -Fallback 1) -ne 1 -or (Get-PositiveTcpPrecheckValue -Value 32 -Fallback 1) -ne 32) {
        throw "TCP precheck values must be normalized to positive integers."
    }
    $script:WorkDir = $tempDir
    $script:logFile = $logPath
    $script:TcpPrecheckEnabled = $true
    $script:TcpPrecheckMinCandidates = 120
    $script:TcpPrecheckTimeoutMs = 200
    $script:TcpPrecheckThreads = 32
    $script:TcpPrecheckMaxCandidates = 30
    Invoke-TcpPrecheck -Port $listenerPort -SelectedIpPath $selectedPath -MapPath $mapPath

    $result = @(Get-Content -LiteralPath $selectedPath)
    if ($result.Count -ne 31) {
        throw "Expected 30 new candidates and one previous candidate, got $($result.Count)."
    }
    if (-not ($result -contains "192.0.2.1")) {
        throw "Previous candidate was removed by TCP precheck."
    }
    if (-not ((Get-Content -LiteralPath $logPath -Raw) -match "TCP precheck input=122 connected=121 kept_new=30 kept_previous=1 elapsed_ms=")) {
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

    $mergeMapPath = Join-Path $tempDir "merge-map.csv"
    $mergeCfstPath = Join-Path $tempDir "merge-cfst.csv"
    $script:csvPath = Join-Path $tempDir "merged.csv"
    [System.IO.File]::WriteAllLines($mergeMapPath, @(
        "203.0.113.9,JP,previous",
        "203.0.113.10,JP,ip.zip",
        "203.0.113.11,JP,ip.zip",
        "203.0.113.12,HK,ip.zip",
        "203.0.113.20,DE,ip.zip"
    ), [System.Text.Encoding]::ASCII)
    [System.IO.File]::WriteAllLines($mergeCfstPath, @(
        "IP,Sent,Received,Loss,Latency,Speed,DataCenter",
        "203.0.113.9,4,4,0,10,9.99,SFO",
        "203.0.113.10,4,4,0,10,10.00,SFO",
        "203.0.113.11,4,4,0,10,11.00,SFO",
        "203.0.113.12,4,4,0,10,1.99,SFO",
        "203.0.113.20,4,4,0,10,0.01,SFO"
    ), [System.Text.Encoding]::ASCII)
    $script:MinSpeedMbps = 0
    $previousNodeKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    [void]$previousNodeKeys.Add("203.0.113.9|443|JP")
    Write-MergedFilteredCsv -WorkItems @([pscustomobject]@{ MapPath = $mergeMapPath; CsvPath = $mergeCfstPath; Port = 443 }) -PreviousNodeKeys $previousNodeKeys

    $output = Import-Csv -LiteralPath $script:csvPath
    $ipHeaderName = "IP" + [string]([char]0x5730) + [string]([char]0x5740)
    $cityHeaderName = [string]([char]0x57CE) + [string]([char]0x5E02)
    if ($output.$ipHeaderName -contains '203.0.113.9') { throw 'Previous JP row below 10 MB/s bypassed its floor.' }
    if ($output.$ipHeaderName -notcontains '203.0.113.10') { throw 'JP row exactly at 10 MB/s was removed.' }
    if ($output.$ipHeaderName -notcontains '203.0.113.11') { throw 'JP row above 10 MB/s was removed.' }
    if ($output | Where-Object { $_.$cityHeaderName -like 'HK *' }) { throw 'HK must be allowed to produce zero rows.' }
    if ($output.$ipHeaderName -notcontains '203.0.113.20') { throw 'Unconfigured DE row must retain global-floor behavior.' }
    $mergeLog = Get-Content -LiteralPath $logPath -Raw
    if ($mergeLog -notmatch 'Country speed floor JP >= 10 MB/s: evaluated=3 removed=1 passed=2\.' -or $mergeLog -notmatch 'Country speed floor HK >= 2 MB/s: evaluated=1 removed=1 passed=0\.') {
        throw 'Country speed floor summaries were not logged.'
    }

    $equalDuration = foreach ($index in 1..31) {
        [pscustomobject]@{ Ip = "203.0.113.$index"; City = "DE"; Source = "ip.zip"; ElapsedMs = 5; Ordinal = $index }
    }
    $equalDurationResult = @(Select-TcpPrecheckCandidates -Successful $equalDuration -MaxCandidates 30)
    if ($equalDurationResult.Count -ne 30 -or $equalDurationResult[0] -ne "203.0.113.1" -or $equalDurationResult[-1] -ne "203.0.113.30") {
        throw "Equal-duration TCP candidates must retain input order."
    }

    Write-Host "Windows script tests passed."
}
finally {
    $env:CFOPT_SOURCE_ONLY = $null
    $listener.Stop()
    Remove-Item -LiteralPath $tempDir -Recurse -Force
}
