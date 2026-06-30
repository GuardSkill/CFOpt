param(
    [string]$DownloadUrl = "https://zip.cm.edu.kg/ip.zip",
    [string]$WorkDir = "H:\PyProjects\CFOptAutoPush",
    [string]$CfstPath = "H:\PyProjects\cfst_windows_amd64\cfst.exe",
    [string[]]$Countries = @("HK", "JP", "KR", "SG", "PH", "VN", "MY", "KZ", "MN", "IE", "US"),
    [int]$Port = 0,
    [string]$Ports = "443,2053,2083,2087,2096,8443",
    [string]$DownloadTestUrl = "https://cf.xiu2.xyz/url",
    [string]$Owner = "GuardSkill",
    [string]$Repo = "CFOpt",
    [string]$Branch = "main",
    [string]$TargetPath = "CloudflareSpeedTest_CD.csv",
    [int]$IntervalDays = 1,
    [int]$MaxLatencyMs = 420,
    [int]$MinReceived = 1,
    [double]$MinSpeedMbps = 0.03,
    [int]$MaxPerCity = 20,
    [int]$CfstThreads = 80,
    [int]$CfstLatencyTestCount = 6,
    [int]$CfstDownloadTestCount = 30,
    [int]$CfstDownloadTestTime = 15,
    [double]$CfstLossRateLimit = 0,
    [int]$MaxParallelCfst = 1,
    [switch]$UseProxyForCfst,
    [string]$FocusCountries = "HK,KR,JP,SG",
    [string]$TestLocationName = "",
    [string]$CfBestIpBaseUrl = "https://zoroaaa.github.io/cf-bestip",
    [int]$CfBestIpPerCountryLimit = 200,
    [double]$RollingReplaceFraction = 0.33,
    [int]$Vps789CtLimit = 100,
    [int]$Vps789MaxDxLatencyMs = 260,
    [double]$Vps789MaxDxLossRate = 5,
    [string]$TokenEnvName = "GITHUB_TOKEN_CFOPT",
    [switch]$Force,
    [switch]$DryRun,
    [switch]$SkipUpload,
    [switch]$CfstDebug,
    [switch]$DisableCfBestIp,
    [switch]$EnableVps789Ct,
    [switch]$DisableVps789Ct
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($TestLocationName)) {
    $TestLocationName = [string]([char]0x6210) + [string]([char]0x90FD) + [string]([char]0x6D4B) + [string]([char]0x901F)
}

$zipPath = Join-Path $WorkDir "ip.zip"
$extractDir = Join-Path $WorkDir "extract"
$csvPath = Join-Path $WorkDir "CloudflareSpeedTest.csv"
$vps789CtCsvPath = Join-Path $WorkDir "VPS789_CF_CT_Candidates.csv"
$stateFile = Join-Path $WorkDir "last-success.txt"
$logFile = Join-Path $WorkDir "auto-push.log"

function Write-Log {
    param([string]$Message)

    $line = "{0} {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    Write-Host $line
    Add-Content -LiteralPath $logFile -Value $line -Encoding UTF8
}

function Get-EffectivePorts {
    if ($Port -gt 0) {
        return @($Port)
    }

    return @(
        $Ports -split '[,\s]+' |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            ForEach-Object { [int]$_ } |
            Where-Object { $_ -gt 0 } |
            Select-Object -Unique
    )
}

function Get-EffectiveFocusCountries {
    return @(
        $FocusCountries -split '[,\s]+' |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            ForEach-Object { $_.Trim().ToUpperInvariant() } |
            Select-Object -Unique
    )
}

function Test-IntervalGate {
    if ($Force -or $DryRun) {
        return $true
    }

    if (-not (Test-Path -LiteralPath $stateFile)) {
        return $true
    }

    $lastText = Get-Content -LiteralPath $stateFile -Raw
    $lastRun = [datetime]::Parse($lastText.Trim())
    $nextRun = $lastRun.AddDays($IntervalDays)

    if ((Get-Date) -lt $nextRun) {
        Write-Log "Skipped. Last successful run was $lastRun. Next run after $nextRun."
        return $false
    }

    return $true
}

function Get-GitHubToken {
    $token = [Environment]::GetEnvironmentVariable($TokenEnvName, "User")
    if ([string]::IsNullOrWhiteSpace($token)) {
        $token = [Environment]::GetEnvironmentVariable($TokenEnvName, "Machine")
    }
    if ([string]::IsNullOrWhiteSpace($token)) {
        throw "Missing GitHub token. Set user environment variable $TokenEnvName first."
    }
    return $token
}

function Resolve-CountryFile {
    param(
        [string]$Country,
        [System.IO.FileInfo[]]$Files
    )

    $fileName = "$Country.txt"
    $matches = @($Files | Where-Object { $_.Name -ieq $fileName })
    if ($matches.Count -eq 0) {
        throw "Country file not found in extracted zip: $fileName"
    }

    return $matches[0]
}

