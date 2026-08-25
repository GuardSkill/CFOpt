param(
    [string]$DownloadUrl = "https://zip.cm.edu.kg/ip.zip",
    [string]$WorkDir = "H:\PyProjects\CFOptAutoPush",
    [string]$CfstPath = "H:\PyProjects\cfst_windows_amd64\cfst.exe",
    [string[]]$Countries = @("HK", "TW", "JP", "KR", "SG", "PH", "VN", "MY", "KZ", "MN", "IE", "US", "DE", "GB", "NL", "IT"),
    [int]$Port = 0,
    [string]$Ports = "443,2053,2083,2087,2096,8443",
    [string]$DownloadTestUrl = "https://cf.xiu2.xyz/url",
    [string]$Owner = "GuardSkill",
    [string]$Repo = "CFOpt",
    [string]$Branch = "main",
    [string]$TargetPath = "CloudflareSpeedTest_CD.csv",
    [int]$IntervalDays = 0,
    [int]$IntervalHours = 4,
    [int]$MaxLatencyMs = 420,
    [int]$MinReceived = 1,
    [double]$MinSpeedMbps = 0.03,
    [int]$MaxPerCity = 20,
    [int]$CfstThreads = 80,
    [int]$CfstLatencyTestCount = 2,
    [int]$CfstDownloadTestCount = 10,
    [int]$CfstDownloadTestTime = 4,
    [int]$FocusCfstDownloadTestCount = 10,
    [int]$FocusCfstDownloadTestTime = 4,
    [double]$CfstLossRateLimit = 0,
    [bool]$CfstEnforceSpeedLimit = $false,
    [int]$MaxParallelCfst = 1,
    [bool]$TcpPrecheckEnabled = $true,
    [int]$TcpPrecheckMinCandidates = 120,
    [int]$TcpPrecheckTimeoutMs = 800,
    [int]$TcpPrecheckThreads = 128,
    [int]$TcpPrecheckMaxCandidates = 30,
    [switch]$UseProxyForCfst,
    [string]$CountryMinSpeedMBPerSec = "JP=10,US=5,KR=3,HK=2,DE=5,GB=3,SG=5",
    [string]$FocusCountries = "SG,HK,TW,JP,KR,US,DE,GB",
    [string]$TestLocationName = "",
    [string]$CfBestIpBaseUrl = "https://zoroaaa.github.io/cf-bestip",
    [int]$CfBestIpPerCountryLimit = 400,
    [bool]$EnableIp164746 = $true,
    [string]$Ip164746Url = "https://ip.164746.xyz/ipTop10.html",
    [int]$Ip164746Limit = 10,
    [string]$Ip164746Country = "JP",
    [bool]$EnableHotPrefixMining = $true,
    [int]$HotPrefixSamples = 4,
    [int]$HotPrefixMaxPrefixesPerCountryPort = 4,
    [string]$HotPrefixCountryMultipliers = "DE=3,HK=2,KR=3",
    [bool]$EnableCtEntryPool = $true,
    [string]$CtEntryCidrs = "104.16.0.0/13,104.24.0.0/14,172.64.0.0/13,162.159.192.0/24,162.159.193.0/24,162.159.195.0/24,198.41.192.0/24,198.41.200.0/24,141.101.115.0/24",
    [int]$CtEntrySamplesPerCidr = 32,
    [ValidateSet('adaptive','hybrid','legacy')]
    [string]$CandidatePoolMode = 'adaptive',
    [int]$AdaptiveMinCandidatesPerWorkItem = 20,
    [bool]$EnableGslegeCloudflareIp = $true,
    [string]$GslegeRawBaseUrl = "https://raw.githubusercontent.com/gslege/CloudflareIP/main",
    [string]$GslegeCountries = "JP,SG,US,DE,NL",
    [int]$GslegePerCountryLimit = 20,
    [bool]$IpZipSampleEnabled = $true,
    [int]$IpZipSamplePercent = 40,
    [int]$IpZipCountryMinCandidates = 40,
    [int]$IpZipCountryMaxCandidates = 320,
    [string]$IpZipCountrySampleMultipliers = "KR=2,US=0.5",
    [double]$RollingReplaceFraction = 0.20,
    [double]$MinPublishRetentionRatio = 0.6,
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
    [switch]$DisableVps789Ct,
    [switch]$DisableProxyipBest,
    [string]$ProxyipBestSource = "https://zip.cm.edu.kg/all.txt",
    [string]$ProxyipBestTargetPath = "proxyip-best.txt",
    [string]$ProxyipBestCountries = "IE,AT,AU,KR,HK,TW,SG,JP,US,DE,GB",
    [int]$ProxyipBestLimit = 10,
    [string]$ProxyipBestCountryLimits = "HK=50",
    [double]$ProxyipBestTimeout = 0.75,
    [int]$ProxyipBestWorkers = 64,
    [string]$ProxyipBestScript = ""
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($TestLocationName)) {
    $TestLocationName = "CD"
}
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if ([string]::IsNullOrWhiteSpace($ProxyipBestScript)) {
    $ProxyipBestScript = Join-Path $repoRoot "scripts\generate_proxyip_best.py"
}

$zipPath = Join-Path $WorkDir "ip.zip"
$extractDir = Join-Path $WorkDir "extract"
$csvPath = Join-Path $WorkDir "CloudflareSpeedTest.csv"
$vps789CtCsvPath = Join-Path $WorkDir "VPS789_CF_CT_Candidates.csv"
$proxyipBestPath = Join-Path $WorkDir "proxyip-best.txt"
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

function Get-FocusExcludedCountries {
    $focusSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($country in @(Get-EffectiveFocusCountries)) {
        [void]$focusSet.Add($country)
    }

    return @(
        foreach ($country in $Countries) {
            $countryCode = $country.Trim().ToUpperInvariant()
            if (-not [string]::IsNullOrWhiteSpace($countryCode) -and -not $focusSet.Contains($countryCode)) {
                $countryCode
            }
        }
    )
}

function Get-SampledIpZipLines {
    param(
        [string[]]$Lines,
        [string]$Country
    )

    $rows = @(
        foreach ($line in $Lines) {
            $trimmed = $line.Trim()
            if (-not [string]::IsNullOrWhiteSpace($trimmed) -and -not $trimmed.StartsWith("#")) {
                $trimmed
            }
        }
    )

    $count = $rows.Count
    if ($count -eq 0 -or -not $IpZipSampleEnabled) {
        return $rows
    }

    $percent = $IpZipSamplePercent
    if ($percent -le 0 -or $percent -gt 100) {
        $percent = 100
    }

    $multiplier = Get-IpZipCountrySampleMultiplier -Country $Country
    $percent = [Math]::Min(100, $percent * $multiplier)
    $minCount = [Math]::Max(0, [int][Math]::Floor($IpZipCountryMinCandidates * $multiplier))
    $maxCount = [int][Math]::Floor($IpZipCountryMaxCandidates * $multiplier)
    $target = [int][Math]::Ceiling($count * $percent / 100.0)
    if ($target -lt $minCount) {
        $target = $minCount
    }
    if ($maxCount -gt 0 -and $target -gt $maxCount) {
        $target = $maxCount
    }
    if ($target -gt $count) {
        $target = $count
    }
    if ($target -ge $count) {
        return $rows
    }

    $sampled = New-Object System.Collections.Generic.List[string]
    $picked = [System.Collections.Generic.HashSet[int]]::new()
    $step = $count / [double]$target
    for ($i = 1; $i -le $target; $i++) {
        $index = [int][Math]::Floor(($i - 1) * $step)
        if ($index -ge $count) {
            $index = $count - 1
        }
        if ($picked.Add($index)) {
            $sampled.Add($rows[$index]) | Out-Null
        }
    }

    return $sampled.ToArray()
}

