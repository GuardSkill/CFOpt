# CFOpt Auto Push

CFOpt generates Edge Tunnel compatible CloudflareSpeedTest CSV files. It downloads candidate IP lists, tests multiple Cloudflare ports with `CloudflareSpeedTest`, filters unstable rows, keeps the best rows per region, and uploads the result to GitHub.

## Files

- `CloudflareSpeedTest_CD.csv`: default Windows/CD output
- `CloudflareSpeedTest_BJ.csv`: default Linux/BJ output
- `CFOpt_Subconverter.ini`: Subconverter config
- `rules/`: routing rules

## Scripts

- `scripts/windows/Invoke-CFOptAutoPush.ps1`
- `scripts/windows/Install-CFOptAutoPushTask.ps1`
- `scripts/linux/invoke-cfopt-auto-push-linux.sh`
- `scripts/linux/install-and-run-cfopt-linux.sh`

Root-level duplicate scripts were removed. The root now keeps only docs, configs, CSVs, and rules.

## Testing Strategy

The default candidate source is:

```text
https://zip.cm.edu.kg/ip.zip
```

Default ports:

```text
443,2053,2083,2087,2096,8443
```

To avoid Hong Kong candidates being crowded out by other regions, the scripts now run:

1. one general test for all configured regions
2. extra focused tests for `HK` by default

Default CFST parameters:

```text
-n 160
-t 6
-dn 60
-dt 15
-tl 420
-tlr 0
-sl 0.01
-p 0
```

The final CSV still keeps the Top 20 rows per region/group.

## Run

Windows:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\windows\Invoke-CFOptAutoPush.ps1" -Force
```

Linux:

```bash
FORCE=1 ./scripts/linux/invoke-cfopt-auto-push-linux.sh
```

One-line Linux bootstrap:

```bash
GITHUB_TOKEN_CFOPT="your token" bash -c "$(curl -fsSL https://raw.githubusercontent.com/GuardSkill/CFOpt/main/scripts/linux/install-and-run-cfopt-linux.sh)"
```

## Focus Regions

Windows:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\windows\Invoke-CFOptAutoPush.ps1" -Force -FocusCountries "HK,SG,JP"
```

Linux:

```bash
FORCE=1 FOCUS_COUNTRIES_CSV="HK,SG,JP" ./scripts/linux/invoke-cfopt-auto-push-linux.sh
```

## Tuning

Windows:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\windows\Invoke-CFOptAutoPush.ps1" -Force -CfstDownloadTestCount 100 -CfstDownloadTestTime 20 -CfstLossRateLimit 0
```

Linux:

```bash
FORCE=1 CFST_DOWNLOAD_TEST_COUNT=100 CFST_DOWNLOAD_TEST_TIME=20 CFST_LOSS_RATE_LIMIT=0 ./scripts/linux/invoke-cfopt-auto-push-linux.sh
```

If every download speed is `0.00 MB/s`, enable debug output:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\windows\Invoke-CFOptAutoPush.ps1" -Force -CfstDebug
```

```bash
FORCE=1 CFST_DEBUG=1 ./scripts/linux/invoke-cfopt-auto-push-linux.sh
```

## vps789

`vps789` currently returns very few CT candidates, so it is disabled by default.

Enable manually:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\windows\Invoke-CFOptAutoPush.ps1" -Force -EnableVps789Ct
```

```bash
FORCE=1 ENABLE_VPS789_CT=1 ./scripts/linux/invoke-cfopt-auto-push-linux.sh
```

Only `cfIpApi.data.CT` is used.

## cf-bestip

`Zoroaaa/cf-bestip` is a better regional candidate source than vps789 because it publishes region-specific Cloudflare Anycast IPv4 lists. It should still be treated as a candidate source rather than a final result source. The final CSV should continue to come from local CFST download tests.

## GitHub Token

Windows:

```powershell
[Environment]::SetEnvironmentVariable("GITHUB_TOKEN_CFOPT", "your token", "User")
```

Linux:

```bash
export GITHUB_TOKEN_CFOPT="your token"
```
