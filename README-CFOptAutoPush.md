# CFOpt Auto Push

This repository automation generates CloudflareSpeedTest CSV files from `ip.zip`, filters bad rows, adds `城市` and `端口` columns, and uploads the result to `GuardSkill/CFOpt`.

## What It Uploads

- Windows/CD script default: `CloudflareSpeedTest_CD.csv`
- Linux/BJ script default: `CloudflareSpeedTest_BJ.csv`
- Subconverter config: `CFOpt_Subconverter.ini`

## Subconverter Config

Root file:

```text
CFOpt_Subconverter.ini
```

Raw URL:

```text
https://raw.githubusercontent.com/GuardSkill/CFOpt/main/CFOpt_Subconverter.ini
```

Use this URL as edgetunnel `订阅转换配置.SUBCONFIG`.

The config does not hard-code proxy IPs. It selects nodes by the online CSV-generated remarks:

- `Polymarket`: only `KR`, `HK`, `MY`, `IE`
- `ClaudeCode`: countries/regions suitable for both Claude/Claude Code and OpenAI/Codex: `KR`, `SG`, `VN`, `MY`, `KZ`, `IE`, `US`, with `PH` and `MN` reserved for future upstream availability

Because generated nodes look like `198.41.223.63:2096#SG [86ms 76.20Mbps]`, the config filters by country/region prefix rather than fixed IPs.

Both scripts:

1. Download `https://zip.cm.edu.kg/ip.zip`
2. Extract the folders matching the configured ports, by default `443`, `2053`, `2083`, `2087`, `2096`, and `8443`
3. Merge selected group files such as `HK.txt`, `KR.txt`, `SG.txt` for each port
4. Save per-port IP-to-group maps such as `selected-ip-city-map-443.csv`
5. Run one `cfst` process per port in parallel
6. Merge all port CSVs and filter unusable or extreme rows
7. Keep at most 20 best rows per source group across all ports
8. Output API-compatible columns including `IP地址`, `端口`, `数据中心`, `城市`, and `TLS`
9. Put subscription remarks in `城市`, such as `SG [86ms 76.20Mbps]`
10. Upload the CSV to GitHub

The current zip groups are country/region codes, so the `城市` value starts with `HK`, `KR`, `SG`, `US`, and similar. It also includes latency and converted Mbps speed so edgetunnel can produce lines such as `198.41.223.63:2096#SG [86ms 76.20Mbps]`.

## Filtering Rules

Defaults:

- Keep rows with `已接收 >= 1`
- Keep rows with `丢包率 < 1`
- Keep rows with `平均延迟 <= 420`
- Keep at most `20` rows per source group across all tested ports, sorted by higher download speed first, then lower latency

Change the latency threshold when running manually:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\Invoke-CFOptAutoPush.ps1" -Force -MaxLatencyMs 300
```

```bash
FORCE=1 MAX_LATENCY_MS=300 ./invoke-cfopt-auto-push-linux.sh
```

## GitHub Token

Create a GitHub fine-grained personal access token with repository contents write access to `GuardSkill/CFOpt`.

Windows:

```powershell
[Environment]::SetEnvironmentVariable("GITHUB_TOKEN_CFOPT", "paste_your_token_here", "User")
```

Close and reopen PowerShell after setting it.

Linux:

```bash
export GITHUB_TOKEN_CFOPT="paste_your_token_here"
```

For cron or systemd, put the token in the script environment, a root-owned env file, or the service unit.

## Windows Usage

Files:

- `scripts/windows/Invoke-CFOptAutoPush.ps1`
- `scripts/windows/Install-CFOptAutoPushTask.ps1`

Expected local `cfst` path:

```text
H:\PyProjects\cfst_windows_amd64\cfst.exe
```

Default working directory:

```text
H:\PyProjects\CFOptAutoPush
```

Dry run without running `cfst` or uploading:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\Invoke-CFOptAutoPush.ps1" -DryRun
```

Generate CSV without upload:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\Invoke-CFOptAutoPush.ps1" -Force -SkipUpload
```

Generate and upload `CloudflareSpeedTest_CD.csv`:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\Invoke-CFOptAutoPush.ps1" -Force
```