function Get-IpZipCountrySampleMultiplier {
    param([string]$Country)

    foreach ($item in @($IpZipCountrySampleMultipliers -split '[,\s]+')) {
        if ([string]::IsNullOrWhiteSpace($item) -or -not $item.Contains("=")) {
            continue
        }
        $parts = $item.Split("=", 2)
        $key = $parts[0].Trim()
        $value = 0.0
        if ($key.Equals($Country, [System.StringComparison]::OrdinalIgnoreCase) -and [double]::TryParse($parts[1].Trim(), [ref]$value) -and $value -gt 0) {
            return $value
        }
    }

    return 1.0
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
    if ($IntervalDays -gt 0) {
        $IntervalHours = $IntervalDays * 24
    }
    $nextRun = $lastRun.AddHours($IntervalHours)

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

function ConvertFrom-CountryMinSpeedMap {
    param(
        [string]$Value,
        [string[]]$AllowedCountries
    )

    $floors = [System.Collections.Generic.Dictionary[string, double]]::new([System.StringComparer]::OrdinalIgnoreCase)
    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $floors
    }

    $allowed = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($country in $AllowedCountries) {
        $countryCode = $country.Trim().ToUpperInvariant()
        if (-not [string]::IsNullOrWhiteSpace($countryCode)) {
            [void]$allowed.Add($countryCode)
        }
    }

    foreach ($rawPair in $Value.Split(',')) {
        $pair = $rawPair.Trim()
        $parts = $pair -split '=', 3
        if ([string]::IsNullOrWhiteSpace($pair) -or $parts.Count -ne 2) {
            throw "Invalid country speed floor entry: $rawPair"
        }

        $countryCode = $parts[0].Trim().ToUpperInvariant()
        $speedText = $parts[1].Trim()
        if ($countryCode -notmatch '^[A-Z]{2}$' -or -not $allowed.Contains($countryCode)) {
            throw "Invalid country speed floor country: $countryCode"
        }

        $speed = 0.0
        if ($speedText -notmatch '^(?:[0-9]+(?:\.[0-9]+)?|\.[0-9]+)$' -or -not [double]::TryParse($speedText, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$speed) -or [double]::IsNaN($speed) -or [double]::IsInfinity($speed)) {
            throw "Invalid country speed floor value: $speedText"
        }
        if ($floors.ContainsKey($countryCode)) {
            throw "Duplicate country speed floor: $countryCode"
        }
        $floors.Add($countryCode, $speed)
    }

    return $floors
}

function Get-CityKeyFromRemark {
    param([string]$Remark)

    if ([string]::IsNullOrWhiteSpace($Remark)) {
        return ""
    }

    $trimmed = $Remark.Trim()
    if ($trimmed -match '\b([A-Za-z]{2})\b') {
        return $Matches[1].ToUpperInvariant()
    }

    return ""
}

function Get-CountryFromColo {
    param([string]$Colo)
    $code = $Colo.Trim().ToUpperInvariant()
    $map = @{
        NRT='JP'; KIX='JP'; FUK='JP'; OKA='JP'
        SIN='SG'; HKG='HK'; ICN='KR'; TPE='TW'; KHH='TW'
        MNL='PH'; CEB='PH'; SGN='VN'; HAN='VN'; KUL='MY'; PEN='MY'
        ALA='KZ'; NQZ='KZ'; ULN='MN'; DUB='IE'
        FRA='DE'; TXL='DE'; BER='DE'; MUC='DE'; DUS='DE'; HAM='DE'
        LHR='GB'; MAN='GB'; EDI='GB'; AMS='NL'; MXP='IT'; FCO='IT'
        LAX='US'; SJC='US'; SEA='US'; PDX='US'; PHX='US'; DEN='US'; DFW='US'; ORD='US'; ATL='US'; MIA='US'; IAD='US'; EWR='US'; JFK='US'; BOS='US'
    }
    if ($map.ContainsKey($code)) { return $map[$code] }
    return ''
}

function Get-CountryFlag {
    param([string]$Code)

    switch ($Code.ToUpperInvariant()) {
        "AT" { return "🇦🇹" }
        "AU" { return "🇦🇺" }
        "CT" { return "🇨🇳" }
        "DE" { return "🇩🇪" }
        "GB" { return "🇬🇧" }
        "HK" { return "🇭🇰" }
        "IE" { return "🇮🇪" }
        "IT" { return "🇮🇹" }
        "JP" { return "🇯🇵" }
        "KR" { return "🇰🇷" }
        "KZ" { return "🇰🇿" }
        "MN" { return "🇲🇳" }
        "MY" { return "🇲🇾" }
        "NL" { return "🇳🇱" }
        "PH" { return "🇵🇭" }
        "SG" { return "🇸🇬" }
        "US" { return "🇺🇸" }
        "VN" { return "🇻🇳" }
        default { return "" }
    }
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
            $dataCenter = if ($columns.Count -gt 2) { $columns[2].Trim() } else { '' }
            $coloCountry = Get-CountryFromColo -Colo $dataCenter
            if (-not [string]::IsNullOrWhiteSpace($coloCountry)) { $cityKey = $coloCountry }
            $portValue = 0
            if ($ip -match '^(?:\d{1,3}\.){3}\d{1,3}$' -and [int]::TryParse($portText, [ref]$portValue) -and -not [string]::IsNullOrWhiteSpace($cityKey)) {
                $entries.Add([pscustomobject]@{
                    Ip = $ip
                    Port = $portValue
                    City = $cityKey
                    DataCenter = $dataCenter
                    Tls = if ($columns.Count -gt 4) { $columns[4].Trim() } else { 'true' }
                    Sent = if ($columns.Count -gt 5) { $columns[5].Trim() } else { '2' }
                    Received = if ($columns.Count -gt 6) { $columns[6].Trim() } else { '2' }
                    Loss = if ($columns.Count -gt 7) { $columns[7].Trim() } else { '0.00' }
                    Latency = if ($columns.Count -gt 8) { $columns[8].Trim() } else { '999' }
                    Speed = if ($columns.Count -gt 9) { $columns[9].Trim() } else { '0' }
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

    $effectivePortSet = [System.Collections.Generic.HashSet[int]]::new()
    foreach ($portValue in @(Get-EffectivePorts)) {
        [void]$effectivePortSet.Add([int]$portValue)
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
            $filterCountry = $false
            try {
                $text = (Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 30).Content
            }
            catch {
                $allUrl = "{0}/ip_all.txt" -f $CfBestIpBaseUrl.TrimEnd("/")
                Write-Log "cf-bestip has no per-country file for $countryCode; falling back to $allUrl."
                $text = (Invoke-WebRequest -Uri $allUrl -UseBasicParsing -TimeoutSec 30).Content
                $filterCountry = $true
            }
            $countsByPort = @{}
            foreach ($line in ($text -split "`r?`n")) {
                $trimmed = $line.Trim()
                if ($trimmed -match '^(?<ip>(?:\d{1,3}\.){3}\d{1,3}):(?<port>\d+)#(?<region>[A-Za-z0-9_-]+)') {
                    if ($filterCountry -and $Matches.region.ToUpperInvariant() -ne $countryCode) {
                        continue
                    }
                    $candidatePort = [int]$Matches.port
                    if (-not $effectivePortSet.Contains($candidatePort)) {
                        continue
                    }
                    if (-not $countsByPort.ContainsKey($candidatePort)) {
                        $countsByPort[$candidatePort] = 0
                    }
                    if ($countsByPort[$candidatePort] -ge $CfBestIpPerCountryLimit) {
                        continue
                    }
                    $candidates.Add([pscustomobject]@{
                        Ip = $Matches.ip
                        Port = $candidatePort
                        City = $countryCode
                    }) | Out-Null
                    $countsByPort[$candidatePort]++
                }
            }
            $countForCountry = 0
            foreach ($value in $countsByPort.Values) {
                $countForCountry += [int]$value
            }
            Write-Log "Fetched $countForCountry cf-bestip candidates for $countryCode across configured ports."
        }
        catch {
            Write-Log "WARN: Failed to fetch cf-bestip candidates for $countryCode`: $($_.Exception.Message)"
        }
    }

    Write-Log "Fetched $($candidates.Count) cf-bestip candidates in total."
    return $candidates.ToArray()
}

function Test-StrictIpv4 {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value) -or $Value -notmatch '^(?:\d{1,3}\.){3}\d{1,3}$') {
        return $false
    }
    foreach ($part in $Value.Split('.')) {
        $octet = 0
        if (-not [int]::TryParse($part, [ref]$octet) -or $octet -lt 0 -or $octet -gt 255) {
            return $false
        }
    }
    return $true
}

