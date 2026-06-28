# CFOpt 自动测速与推送

这套脚本会自动下载 `ip.zip`，按多个端口并行测速，合并结果，过滤不可用或高延迟节点，然后把最终 CSV 上传到 `GuardSkill/CFOpt`。

## 上传文件

- Windows/CD 默认上传：`CloudflareSpeedTest_CD.csv`
- Linux/BJ 默认上传：`CloudflareSpeedTest_BJ.csv`
- 订阅转换配置：`CFOpt_Subconverter.ini`

## 数据流程

1. 下载 `https://zip.cm.edu.kg/ip.zip`
2. 解压并读取多个端口目录，默认 `443`、`2053`、`2083`、`2087`、`2096`、`8443`
3. 每个端口分别合并指定国家/地区文件，例如 `HK.txt`、`KR.txt`、`SG.txt`
4. 每个端口生成独立的 IP 到国家/地区映射，例如 `selected-ip-city-map-443.csv`
5. 每个端口启动一个 `cfst` 进程，并行测速
6. 合并所有端口的 CSV 结果
7. 过滤不可用或高延迟结果
8. 每个国家/地区最多保留 Top 20，优先下载速度更高，其次平均延迟更低
9. 输出 edgetunnel 兼容列：`IP地址`、`端口`、`数据中心`、`城市`、`TLS`
10. 上传到 GitHub

最终节点备注会类似：

```text
198.41.223.63:2096#SG [86ms 76.20Mbps]
```

## 默认过滤规则

- 保留 `已接收 >= 1`
- 保留 `丢包率 < 1`
- 保留 `平均延迟 <= 420`
- 保留 `下载速度 >= 0.01 Mbps`，避免 0.00 速结果进入订阅
- 每个国家/地区最多保留 `20` 条，跨所有测试端口一起排名

临时调整延迟阈值：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\Invoke-CFOptAutoPush.ps1" -Force -MaxLatencyMs 300
```

```bash
FORCE=1 MAX_LATENCY_MS=300 ./invoke-cfopt-auto-push-linux.sh
```

如果结果全是 `0.00 MB/s`，用 cfst 调试模式排查下载测速地址、IP 或网络问题：

```bash
FORCE=1 CFST_DEBUG=1 ./invoke-cfopt-auto-push-linux.sh
```

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\Invoke-CFOptAutoPush.ps1" -Force -CfstDebug
```

## Windows 使用

默认路径：

```text
H:\PyProjects\cfst_windows_amd64\cfst.exe
H:\PyProjects\CFOptAutoPush
```

只下载、解压、准备输入，不测速、不上传：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\Invoke-CFOptAutoPush.ps1" -DryRun
```

生成 CSV 但不上传：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\Invoke-CFOptAutoPush.ps1" -Force -SkipUpload
```

默认多端口并行测速并上传：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\Invoke-CFOptAutoPush.ps1" -Force
```

指定一组端口：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\Invoke-CFOptAutoPush.ps1" -Force -Ports "443,2053,2083,2087,2096,8443"
```

