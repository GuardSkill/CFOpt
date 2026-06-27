param(
    [string]$DownloadUrl = "https://zip.cm.edu.kg/ip.zip",
    [string]$WorkDir = "H:\PyProjects\CFOptAutoPush",
    [string]$CfstPath = "H:\PyProjects\cfst_windows_amd64\cfst.exe",
    [string[]]$Countries = @("HK", "KR", "SG", "PH", "VN", "MY", "KZ", "MN", "IE", "US"),
    [int]$Port = 443,
    [string]$DownloadTestUrl = "",
    [string]$Owner = "GuardSkill",
    [string]$Repo = "CFOpt",
    [string]$Branch = "main",
    [string]$TargetPath = "CloudflareSpeedTest_CD.csv",
    [int]$IntervalDays = 6,
    [int]$MaxLatencyMs = 420,
    [int]$MinReceived = 1,
    [string]$TokenEnvName = "GITHUB_TOKEN_CFOPT",
    [switch]$Force,
    [switch]$DryRun,
    [switch]$SkipUpload
)

$ErrorActionPreference = "Stop"

$zipPath = Join-Path $WorkDir "ip.zip"
$extractDir = Join-Path $WorkDir "extract"
$selectedIpPath = Join-Path $WorkDir "selected-ip.txt"
$selectedIpCityMapPath = Join-Path $WorkDir "selected-ip-city-map.csv"
$csvPath = Join-Path $WorkDir "CloudflareSpeedTest.csv"
$stateFile = Join-Path $WorkDir "last-success.txt"
$logFile = Join-Path $WorkDir "auto-push.log"