function ConvertFrom-Ip164746Text {
    param(
        [string]$Text,
        [int]$Limit = $Ip164746Limit,
        [string]$Country = $Ip164746Country
    )

    if ($Limit -le 0) {
        return @()
    }
    $countryCode = $Country.Trim().ToUpperInvariant()
    if ($countryCode -notmatch '^[A-Z]{2}$') {
        throw "Invalid ip.164746.xyz country code: $Country"
    }
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $candidates = New-Object System.Collections.Generic.List[object]
    foreach ($token in @($Text -split '[,;\s]+')) {
        $ip = $token.Trim()
        if (-not (Test-StrictIpv4 -Value $ip) -or -not $seen.Add($ip)) {
            continue
        }
        $candidates.Add([pscustomobject]@{ Ip = $ip; Port = 443; City = $countryCode }) | Out-Null
        if ($candidates.Count -ge $Limit) {
            break
        }
    }
    return $candidates.ToArray()
}

function Get-Ip164746Candidates {
    if (-not $EnableIp164746) {
        Write-Log "ip.164746.xyz candidate source disabled."
        return @()
    }
    try {
        Write-Log "Fetching ip.164746.xyz candidates: $Ip164746Url"
        $text = (Invoke-WebRequest -Uri $Ip164746Url -UseBasicParsing -TimeoutSec 30).Content
        $candidates = @(ConvertFrom-Ip164746Text -Text $text -Limit $Ip164746Limit -Country $Ip164746Country)
        Write-Log "Fetched $($candidates.Count) ip.164746.xyz candidates for $($Ip164746Country.Trim().ToUpperInvariant()) on port 443."
        return $candidates
    }
    catch {
        Write-Log "WARN: Failed to fetch ip.164746.xyz candidates: $($_.Exception.Message)"
        return @()
    }
}