临时只测单端口：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\Invoke-CFOptAutoPush.ps1" -Force -Port 8443
```

## Linux 使用

一行安装并立即运行：

```bash
GITHUB_TOKEN_CFOPT="你的 token" bash -c "$(curl -fsSL https://raw.githubusercontent.com/GuardSkill/CFOpt/main/scripts/linux/install-and-run-cfopt-linux.sh)"
```

如果已经在仓库目录里，只是想手动立即更新一次，用：

```bash
FORCE=1 ./invoke-cfopt-auto-push-linux.sh
```

准备 `cfst`：

```bash
mkdir -p "$HOME/cfopt-auto-push"
cp ./cfst "$HOME/cfopt-auto-push/cfst"
chmod +x "$HOME/cfopt-auto-push/cfst"
chmod +x ./invoke-cfopt-auto-push-linux.sh
export GITHUB_TOKEN_CFOPT="你的 token"
```

默认多端口并行测速并上传：

```bash
FORCE=1 ./invoke-cfopt-auto-push-linux.sh
```

生成 CSV 但不上传：

```bash
FORCE=1 SKIP_UPLOAD=1 ./invoke-cfopt-auto-push-linux.sh
```

指定端口列表：

```bash
FORCE=1 PORTS="443,2053,2083,2087,2096,8443" ./invoke-cfopt-auto-push-linux.sh
```

临时只测单端口：

```bash
FORCE=1 PORT=8443 ./invoke-cfopt-auto-push-linux.sh
```

常用环境变量：

```bash
WORK_DIR="$HOME/cfopt-auto-push"
CFST_PATH="$HOME/cfopt-auto-push/cfst"
PORTS="443,2053,2083,2087,2096,8443"
TARGET_PATH="CloudflareSpeedTest_BJ.csv"
INTERVAL_DAYS=3
MAX_LATENCY_MS=420
MIN_SPEED_MBPS=0.01
MAX_PER_CITY=20
COUNTRIES_CSV="HK,KR,SG,PH,VN,MY,KZ,MN,IE,US"
```

## 端口说明

`ip.zip` 里面已经按端口分目录。脚本现在默认读取多个端口目录并并行测速，最后合并成一个 CSV。

- Windows 默认：`-Ports "443,2053,2083,2087,2096,8443"`
- Linux 默认：`PORTS="443,2053,2083,2087,2096,8443"`
- 单端口覆盖：Windows 用 `-Port 8443`，Linux 用 `PORT=8443`
- `443` 不给 `cfst` 传 `-tp`，使用 cfst 默认 443
- 非 443 端口会给 `cfst` 传 `-tp <端口>`

如果测速 `80` 端口，`cfst` 还需要 HTTP 下载测速地址：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\Invoke-CFOptAutoPush.ps1" -Force -Port 80 -DownloadTestUrl "http://speed.cloudflare.com/__down?bytes=99999999"
```

```bash
FORCE=1 PORT=80 DOWNLOAD_TEST_URL="http://speed.cloudflare.com/__down?bytes=99999999" ./invoke-cfopt-auto-push-linux.sh
```

前提是下载的 `ip.zip` 里存在 `80` 目录。

## GitHub Token

Windows：

```powershell
[Environment]::SetEnvironmentVariable("GITHUB_TOKEN_CFOPT", "你的 token", "User")
```

Linux：

```bash
export GITHUB_TOKEN_CFOPT="你的 token"
```

## 中间文件

- `CloudflareSpeedTest.csv`：最终合并过滤后准备上传的 CSV
- `CloudflareSpeedTest-443.csv`：单个端口的原始测速 CSV
- `selected-ip-443.txt`：给 `cfst` 使用的单端口输入
- `selected-ip-city-map-443.csv`：单端口 IP 到国家/地区的映射
- `cfst-443-stdout.log` / `cfst-443-stderr.log`：单端口测速日志
- `auto-push.log`：总日志
- `last-success.txt`：上次成功上传时间

## vps789 CT candidates

The scripts fetch `https://vps789.com/openApi/cfIpApi` by default and only use `data.CT`, which is the China Telecom Cloudflare preferred-IP list. These IPs are added to every CFST port input and tested together with candidates from `ip.zip`.

- Enabled by default: Windows enabled; Linux `ENABLE_VPS789_CT=1`
- Disable: Windows `-DisableVps789Ct`; Linux `ENABLE_VPS789_CT=0`
- Default limit: `Vps789CtLimit=50` / `VPS789_CT_LIMIT=50`
- Default filter: China Telecom latency `<=260ms`, China Telecom loss `<=5`
- Helper export: `VPS789_CF_CT_Candidates.csv`

`hostMonitorList` looks more like a VPS/domain/IP monitor list and is not guaranteed to contain only Cloudflare Anycast IPs, so it is not merged directly into the Edge Tunnel CSV. The main merged speed-test CSV only adds `cfIpApi.data.CT`, then lets CFST test and filter it.