function Write-Log {
    param([string]$Message)

    $line = "{0} {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    Write-Host $line
    Add-Content -LiteralPath $logFile -Value $line -Encoding UTF8
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

function Invoke-Cfst {
    if (-not (Test-Path -LiteralPath $CfstPath)) {
        throw "cfst executable not found: $CfstPath"
    }

    if (Test-Path -LiteralPath $csvPath) {
        Remove-Item -LiteralPath $csvPath -Force
    }

    $cfstArgs = @("-f", $selectedIpPath, "-o", $csvPath)
    if ($Port -ne 443) {
        $cfstArgs += @("-tp", ([string]$Port))
    }
    if (-not [string]::IsNullOrWhiteSpace($DownloadTestUrl)) {
        $cfstArgs += @("-url", $DownloadTestUrl)
    }

    $argumentText = Join-ProcessArguments -Arguments $cfstArgs
    $stdinPath = Join-Path $WorkDir "cfst-stdin.txt"
    $stdoutPath = Join-Path $WorkDir "cfst-stdout.log"
    $stderrPath = Join-Path $WorkDir "cfst-stderr.log"
    Set-Content -LiteralPath $stdinPath -Value "" -Encoding ASCII

    if ($Port -eq 443) {
        Write-Log "Running cfst on default port 443: $CfstPath $argumentText"
    }
    else {
        Write-Log "Running cfst on port ${Port}: $CfstPath $argumentText"
    }

    $process = Start-Process `
        -FilePath $CfstPath `
        -ArgumentList $argumentText `
        -RedirectStandardInput $stdinPath `
        -RedirectStandardOutput $stdoutPath `
        -RedirectStandardError $stderrPath `
        -NoNewWindow `
        -Wait `
        -PassThru

    if (Test-Path -LiteralPath $stdoutPath) {
        Get-Content -LiteralPath $stdoutPath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object {
            Write-Log "cfst: $_"
        }
    }
    if (Test-Path -LiteralPath $stderrPath) {
        Get-Content -LiteralPath $stderrPath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object {
            Write-Log "cfst stderr: $_"
        }
    }

    if ($process.ExitCode -ne 0) {
        throw "cfst failed with exit code $($process.ExitCode)."
    }

    if (-not (Test-Path -LiteralPath $csvPath)) {
        throw "cfst completed but output CSV was not created: $csvPath"
    }
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

function Filter-CfstCsv {
    if (-not (Test-Path -LiteralPath $csvPath)) {
        throw "CSV file not found for filtering: $csvPath"
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $lines = [System.IO.File]::ReadAllLines($csvPath, $utf8NoBom)
    if ($lines.Count -le 1) {
        throw "CSV has no data rows: $csvPath"
    }

    $cityByIp = @{}
    if (Test-Path -LiteralPath $selectedIpCityMapPath) {
        $mapLines = [System.IO.File]::ReadAllLines($selectedIpCityMapPath, $utf8NoBom)
        foreach ($mapLine in $mapLines) {
            if ([string]::IsNullOrWhiteSpace($mapLine)) {
                continue
            }
            $parts = $mapLine -split ",", 2
            if ($parts.Count -eq 2 -and -not $cityByIp.ContainsKey($parts[0])) {
                $cityByIp[$parts[0]] = $parts[1]
            }
        }
    }

    $kept = New-Object System.Collections.Generic.List[string]
    $header = $lines[0]
    if ($header -notmatch "(^|,)城市($|,)") {
        $header = "$header,城市"
    }
    if ($header -notmatch "(^|,)端口($|,)") {
        $header = "$header,端口"
    }
    $kept.Add($header)
    $removed = 0

    for ($i = 1; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        $columns = $line -split ","
        if ($columns.Count -lt 5) {
            $removed++
            continue
        }

        $ip = $columns[0].Trim()
        $received = Convert-ToNumber $columns[2]
        $lossRate = Convert-ToNumber $columns[3]
        $latency = Convert-ToNumber $columns[4]

        if ($null -eq $received -or $null -eq $lossRate -or $null -eq $latency) {
            $removed++
            continue
        }

        if ($received -lt $MinReceived -or $lossRate -ge 1 -or $latency -gt $MaxLatencyMs) {
            $removed++
            continue
        }

        $city = ""
        if ($cityByIp.ContainsKey($ip)) {
            $city = $cityByIp[$ip]
        }

        if ($lines[0] -match "(^|,)城市($|,)" -and $lines[0] -match "(^|,)端口($|,)") {
            $kept.Add($line)
        }
        else {
            $kept.Add("$line,$city,$Port")
        }
    }

    if ($kept.Count -le 1) {
        throw "Filtering removed all CSV rows. Check MaxLatencyMs=$MaxLatencyMs and MinReceived=$MinReceived."
    }

    [System.IO.File]::WriteAllLines($csvPath, $kept.ToArray(), $utf8NoBom)
    Write-Log "Filtered CSV rows and added city/port columns. Kept $($kept.Count - 1), removed $removed. Rules: received >= $MinReceived, loss < 1, latency <= $MaxLatencyMs ms."
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

    $portDir = Join-Path $extractDir ([string]$Port)
    if (-not (Test-Path -LiteralPath $portDir)) {
        throw "Port folder not found in extracted zip: $portDir"
    }

    Write-Log "Using IP files from zip port folder: $portDir"
    $allTxtFiles = @(Get-ChildItem -LiteralPath $portDir -File -Filter "*.txt")
    if ($allTxtFiles.Count -eq 0) {
        throw "No .txt files found after extraction."
    }

    $selectedFiles = foreach ($country in $Countries) {
        try {
            Resolve-CountryFile -Country $country -Files $allTxtFiles
        }
        catch {
            Write-Log "WARN: $($_.Exception.Message). Skipping $country."
        }
    }

    if (@($selectedFiles).Count -eq 0) {
        throw "None of the requested country files were found: $($Countries -join ', ')"
    }

    $selectedCountryNames = @($selectedFiles | ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension($_.Name) })
    Write-Log "Merging country files: $($selectedCountryNames -join ', ')"
    if (Test-Path -LiteralPath $selectedIpPath) {
        Remove-Item -LiteralPath $selectedIpPath -Force
    }
    if (Test-Path -LiteralPath $selectedIpCityMapPath) {
        Remove-Item -LiteralPath $selectedIpCityMapPath -Force
    }

    foreach ($file in $selectedFiles) {
        $city = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
        $ipLines = @(Get-Content -LiteralPath $file.FullName | Where-Object {
            -not [string]::IsNullOrWhiteSpace($_) -and -not $_.TrimStart().StartsWith("#")
        } | ForEach-Object { $_.Trim() })

        $ipLines | Add-Content -LiteralPath $selectedIpPath -Encoding ASCII
        foreach ($ipLine in $ipLines) {
            Add-Content -LiteralPath $selectedIpCityMapPath -Value "$ipLine,$city" -Encoding ASCII
        }
    }

    $lineCount = (Get-Content -LiteralPath $selectedIpPath | Where-Object {
        -not [string]::IsNullOrWhiteSpace($_) -and -not $_.TrimStart().StartsWith("#")
    }).Count
    if ($lineCount -eq 0) {
        throw "Merged IP file is empty: $selectedIpPath"
    }
    Write-Log "Merged $lineCount IP lines into $selectedIpPath."

    if ($DryRun) {
        Write-Log "Dry run enabled. Skipping cfst execution and GitHub upload."
        $dryRunArgs = @("-f", $selectedIpPath, "-o", $csvPath)
        if ($Port -ne 443) {
            $dryRunArgs += @("-tp", ([string]$Port))
        }
        if (-not [string]::IsNullOrWhiteSpace($DownloadTestUrl)) {
            $dryRunArgs += @("-url", $DownloadTestUrl)
        }
        Write-Log "Would run: `"$CfstPath`" $(Join-ProcessArguments -Arguments $dryRunArgs)"
        exit 0
    }

    Invoke-Cfst
    Filter-CfstCsv

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
    throw
}