function ConvertFrom-GslegeCountryText {
    param([string]$Text, [string]$Country, [int]$Limit = 20)
    $result = [System.Collections.Generic.List[object]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($line in @($Text -split "`r?`n")) {
        if ($line -notmatch '^\s*((?:\d{1,3}\.){3}\d{1,3})') { continue }
        $ip = $Matches[1]
        if ((Test-StrictIpv4 -Value $ip) -and $seen.Add($ip)) {
            $result.Add([pscustomobject]@{ Ip = $ip; Port = 443; City = $Country.Trim().ToUpperInvariant() }) | Out-Null
            if ($result.Count -ge [math]::Max(1, $Limit)) { break }
        }
    }
    return $result.ToArray()
}

function Get-GslegeCloudflareIpCandidates {
    if (-not $EnableGslegeCloudflareIp) {
        Write-Log "gslege/CloudflareIP candidate source disabled."
        return @()
    }
    $result = [System.Collections.Generic.List[object]]::new()
    foreach ($country in @($GslegeCountries -split '[,\s]+' | Where-Object { $_ })) {
        $code = $country.Trim().ToUpperInvariant()
        try {
            $url = "$($GslegeRawBaseUrl.TrimEnd('/'))/$code.txt"
            $text = (Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 20).Content
            foreach ($candidate in @(ConvertFrom-GslegeCountryText -Text $text -Country $code -Limit $GslegePerCountryLimit)) {
                $result.Add($candidate) | Out-Null
            }
        }
        catch { Write-Log "WARN: Failed to fetch gslege/CloudflareIP $code candidates: $($_.Exception.Message)" }
    }
    Write-Log "Fetched $($result.Count) gslege/CloudflareIP candidates across $GslegeCountries on port 443."
    return $result.ToArray()
}

function Get-HotPrefixMiningCandidates {
    param([object[]]$SeedCandidates = @())
    if (-not $EnableHotPrefixMining) { return @() }
    $prefixesByPool = @{}
    foreach ($seed in @($SeedCandidates)) {
        $ip = [string]$seed.Ip
        $city = ([string]$seed.City).Trim().ToUpperInvariant()
        $seedPort = if ($null -ne $seed.Port) { [int]$seed.Port } else { 443 }
        if (-not (Test-StrictIpv4 -Value $ip) -or [string]::IsNullOrWhiteSpace($city)) { continue }
        $poolKey = "$city|$seedPort"
        if (-not $prefixesByPool.ContainsKey($poolKey)) { $prefixesByPool[$poolKey] = [System.Collections.Generic.List[string]]::new() }
        $prefix = $ip -replace '\d+$', ''
        $multiplier = 1
        foreach ($entry in @($HotPrefixCountryMultipliers -split '[,\s]+' | Where-Object { $_ })) {
            if ($entry -match '^([A-Za-z]{2})=(\d+)$' -and $Matches[1].ToUpperInvariant() -eq $city) { $multiplier = [math]::Max(1,[int]$Matches[2]); break }
        }
        if (-not $prefixesByPool[$poolKey].Contains($prefix) -and $prefixesByPool[$poolKey].Count -lt ([math]::Max(1, $HotPrefixMaxPrefixesPerCountryPort) * $multiplier)) {
            $prefixesByPool[$poolKey].Add($prefix)
        }
    }
    $result = [System.Collections.Generic.List[object]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $count = [math]::Min(254, [math]::Max(1, $HotPrefixSamples))
    $rotation = (Get-Date).DayOfYear % 254
    foreach ($poolKey in @($prefixesByPool.Keys | Sort-Object)) {
        $poolParts = $poolKey -split '\|'
        $poolMultiplier = 1
        foreach ($entry in @($HotPrefixCountryMultipliers -split '[,\s]+' | Where-Object { $_ })) {
            if ($entry -match '^([A-Za-z]{2})=(\d+)$' -and $Matches[1].ToUpperInvariant() -eq $poolParts[0]) { $poolMultiplier = [math]::Max(1,[int]$Matches[2]); break }
        }
        foreach ($prefix in $prefixesByPool[$poolKey]) {
            $poolCount = [math]::Min(254, $count * $poolMultiplier)
            for ($index = 0; $index -lt $poolCount; $index++) {
                $hostPart = (($rotation + [math]::Floor($index * 254 / $poolCount)) % 254) + 1
                $ip = "$prefix$hostPart"
                $uniqueKey = "$ip|$($poolParts[1])|$($poolParts[0])"
                if ($seen.Add($uniqueKey)) { $result.Add([pscustomobject]@{ Ip = $ip; Port = [int]$poolParts[1]; City = $poolParts[0] }) | Out-Null }
            }
        }
    }
    return $result.ToArray()
}

function ConvertTo-Ipv4UInt32 {
    param([string]$Ip)
    if (-not (Test-StrictIpv4 -Value $Ip)) { throw "Invalid IPv4 address: $Ip" }
    $parts = @($Ip -split '\.' | ForEach-Object { [uint64][int]$_ })
    return [uint64](($parts[0] * 16777216) + ($parts[1] * 65536) + ($parts[2] * 256) + $parts[3])
}

function ConvertFrom-Ipv4UInt32 {
    param([uint64]$Value)
    return "$(($Value -shr 24) -band 255).$(($Value -shr 16) -band 255).$(($Value -shr 8) -band 255).$($Value -band 255)"
}

function Get-CtEntryPoolCandidates {
    param([int[]]$SelectedPorts)
    if (-not $EnableCtEntryPool) { return @() }
    $ips = [System.Collections.Generic.List[string]]::new()
    $seenIps = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $sampleCount = [math]::Max(1, $CtEntrySamplesPerCidr)
    $rotation = (Get-Date).DayOfYear
    foreach ($cidr in @($CtEntryCidrs -split '[,\s]+' | Where-Object { $_ })) {
        if ($cidr -notmatch '^((?:\d{1,3}\.){3}\d{1,3})/(\d|[12]\d|3[0-2])$') { throw "Invalid CT entry CIDR: $cidr" }
        $base = ConvertTo-Ipv4UInt32 -Ip $Matches[1]
        $prefixLength = [int]$Matches[2]
        $size = [uint64][math]::Pow(2, 32 - $prefixLength)
        $network = [uint64]([math]::Floor($base / $size) * $size)
        $usable = if ($size -gt 2) { $size - 2 } else { $size }
        for ($index = 0; $index -lt $sampleCount; $index++) {
            $offset = if ($size -gt 2) { 1 + (($rotation + [uint64][math]::Floor($index * $usable / $sampleCount)) % $usable) } else { ($rotation + $index) % $size }
            $ip = ConvertFrom-Ipv4UInt32 -Value ($network + $offset)
            if ($seenIps.Add($ip)) { $ips.Add($ip) }
        }
    }
    $result = [System.Collections.Generic.List[object]]::new()
    foreach ($portValue in $SelectedPorts) {
        foreach ($ip in $ips) { $result.Add([pscustomobject]@{ Ip = $ip; Port = $portValue; City = 'CT-SEED' }) | Out-Null }
    }
    return $result.ToArray()
}

function New-PortWorkItem {
    param(
        [int]$CurrentPort,
        [object[]]$Vps789CtIps,
        [object[]]$CfBestIpCandidates,
        [object[]]$Ip164746Candidates = @(),
        [object[]]$GslegeCandidates = @(),
        [object[]]$HotPrefixMiningCandidates = @(),
        [object[]]$CtEntryPoolCandidates = @(),
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
    $ipZipAdded = 0
    function Add-IpZipCandidates {
        foreach ($file in $selectedFiles) {
            $city = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
            $sampledLines = @(Get-SampledIpZipLines -Lines @(Get-Content -LiteralPath $file.FullName) -Country $city)
            foreach ($ipLine in $sampledLines) {
                if ($seenIps.Add($ipLine)) {
                    Add-Content -LiteralPath $selectedIpPath -Value $ipLine -Encoding ASCII
                    Add-Content -LiteralPath $selectedIpCityMapPath -Value "$ipLine,$city,ip.zip" -Encoding ASCII
                    $script:__cfoptIpZipAdded++
                }
            }
        }
    }
    $script:__cfoptIpZipAdded = 0
    if ($CandidatePoolMode -in @('legacy','hybrid')) { Add-IpZipCandidates }

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
            $previousAdded++
        }
        Add-Content -LiteralPath $selectedIpCityMapPath -Value "$ip,$($entry.City),previous" -Encoding ASCII
    }

    $cfBestIpAdded = 0
    foreach ($candidate in $(if ($CandidatePoolMode -ne 'legacy') { @($CfBestIpCandidates) } else { @() })) {
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

    $ip164746Added = 0
    foreach ($candidate in $(if ($CandidatePoolMode -ne 'legacy') { @($Ip164746Candidates) } else { @() })) {
        if ($candidate.Port -ne $CurrentPort -or -not $selectedCountrySet.Contains([string]$candidate.City)) {
            continue
        }
        $ip = [string]$candidate.Ip
        if (-not (Test-StrictIpv4 -Value $ip)) {
            continue
        }
        if ($seenIps.Add($ip)) {
            Add-Content -LiteralPath $selectedIpPath -Value $ip -Encoding ASCII
            $ip164746Added++
        }
        Add-Content -LiteralPath $selectedIpCityMapPath -Value "$ip,$($candidate.City),ip164746" -Encoding ASCII
    }

    $gslegeAdded = 0
    foreach ($candidate in $(if ($CandidatePoolMode -ne 'legacy') { @($GslegeCandidates) } else { @() })) {
        if ($candidate.Port -ne $CurrentPort -or -not $selectedCountrySet.Contains([string]$candidate.City)) { continue }
        $ip = [string]$candidate.Ip
        if (-not (Test-StrictIpv4 -Value $ip)) { continue }
        if ($seenIps.Add($ip)) {
            Add-Content -LiteralPath $selectedIpPath -Value $ip -Encoding ASCII
            $gslegeAdded++
        }
        Add-Content -LiteralPath $selectedIpCityMapPath -Value "$ip,$($candidate.City),gslege" -Encoding ASCII
    }

    $hotMineAdded = 0
    foreach ($candidate in $(if ($CandidatePoolMode -ne 'legacy') { @($HotPrefixMiningCandidates) } else { @() })) {
        if ($candidate.Port -ne $CurrentPort -or -not $selectedCountrySet.Contains([string]$candidate.City)) { continue }
        $ip = [string]$candidate.Ip
        if (-not (Test-StrictIpv4 -Value $ip)) { continue }
        if ($seenIps.Add($ip)) { Add-Content -LiteralPath $selectedIpPath -Value $ip -Encoding ASCII; $hotMineAdded++ }
        Add-Content -LiteralPath $selectedIpCityMapPath -Value "$ip,$($candidate.City),hot-mine" -Encoding ASCII
    }

    $ctEntryAdded = 0
    if ($ScopeName -eq 'all') {
        foreach ($candidate in @($CtEntryPoolCandidates)) {
            if ($candidate.Port -ne $CurrentPort) { continue }
            $ip = [string]$candidate.Ip
            if (-not (Test-StrictIpv4 -Value $ip)) { continue }
            if ($seenIps.Add($ip)) { Add-Content -LiteralPath $selectedIpPath -Value $ip -Encoding ASCII; $ctEntryAdded++ }
            Add-Content -LiteralPath $selectedIpCityMapPath -Value "$ip,CT-SEED,ct-pool" -Encoding ASCII
        }
    }

    if ($CandidatePoolMode -eq 'adaptive' -and $seenIps.Count -lt [math]::Max(1, $AdaptiveMinCandidatesPerWorkItem)) {
        Write-Log "Adaptive pool has only $($seenIps.Count) candidates for port $CurrentPort scope $ScopeName; falling back to ip.zip."
        Add-IpZipCandidates
    }
    $ipZipAdded = $script:__cfoptIpZipAdded
    Remove-Variable -Name __cfoptIpZipAdded -Scope Script -ErrorAction SilentlyContinue

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

    Write-Log "Merged $lineCount IP lines for port $CurrentPort scope $ScopeName mode $CandidatePoolMode into $selectedIpPath. ip.zip added: $ipZipAdded. previous added: $previousAdded. cf-bestip added: $cfBestIpAdded. ip164746 added: $ip164746Added. gslege added: $gslegeAdded. hot-mine added: $hotMineAdded. ct-pool added: $ctEntryAdded. vps789 CT added: $vps789Added."
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

function New-PreviousPortWorkItem {
    param(
        [int]$CurrentPort,
        [object[]]$PreviousCsvEntries
    )

    $entries = @($PreviousCsvEntries | Where-Object { $_.Port -eq $CurrentPort })
    if ($entries.Count -eq 0) {
        return $null
    }

    $scopeName = "previous"
    $selectedIpPath = Join-Path $WorkDir "selected-ip-$CurrentPort-$scopeName.txt"
    $selectedIpCityMapPath = Join-Path $WorkDir "selected-ip-city-map-$CurrentPort-$scopeName.csv"
    $portCsvPath = Join-Path $WorkDir "CloudflareSpeedTest-$CurrentPort-$scopeName.csv"
    foreach ($path in @($selectedIpPath, $selectedIpCityMapPath, $portCsvPath)) {
        if (Test-Path -LiteralPath $path) {
            Remove-Item -LiteralPath $path -Force
        }
    }

    $seenIps = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in $entries) {
        $ip = ([string]$entry.Ip).Trim()
        $city = ([string]$entry.City).Trim()
        if ([string]::IsNullOrWhiteSpace($ip) -or [string]::IsNullOrWhiteSpace($city)) {
            continue
        }
        if ($seenIps.Add($ip)) {
            Add-Content -LiteralPath $selectedIpPath -Value $ip -Encoding ASCII
        }
        Add-Content -LiteralPath $selectedIpCityMapPath -Value "$ip,$city,previous" -Encoding ASCII
    }

    if ($seenIps.Count -eq 0) {
        return $null
    }

    Write-Log "Prepared $($seenIps.Count) previous nodes for full download retest on port $CurrentPort."
    return [pscustomobject]@{
        Port = $CurrentPort
        Scope = $scopeName
        SelectedIpPath = $selectedIpPath
        MapPath = $selectedIpCityMapPath
        CsvPath = $portCsvPath
        StdoutPath = Join-Path $WorkDir "cfst-$CurrentPort-$scopeName-stdout.log"
        StderrPath = Join-Path $WorkDir "cfst-$CurrentPort-$scopeName-stderr.log"
        StdinPath = Join-Path $WorkDir "cfst-$CurrentPort-$scopeName-stdin.txt"
        DownloadTestCount = $seenIps.Count
    }
}

function New-CtEntryPortWorkItem {
    param([int]$CurrentPort, [object[]]$Candidates)
    $entries = @($Candidates | Where-Object { $_.Port -eq $CurrentPort })
    if ($entries.Count -eq 0) { return $null }
    $scopeName = 'ct-entry'
    $selectedIpPath = Join-Path $WorkDir "selected-ip-$CurrentPort-$scopeName.txt"
    $mapPath = Join-Path $WorkDir "selected-ip-city-map-$CurrentPort-$scopeName.csv"
    $csvPathForPort = Join-Path $WorkDir "CloudflareSpeedTest-$CurrentPort-$scopeName.csv"
    foreach ($path in @($selectedIpPath,$mapPath,$csvPathForPort)) { if (Test-Path $path) { Remove-Item $path -Force } }
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in $entries) {
        $ip = [string]$entry.Ip
        if ((Test-StrictIpv4 $ip) -and $seen.Add($ip)) {
            Add-Content $selectedIpPath $ip -Encoding ASCII
            Add-Content $mapPath "$ip,CT-SEED,ct-pool" -Encoding ASCII
        }
    }
    if ($seen.Count -eq 0) { return $null }
    Write-Log "Prepared $($seen.Count) dedicated CT entry candidates for port $CurrentPort."
    return [pscustomobject]@{
        Port=$CurrentPort; Scope=$scopeName; SelectedIpPath=$selectedIpPath; MapPath=$mapPath; CsvPath=$csvPathForPort
        StdoutPath=Join-Path $WorkDir "cfst-$CurrentPort-$scopeName-stdout.log"
        StderrPath=Join-Path $WorkDir "cfst-$CurrentPort-$scopeName-stderr.log"
        StdinPath=Join-Path $WorkDir "cfst-$CurrentPort-$scopeName-stdin.txt"
    }
}

function Get-PositiveTcpPrecheckValue {
    param(
        [int]$Value,
        [int]$Fallback
    )

    if ($Value -gt 0) {
        return $Value
    }
    return $Fallback
}

function Select-TcpPrecheckCandidates {
    param(
        [object[]]$Successful,
        [int]$MaxCandidates
    )

    $groupCounts = @{}
    foreach ($candidate in @($Successful | Sort-Object ElapsedMs, Ordinal)) {
        $groupKey = "$($candidate.City)|$($candidate.Source)"
        $currentCount = if ($groupCounts.ContainsKey($groupKey)) { [int]$groupCounts[$groupKey] } else { 0 }
        if ($currentCount -lt $MaxCandidates) {
            $candidate.Ip
            $groupCounts[$groupKey] = $currentCount + 1
        }
    }
}

function Invoke-TcpPrecheck {
    param(
        [int]$Port,
        [string]$SelectedIpPath,
        [string]$MapPath
    )

    $inputLines = @(Get-Content -LiteralPath $SelectedIpPath | Where-Object {
        -not [string]::IsNullOrWhiteSpace($_) -and -not $_.TrimStart().StartsWith("#")
    })
    if (-not $TcpPrecheckEnabled -or $inputLines.Count -le $TcpPrecheckMinCandidates) {
        return
    }

    $effectiveTimeoutMs = Get-PositiveTcpPrecheckValue -Value $TcpPrecheckTimeoutMs -Fallback 800
    $effectiveThreads = Get-PositiveTcpPrecheckValue -Value $TcpPrecheckThreads -Fallback 128
    $effectiveMaxCandidates = Get-PositiveTcpPrecheckValue -Value $TcpPrecheckMaxCandidates -Fallback 30

    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $mapByIp = @{}
        foreach ($line in @(Get-Content -LiteralPath $MapPath)) {
            $fields = $line -split ',', 3
            if ($fields.Count -lt 3) {
                continue
            }
            $ip = $fields[0].Trim()
            $candidate = [pscustomobject]@{ Ip = $ip; City = $fields[1].Trim(); Source = $fields[2].Trim() }
            if (-not $mapByIp.ContainsKey($ip) -or $candidate.Source -eq "previous" -or ($mapByIp[$ip].Source -eq "unknown" -and $candidate.Source -ne "unknown")) {
                $mapByIp[$ip] = $candidate
            }
        }

        $previous = [System.Collections.Generic.List[string]]::new()
        $newCandidates = [System.Collections.Generic.List[object]]::new()
        $ordinal = 0
        foreach ($rawIp in $inputLines) {
            $ip = $rawIp.Trim()
            $mapped = $mapByIp[$ip]
            if ($null -ne $mapped -and $mapped.Source -eq "previous") {
                $previous.Add($ip)
            }
            else {
                if ($null -eq $mapped) {
                    $mapped = [pscustomobject]@{ Ip = $ip; City = "UNKNOWN"; Source = "unknown" }
                }
                $ordinal++
                $mapped | Add-Member -NotePropertyName Ordinal -NotePropertyValue $ordinal -Force
                $newCandidates.Add($mapped)
            }
        }

        $successful = [System.Collections.Generic.List[object]]::new()
        for ($offset = 0; $offset -lt $newCandidates.Count; $offset += $effectiveThreads) {
            $batch = [System.Collections.Generic.List[object]]::new()
            $lastIndex = [Math]::Min($offset + $effectiveThreads - 1, $newCandidates.Count - 1)
            foreach ($index in $offset..$lastIndex) {
                $candidate = $newCandidates[$index]
                $client = [System.Net.Sockets.TcpClient]::new()
                $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                try {
                    $asyncResult = $client.BeginConnect($candidate.Ip, $Port, $null, $null)
                    $batch.Add([pscustomobject]@{ Candidate = $candidate; Client = $client; AsyncResult = $asyncResult; Stopwatch = $stopwatch })
                }
                catch {
                    $client.Dispose()
                }
            }

            $pendingItems = [System.Collections.Generic.List[object]]::new()
            foreach ($pending in $batch) {
                $pendingItems.Add($pending)
            }
            while ($pendingItems.Count -gt 0) {
                $madeProgress = $false
                foreach ($pending in @($pendingItems.ToArray())) {
                    $completed = $pending.AsyncResult.IsCompleted
                    $expired = $pending.Stopwatch.ElapsedMilliseconds -ge $effectiveTimeoutMs
                    if (-not $completed -and -not $expired) {
                        continue
                    }
                    try {
                        if ($completed -and $pending.Client.Connected) {
                            $elapsedMs = [int]$pending.Stopwatch.ElapsedMilliseconds
                            $pending.Client.EndConnect($pending.AsyncResult)
                            $successful.Add([pscustomobject]@{
                                Ip = $pending.Candidate.Ip
                                City = $pending.Candidate.City
                                Source = $pending.Candidate.Source
                                ElapsedMs = $elapsedMs
                                Ordinal = $pending.Candidate.Ordinal
                            })
                        }
                    }
                    catch {
                    }
                    finally {
                        $pending.AsyncResult.AsyncWaitHandle.Close()
                        $pending.Client.Dispose()
                        [void]$pendingItems.Remove($pending)
                        $madeProgress = $true
                    }
                }
                if (-not $madeProgress) {
                    Start-Sleep -Milliseconds 1
                }
            }
        }

        $keptNew = @(Select-TcpPrecheckCandidates -Successful $successful.ToArray() -MaxCandidates $effectiveMaxCandidates)

        $result = [System.Collections.Generic.List[string]]::new()
        $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($ip in @($keptNew) + @($previous)) {
            if ($seen.Add($ip)) {
                $result.Add($ip)
            }
        }
        [System.IO.File]::WriteAllLines($SelectedIpPath, $result, [System.Text.Encoding]::ASCII)
        $timer.Stop()
        Write-Log "TCP precheck input=$($inputLines.Count) connected=$($successful.Count) kept_new=$($keptNew.Count) kept_previous=$($previous.Count) elapsed_ms=$($timer.ElapsedMilliseconds) port=$Port"
    }
    catch {
        Write-Log "WARN: TCP precheck failed; using original candidates."
    }
}

