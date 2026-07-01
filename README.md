# CFOpt

## 中文说明

CFOpt 是一个 Cloudflare 优选 IP 自动测速与发布工具。它会下载候选 IP，按多个 Cloudflare 端口运行 `CloudflareSpeedTest`，过滤不可用、丢包和低速结果，然后生成 Edge Tunnel 可导入的 CSV 并上传到 GitHub。

### 一键运行

Windows 首次运行并安装每日任务：

```powershell
git clone https://github.com/GuardSkill/CFOpt.git H:\Projects\CFOpt
cd H:\Projects\CFOpt
[Environment]::SetEnvironmentVariable("GITHUB_TOKEN_CFOPT", "你的 GitHub token", "User")
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\windows\Invoke-CFOptAutoPush.ps1" -Force
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\windows\Install-CFOptAutoPushTask.ps1"
```

Linux / 容器一键下载、授权、运行，并用 crontab 每天自动检查：

```bash
GITHUB_TOKEN_CFOPT="你的 GitHub token" AUTORUN_BACKEND=cron INSTALL_DAILY_AUTORUN=1 bash -c "$(curl -fsSL https://raw.githubusercontent.com/GuardSkill/CFOpt/main/scripts/linux/install-and-run-cfopt-linux.sh)"
```

只手动跑一次：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\windows\Invoke-CFOptAutoPush.ps1" -Force
```

```bash
FORCE=1 ./scripts/linux/invoke-cfopt-auto-push-linux.sh
```

### 输出文件

- `CloudflareSpeedTest_CD.csv`：Windows / 成都测速默认输出。
- `CloudflareSpeedTest_BJ.csv`：Linux / 北京测速默认输出。
- `proxyip-best.txt`：每日从 `https://zip.cm.edu.kg/all.txt` 拉取并按 TCP 连接延迟筛选出的每国 Top 10 ProxyIP，供 Edge Tunnel 订阅生成阶段使用。
- `CFOpt_Subconverter.ini`：Subconverter 配置。
- `CFOpt_Subconverter_lite.ini`：精简版 Subconverter 配置。
- `rules/`：分流规则。

`CFOpt_Subconverter.ini` 和 `CFOpt_Subconverter_lite.ini` 不参与 IP 候选来源、测速、筛选和 CSV 合并逻辑；一般不需要随着测速脚本一起修改。

### 目录结构

- `scripts/windows/Invoke-CFOptAutoPush.ps1`：Windows 自动测速上传脚本。
- `scripts/windows/Install-CFOptAutoPushTask.ps1`：Windows 每日计划任务安装脚本。
- `scripts/linux/invoke-cfopt-auto-push-linux.sh`：Linux 自动测速上传脚本。
- `scripts/linux/install-and-run-cfopt-linux.sh`：Linux 一键下载、授权、运行和安装自动任务脚本。

根目录只保留 README、配置、CSV 和规则文件；脚本统一放在 `scripts/` 下。

### 测速来源

默认候选来源：

```text
https://zip.cm.edu.kg/ip.zip
```

额外候选来源默认开启：

```text
https://zoroaaa.github.io/cf-bestip/ip_*.txt
```

`cf-bestip` 会按地区提供候选，例如 `ip_HK.txt`、`ip_JP.txt`、`ip_SG.txt`、`ip_US.txt`。脚本会按当前端口筛选 `IP:端口#地区-score`，再交给本地 CFST 实测。

`vps789` 的 `cfIpApi.data.CT` 当前返回的电信候选很少，所以默认关闭。需要时手动开启：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\windows\Invoke-CFOptAutoPush.ps1" -Force -EnableVps789Ct
```

```bash
FORCE=1 ENABLE_VPS789_CT=1 ./scripts/linux/invoke-cfopt-auto-push-linux.sh
```

脚本只取 `CT`，不会混入 `CU`、`CM` 或综合组。

### 端口和筛选

默认测速端口：

```text
443,2053,2083,2087,2096,8443
```

默认地区：

```text
HK,JP,KR,SG,PH,VN,MY,KZ,MN,IE,US
```

默认额外重点测速地区：

```text
HK,KR,JP,SG
```

默认 CFST 参数：

```text
-n 80
-t 6
-dn 30
-dt 15
-tl 420
-tlr 0
-sl 0
-p 0
```

默认外层 CFST 任务串行运行：

```text
MaxParallelCfst=1
MAX_PARALLEL_CFST=1
```

最终 CSV 会按地区 / 分组保留 Top 20。

### 无代理测速

CFST 子进程默认不会继承 `HTTP_PROXY`、`HTTPS_PROXY`、`ALL_PROXY` 等代理环境变量，测速结果代表本机到候选 IP 的裸连质量。

如果确实要让 CFST 走代理：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\windows\Invoke-CFOptAutoPush.ps1" -Force -UseProxyForCfst
```

```bash
FORCE=1 USE_PROXY_FOR_CFST=1 ./scripts/linux/invoke-cfopt-auto-push-linux.sh
```

### 城市列格式

城市列会包含国旗、地区、测速位置编号和候选来源，Windows/成都和 Linux/北京两边格式保持一致：`国旗 地区 [位置名称#编号 来源]`。

Windows / 成都测速：

```text
🇭🇰 HK [成都测速#01 ip.zip]
🇭🇰 HK [成都测速#02 cf-bestip]
🇭🇰 HK [成都测速#03 vps789]
```

Linux / 北京测速：

```text
🇭🇰 HK [北京测速#01 ip.zip]
🇯🇵 JP [北京测速#01 cf-bestip]
```

来源可能是：

