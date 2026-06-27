# CFOpt 自动测速与推送

这套脚本会自动下载 `ip.zip`，按端口和分组整理 IP，调用 `cfst` 测速，过滤不可用或高延迟结果，给最终 CSV 增加 `城市` 和 `端口` 两列，然后推送到 `GuardSkill/CFOpt`。

## 上传文件

- Windows/CD 默认上传：`CloudflareSpeedTest_CD.csv`
- Linux/BJ 默认上传：`CloudflareSpeedTest_BJ.csv`

## 数据流程

1. 下载 `https://zip.cm.edu.kg/ip.zip`
2. 解压并选择端口目录，例如 `443`
3. 合并指定分组文件，例如 `HK.txt`、`KR.txt`、`SG.txt`
4. 生成 `selected-ip-city-map.csv`，记录每个 IP 来自哪个分组
5. 调用 `cfst` 测速
6. 过滤结果
7. 每个分组最多保留最优 10 个 IP
8. 输出兼容 edgetunnel 的列：`IP地址`、`端口`、`数据中心`、`城市`、`TLS`
9. `城市` 列会写成订阅备注，例如 `SG [86ms 76.20Mbps]`
10. 上传到 GitHub

当前 `ip.zip` 的分组主要是国家/地区代码，所以 `城市` 列会以 `HK`、`KR`、`SG`、`US` 这类值开头，并追加延迟和 Mbps 速度。edgetunnel 会把它转换成类似 `198.41.223.63:2096#SG [86ms 76.20Mbps]` 的行。

## 默认过滤规则

- 保留 `已接收 >= 1`
- 保留 `丢包率 < 1`
- 保留 `平均延迟 <= 420`
- 每个分组最多保留 10 个，优先下载速度更高，其次平均延迟更低

临时调整延迟阈值：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\Invoke-CFOptAutoPush.ps1" -Force -MaxLatencyMs 300
```

```bash
FORCE=1 MAX_LATENCY_MS=300 ./invoke-cfopt-auto-push-linux.sh
```

## GitHub Token

创建一个 GitHub fine-grained personal access token，给 `GuardSkill/CFOpt` 仓库 Contents 写入权限。

Windows 设置：

```powershell
[Environment]::SetEnvironmentVariable("GITHUB_TOKEN_CFOPT", "你的 token", "User")
```

设置后重新打开 PowerShell。

Linux 设置：

```bash
export GITHUB_TOKEN_CFOPT="你的 token"
```

## Windows 使用

文件：

- `scripts/windows/Invoke-CFOptAutoPush.ps1`
- `scripts/windows/Install-CFOptAutoPushTask.ps1`

默认 `cfst` 路径：

```text
H:\PyProjects\cfst_windows_amd64\cfst.exe
```

默认工作目录：

```text
H:\PyProjects\CFOptAutoPush
```

只下载、解压、合并，不测速、不上传：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\Invoke-CFOptAutoPush.ps1" -DryRun
```

生成 CSV 但不上传：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\Invoke-CFOptAutoPush.ps1" -Force -SkipUpload
```

生成并上传 `CloudflareSpeedTest_CD.csv`：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\Invoke-CFOptAutoPush.ps1" -Force
```

