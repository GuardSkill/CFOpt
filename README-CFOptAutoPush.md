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

The `cf-bestip` regional source is also enabled by default:

```text
https://zoroaaa.github.io/cf-bestip/ip_*.txt
```

The scripts parse entries like `IP:port#region-score`, keep only candidates that match the current CFST port, and then run local CFST download tests.

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

## Daily Rolling Retest

The scripts run at most once per day by default:

```text
INTERVAL_DAYS=1
```

Each run downloads the current target CSV from GitHub, adds those existing nodes back into the CFST inputs, and retests them. For each region/group:

- old nodes that fail the current filters are removed
- at most about 2/3 of the final rows can be old nodes
- at least about 1/3 is filled by the best newly tested candidates when available
- if new candidates are not enough, passing old nodes can fill the remaining slots

Default replacement fraction:

```text
0.33
```

Windows:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\windows\Invoke-CFOptAutoPush.ps1" -Force -RollingReplaceFraction 0.5
```

Linux:

```bash
FORCE=1 ROLLING_REPLACE_FRACTION=0.5 ./scripts/linux/invoke-cfopt-auto-push-linux.sh
```

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

## City Column

Windows/CD defaults to `成都测速`:

```text
HK [成都测速#01]
JP [成都测速#01]
```

Linux/BJ defaults to `北京测速`:

```text
HK[北京测速01]
JP[北京测速01]
```

## cf-bestip

`Zoroaaa/cf-bestip` is enabled by default as an extra regional candidate source. The final CSV still comes from local CFST download tests.

Disable it on Windows:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\windows\Invoke-CFOptAutoPush.ps1" -Force -DisableCfBestIp
```

Disable it on Linux:

```bash
FORCE=1 ENABLE_CFBESTIP=0 ./scripts/linux/invoke-cfopt-auto-push-linux.sh
```

## GitHub Token

Windows:

```powershell
[Environment]::SetEnvironmentVariable("GITHUB_TOKEN_CFOPT", "your token", "User")
```

Linux:

```bash
export GITHUB_TOKEN_CFOPT="your token"
```

## Background Autorun

Windows:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\windows\Install-CFOptAutoPushTask.ps1"
```

The task runs daily at `04:00` and also checks shortly after startup.

Linux:

```bash
GITHUB_TOKEN_CFOPT="your token" bash -c "$(curl -fsSL https://raw.githubusercontent.com/GuardSkill/CFOpt/main/scripts/linux/install-and-run-cfopt-linux.sh)"
```

The bootstrap script installs a user `systemd` timer when available, otherwise it falls back to `crontab`. The default schedule is daily at `04:00`.
