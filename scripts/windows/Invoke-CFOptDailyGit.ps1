param(
    [string]$RepoRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)),
    [string]$WorkDir = (Join-Path $RepoRoot ".cfopt-work"),
    [string]$RunnerPath = (Join-Path $PSScriptRoot "Invoke-CFOptAutoPush.ps1"),
    [string]$CfstPath = (Join-Path $WorkDir "cfst.exe"),
    [string]$Remote = "origin",
    [string]$Branch = "main",
    [int]$PushAttempts = 3
)

$ErrorActionPreference = "Stop"

function Invoke-Git {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)

    & git -C $RepoRoot @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') failed with code $LASTEXITCODE"
    }
}

New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
$generatedCsv = Join-Path $WorkDir "CloudflareSpeedTest.csv"
$runnerLog = Join-Path $WorkDir "auto-push.log"
$wrapperLog = Join-Path $WorkDir "daily-git.log"

Start-Transcript -LiteralPath $wrapperLog -Append | Out-Null
try {
    # Recover cleanly if a previous run committed locally but its push was interrupted.
    Invoke-Git pull --rebase $Remote $Branch

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $RunnerPath `
        -WorkDir $WorkDir `
        -CfstPath $CfstPath `
        -Force `
        -AutoDetectNetworkIsp `
        -SkipUpload
    if ($LASTEXITCODE -ne 0) {
        throw "CFOpt runner exited with code $LASTEXITCODE"
    }

    $detection = Select-String -LiteralPath $runnerLog -Pattern 'Direct ISP detected: .*; target=([^;]+);' |
        Select-Object -Last 1
    $targetMatch = [regex]::Match([string]$detection.Line, 'target=([^;]+);')
    if (-not $targetMatch.Success) {
        throw "Could not determine the ISP-specific target CSV from $runnerLog"
    }

    $targetName = $targetMatch.Groups[1].Value
    if ($targetName -notin @("CloudflareSpeedTest_CD.csv", "CloudflareSpeedTest_CD_CM.csv")) {
        throw "Unexpected ISP-specific target CSV: $targetName"
    }

    Copy-Item -LiteralPath $generatedCsv -Destination (Join-Path $RepoRoot $targetName) -Force
    Invoke-Git add -- $targetName

    & git -C $RepoRoot diff --cached --quiet -- $targetName
    $diffResult = $LASTEXITCODE
    if ($diffResult -eq 0) {
        Write-Host "No changes to publish for $targetName"
        return
    }
    if ($diffResult -ne 1) {
        throw "git diff failed with code $diffResult"
    }

    Invoke-Git commit -m "Update $targetName"

    # A different benchmark host may update main while this long test is running.
    for ($attempt = 1; $attempt -le $PushAttempts; $attempt++) {
        Invoke-Git pull --rebase $Remote $Branch
        & git -C $RepoRoot push $Remote $Branch
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Updated and pushed $targetName"
            return
        }
        if ($attempt -lt $PushAttempts) {
            Start-Sleep -Seconds (5 * $attempt)
        }
    }

    throw "git push failed after $PushAttempts attempts"
}
finally {
    Stop-Transcript | Out-Null
}