安装开机自动任务：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\Install-CFOptAutoPushTask.ps1"
```

计划任务名是 `CFOpt Auto Push`。它会在开机后延迟一小会儿运行。脚本内部会检查 `last-success.txt`，默认距离上次成功上传满 6 天才再次执行。

## Linux 使用

文件：

- `scripts/linux/invoke-cfopt-auto-push-linux.sh`

你需要自己准备 Linux 版 `cfst` 二进制文件。

示例：

```bash
mkdir -p "$HOME/cfopt-auto-push"
cp ./cfst "$HOME/cfopt-auto-push/cfst"
chmod +x "$HOME/cfopt-auto-push/cfst"
chmod +x ./invoke-cfopt-auto-push-linux.sh
export GITHUB_TOKEN_CFOPT="你的 token"
```

只下载、解压、合并：

```bash
DRY_RUN=1 ./invoke-cfopt-auto-push-linux.sh
```

生成 CSV 但不上传：

```bash
FORCE=1 SKIP_UPLOAD=1 ./invoke-cfopt-auto-push-linux.sh
```

生成并上传 `CloudflareSpeedTest_BJ.csv`：

```bash
FORCE=1 ./invoke-cfopt-auto-push-linux.sh
```

常用环境变量：

```bash
WORK_DIR="$HOME/cfopt-auto-push"
CFST_PATH="$HOME/cfopt-auto-push/cfst"
PORT=443
TARGET_PATH="CloudflareSpeedTest_BJ.csv"
INTERVAL_DAYS=6
MAX_LATENCY_MS=420
MAX_PER_CITY=10
COUNTRIES_CSV="HK,KR,SG,PH,VN,MY,KZ,MN,IE,US"
```

## Linux 自动化

开机运行一次：

```cron
@reboot GITHUB_TOKEN_CFOPT=你的token CFST_PATH=/home/ubuntu/cfopt-auto-push/cfst /home/ubuntu/cfopt-auto-push/invoke-cfopt-auto-push-linux.sh >> /home/ubuntu/cfopt-auto-push/cron.log 2>&1
```

每天运行一次，让脚本内部判断是否满 6 天：

```cron
20 4 * * * GITHUB_TOKEN_CFOPT=你的token CFST_PATH=/home/ubuntu/cfopt-auto-push/cfst /home/ubuntu/cfopt-auto-push/invoke-cfopt-auto-push-linux.sh >> /home/ubuntu/cfopt-auto-push/cron.log 2>&1
```

systemd service 示例：

```ini
[Unit]
Description=CFOpt Auto Push
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
Environment=GITHUB_TOKEN_CFOPT=你的token
Environment=WORK_DIR=/home/ubuntu/cfopt-auto-push
Environment=CFST_PATH=/home/ubuntu/cfopt-auto-push/cfst
ExecStart=/home/ubuntu/cfopt-auto-push/invoke-cfopt-auto-push-linux.sh
```

systemd timer 示例：

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

脚本内部仍然会按 6 天间隔控制真实执行。

## 端口说明

`ip.zip` 里面已经按端口分目录。脚本只读取和配置端口一致的目录。

- `443`：读取 `443` 目录，不给 `cfst` 传 `-tp`，使用 cfst 默认 443
- `8443`：读取 `8443` 目录，并给 `cfst` 传 `-tp 8443`

如果测速 80 端口，cfst 还需要 HTTP 下载测速地址：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\Invoke-CFOptAutoPush.ps1" -Force -Port 80 -DownloadTestUrl "http://speed.cloudflare.com/__down?bytes=99999999"
```

```bash
FORCE=1 PORT=80 DOWNLOAD_TEST_URL="http://speed.cloudflare.com/__down?bytes=99999999" ./invoke-cfopt-auto-push-linux.sh
```

前提是下载的 `ip.zip` 里存在 `80` 目录。

## 日志和中间文件

Windows 默认目录：

```text
H:\PyProjects\CFOptAutoPush
```

Linux 默认目录：

```text
$HOME/cfopt-auto-push
```

重要文件：

- `auto-push.log`：运行日志
- `last-success.txt`：上次成功上传时间
- `ip.zip`：下载缓存
- `extract`：解压目录
- `selected-ip.txt`：给 cfst 使用的合并 IP 文件
- `selected-ip-city-map.csv`：IP 到分组的映射，用于生成 `城市` 列
- `CloudflareSpeedTest.csv`：过滤后准备上传的 CSV，使用 edgetunnel 兼容列
- `cfst-stdin.txt`：Windows 下自动给 cfst 最后的“按回车退出”喂空行
- `cfst-stdout.log` / `cfst-stderr.log`：cfst 输出日志

## 常见问题

- 缺少 token：设置 `GITHUB_TOKEN_CFOPT`
- 缺少 cfst：Windows 检查 `CfstPath`，Linux 检查 `CFST_PATH`
- 下载被 Cloudflare 拦截：如果本地已有 `ip.zip` 缓存，脚本会复用缓存
- 某个分组文件不存在：脚本会 warning 并跳过
- 端口目录不存在：脚本会停止，避免混用其他端口 IP
- GitHub metadata 404：表示目标文件还不存在，脚本会创建
- GitHub upload 仍然 404：检查仓库名、分支、token 权限和私有仓库访问权限