Install startup automation:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\Install-CFOptAutoPushTask.ps1"
```

The scheduled task is named `CFOpt Auto Push`. It runs at startup after a short delay. The main script records the last successful upload and only runs again after `IntervalDays`, default `6`.

## Linux Usage

File:

- `scripts/linux/invoke-cfopt-auto-push-linux.sh`

You provide the Linux `cfst` binary yourself.

Example setup:

```bash
mkdir -p "$HOME/cfopt-auto-push"
cp ./cfst "$HOME/cfopt-auto-push/cfst"
chmod +x "$HOME/cfopt-auto-push/cfst"
chmod +x ./invoke-cfopt-auto-push-linux.sh
export GITHUB_TOKEN_CFOPT="paste_your_token_here"
```

Dry run:

```bash
DRY_RUN=1 ./invoke-cfopt-auto-push-linux.sh
```

Generate CSV without upload:

```bash
FORCE=1 SKIP_UPLOAD=1 ./invoke-cfopt-auto-push-linux.sh
```

Generate and upload `CloudflareSpeedTest_BJ.csv`:

```bash
FORCE=1 ./invoke-cfopt-auto-push-linux.sh
```

Useful environment variables:

```bash
WORK_DIR="$HOME/cfopt-auto-push"
CFST_PATH="$HOME/cfopt-auto-push/cfst"
PORTS="443,2053,2083,2087,2096,8443"
# Set PORT=443 to force a single-port run.
TARGET_PATH="CloudflareSpeedTest_BJ.csv"
INTERVAL_DAYS=6
MAX_LATENCY_MS=420
MAX_PER_CITY=20
COUNTRIES_CSV="HK,KR,SG,PH,VN,MY,KZ,MN,IE,US"
```

## Linux Automation

Cron example, run at reboot:

```cron
@reboot GITHUB_TOKEN_CFOPT=your_token_here CFST_PATH=/home/ubuntu/cfopt-auto-push/cfst /home/ubuntu/cfopt-auto-push/invoke-cfopt-auto-push-linux.sh >> /home/ubuntu/cfopt-auto-push/cron.log 2>&1
```

Cron example, run daily and let the script enforce the 6-day interval:

```cron
20 4 * * * GITHUB_TOKEN_CFOPT=your_token_here CFST_PATH=/home/ubuntu/cfopt-auto-push/cfst /home/ubuntu/cfopt-auto-push/invoke-cfopt-auto-push-linux.sh >> /home/ubuntu/cfopt-auto-push/cron.log 2>&1
```

Systemd service example:

```ini
[Unit]
Description=CFOpt Auto Push
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
Environment=GITHUB_TOKEN_CFOPT=your_token_here
Environment=WORK_DIR=/home/ubuntu/cfopt-auto-push
Environment=CFST_PATH=/home/ubuntu/cfopt-auto-push/cfst
ExecStart=/home/ubuntu/cfopt-auto-push/invoke-cfopt-auto-push-linux.sh
```

Systemd timer example:

```ini
[Unit]
Description=Run CFOpt Auto Push daily

[Timer]
OnBootSec=5min
OnUnitActiveSec=1d
Persistent=true

[Install]
WantedBy=timers.target
```

The script still enforces the 6-day interval internally.

## Port Behavior

`ip.zip` contains folders named by port. By default the scripts run all configured ports in parallel and merge the results into one CSV.

- Windows default: `-Ports "443,2053,2083,2087,2096,8443"`
- Linux default: `PORTS="443,2053,2083,2087,2096,8443"`
- Single-port override: Windows `-Port 8443`, Linux `PORT=8443`
- `443`: does not pass `-tp`, so cfst uses its default 443 behavior
- Non-443 ports: pass `-tp <port>`

For port 80, cfst also needs an HTTP download URL:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\Invoke-CFOptAutoPush.ps1" -Force -Port 80 -DownloadTestUrl "http://speed.cloudflare.com/__down?bytes=99999999"
```

```bash
FORCE=1 PORT=80 DOWNLOAD_TEST_URL="http://speed.cloudflare.com/__down?bytes=99999999" ./invoke-cfopt-auto-push-linux.sh
```

This only works if the downloaded zip contains an `80` folder.

## Logs And Generated Files

Windows default work dir:

```text
H:\PyProjects\CFOptAutoPush
```

Linux default work dir:

```text
$HOME/cfopt-auto-push
```

Important files:

- `auto-push.log`: run log
- `last-success.txt`: last successful upload time
- `ip.zip`: downloaded zip cache
- `extract`: extracted zip contents
- `selected-ip.txt`: merged cfst input
- `selected-ip-city-map.csv`: IP-to-group map used for the `城市` column
- `CloudflareSpeedTest.csv`: generated and filtered CSV before upload, using edgetunnel-compatible columns
- `cfst-stdin.txt` on Windows: blank line for cfst final Enter prompt
- `cfst-stdout.log` and `cfst-stderr.log`: captured cfst output

## Common Issues

- Missing token: set `GITHUB_TOKEN_CFOPT`.
- Missing `cfst`: set `CfstPath` on Windows or `CFST_PATH` on Linux.
- Download blocked: the source sometimes returns a Cloudflare challenge. If `ip.zip` already exists, the scripts reuse the cached zip.
- Missing group file: the scripts log a warning and continue with available groups.
- Missing port folder: the scripts stop instead of mixing IPs from another port.
- GitHub 404 during metadata lookup: treated as "file does not exist yet"; the upload creates it.
- GitHub upload still returns 404: check repository name, branch, token permissions, and private repository access.