- `ip.zip`
- `cf-bestip`
- `vps789`
- `previous`：从上一轮已发布 CSV 带回并复测的旧节点。
- `unknown`：历史数据或异常情况下无法识别来源。

### 每日滚动复测

脚本默认每天最多运行一次：

```text
IntervalDays=1
```

每次运行会先下载 GitHub 上当前目标 CSV，把旧节点重新加入 CFST 输入进行复测。最终每个地区执行滚动保鲜：

- 本轮不达标的旧节点会被淘汰。
- 每个地区最多保留约 2/3 旧节点。
- 至少约 1/3 位置优先由本轮新测出的最佳候选补入。
- 如果新候选不足，才继续用达标旧节点补满。

默认替换比例：

```text
0.33
```

### 调参

提高下载测速数量和时间：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\windows\Invoke-CFOptAutoPush.ps1" -Force -CfstDownloadTestCount 100 -CfstDownloadTestTime 20 -CfstLossRateLimit 0
```

```bash
FORCE=1 CFST_DOWNLOAD_TEST_COUNT=100 CFST_DOWNLOAD_TEST_TIME=20 CFST_LOSS_RATE_LIMIT=0 ./scripts/linux/invoke-cfopt-auto-push-linux.sh
```

如果下载速度全是 `0.00 MB/s`，开启调试：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\windows\Invoke-CFOptAutoPush.ps1" -Force -CfstDebug
```

```bash
FORCE=1 CFST_DEBUG=1 ./scripts/linux/invoke-cfopt-auto-push-linux.sh
```

### 自动任务

Windows：

```powershell
cd H:\Projects\CFOpt
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\windows\Install-CFOptAutoPushTask.ps1"
```

Linux 容器：

```bash
GITHUB_TOKEN_CFOPT="你的 GitHub token" AUTORUN_BACKEND=cron bash -c "$(curl -fsSL https://raw.githubusercontent.com/GuardSkill/CFOpt/main/scripts/linux/install-and-run-cfopt-linux.sh)"
```

默认每天 `04:00` 检查并运行。

---

## English

CFOpt automatically benchmarks Cloudflare candidate IPs, filters unstable results, generates Edge Tunnel compatible CSV files, and uploads them to GitHub.

### Quick Start

Windows first run and daily task:

```powershell
git clone https://github.com/GuardSkill/CFOpt.git H:\Projects\CFOpt
cd H:\Projects\CFOpt
[Environment]::SetEnvironmentVariable("GITHUB_TOKEN_CFOPT", "your GitHub token", "User")
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\windows\Invoke-CFOptAutoPush.ps1" -Force
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\windows\Install-CFOptAutoPushTask.ps1"
```

Linux / container bootstrap with cron:

```bash
GITHUB_TOKEN_CFOPT="your GitHub token" AUTORUN_BACKEND=cron INSTALL_DAILY_AUTORUN=1 bash -c "$(curl -fsSL https://raw.githubusercontent.com/GuardSkill/CFOpt/main/scripts/linux/install-and-run-cfopt-linux.sh)"
```

### Outputs

- `CloudflareSpeedTest_CD.csv`: default Windows / Chengdu output.
- `CloudflareSpeedTest_BJ.csv`: default Linux / Beijing output.
- `proxyip-best.txt`: daily per-country Top 10 ProxyIP list selected from `https://zip.cm.edu.kg/all.txt` by TCP connect latency for Edge Tunnel subscription generation.
- `CFOpt_Subconverter.ini`: Subconverter config.
- `CFOpt_Subconverter_lite.ini`: lite Subconverter config.
- `rules/`: routing rules.

The Subconverter configs are not part of candidate collection, benchmarking, filtering, or CSV merging, so they usually do not need changes when the benchmark scripts change.

### Candidate Sources

Default source:

```text
https://zip.cm.edu.kg/ip.zip
```

Extra source enabled by default:

```text
https://zoroaaa.github.io/cf-bestip/ip_*.txt
```

`vps789` CT candidates are disabled by default because the API currently returns very few usable entries. Enable it manually with `-EnableVps789Ct` on Windows or `ENABLE_VPS789_CT=1` on Linux.

### Ports and Filters

Default ports:

```text
443,2053,2083,2087,2096,8443
```

Default CFST parameters:

```text
-n 80
-t 6
-dn 30
-dt 15
-tl 420
-tlr 0
-sl 0
-p 0
```

The final CSV keeps the Top 20 rows per region/group.

### Direct, Non-Proxy Benchmarking

CFST child processes do not inherit proxy environment variables by default. This keeps benchmark results representative of direct connectivity from the host to candidate IPs.

To intentionally benchmark through a proxy, use `-UseProxyForCfst` on Windows or `USE_PROXY_FOR_CFST=1` on Linux.

### City Column

The city column includes the country flag, region, location index, and source:

```text
🇭🇰 HK [成都测速#01 ip.zip]
🇭🇰 HK [成都测速#02 cf-bestip]
🇭🇰 HK [成都测速#03 vps789]
🇭🇰 HK [成都测速#04 previous]
```

Possible sources are `ip.zip`, `cf-bestip`, `vps789`, `previous`, and `unknown`.

### Rolling Retest

Each run fetches the current published CSV, retests old nodes, removes failing nodes, keeps at most about two thirds old nodes per group, and fills the rest with the best newly tested candidates. The default replacement fraction is `0.33`.

### Debugging

If every download speed is `0.00 MB/s`, enable CFST debug output:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\windows\Invoke-CFOptAutoPush.ps1" -Force -CfstDebug
```

```bash
FORCE=1 CFST_DEBUG=1 ./scripts/linux/invoke-cfopt-auto-push-linux.sh
```