function Join-ProcessArguments {
    param([string[]]$Arguments)

    return ($Arguments | ForEach-Object {
        if ($_ -match '[\s"]') {
            '"' + ($_ -replace '"', '\"') + '"'
        }
        else {
            $_
        }
    }) -join " "
}

function Convert-ToNumber {
    param([string]$Value)

    $normalized = ($Value -replace "%", "").Trim()
    if ([string]::IsNullOrWhiteSpace($normalized)) {
        return $null
    }

    $culture = [System.Globalization.CultureInfo]::InvariantCulture
    $result = 0.0
    if ([double]::TryParse($normalized, [System.Globalization.NumberStyles]::Float, $culture, [ref]$result)) {
        return $result
    }

    return $null
}

function Get-CityKeyFromRemark {
    param([string]$Remark)

    if ([string]::IsNullOrWhiteSpace($Remark)) {
        return ""
    }

    $trimmed = $Remark.Trim()
    if ($trimmed -match '^([A-Za-z0-9_-]+)') {
        return $Matches[1].ToUpperInvariant()
    }

    return ""
}

function Get-PreviousCsvEntries {
    $rawUrl = "https://raw.githubusercontent.com/$Owner/$Repo/$Branch/$TargetPath"
    $entries = New-Object System.Collections.Generic.List[object]

    try {
        Write-Log "Fetching previous CSV for rolling retest: $rawUrl"
        $text = (Invoke-WebRequest -Uri $rawUrl -UseBasicParsing -TimeoutSec 30).Content
        $lines = @($text -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        foreach ($line in ($lines | Select-Object -Skip 1)) {
            $columns = $line -split ","
            if ($columns.Count -lt 4) {
                continue
            }

            $ip = $columns[0].Trim()
            $portText = $columns[1].Trim()
            $cityKey = Get-CityKeyFromRemark -Remark $columns[3]
            $portValue = 0
            if ($ip -match '^(?:\d{1,3}\.){3}\d{1,3}$' -and [int]::TryParse($portText, [ref]$portValue) -and -not [string]::IsNullOrWhiteSpace($cityKey)) {
                $entries.Add([pscustomobject]@{
                    Ip = $ip
                    Port = $portValue
                    City = $cityKey
                }) | Out-Null
            }
        }
        Write-Log "Loaded $($entries.Count) previous CSV nodes for rolling retest."
    }
    catch {
        Write-Log "WARN: Failed to fetch previous CSV for rolling retest: $($_.Exception.Message)"
    }

    return $entries.ToArray()
}

function Update-ZipCache {
    $tempZipPath = Join-Path $WorkDir "ip.download.zip"

    if (Test-Path -LiteralPath $tempZipPath) {
        Remove-Item -LiteralPath $tempZipPath -Force
    }

    try {
        Write-Log "Downloading $DownloadUrl"
        Invoke-WebRequest -Uri $DownloadUrl -OutFile $tempZipPath -UseBasicParsing
        Move-Item -LiteralPath $tempZipPath -Destination $zipPath -Force
        Write-Log "Downloaded zip cache: $zipPath"
    }
    catch {
        if (Test-Path -LiteralPath $tempZipPath) {
            Remove-Item -LiteralPath $tempZipPath -Force -ErrorAction SilentlyContinue
        }

        if (Test-Path -LiteralPath $zipPath) {
            Write-Log "WARN: Download failed: $($_.Exception.Message)"
            Write-Log "WARN: Reusing existing zip cache: $zipPath"
            return
        }

        throw
    }
}

function Get-Vps789CtIps {
    if ((-not $EnableVps789Ct) -or $DisableVps789Ct) {
        Write-Log "vps789 CT candidate source disabled."
        return @()
    }

    try {
        Write-Log "Fetching vps789 Cloudflare CT candidates."
        $response = Invoke-RestMethod -Uri "https://vps789.com/openApi/cfIpApi" -UseBasicParsing -TimeoutSec 30
        $items = @($response.data.CT)
        if ($items.Count -eq 0) {
            Write-Log "WARN: vps789 CT API returned no candidates."
            return @()
        }

        $filtered = @(
            $items |
                Where-Object {
                    $_.ip -match '^(?:\d{1,3}\.){3}\d{1,3}$' -and
                    [double]$_.dxLatencyAvg -le $Vps789MaxDxLatencyMs -and
                    [double]$_.dxPkgLostRateAvg -le $Vps789MaxDxLossRate
                } |
                Sort-Object @{ Expression = "dxPkgLostRateAvg"; Descending = $false }, @{ Expression = "dxLatencyAvg"; Descending = $false }, @{ Expression = "avgScore"; Descending = $false } |
                Select-Object -First $Vps789CtLimit
        )

        $candidateLines = New-Object System.Collections.Generic.List[string]
        $candidateLines.Add("No,IP,Line,DXLatencyMs,DXLossRate,LTLatencyMs,LTLossRate,YDLatencyMs,YDLossRate,UpdatedAt,Remark")
        $index = 0
        foreach ($item in $filtered) {
            $index++
            $remark = "CT{0:00}" -f $index
            $candidateLines.Add(("{0},{1},CT,{2},{3},{4},{5},{6},{7},{8},{9}" -f
                $remark,
                $item.ip,
                $item.dxLatencyAvg,
                $item.dxPkgLostRateAvg,
                $item.ltLatencyAvg,
                $item.ltPkgLostRateAvg,
                $item.ydLatencyAvg,
                $item.ydPkgLostRateAvg,
                $item.createdTime,
                "vps789-ct"))
        }
        [System.IO.File]::WriteAllLines($vps789CtCsvPath, $candidateLines.ToArray(), (New-Object System.Text.UTF8Encoding($false)))

        Write-Log "Fetched $($filtered.Count) vps789 CT candidates. Exported $vps789CtCsvPath."
        return $filtered
    }
    catch {
        Write-Log "WARN: Failed to fetch vps789 CT candidates: $($_.Exception.Message)"
        return @()
    }
}

function Get-CfBestIpCandidates {
    if ($DisableCfBestIp) {
        Write-Log "cf-bestip candidate source disabled."
        return @()
    }

    $candidates = New-Object System.Collections.Generic.List[object]
    foreach ($country in $Countries) {
        $countryCode = $country.Trim().ToUpperInvariant()
        if ([string]::IsNullOrWhiteSpace($countryCode)) {
            continue
        }

        $url = "{0}/ip_{1}.txt" -f $CfBestIpBaseUrl.TrimEnd("/"), $countryCode
        try {
            Write-Log "Fetching cf-bestip candidates: $url"
            $text = (Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 30).Content
            $countForCountry = 0
            foreach ($line in ($text -split "`r?`n")) {
                if ($countForCountry -ge $CfBestIpPerCountryLimit) {
                    break
                }
                $trimmed = $line.Trim()
                if ($trimmed -match '^(?<ip>(?:\d{1,3}\.){3}\d{1,3}):(?<port>\d+)#(?<region>[A-Za-z0-9_-]+)') {
                    $candidates.Add([pscustomobject]@{
                        Ip = $Matches.ip
                        Port = [int]$Matches.port
                        City = $countryCode
                    }) | Out-Null
                    $countForCountry++
                }
            }
            Write-Log "Fetched $countForCountry cf-bestip candidates for $countryCode."
        }
        catch {
            Write-Log "WARN: Failed to fetch cf-bestip candidates for $countryCode`: $($_.Exception.Message)"
        }
    }

    Write-Log "Fetched $($candidates.Count) cf-bestip candidates in total."
    return $candidates.ToArray()
}

function New-PortWorkItem {
    param(
        [int]$CurrentPort,
        [object[]]$Vps789CtIps,
        [object[]]$CfBestIpCandidates,
        [object[]]$PreviousCsvEntries,
        [string[]]$SelectedCountries = $Countries,
        [string]$ScopeName = "all",
        [bool]$IncludeVps789Ct = $true
    )

    $portDir = Join-Path $extractDir ([string]$CurrentPort)
    if (-not (Test-Path -LiteralPath $portDir)) {
        Write-Log "WARN: Port folder not found in extracted zip: $portDir. Skipping port $CurrentPort."
        return $null
    }

    Write-Log "Using IP files from zip port folder: $portDir"
    $allTxtFiles = @(Get-ChildItem -LiteralPath $portDir -File -Filter "*.txt")
    if ($allTxtFiles.Count -eq 0) {
        Write-Log "WARN: No .txt files found for port $CurrentPort. Skipping."
        return $null
    }

    $selectedFiles = foreach ($country in $SelectedCountries) {
        try {
            Resolve-CountryFile -Country $country -Files $allTxtFiles
        }
        catch {
            Write-Log "WARN: $($_.Exception.Message). Skipping $country on port $CurrentPort."
        }
    }

    if (@($selectedFiles).Count -eq 0) {
        Write-Log "WARN: None of the requested country files were found for port $CurrentPort."
        return $null
    }

    $safeScopeName = $ScopeName -replace '[^A-Za-z0-9_-]', '_'
    $selectedIpPath = Join-Path $WorkDir "selected-ip-$CurrentPort-$safeScopeName.txt"
    $selectedIpCityMapPath = Join-Path $WorkDir "selected-ip-city-map-$CurrentPort-$safeScopeName.csv"
    $portCsvPath = Join-Path $WorkDir "CloudflareSpeedTest-$CurrentPort-$safeScopeName.csv"
    foreach ($path in @($selectedIpPath, $selectedIpCityMapPath, $portCsvPath)) {
        if (Test-Path -LiteralPath $path) {
            Remove-Item -LiteralPath $path -Force
        }
    }

    $seenIps = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($file in $selectedFiles) {
        $city = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
        $ipLines = @(Get-Content -LiteralPath $file.FullName | Where-Object {
            -not [string]::IsNullOrWhiteSpace($_) -and -not $_.TrimStart().StartsWith("#")
        } | ForEach-Object { $_.Trim() } | Where-Object { $seenIps.Add($_) })

        $ipLines | Add-Content -LiteralPath $selectedIpPath -Encoding ASCII
        foreach ($ipLine in $ipLines) {
            Add-Content -LiteralPath $selectedIpCityMapPath -Value "$ipLine,$city,ip.zip" -Encoding ASCII
        }
    }

    $selectedCountrySet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($country in $SelectedCountries) {
        [void]$selectedCountrySet.Add($country.Trim())
    }

    $previousAdded = 0
    foreach ($entry in @($PreviousCsvEntries)) {
        if ($entry.Port -ne $CurrentPort) {
            continue
        }
        if (-not $selectedCountrySet.Contains([string]$entry.City)) {
            continue
        }
        $ip = [string]$entry.Ip
        if ([string]::IsNullOrWhiteSpace($ip)) {
            continue
        }
        $ip = $ip.Trim()
        if ($seenIps.Add($ip)) {
            Add-Content -LiteralPath $selectedIpPath -Value $ip -Encoding ASCII
            Add-Content -LiteralPath $selectedIpCityMapPath -Value "$ip,$($entry.City),previous" -Encoding ASCII
            $previousAdded++
        }
    }

    $cfBestIpAdded = 0
    foreach ($candidate in @($CfBestIpCandidates)) {
        if ($candidate.Port -ne $CurrentPort) {
            continue
        }
        if (-not $selectedCountrySet.Contains([string]$candidate.City)) {
            continue
        }
        $ip = [string]$candidate.Ip
        if ([string]::IsNullOrWhiteSpace($ip)) {
            continue
        }
        $ip = $ip.Trim()
        if ($seenIps.Add($ip)) {
            Add-Content -LiteralPath $selectedIpPath -Value $ip -Encoding ASCII
            $cfBestIpAdded++
        }
        Add-Content -LiteralPath $selectedIpCityMapPath -Value "$ip,$($candidate.City),cf-bestip" -Encoding ASCII
    }

    $vps789Added = 0
    foreach ($candidate in $(if ($IncludeVps789Ct) { @($Vps789CtIps) } else { @() })) {
        $ip = [string]$candidate.ip
        if ([string]::IsNullOrWhiteSpace($ip)) {
            continue
        }
        $ip = $ip.Trim()
        if ($seenIps.Add($ip)) {
            Add-Content -LiteralPath $selectedIpPath -Value $ip -Encoding ASCII
            $vps789Added++
        }
        Add-Content -LiteralPath $selectedIpCityMapPath -Value "$ip,VPS789CT,vps789" -Encoding ASCII
    }

    $lineCount = (Get-Content -LiteralPath $selectedIpPath | Where-Object {
        -not [string]::IsNullOrWhiteSpace($_) -and -not $_.TrimStart().StartsWith("#")
    }).Count
    if ($lineCount -eq 0) {
        Write-Log "WARN: Merged IP file is empty for port $CurrentPort. Skipping."
        return $null
    }

    Write-Log "Merged $lineCount IP lines for port $CurrentPort scope $ScopeName into $selectedIpPath. previous added: $previousAdded. cf-bestip added: $cfBestIpAdded. vps789 CT added: $vps789Added."
    return [pscustomobject]@{
        Port = $CurrentPort
        Scope = $ScopeName
        SelectedIpPath = $selectedIpPath
        MapPath = $selectedIpCityMapPath
        CsvPath = $portCsvPath
        StdoutPath = Join-Path $WorkDir "cfst-$CurrentPort-$safeScopeName-stdout.log"
        StderrPath = Join-Path $WorkDir "cfst-$CurrentPort-$safeScopeName-stderr.log"
        StdinPath = Join-Path $WorkDir "cfst-$CurrentPort-$safeScopeName-stdin.txt"
    }
}

function Start-CfstProcesses {
    param([object[]]$WorkItems)

    if (-not (Test-Path -LiteralPath $CfstPath)) {
        throw "cfst executable not found: $CfstPath"
    }

    $running = New-Object System.Collections.Generic.List[object]
    $completed = New-Object System.Collections.Generic.List[object]
    foreach ($item in $WorkItems) {
        while ($running.Count -ge $MaxParallelCfst) {
        $finished = @($running.ToArray() | Where-Object { $_.Process.HasExited })
            foreach ($finishedItem in $finished) {
                $completed.Add($finishedItem) | Out-Null
                [void]$running.Remove($finishedItem)
            }
            if ($running.Count -ge $MaxParallelCfst) {
                Start-Sleep -Seconds 2
            }
        }

        foreach ($path in @($item.StdoutPath, $item.StderrPath, $item.StdinPath)) {
            if (Test-Path -LiteralPath $path) {
                Remove-Item -LiteralPath $path -Force
            }
        }
        Set-Content -LiteralPath $item.StdinPath -Value "" -Encoding ASCII

        $cfstArgs = @(
            "-f", $item.SelectedIpPath,
            "-o", $item.CsvPath,
            "-n", ([string]$CfstThreads),
            "-t", ([string]$CfstLatencyTestCount),
            "-dn", ([string]$CfstDownloadTestCount),
            "-dt", ([string]$CfstDownloadTestTime),
            "-tl", ([string]$MaxLatencyMs),
            "-tlr", ($CfstLossRateLimit.ToString("0.##", [System.Globalization.CultureInfo]::InvariantCulture)),
            "-p", "0"
        )
        if ($item.Port -ne 443) {
            $cfstArgs += @("-tp", ([string]$item.Port))
        }
        if (-not [string]::IsNullOrWhiteSpace($DownloadTestUrl)) {
            $cfstArgs += @("-url", $DownloadTestUrl)
        }
        if ($MinSpeedMbps -gt 0) {
            $cfstArgs += @("-sl", $MinSpeedMbps.ToString("0.##", [System.Globalization.CultureInfo]::InvariantCulture))
        }
        if ($CfstDebug) {
            $cfstArgs += "-debug"
        }

        $argumentText = Join-ProcessArguments -Arguments $cfstArgs
        Write-Log "Starting cfst on port $($item.Port) scope $($item.Scope): $CfstPath $argumentText"
        $proxyEnvNames = @("HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "NO_PROXY", "http_proxy", "https_proxy", "all_proxy", "no_proxy")
        $savedProxyEnv = @{}
        if (-not $UseProxyForCfst) {
            foreach ($envName in $proxyEnvNames) {
                $envItem = Get-Item -LiteralPath "Env:$envName" -ErrorAction SilentlyContinue
                if ($null -ne $envItem) {
                    $savedProxyEnv[$envName] = $envItem.Value
                    Remove-Item -LiteralPath "Env:$envName" -ErrorAction SilentlyContinue
                }
            }
        }

        try {
            $process = Start-Process `
                -FilePath $CfstPath `
                -ArgumentList $argumentText `
                -RedirectStandardInput $item.StdinPath `
                -RedirectStandardOutput $item.StdoutPath `
                -RedirectStandardError $item.StderrPath `
                -NoNewWindow `
                -PassThru
        }
        finally {
            if (-not $UseProxyForCfst) {
                foreach ($envName in $proxyEnvNames) {
                    Remove-Item -LiteralPath "Env:$envName" -ErrorAction SilentlyContinue
                }
                foreach ($entry in $savedProxyEnv.GetEnumerator()) {
                    Set-Item -LiteralPath "Env:$($entry.Key)" -Value $entry.Value
                }
            }
        }

        $running.Add([pscustomobject]@{ Item = $item; Process = $process }) | Out-Null
    }

    foreach ($remaining in $running.ToArray()) {
        $completed.Add($remaining) | Out-Null
    }

    return $completed.ToArray()
}

function Wait-CfstProcesses {
    param([object[]]$Running)

    $failed = New-Object System.Collections.Generic.List[string]
    foreach ($entry in $Running) {
        $process = $entry.Process
        $item = $entry.Item
        $process.WaitForExit()

        if (Test-Path -LiteralPath $item.StdoutPath) {
            Get-Content -LiteralPath $item.StdoutPath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object {
                Write-Log "cfst[$($item.Port)]: $_"
            }
        }
        if (Test-Path -LiteralPath $item.StderrPath) {
            Get-Content -LiteralPath $item.StderrPath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object {
                Write-Log "cfst[$($item.Port)] stderr: $_"
            }
        }

        if ($null -ne $process.ExitCode -and $process.ExitCode -ne 0) {
            $failed.Add("port $($item.Port) exit code $($process.ExitCode)") | Out-Null
            continue
        }

        if (-not (Test-Path -LiteralPath $item.CsvPath)) {
            Write-Log "WARN: cfst completed but CSV was not created for port $($item.Port) scope $($item.Scope): $($item.CsvPath)"
        }
    }

    if ($failed.Count -gt 0) {
        throw "One or more cfst runs failed: $($failed -join '; ')"
    }
}

function Write-MergedFilteredCsv {
    param(
        [object[]]$WorkItems,
        [System.Collections.Generic.HashSet[string]]$PreviousNodeKeys
    )

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $cityHeaderName = [string]([char]0x57CE) + [string]([char]0x5E02)
    $portHeaderName = [string]([char]0x7AEF) + [string]([char]0x53E3)
    $ipHeaderName = "IP" + [string]([char]0x5730) + [string]([char]0x5740)
    $coloHeaderName = [string]([char]0x6570) + [string]([char]0x636E) + [string]([char]0x4E2D) + [string]([char]0x5FC3)
    $tlsHeaderName = "TLS"
    $sentHeaderName = [string]([char]0x5DF2) + [string]([char]0x53D1) + [string]([char]0x9001)
    $receivedHeaderName = [string]([char]0x5DF2) + [string]([char]0x63A5) + [string]([char]0x6536)
    $lossHeaderName = [string]([char]0x4E22) + [string]([char]0x5305) + [string]([char]0x7387)
    $latencyHeaderName = [string]([char]0x5E73) + [string]([char]0x5747) + [string]([char]0x5EF6) + [string]([char]0x8FDF)
    $speedHeaderName = [string]([char]0x4E0B) + [string]([char]0x8F7D) + [string]([char]0x901F) + [string]([char]0x5EA6) + "(MB/s)"

    $candidateRows = New-Object System.Collections.Generic.List[object]
    $removed = 0

    foreach ($item in $WorkItems) {
        if (-not (Test-Path -LiteralPath $item.CsvPath)) {
            Write-Log "WARN: Missing cfst CSV for port $($item.Port): $($item.CsvPath). Skipping."
            continue
        }

        $cityByIp = @{}
        $sourceByIp = @{}
        if (Test-Path -LiteralPath $item.MapPath) {
            $mapLines = [System.IO.File]::ReadAllLines($item.MapPath, $utf8NoBom)
            foreach ($mapLine in $mapLines) {
                if ([string]::IsNullOrWhiteSpace($mapLine)) {
                    continue
                }
                $parts = $mapLine -split ",", 3
                if ($parts.Count -ge 2) {
                    $mappedIp = $parts[0]
                    $mappedSource = if ($parts.Count -ge 3 -and -not [string]::IsNullOrWhiteSpace($parts[2])) { $parts[2] } else { "unknown" }
                    $shouldSet = -not $cityByIp.ContainsKey($mappedIp)
                    if (-not $shouldSet -and @("previous", "unknown") -contains $sourceByIp[$mappedIp] -and @("previous", "unknown") -notcontains $mappedSource) {
                        $shouldSet = $true
                    }
                    if ($shouldSet) {
                        $cityByIp[$mappedIp] = $parts[1]
                        $sourceByIp[$mappedIp] = $mappedSource
                    }
                }
            }
        }

        $lines = [System.IO.File]::ReadAllLines($item.CsvPath, $utf8NoBom)
        if ($lines.Count -le 1) {
            Write-Log "WARN: CSV has no data rows for port $($item.Port)."
            continue
        }

        for ($i = 1; $i -lt $lines.Count; $i++) {
            $line = $lines[$i]
            if ([string]::IsNullOrWhiteSpace($line)) {
                continue
            }

            $columns = $line -split ","
            if ($columns.Count -lt 6) {
                $removed++
                continue
            }

            $ip = $columns[0].Trim()
            $received = Convert-ToNumber $columns[2]
            $lossRate = Convert-ToNumber $columns[3]
            $latency = Convert-ToNumber $columns[4]
            $speed = Convert-ToNumber $columns[5]

            if ($null -eq $received -or $null -eq $lossRate -or $null -eq $latency -or $null -eq $speed) {
                $removed++
                continue
            }

            if ($received -lt $MinReceived -or $lossRate -ge 1 -or $latency -gt $MaxLatencyMs) {
                $removed++
                continue
            }
            $speedMbps = [math]::Round($speed * 8, 2)
            if ($speedMbps -lt $MinSpeedMbps) {
                $removed++
                continue
            }

            $city = ""
            if ($cityByIp.ContainsKey($ip)) {
                $city = $cityByIp[$ip]
            }
            $dataCenter = if ($columns.Count -gt 6) { $columns[6].Trim() } else { "" }
            if ($city -eq "VPS789CT") {
                if (-not [string]::IsNullOrWhiteSpace($dataCenter) -and $dataCenter -ne "N/A") {
                    $city = $dataCenter
                }
                else {
                    $city = "CT"
                }
            }
            $source = if ($sourceByIp.ContainsKey($ip)) { $sourceByIp[$ip] } else { "unknown" }

            $speedMbps = $speedMbps.ToString("0.00", [System.Globalization.CultureInfo]::InvariantCulture)
            $latencyText = [math]::Round($latency, 0).ToString("0", [System.Globalization.CultureInfo]::InvariantCulture)
            $remark = "$city [$($latencyText)ms $($speedMbps)Mbps]"
            $candidateRows.Add([pscustomobject]@{
                Ip = $ip
                Port = [string]$item.Port
                DataCenter = $dataCenter
                City = $remark
                Tls = "true"
                Sent = $columns[1].Trim()
                Received = $columns[2].Trim()
                Loss = $columns[3].Trim()
                Latency = $columns[4].Trim()
                Speed = $columns[5].Trim()
                CityKey = $city
                SpeedNumber = $speed
                LatencyNumber = $latency
                IsPrevious = $PreviousNodeKeys.Contains("$ip|$($item.Port)|$city")
                Source = $source
            })
        }
    }

    $dedupRows = @(
        $candidateRows |
            Group-Object @{ Expression = { "$($_.Ip)|$($_.Port)|$($_.CityKey)" } } |
            ForEach-Object {
                $_.Group | Sort-Object @{ Expression = "LatencyNumber"; Descending = $false }, @{ Expression = "SpeedNumber"; Descending = $true } | Select-Object -First 1
            }
    )

    $keptRows = @(
        $dedupRows |
            Group-Object CityKey |
            ForEach-Object {
                $sortedGroup = @($_.Group | Sort-Object @{ Expression = "LatencyNumber"; Descending = $false }, @{ Expression = "SpeedNumber"; Descending = $true })
                $maxPreviousKeep = [math]::Max(0, [math]::Floor($MaxPerCity * (1 - $RollingReplaceFraction)))
                $oldRows = @($sortedGroup | Where-Object { $_.IsPrevious } | Select-Object -First $maxPreviousKeep)
                $newRows = @($sortedGroup | Where-Object { -not $_.IsPrevious } | Select-Object -First ([math]::Max(0, $MaxPerCity - $oldRows.Count)))
                $selectedRows = @($oldRows + $newRows)
                if ($selectedRows.Count -lt $MaxPerCity) {
                    $selectedKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                    foreach ($selected in $selectedRows) {
                        [void]$selectedKeys.Add("$($selected.Ip)|$($selected.Port)|$($selected.CityKey)")
                    }
                    $fillRows = @(
                        $sortedGroup |
                            Where-Object { -not $selectedKeys.Contains("$($_.Ip)|$($_.Port)|$($_.CityKey)") } |
                            Select-Object -First ($MaxPerCity - $selectedRows.Count)
                    )
                    $selectedRows = @($selectedRows + $fillRows)
                }
                $selectedRows
            } |
            Sort-Object CityKey, @{ Expression = "LatencyNumber"; Descending = $false }, @{ Expression = "SpeedNumber"; Descending = $true }
    )

    if ($keptRows.Count -lt $candidateRows.Count) {
        $removed += ($candidateRows.Count - $keptRows.Count)
    }

    $kept = New-Object System.Collections.Generic.List[string]
    $kept.Add("$ipHeaderName,$portHeaderName,$coloHeaderName,$cityHeaderName,$tlsHeaderName,$sentHeaderName,$receivedHeaderName,$lossHeaderName,$latencyHeaderName,$speedHeaderName")
    $regionCounters = @{}
    foreach ($row in $keptRows) {
        $regionKey = if ([string]::IsNullOrWhiteSpace($row.CityKey)) { "UNK" } else { $row.CityKey }
        if (-not $regionCounters.ContainsKey($regionKey)) {
            $regionCounters[$regionKey] = 0
        }
        $regionCounters[$regionKey]++
        $regionNumber = $regionCounters[$regionKey].ToString("00", [System.Globalization.CultureInfo]::InvariantCulture)
        $sourceText = if ([string]::IsNullOrWhiteSpace($row.Source)) { "unknown" } else { $row.Source }
        $numberedCity = "$regionKey [$TestLocationName#$regionNumber $sourceText]"
        $kept.Add("$($row.Ip),$($row.Port),$($row.DataCenter),$numberedCity,$($row.Tls),$($row.Sent),$($row.Received),$($row.Loss),$($row.Latency),$($row.Speed)")
    }

    if ($kept.Count -le 1) {
        throw "Filtering removed all CSV rows. Check MaxLatencyMs=$MaxLatencyMs, MinReceived=$MinReceived, and MinSpeedMbps=$MinSpeedMbps. If cfst reports 0.00 MB/s, rerun with -CfstDebug."
    }

    [System.IO.File]::WriteAllLines($csvPath, $kept.ToArray(), $utf8NoBom)
    Write-Log "Merged and filtered CSV rows across ports. Kept $($kept.Count - 1), removed $removed. Top $MaxPerCity per country/group. Rules: received >= $MinReceived, loss < 1, latency <= $MaxLatencyMs ms, speed >= $MinSpeedMbps Mbps."
}

function Publish-ToGitHub {
    $token = Get-GitHubToken
    $encodedPath = ($TargetPath -split "/" | ForEach-Object { [uri]::EscapeDataString($_) }) -join "/"
    $uri = "https://api.github.com/repos/$Owner/$Repo/contents/$encodedPath"
    $headers = @{
        Authorization = "Bearer $token"
        Accept = "application/vnd.github+json"
        "X-GitHub-Api-Version" = "2022-11-28"
        "User-Agent" = "CFOptAutoPush"
    }

    Write-Log "Reading current GitHub file metadata: $Owner/$Repo/$TargetPath"
    $existingSha = $null
    try {
        $existing = Invoke-RestMethod -Method Get -Uri "$uri`?ref=$Branch" -Headers $headers
        $existingSha = $existing.sha
        Write-Log "GitHub file exists. Upload will update existing file."
    }
    catch {
        $statusCode = $null
        if ($_.Exception.Response) {
            $statusCode = [int]$_.Exception.Response.StatusCode
        }

        if ($statusCode -eq 404) {
            Write-Log "GitHub file was not found. Upload will create a new file."
        }
        else {
            throw
        }
    }

    $bytes = [System.IO.File]::ReadAllBytes($csvPath)
    $content = [Convert]::ToBase64String($bytes)
    $bodyMap = @{
        message = "Update $TargetPath"
        content = $content
        branch = $Branch
    }
    if (-not [string]::IsNullOrWhiteSpace($existingSha)) {
        $bodyMap.sha = $existingSha
    }
    $body = $bodyMap | ConvertTo-Json -Depth 5

    Write-Log "Uploading CSV to GitHub branch $Branch."
    Invoke-RestMethod -Method Put -Uri $uri -Headers $headers -Body $body -ContentType "application/json" | Out-Null
}

try {
    New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
    Write-Log "Starting CFOpt auto push."

    if (-not (Test-IntervalGate)) {
        exit 0
    }

    if (Test-Path -LiteralPath $extractDir) {
        Remove-Item -LiteralPath $extractDir -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $extractDir | Out-Null

    Update-ZipCache

    Write-Log "Extracting $zipPath"
    Expand-Archive -LiteralPath $zipPath -DestinationPath $extractDir -Force

    $effectivePorts = @(Get-EffectivePorts)
    if ($effectivePorts.Count -eq 0) {
        throw "No ports configured."
    }
    Write-Log "Configured ports: $($effectivePorts -join ', ')"

    $previousCsvEntries = @(Get-PreviousCsvEntries)
    $previousNodeKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in $previousCsvEntries) {
        [void]$previousNodeKeys.Add("$($entry.Ip)|$($entry.Port)|$($entry.City)")
    }

    $vps789CtIps = @(Get-Vps789CtIps)
    $cfBestIpCandidates = @(Get-CfBestIpCandidates)
    $generatedWorkItems = foreach ($effectivePort in $effectivePorts) {
            New-PortWorkItem -CurrentPort $effectivePort -Vps789CtIps $vps789CtIps -CfBestIpCandidates $cfBestIpCandidates -PreviousCsvEntries $previousCsvEntries -SelectedCountries $Countries -ScopeName "all" -IncludeVps789Ct $true
            foreach ($focusCountry in @(Get-EffectiveFocusCountries)) {
                if ($Countries -contains $focusCountry) {
                    New-PortWorkItem -CurrentPort $effectivePort -Vps789CtIps @() -CfBestIpCandidates $cfBestIpCandidates -PreviousCsvEntries $previousCsvEntries -SelectedCountries @($focusCountry) -ScopeName "focus-$focusCountry" -IncludeVps789Ct $false
                }
            }
        }
    $workItems = @($generatedWorkItems | Where-Object { $null -ne $_ })
    if ($workItems.Count -eq 0) {
        throw "No usable port/country inputs were prepared."
    }

    if ($DryRun) {
        Write-Log "Dry run enabled. Skipping cfst execution and GitHub upload."
        foreach ($item in $workItems) {
            $dryRunArgs = @(
                "-f", $item.SelectedIpPath,
                "-o", $item.CsvPath,
                "-n", ([string]$CfstThreads),
                "-t", ([string]$CfstLatencyTestCount),
                "-dn", ([string]$CfstDownloadTestCount),
                "-dt", ([string]$CfstDownloadTestTime),
                "-tl", ([string]$MaxLatencyMs),
                "-tlr", ($CfstLossRateLimit.ToString("0.##", [System.Globalization.CultureInfo]::InvariantCulture)),
                "-p", "0"
            )
            if ($item.Port -ne 443) {
                $dryRunArgs += @("-tp", ([string]$item.Port))
            }
            if (-not [string]::IsNullOrWhiteSpace($DownloadTestUrl)) {
                $dryRunArgs += @("-url", $DownloadTestUrl)
            }
            if ($MinSpeedMbps -gt 0) {
                $dryRunArgs += @("-sl", $MinSpeedMbps.ToString("0.##", [System.Globalization.CultureInfo]::InvariantCulture))
            }
            if ($CfstDebug) {
                $dryRunArgs += "-debug"
            }
            Write-Log "Would run: `"$CfstPath`" $(Join-ProcessArguments -Arguments $dryRunArgs)"
        }
        exit 0
    }

    $running = @(Start-CfstProcesses -WorkItems $workItems)
    Wait-CfstProcesses -Running $running
    Write-MergedFilteredCsv -WorkItems $workItems -PreviousNodeKeys $previousNodeKeys

    if ($SkipUpload) {
        Write-Log "SkipUpload enabled. CSV generated but GitHub upload and success-state update were skipped."
        exit 0
    }

    Publish-ToGitHub

    (Get-Date).ToString("o") | Set-Content -LiteralPath $stateFile -Encoding ASCII
    Write-Log "Completed successfully. Uploaded $csvPath to $Owner/$Repo/$TargetPath."
}
catch {
    Write-Log "ERROR: $($_.Exception.Message)"
    Write-Log "ERROR_DETAIL: $($_.InvocationInfo.PositionMessage)"
    Write-Log "ERROR_STACK: $($_.ScriptStackTrace)"
    throw
}