function Get-NonEmptyWorkItems {
    param([object[]]$WorkItems)

    foreach ($item in $WorkItems) {
        $hasCandidates = (Test-Path -LiteralPath $item.SelectedIpPath) -and @(
            Get-Content -LiteralPath $item.SelectedIpPath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        ).Count -gt 0
        if ($hasCandidates) {
            $item
        }
        else {
            Write-Log "WARN: Skipping empty TCP precheck work item port=$($item.Port) scope=$($item.Scope)."
        }
    }
}

function Get-CfstArguments {
    param([object]$Item)

    $downloadTestCount = $CfstDownloadTestCount
    $downloadTestTime = $CfstDownloadTestTime
    if ([string]$Item.Scope -like "focus-*") {
        $downloadTestCount = $FocusCfstDownloadTestCount
        $downloadTestTime = $FocusCfstDownloadTestTime
    }
    if ($Item.PSObject.Properties.Name -contains "DownloadTestCount" -and [int]$Item.DownloadTestCount -gt 0) {
        $downloadTestCount = [int]$Item.DownloadTestCount
    }

    $arguments = @(
        "-f", $Item.SelectedIpPath,
        "-o", $Item.CsvPath,
        "-n", ([string]$CfstThreads),
        "-t", ([string]$CfstLatencyTestCount),
        "-dn", ([string]$downloadTestCount),
        "-dt", ([string]$downloadTestTime),
        "-tl", ([string]$MaxLatencyMs),
        "-tlr", ($CfstLossRateLimit.ToString("0.##", [System.Globalization.CultureInfo]::InvariantCulture)),
        "-p", "0"
    )
    if ($Item.Port -ne 443) {
        $arguments += @("-tp", ([string]$Item.Port))
    }
    if (-not [string]::IsNullOrWhiteSpace($DownloadTestUrl)) {
        $arguments += @("-url", $DownloadTestUrl)
    }
    # CFST keeps extending the download queue when -sl is set until -dn rows
    # pass the floor. Apply the same floor after CSV merge instead so -dn is a
    # hard upper bound for each work item.
    if ($CfstEnforceSpeedLimit -and $MinSpeedMbps -gt 0) {
        $arguments += @("-sl", $MinSpeedMbps.ToString("0.##", [System.Globalization.CultureInfo]::InvariantCulture))
    }
    if ($CfstDebug) {
        $arguments += "-debug"
    }
    return $arguments
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

        $cfstArgs = @(Get-CfstArguments -Item $item)

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
        while (-not $process.HasExited) {
            Start-Sleep -Milliseconds 250
        }

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
    $countrySpeedStats = @{}
    foreach ($countryCode in $countryMinSpeedByCode.Keys) {
        $countrySpeedStats[$countryCode] = [pscustomobject]@{
            Evaluated = 0
            Protected = 0
            Removed = 0
            Passed = 0
        }
    }

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
            $speedText = $columns[5].Trim()
            $speed = 0.0

            if ($null -eq $received -or $null -eq $lossRate -or $null -eq $latency -or $speedText -notmatch '^(?:[0-9]+(?:\.[0-9]+)?|\.[0-9]+)$' -or -not [double]::TryParse($speedText, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$speed) -or [double]::IsNaN($speed) -or [double]::IsInfinity($speed)) {
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
            $coloCountry = Get-CountryFromColo -Colo $dataCenter
            if (-not [string]::IsNullOrWhiteSpace($coloCountry)) {
                $city = $coloCountry
            }
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
                IsProtected = $false
            })
        }
    }

    $dedupRows = @(
        $candidateRows |
            Group-Object @{ Expression = { "$($_.Ip)|$($_.CityKey)" } } |
            ForEach-Object {
                $_.Group | Sort-Object @{ Expression = "SpeedNumber"; Descending = $true }, @{ Expression = "LatencyNumber"; Descending = $false }, @{ Expression = "Port"; Descending = $false } | Select-Object -First 1
            }
    )

    if ($dedupRows.Count -lt $candidateRows.Count) {
        $removed += ($candidateRows.Count - $dedupRows.Count)
    }

    $floorFilteredRows = New-Object System.Collections.Generic.List[object]
    foreach ($cityGroup in @($dedupRows | Group-Object CityKey)) {
        $city = [string]$cityGroup.Name
        $rankedRows = @($cityGroup.Group | Sort-Object @{ Expression = "SpeedNumber"; Descending = $true }, @{ Expression = "LatencyNumber"; Descending = $false }, @{ Expression = "Ip"; Descending = $false })
        for ($rank = 0; $rank -lt $rankedRows.Count; $rank++) {
            $row = $rankedRows[$rank]
            if (-not $countryMinSpeedByCode.ContainsKey($city)) {
                $floorFilteredRows.Add($row)
                continue
            }

            $stats = $countrySpeedStats[$city]
            $stats.Evaluated++
            if ($row.SpeedNumber -lt $countryMinSpeedByCode[$city]) {
                $stats.Removed++
                $removed++
                continue
            }
            $stats.Passed++
            $floorFilteredRows.Add($row)
        }
    }

    foreach ($countryCode in @($countryMinSpeedByCode.Keys | Sort-Object)) {
        $floor = $countryMinSpeedByCode[$countryCode].ToString("R", [System.Globalization.CultureInfo]::InvariantCulture)
        $stats = $countrySpeedStats[$countryCode]
        Write-Log "Country speed floor $countryCode >= $floor MB/s: evaluated=$($stats.Evaluated) protected=$($stats.Protected) removed=$($stats.Removed) passed=$($stats.Passed)."
    }

    $keptRows = @(
        $floorFilteredRows |
            Group-Object CityKey |
            ForEach-Object {
                $sortedGroup = @($_.Group | Sort-Object @{ Expression = "LatencyNumber"; Descending = $false }, @{ Expression = "SpeedNumber"; Descending = $true })
                $protectedRows = @($_.Group | Where-Object { $_.IsProtected } | Sort-Object @{ Expression = "SpeedNumber"; Descending = $true }, @{ Expression = "LatencyNumber"; Descending = $false } | Select-Object -First $MaxPerCity)
                $protectedKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                foreach ($protected in $protectedRows) {
                    [void]$protectedKeys.Add("$($protected.Ip)|$($protected.CityKey)")
                }
                $remainingGroup = @($sortedGroup | Where-Object { -not $protectedKeys.Contains("$($_.Ip)|$($_.CityKey)") })
                $maxPreviousKeep = [math]::Max(0, [math]::Floor($MaxPerCity * (1 - $RollingReplaceFraction)))
                $oldRows = @($remainingGroup | Where-Object { $_.IsPrevious } | Select-Object -First ([math]::Min($maxPreviousKeep, [math]::Max(0, $MaxPerCity - $protectedRows.Count))))
                $newRows = @($remainingGroup | Where-Object { -not $_.IsPrevious } | Select-Object -First ([math]::Max(0, $MaxPerCity - $protectedRows.Count - $oldRows.Count)))
                $selectedRows = @($protectedRows + $oldRows + $newRows)
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

    if ($keptRows.Count -lt $floorFilteredRows.Count) {
        $removed += ($floorFilteredRows.Count - $keptRows.Count)
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
        $speedLabel = $row.SpeedNumber.ToString("0.0", [System.Globalization.CultureInfo]::InvariantCulture)
        $numberedCity = "$regionKey [$TestLocationName#$regionNumber $($speedLabel)MB/s]"
        $kept.Add("$($row.Ip),$($row.Port),$($row.DataCenter),$numberedCity,$($row.Tls),$($row.Sent),$($row.Received),$($row.Loss),$($row.Latency),$($row.Speed)")
    }

    if ($kept.Count -le 1) {
        throw "Filtering removed all CSV rows. Check MaxLatencyMs=$MaxLatencyMs, MinReceived=$MinReceived, and MinSpeedMbps=$MinSpeedMbps. If cfst reports 0.00 MB/s, rerun with -CfstDebug."
    }

    [System.IO.File]::WriteAllLines($csvPath, $kept.ToArray(), (New-Object System.Text.UTF8Encoding($true)))
    Write-Log "Merged and filtered CSV rows across ports. Kept $($kept.Count - 1), removed $removed. Top $MaxPerCity per country/group. Rules: received >= $MinReceived, loss < 1, latency <= $MaxLatencyMs ms, speed >= $MinSpeedMbps Mbps."
}

function Publish-FileToGitHub {
    param(
        [string]$LocalPath,
        [string]$UploadTargetPath
    )
    $token = Get-GitHubToken
    $encodedPath = ($UploadTargetPath -split "/" | ForEach-Object { [uri]::EscapeDataString($_) }) -join "/"
    $uri = "https://api.github.com/repos/$Owner/$Repo/contents/$encodedPath"
    $headers = @{
        Authorization = "Bearer $token"
        Accept = "application/vnd.github+json"
        "X-GitHub-Api-Version" = "2022-11-28"
        "User-Agent" = "CFOptAutoPush"
    }

    function Invoke-GitHubRestMethodWithRetry {
        param(
            [hashtable]$Parameters,
            [int]$MaxAttempts = 3,
            [int]$InitialDelaySeconds = 2
        )

        for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
            try {
                return Invoke-RestMethod @Parameters
            }
            catch {
                if ($attempt -ge $MaxAttempts) {
                    throw
                }

                Write-Log "WARN: GitHub request failed on attempt $attempt/$($MaxAttempts): $($_.Exception.Message). Retrying."
                Start-Sleep -Seconds ($InitialDelaySeconds * $attempt)
            }
        }
    }

    Write-Log "Reading current GitHub file metadata: $Owner/$Repo/$UploadTargetPath"
    $existingSha = $null
    try {
        $existing = Invoke-GitHubRestMethodWithRetry -Parameters @{
            Method = "Get"
            Uri = "$uri`?ref=$Branch"
            Headers = $headers
        }
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

    $bytes = [System.IO.File]::ReadAllBytes($LocalPath)
    $content = [Convert]::ToBase64String($bytes)
    $bodyMap = @{
        message = "Update $UploadTargetPath"
        content = $content
        branch = $Branch
    }
    if (-not [string]::IsNullOrWhiteSpace($existingSha)) {
        $bodyMap.sha = $existingSha
    }
    $body = $bodyMap | ConvertTo-Json -Depth 5

    Write-Log "Uploading $LocalPath to GitHub branch $Branch as $UploadTargetPath."
    Invoke-GitHubRestMethodWithRetry -Parameters @{
        Method = "Put"
        Uri = $uri
        Headers = $headers
        Body = $body
        ContentType = "application/json"
    } | Out-Null
}

function Assert-PublicationSafety {
    param([object[]]$PreviousCsvEntries)

    $previous = @($PreviousCsvEntries)
    if ($previous.Count -eq 0) {
        return
    }
    $currentLines = @(
        Get-Content -LiteralPath $csvPath |
            Select-Object -Skip 1 |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
    $minimumTotal = [math]::Ceiling($previous.Count * $MinPublishRetentionRatio)
    if ($currentLines.Count -lt $minimumTotal) {
        throw "Publication safety check blocked upload: current rows $($currentLines.Count) are below $minimumTotal required from $($previous.Count) previous rows."
    }

    $currentCounts = @{}
    foreach ($line in $currentLines) {
        $columns = $line -split ','
        if ($columns.Count -lt 4) { continue }
        $city = Get-CityKeyFromRemark -Remark $columns[3]
        if (-not [string]::IsNullOrWhiteSpace($city)) {
            $currentCounts[$city] = 1 + [int]($currentCounts[$city])
        }
    }
    foreach ($group in @($previous | Group-Object City)) {
        $city = [string]$group.Name
        $minimumCity = [math]::Ceiling($group.Count * $MinPublishRetentionRatio)
        $currentCity = if ($currentCounts.ContainsKey($city)) { [int]$currentCounts[$city] } else { 0 }
        if ($currentCity -lt $minimumCity) {
            throw "Publication safety check blocked upload: $city has $currentCity rows, below $minimumCity required from $($group.Count) previous rows."
        }
    }
    Write-Log "Publication safety check passed: current=$($currentLines.Count) previous=$($previous.Count) retention_ratio=$MinPublishRetentionRatio."
}

function Merge-RollingPublicationCsv {
    param([object[]]$PreviousCsvEntries)
    $previous = @($PreviousCsvEntries)
    if ($previous.Count -eq 0 -or -not (Test-Path $csvPath)) { return }
    $header = (Get-Content $csvPath -TotalCount 1)
    $currentRows = [System.Collections.Generic.List[object]]::new()
    foreach ($line in @(Get-Content $csvPath | Select-Object -Skip 1)) {
        $c = $line -split ','
        if ($c.Count -lt 10) { continue }
        $city = Get-CityKeyFromRemark $c[3]
        $currentRows.Add([pscustomobject]@{ Ip=$c[0];Port=[int]$c[1];DataCenter=$c[2];City=$city;Tls=$c[4];Sent=$c[5];Received=$c[6];Loss=$c[7];Latency=$c[8];Speed=$c[9];SpeedNumber=[double]$c[9];LatencyNumber=[double]$c[8];IsCurrent=$true }) | Out-Null
    }
    $oldRows = @($previous | ForEach-Object {
        $speedNumber=0.0; [void][double]::TryParse([string]$_.Speed,[System.Globalization.NumberStyles]::Float,[System.Globalization.CultureInfo]::InvariantCulture,[ref]$speedNumber)
        $latencyNumber=999.0; [void][double]::TryParse([string]$_.Latency,[System.Globalization.NumberStyles]::Float,[System.Globalization.CultureInfo]::InvariantCulture,[ref]$latencyNumber)
        [pscustomobject]@{ Ip=$_.Ip;Port=[int]$_.Port;DataCenter=$_.DataCenter;City=$_.City;Tls=$_.Tls;Sent=$_.Sent;Received=$_.Received;Loss=$_.Loss;Latency=$_.Latency;Speed=$_.Speed;SpeedNumber=$speedNumber;LatencyNumber=$latencyNumber;IsCurrent=$false }
    })
    $allCities = @($oldRows.City + $currentRows.City | Where-Object { $_ } | Sort-Object -Unique)
    $selected = [System.Collections.Generic.List[object]]::new()
    foreach ($city in $allCities) {
        $old = @($oldRows | Where-Object City -eq $city | Sort-Object @{Expression='SpeedNumber';Descending=$true},@{Expression='LatencyNumber';Descending=$false})
        $cur = @($currentRows | Where-Object City -eq $city | Sort-Object @{Expression='SpeedNumber';Descending=$true},@{Expression='LatencyNumber';Descending=$false})
        if ($old.Count -eq 0) {
            foreach ($row in @($cur | Select-Object -First $MaxPerCity)) { $selected.Add($row) | Out-Null }
            continue
        }
        $targetCount = [math]::Min($MaxPerCity,$old.Count)
        $replaceSlots = [math]::Max(1,[math]::Ceiling($targetCount * $RollingReplaceFraction))
        $keepCount = [math]::Max(0,$targetCount-$replaceSlots)
        $chosen = [System.Collections.Generic.List[object]]::new()
        $keys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($oldRow in @($old | Select-Object -First $keepCount)) {
            $fresh = $cur | Where-Object { $_.Ip -eq $oldRow.Ip -and $_.Port -eq $oldRow.Port } | Select-Object -First 1
            $row = if ($null -ne $fresh) { $fresh } else { $oldRow }
            if ($keys.Add("$($row.Ip)|$($row.Port)")) { $chosen.Add($row) | Out-Null }
        }
        $remaining = @($cur + $old | Sort-Object @{Expression='SpeedNumber';Descending=$true},@{Expression='LatencyNumber';Descending=$false})
        foreach ($row in $remaining) {
            if ($chosen.Count -ge $targetCount) { break }
            if ($keys.Add("$($row.Ip)|$($row.Port)")) { $chosen.Add($row) | Out-Null }
        }
        foreach ($row in $chosen) { $selected.Add($row) | Out-Null }
        Write-Log "Rolling merge ${city}: previous=$($old.Count) current=$($cur.Count) output=$($chosen.Count) replacement_slots=$replaceSlots."
    }
    $lines = [System.Collections.Generic.List[string]]::new(); $lines.Add($header) | Out-Null
    foreach ($group in @($selected | Group-Object City | Sort-Object Name)) {
        $index=0
        foreach ($row in @($group.Group | Sort-Object @{Expression='LatencyNumber';Descending=$false},@{Expression='SpeedNumber';Descending=$true})) {
            $index++; $label="$($row.City) [$TestLocationName#$($index.ToString('00')) $(([double]$row.Speed).ToString('0.0',[System.Globalization.CultureInfo]::InvariantCulture))MB/s]"
            $lines.Add("$($row.Ip),$($row.Port),$($row.DataCenter),$label,$($row.Tls),$($row.Sent),$($row.Received),$($row.Loss),$($row.Latency),$($row.Speed)") | Out-Null
        }
    }
    [System.IO.File]::WriteAllLines($csvPath,$lines,(New-Object System.Text.UTF8Encoding($true)))
    Write-Log "Rolling publication merge completed: previous=$($previous.Count) current=$($currentRows.Count) output=$($selected.Count)."
}

function Publish-ToGitHub {
    Publish-FileToGitHub -LocalPath $csvPath -UploadTargetPath $TargetPath
}

function New-ProxyipBestFile {
    if ($DisableProxyipBest) {
        Write-Log "proxyip-best generation disabled."
        return
    }
    if (-not (Test-Path -LiteralPath $ProxyipBestScript)) {
        Write-Log "WARN: proxyip-best script not found: $ProxyipBestScript"
        return
    }
    Write-Log "Generating proxyip best list from $ProxyipBestSource"
    & python $ProxyipBestScript --source $ProxyipBestSource --output $proxyipBestPath --countries $ProxyipBestCountries --limit $ProxyipBestLimit --country-limits $ProxyipBestCountryLimits --timeout $ProxyipBestTimeout --workers $ProxyipBestWorkers
    if ($LASTEXITCODE -ne 0) {
        Write-Log "WARN: proxyip-best generation failed with exit code $LASTEXITCODE."
        return
    }
    Write-Log "Generated proxyip best list: $proxyipBestPath"
}

$countryMinSpeedByCode = ConvertFrom-CountryMinSpeedMap `
    -Value $CountryMinSpeedMBPerSec `
    -AllowedCountries $Countries

if ($env:CFOPT_SOURCE_ONLY -ne "1") {
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
    $ip164746Candidates = @(Get-Ip164746Candidates)
    $gslegeCandidates = @(Get-GslegeCloudflareIpCandidates)
    $hotPrefixMiningCandidates = @(Get-HotPrefixMiningCandidates -SeedCandidates @($ip164746Candidates + $gslegeCandidates + $cfBestIpCandidates + $previousCsvEntries))
    Write-Log "Generated $($hotPrefixMiningCandidates.Count) rotating hot-prefix candidates for all available country/port pools."
    $ctEntryPoolCandidates = @(Get-CtEntryPoolCandidates -SelectedPorts $effectivePorts)
    Write-Log "Generated $($ctEntryPoolCandidates.Count) CT entry candidates across $($effectivePorts.Count) configured ports."
    $allCountries = @(Get-FocusExcludedCountries)
    $generatedWorkItems = foreach ($effectivePort in $effectivePorts) {
            New-CtEntryPortWorkItem -CurrentPort $effectivePort -Candidates $ctEntryPoolCandidates
            if ($allCountries.Count -gt 0) {
                New-PortWorkItem -CurrentPort $effectivePort -Vps789CtIps $vps789CtIps -CfBestIpCandidates $cfBestIpCandidates -Ip164746Candidates $ip164746Candidates -GslegeCandidates $gslegeCandidates -HotPrefixMiningCandidates $hotPrefixMiningCandidates -PreviousCsvEntries $previousCsvEntries -SelectedCountries $allCountries -ScopeName "all" -IncludeVps789Ct $true
            }
            foreach ($focusCountry in @(Get-EffectiveFocusCountries)) {
                if ($Countries -contains $focusCountry) {
                    New-PortWorkItem -CurrentPort $effectivePort -Vps789CtIps @() -CfBestIpCandidates $cfBestIpCandidates -Ip164746Candidates $ip164746Candidates -GslegeCandidates $gslegeCandidates -HotPrefixMiningCandidates $hotPrefixMiningCandidates -PreviousCsvEntries $previousCsvEntries -SelectedCountries @($focusCountry) -ScopeName "focus-$focusCountry" -IncludeVps789Ct $false
                }
            }
        }
    $workItems = @($generatedWorkItems | Where-Object { $null -ne $_ })
    if ($workItems.Count -eq 0) {
        throw "No usable port/country inputs were prepared."
    }

    foreach ($item in $workItems) {
        Invoke-TcpPrecheck -Port $item.Port -SelectedIpPath $item.SelectedIpPath -MapPath $item.MapPath
    }
    $workItems = @(Get-NonEmptyWorkItems -WorkItems $workItems)
    if ($workItems.Count -eq 0) {
        throw "No usable port/country inputs remained after TCP precheck."
    }

    if ($DryRun) {
        Write-Log "Dry run enabled. Skipping cfst execution and GitHub upload."
        foreach ($item in $workItems) {
            $dryRunArgs = @(Get-CfstArguments -Item $item)
            Write-Log "Would run: `"$CfstPath`" $(Join-ProcessArguments -Arguments $dryRunArgs)"
        }
        exit 0
    }

    $running = @(Start-CfstProcesses -WorkItems $workItems)
    Wait-CfstProcesses -Running $running
    Write-MergedFilteredCsv -WorkItems $workItems -PreviousNodeKeys $previousNodeKeys
    Merge-RollingPublicationCsv -PreviousCsvEntries $previousCsvEntries
    Assert-PublicationSafety -PreviousCsvEntries $previousCsvEntries

    if ($SkipUpload) {
        Write-Log "SkipUpload enabled. CSV generated but GitHub upload and success-state update were skipped."
        exit 0
    }

    Publish-ToGitHub
    New-ProxyipBestFile
    if (Test-Path -LiteralPath $proxyipBestPath) {
        Publish-FileToGitHub -LocalPath $proxyipBestPath -UploadTargetPath $ProxyipBestTargetPath
    }

    (Get-Date).ToString("o") | Set-Content -LiteralPath $stateFile -Encoding ASCII
    Write-Log "Completed successfully. Uploaded $csvPath to $Owner/$Repo/$TargetPath."
}
catch {
    Write-Log "ERROR: $($_.Exception.Message)"
    Write-Log "ERROR_DETAIL: $($_.InvocationInfo.PositionMessage)"
    Write-Log "ERROR_STACK: $($_.ScriptStackTrace)"
    throw
}
}
