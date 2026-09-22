# CFOpt

## 中文说明

CFOpt 是一个 Cloudflare 优选 IP 自动测速与发布工具。它会下载候选 IP，按多个 Cloudflare 端口运行 `CloudflareSpeedTest`，过滤不可用、丢包和低速结果，然后生成 Edge Tunnel 可导入的 CSV 并上传到 GitHub。

### 当前自动化方式

仓库使用 [Update CFOpt CSVs](./.github/workflows/update-csv.yml) 统一调度两个 self-hosted runner：

| Runner | 实际线路 | 输出 | 标签 |
| --- | --- | --- | --- |
| 成都 Windows | 自动识别中国电信/中国移动 | `CTC_CD.csv` 或 `CMCC_CD.csv` | `self-hosted, Windows, X64, cfopt, chengdu` |
| 北京 Linux / UCloud | UCloud 地址段、CMCC 出口 | `CMCC_BJ.csv` | `self-hosted, Linux, X64, cfopt, beijing` |
| 四川 Windows（待部署） | 德阳中国移动 | `CMCC_SC.csv` | `self-hosted, Windows, X64, cfopt, sichuan, cmcc` |

四川配置使用独立的 [Update Sichuan CMCC CSV](./.github/workflows/update-sc-csv.yml)，目前仅手动触发，待朋友的 runner 安装并验证后再启用定时调度。首次成功测速后才生成 `CMCC_SC.csv`，不会复制成都结果冒充四川新测结果。

给 Windows 用户的 EXE 服务安装包可用 `scripts/windows/Build-RunnerInstaller.ps1` 构建，详见 [安装包使用说明](docs/windows-runner-installer.md)。安装包需要临时 runner 注册令牌，不包含个人 GitHub Token。

workflow 每天北京时间 `04:00` 触发，也可在 GitHub 的 **Actions → Update CFOpt CSVs → Run workflow** 中选择双端、仅成都或仅北京。每个 job 使用仓库内置的短期 `GITHUB_TOKEN` 发布，不需要在 runner 保存个人令牌。完整安装、迁移与验证步骤见 [Self-hosted runner 部署指南](docs/runner-deployment.md)。

只手动执行一次测速脚本：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\windows\Invoke-CFOptAutoPush.ps1" -Force -AutoDetectNetworkIsp
```

```bash
GITHUB_TOKEN_CFOPT="你的 GitHub token" FORCE=1 TARGET_PATH=CMCC_BJ.csv ./scripts/linux/invoke-cfopt-auto-push-linux.sh
```

### 输出文件

- `CTC_CD.csv`：Windows / 成都电信测速输出。
- `CMCC_CD.csv`：Windows / 成都移动测速输出。
- `CMCC_SC.csv`：四川移动配置，首个测点为德阳；待该测点首次成功发布后生成。
- `CMCC_BJ.csv`：Linux / 北京移动（UCloud 地址段、CMCC 出口）测速输出。
- `proxyip-best.txt`：每日从 `https://zip.cm.edu.kg/all.txt` 拉取，完成 TLS/HTTP 可用性验证后按响应延迟筛选出的 ProxyIP，默认每国 Top 10，HK 默认 Top 50，供 Edge Tunnel 订阅生成阶段继续筛选使用。
- `CFOpt_Subconverter.ini`：Subconverter 配置。
- `CFOpt_Subconverter_lite.ini`：精简版 Subconverter 配置。
- `CFOpt_Subconverter_lite_cmliussss.ini`：面向 CMLiussss / `asdlokj1qpi233/subconverter` 后端的精简配置，`ruleset=` 数量控制在默认上限 64 以下。
- `rules/`：分流规则。

订阅转换配置文件使用本仓库的 raw 地址：

```text
https://raw.githubusercontent.com/GuardSkill/CFOpt/main/CFOpt_Subconverter.ini
https://raw.githubusercontent.com/GuardSkill/CFOpt/main/CFOpt_Subconverter_lite.ini
https://raw.githubusercontent.com/GuardSkill/CFOpt/main/CFOpt_Subconverter_lite_cmliussss.ini
```

CMLiussss 后端推荐填写 `CFOpt_Subconverter_lite_cmliussss.ini`，避免旧 `lite.ini` URL 被后端缓存后继续回落默认模板。

`CFOpt_Subconverter*.ini` 不参与 IP 候选来源、测速、筛选和 CSV 合并逻辑；一般不需要随着测速脚本一起修改。

### 仓库结构与文件职责

```text
CFOpt/
├─ .github/workflows/        GitHub Actions 调度入口
├─ rules/                    Subconverter 分流规则
├─ scripts/
│  ├─ windows/               成都 Windows 测速、发布及旧计划任务兼容脚本
│  ├─ linux/                 北京 Linux 测速、发布及旧 cron/systemd 兼容脚本
│  ├─ adaptive_pool.py       热前缀、自适应候选池和滚动保留辅助逻辑
│  └─ generate_proxyip_best.py  ProxyIP 探测和排序
├─ tests/                    Windows、Linux 和配置回归测试
├─ docs/
│  ├─ runner-deployment.md   新 runner 部署、迁移和故障排查
│  ├─ benchmarks/            已完成的性能验证记录
│  └─ superpowers/           历史设计与实施记录，不参与运行
├─ CTC_CD.csv                成都电信发布结果
├─ CMCC_CD.csv               成都移动发布结果
├─ CMCC_BJ.csv               北京移动发布结果
├─ proxyip-best.txt          Edge Tunnel 使用的 ProxyIP 排名
├─ CFOpt_Subconverter.ini    完整订阅转换配置
├─ CFOpt_Subconverter_lite.ini  精简订阅转换配置
└─ CFOpt_Subconverter_lite_cmliussss.ini  CMLiussss 后端兼容配置
```

运行关系是：workflow 选择 runner → runner checkout 当前 `main` → 下载 CFST → 调用对应平台脚本 → 脚本拉取候选并测速 → 通过 GitHub Contents API 原子更新目标 CSV。`rules/` 和三份 Subconverter 配置只负责消费结果与分流，不参与测速。

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

默认还会从 `https://ip.164746.xyz/ipTop10.html` 获取由 `cf-speed-dns` 预筛的 Top 10 候选。该来源只加入 `443` 端口的 `JP` 重点范围，进入本地 TCP 粗筛和 CFST 后才可能发布，来源标记为 `ip164746`。Windows 可用 `-EnableIp164746:$false` 关闭，Linux 可用 `ENABLE_IP164746=0` 关闭；URL、数量和归属范围可分别通过 `Ip164746Url` / `IP164746_URL`、`Ip164746Limit` / `IP164746_LIMIT`、`Ip164746Country` / `IP164746_COUNTRY` 覆盖。

默认还会读取 `gslege/CloudflareIP` 的 `JP/SG/US/DE/NL.txt`，每个地区最多取前 20 个种子，仅加入 `443` 端口并由本机重新测速，来源标记为 `gslege`。Windows 可用 `-EnableGslegeCloudflareIp:$false`，Linux 可用 `ENABLE_GSLEGE_CLOUDFLAREIP=0` 关闭。

Windows 和 Linux 流程都会对所有地区进行独立热前缀挖掘：从上一轮优胜节点、`cf-bestip`、`gslege` 和 `ip164746` 种子中，按“地区+端口”学习活跃 `/24`；每池最多使用 4 个前缀，每个前缀按日期轮换生成 4 个新地址，再进入本机 TCP 粗筛和 CFST。它不是重复使用成品 IP，而是在优胜网段内持续探索新地址，来源标记为 `hot-mine`。Windows 使用 `EnableHotPrefixMining` 等参数，Linux 使用对应的 `ENABLE_HOT_PREFIX_MINING`、`HOT_PREFIX_SAMPLES` 和 `HOT_PREFIX_MAX_PREFIXES_PER_COUNTRY_PORT` 环境变量。

Windows 和 Linux 流程还会从电信入口候选段分层抽样，默认包括 `104.16.0.0/13`、`104.24.0.0/14`、`172.64.0.0/13` 以及 WARP/Tunnel/合作段中指定的 `/24`。每段默认轮换抽取 32 个 IPv4，并在 `443/2053/2083/2087/2096/8443` 每个已配置端口测试一次；不按 focus 重复，来源为 `ct-pool`。这只验证其作为 CF TLS/下载入口的实际表现，不启用 IPv6 或 7844 专用协议测试。通过 `EnableCtEntryPool`、`CtEntryCidrs` 和 `CtEntrySamplesPerCidr` 配置。

Windows 的 `CandidatePoolMode=adaptive` 与 Linux 的 `CANDIDATE_POOL_MODE=adaptive` 默认启用：地区工作项优先使用 `cf-bestip + gslege + ip164746 + hot-mine`，历史节点由独立任务全量复测；当某个地区/端口不足 20 个候选时自动用 `ip.zip` 补齐，避免冷门地区断档。`hybrid` 保留全部新候选来源，`legacy` 用于回归对照。成都 443 等量 A/B（各 320 个输入、各下载测试 40 个）中，旧池没有节点达到 5 MB/s，自适应池有 11 个达到 5 MB/s，最高 NRT 127.61 MB/s、SIN 38.46 MB/s。

无国家标签的补充源包括 [CMLiu 移动优选 IPv4](https://cf.090227.xyz/cmcc)、[RIPEstat AS13335](https://stat.ripe.net/data/announced-prefixes/data.json?resource=AS13335) 和 [RIPEstat AS209242](https://stat.ripe.net/data/announced-prefixes/data.json?resource=AS209242)。先从各 ASN 均匀抽样最多 96 个 IPv4 前缀、每日轮换地址并做 TCP 粗筛；然后 `scripts/channel_latency_pool.py` 对新旧渠道分别用 CFST 只测延迟，新渠道使用 HTTPing 请求 BestCF `/ip.json` 获取数据中心码来归国，旧渠道保留原有国家来源信息。按「渠道 × 国家」跨所有端口统一选择延迟前 20 个，加入相应国家的工作项；无法识别国家的新节点不会发布。第二阶段 CFST 只测 TCP 延迟和丢包，再由 `scripts/bestcf_probe.py` 对每个工作项延迟前 15 个请求同一候选域名的 `/ip.json` 与 `/__down`，确认最终 Colo/国家并测量下载速度。历史已发布节点仍会全部复测。Windows 可设置 `GenericPoolMaxPrefixes`、`GenericPoolTopPerSource`（TCP 粗筛上限）、`ChannelLatencyTopPerCountry`；Linux 对应 `GENERIC_POOL_MAX_PREFIXES`、`GENERIC_POOL_TOP_PER_SOURCE`、`CHANNEL_LATENCY_TOP_PER_COUNTRY`。Windows 需要 `python` 命令可用，Linux 需要 `python3`。

最终地区以同一候选 `/ip.json` 返回的 Cloudflare Colo 为准，例如 `NRT/KIX→JP`、`SIN→SG`、`HKG→HK`、`ICN→KR`、`FRA/TXL→DE`、`LHR→GB`、`AMS→NL`、`LAX/SJC/SEA→US`。上一轮节点也按 Colo 重新归类后参与热前缀学习和发布保护，避免把 `SIN` 节点沿用为 `JP/GB`。DE、HK、KR 默认分别使用 3、2、3 倍热前缀探索预算，Windows 可通过 `HotPrefixCountryMultipliers`、Linux 可通过 `HOT_PREFIX_COUNTRY_MULTIPLIERS` 调整。

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
HK,TW,JP,KR,SG,PH,VN,MY,KZ,MN,IE,US
```

默认额外重点测速地区：

```text
SG,HK,TW,JP,KR,US,DE,GB
```

默认 CFST 延迟阶段参数：

```text
-n 80
-t 2
-dd
-tl 420
-tlr 0
-sl 0
-p 0
```

下载阶段默认对普通与重点工作项的延迟前 15 个节点并发请求 20 MB 的同源 `/__down`，单节点最多 4 秒；历史工作项全部复测。仍可通过 `CfstDownloadTestCount` / `FocusCfstDownloadTestCount`、`CfstDownloadTestTime` / `FocusCfstDownloadTestTime` 或对应 Linux 环境变量覆盖。

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
- `ip164746`：`ip.164746.xyz/ipTop10.html` 的预筛候选，仅用于 JP/443。
- `gslege`：`gslege/CloudflareIP` 的地区预筛种子，仅用于 443。
- `hot-mine`：按地区和端口从优胜 `/24` 中轮换生成、由成都本机发现的新候选。
- `ct-pool`：从电信入口候选 CIDR 分层抽样并进行多端口 TLS/下载验证。

### 每日滚动复测

脚本默认每天最多运行一次：

```text
IntervalDays=1
```

每次运行会先下载 GitHub 上当前目标 CSV，把旧节点重新加入 CFST 输入进行复测。最终每个地区执行滚动保鲜：

- 本轮不达标的旧节点会被淘汰。
- 最终每个国家/地区最多保留 20 个、尽量至少保留 10 个，不区分新旧节点。先应用正常下载速度门槛；不足 10 个时，从本轮延迟和丢包达标的同地区节点中按延迟从低到高补足，补位节点允许下载速度为 0。Windows 可通过 `MinNodesPerCountry`、Linux 可通过 `MIN_NODES_PER_COUNTRY` 调整保底数量。
- 如果本轮连延迟合格的候选也不足 10 个，则只发布实际可用的数量；不会恢复本轮未返回结果的历史节点，也不会伪造节点。
- 发布安全阈值按整份 CSV 的总量判断，防止整机网络波动造成全局异常缩水；单个地区可以正常清除大批已过期节点。

### 调参

Windows 和 Linux 默认会在 CFST 延迟测试前做一次本机 TCP 粗筛。只有候选数超过 120 的工作项才会粗筛；连接超时为 800ms，并发数为 128，每个地区和来源最多保留 30 个新候选。上一轮节点会进入独立的 `previous` 工作项，并由 BestCF 阶段全部下载复测；这样旧节点必须在本轮重新通过延迟、丢包和下载测试才能发布。

默认启用 BestCF 同源测速：候选 IP 被编码为专属测试域名，先请求 `/ip.json` 确认 Colo/国家，再请求同一域名的 `/__down?bytes=20000000` 流式计速。详细结果写入工作目录的 `bestcf-probe-diagnostics.csv`，其中会分别标记 `http_error`、`timeout`、`dns_error`、`tls_error`、`no_data` 和有实际响应数据但未达到门槛的 `low_speed`，并列出渠道预判与最终确认国家的差异。无法通过 `/ip.json` 确认身份的节点不会进入发布保底；已经确认国家但下载失败的节点仍可按低延迟规则补位。可用 Windows `EnableBestCfProbe` / Linux `ENABLE_BESTCF_PROBE` 关闭并退回 CFST 内置下载模式；测速域后缀可通过 `BestCfProbeHostSuffix` / `BESTCF_PROBE_HOST_SUFFIX` 覆盖。

临时关闭粗筛或调整参数：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\windows\Invoke-CFOptAutoPush.ps1" -Force -TcpPrecheckEnabled $false
```

```bash
FORCE=1 TCP_PRECHECK_ENABLED=0 ./scripts/linux/invoke-cfopt-auto-push-linux.sh
```

可调参数为 `TcpPrecheckMinCandidates` / `TCP_PRECHECK_MIN_CANDIDATES`、`TcpPrecheckTimeoutMs` / `TCP_PRECHECK_TIMEOUT_MS`、`TcpPrecheckThreads` / `TCP_PRECHECK_THREADS` 和 `TcpPrecheckMaxCandidates` / `TCP_PRECHECK_MAX_CANDIDATES`。

提高下载测速数量和时间：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\windows\Invoke-CFOptAutoPush.ps1" -Force -CfstDownloadTestCount 100 -CfstDownloadTestTime 20 -CfstLossRateLimit 0
```

```bash
FORCE=1 CFST_DOWNLOAD_TEST_COUNT=100 CFST_DOWNLOAD_TEST_TIME=20 CFST_LOSS_RATE_LIMIT=0 ./scripts/linux/invoke-cfopt-auto-push-linux.sh
```

如果下载测速失败或全是 `0.00 MB/s`，先查看工作目录中的 `bestcf-probe-diagnostics.csv`；它会列出 HTTP 状态、失败分类、实际接收字节和已确认的 Colo/国家。需要继续检查前置延迟阶段时再开启 CFST 调试：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\windows\Invoke-CFOptAutoPush.ps1" -Force -CfstDebug
```

```bash
FORCE=1 CFST_DEBUG=1 ./scripts/linux/invoke-cfopt-auto-push-linux.sh
```

### 自动任务

GitHub Actions / self-hosted runner（推荐）：

- `.github/workflows/update-csv.yml` 每天北京时间 `04:00` 调度成都 Windows 与北京 Linux runner。
- Windows runner 自动识别当前直连运营商，并发布 `CTC_CD.csv` 或 `CMCC_CD.csv`。
- 北京 UCloud runner 发布 `CMCC_BJ.csv`。
- workflow 使用仓库内置的短期 `GITHUB_TOKEN`，不需要在 runner 上保存个人令牌。
- Actions runner 必须分别注册到 `GuardSkill/CFOpt`，并带有标准的 `self-hosted/windows/x64` 或 `self-hosted/linux/x64` 标签。

迁移到 Actions runner 并验证首次发布后，应停用旧的 Windows 计划任务和 Linux cron，避免重复测速。

以下方式仅为不使用 Actions 时的兼容方案，不要与 self-hosted runner 同时启用。

旧 Windows 计划任务：

```powershell
cd H:\Projects\CFOpt
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\windows\Install-CFOptAutoPushTask.ps1"
```

Windows 任务使用禁用系统代理的公网探针识别当前直连运营商：中国移动写入 `CMCC_CD.csv`，中国电信写入 `CTC_CD.csv`。两种线路使用独立的成功时间状态；探针冲突、未知运营商或无法识别时停止发布，避免覆盖错误的 CSV。仅检测、不测速可运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\windows\Invoke-CFOptAutoPush.ps1" -DetectNetworkIspOnly
```

旧 Linux cron/systemd：

```bash
GITHUB_TOKEN_CFOPT="你的 GitHub token" AUTORUN_BACKEND=cron bash -c "$(curl -fsSL https://raw.githubusercontent.com/GuardSkill/CFOpt/main/scripts/linux/install-and-run-cfopt-linux.sh)"
```

旧任务默认每天约 `03:30` 检查并运行。

---

### 国家下载速度下限

默认的国家下载速度下限为 `JP=10,US=2,KR=3,HK=2,DE=5,GB=3,SG=5`。TW 默认不设国家下载速度下限。Windows 使用参数 `CountryMinSpeedMBPerSec`，Linux 使用环境变量 `COUNTRY_MIN_SPEED_MB_PER_SEC`；数值的单位是 CFST 原始 `MB/s`，而不是 Mbps。速度大于等于下限即为达标，脚本优先发布达标节点；仅当该地区不足默认 10 个时，才用本轮延迟、丢包合格的低延迟节点补位，补位节点不要求下载达标。

默认重点测速范围（focus scope）是 `SG,HK,TW,JP,KR,US,DE,GB`；其中 US 与 TW 会作为独立重点范围测速。脚本先按国家和 IP 去重并保留本轮速度最高的测量，再执行国家下限。新旧节点一视同仁。最终 CSV 的城市栏不再显示来源，而显示一位小数的下载速度，例如 `DE [CD#01 13.1MB/s]`。

覆盖 Windows 下限：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\windows\Invoke-CFOptAutoPush.ps1" -Force -CountryMinSpeedMBPerSec "JP=12,US=6,KR=4,HK=3,DE=6,GB=4,SG=6"
```

禁用 Windows 国家下限：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\windows\Invoke-CFOptAutoPush.ps1" -Force -CountryMinSpeedMBPerSec ""
```

覆盖 Linux 下限：

```bash
FORCE=1 COUNTRY_MIN_SPEED_MB_PER_SEC='JP=12,US=6,KR=4,HK=3,DE=6,GB=4,SG=6' ./scripts/linux/invoke-cfopt-auto-push-linux.sh
```

禁用 Linux 国家下限：

```bash
FORCE=1 COUNTRY_MIN_SPEED_MB_PER_SEC='' ./scripts/linux/invoke-cfopt-auto-push-linux.sh
```

默认外层 CFST 并发为单进程（`MaxParallelCfst=1` / `MAX_PARALLEL_CFST=1`），避免同时进行的下载测试占满约 `80 MB/s` 的接入链路；如需提高并发，请结合实际带宽谨慎调整。

## English

CFOpt automatically benchmarks Cloudflare candidate IPs, filters unstable results, generates Edge Tunnel compatible CSV files, and uploads them to GitHub.

### Automation

The recommended setup uses `.github/workflows/update-csv.yml` to dispatch daily jobs to two repository-level self-hosted runners. The Windows runner detects China Telecom or China Mobile and publishes `CTC_CD.csv` or `CMCC_CD.csv`; the Beijing Linux/UCloud runner publishes `CMCC_BJ.csv`. Jobs use the scoped, short-lived Actions token instead of a personal token stored on the host.

See [Self-hosted runner deployment](docs/runner-deployment.md) for registration, migration, verification, legacy-task shutdown, and troubleshooting instructions.

### Outputs

- `CTC_CD.csv`: Windows / Chengdu China Telecom output.
- `CMCC_CD.csv`: Windows / Chengdu China Mobile output.
- `CMCC_BJ.csv`: Linux / Beijing China Mobile output (UCloud address space announced through CMCC).
- `proxyip-best.txt`: daily ProxyIP list selected from `https://zip.cm.edu.kg/all.txt` after TLS/HTTP validation and ranked by response latency for Edge Tunnel subscription generation. Defaults to Top 10 per country, with HK expanded to Top 50 for downstream reachability filtering.
- `CFOpt_Subconverter.ini`: Subconverter config.
- `CFOpt_Subconverter_lite.ini`: lite Subconverter config.
- `CFOpt_Subconverter_lite_cmliussss.ini`: lite config for CMLiussss / `asdlokj1qpi233/subconverter` backends, keeping `ruleset=` entries under the default limit of 64.
- `rules/`: routing rules.

Use this repository's raw URLs as Subconverter config files:

```text
https://raw.githubusercontent.com/GuardSkill/CFOpt/main/CFOpt_Subconverter.ini
https://raw.githubusercontent.com/GuardSkill/CFOpt/main/CFOpt_Subconverter_lite.ini
https://raw.githubusercontent.com/GuardSkill/CFOpt/main/CFOpt_Subconverter_lite_cmliussss.ini
```

For CMLiussss backends, prefer `CFOpt_Subconverter_lite_cmliussss.ini` to avoid stale backend cache for the older `lite.ini` URL.

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

The runners also fetch the pre-ranked Top 10 list from `https://ip.164746.xyz/ipTop10.html`. These candidates are injected only into the `JP` focus scope on port `443`, tagged as `ip164746`, and must still pass the local TCP precheck and CFST benchmark. Disable the source with `-EnableIp164746:$false` on Windows or `ENABLE_IP164746=0` on Linux. The URL, limit, and assigned focus country are configurable through `Ip164746Url` / `IP164746_URL`, `Ip164746Limit` / `IP164746_LIMIT`, and `Ip164746Country` / `IP164746_COUNTRY`.

The runners also load the first 20 seeds per country from `gslege/CloudflareIP` for `JP/SG/US/DE/NL`. They are injected only on port `443`, tagged as `gslege`, and re-benchmarked locally. Disable with `-EnableGslegeCloudflareIp:$false` or `ENABLE_GSLEGE_CLOUDFLAREIP=0`.

`vps789` CT candidates are disabled by default because the API currently returns very few usable entries. Enable it manually with `-EnableVps789Ct` on Windows or `ENABLE_VPS789_CT=1` on Linux.

### Ports and Filters

Default ports:

```text
443,2053,2083,2087,2096,8443
```

Default CFST latency-stage parameters:

```text
-n 80
-t 2
-dd
-tl 420
-tlr 0
-sl 0
-p 0
```

The download stage probes the 15 lowest-latency candidates in each normal or focus work item through a same-origin 20 MB `/__down` response for up to four seconds per candidate. Historical work items are fully retested. The count and duration remain configurable through the `Cfst*` / `FocusCfst*` parameters or matching Linux environment variables.

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

Possible sources are `ip.zip`, `cf-bestip`, `ip164746`, `gslege`, `vps789`, `previous`, and `unknown`.

### Rolling Retest

Each run fetches the current published CSV and fully retests every old node in a dedicated per-port job. Missing historical rows are never restored. Each country/group keeps at most 20 nodes and, when enough latency-qualified candidates exist, at least 10 regardless of whether they are old or new. The normal speed policy is applied first; a group below 10 is filled by lowest latency from candidates that passed receive, loss, and latency checks, even when their measured download speed is zero. Configure the floor with Windows `MinNodesPerCountry` or Linux `MIN_NODES_PER_COUNTRY`.

The publication safety ratio applies to the total CSV size, protecting against broad probe-host network failures while allowing one expired region to shrink normally.

### TCP Precheck

Windows and Linux perform a local TCP precheck before CFST latency testing. It runs only when a work item has more than 120 candidates, uses an 800ms timeout with 128 concurrent connects, and retains at most 30 new candidates per region/source group. Previous nodes use a separate full-history job and are all download-tested by the BestCF stage, so every retained historical node has a fresh result.

The default is now a same-origin BestCF probe. Each candidate IP is encoded into its own test hostname; `/ip.json` confirms Colo/country and `/__down?bytes=20000000` measures streamed throughput through that same hostname. `bestcf-probe-diagnostics.csv` distinguishes `http_error`, `timeout`, `dns_error`, `tls_error`, `no_data`, and successful transfers that are genuinely below policy as `low_speed`, while also recording source-country versus confirmed-country differences. Candidates whose identity cannot be confirmed by `/ip.json` are ineligible even for the minimum-count fallback; confirmed candidates whose download fails may still fill that fallback by latency. Disable it with Windows `EnableBestCfProbe` or Linux `ENABLE_BESTCF_PROBE` to restore CFST's built-in download mode. Override the service with `BestCfProbeHostSuffix` / `BESTCF_PROBE_HOST_SUFFIX` when using a compatible self-hosted endpoint.

Disable it for one run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\windows\Invoke-CFOptAutoPush.ps1" -Force -TcpPrecheckEnabled $false
```

```bash
FORCE=1 TCP_PRECHECK_ENABLED=0 ./scripts/linux/invoke-cfopt-auto-push-linux.sh
```

The tuning pairs are `TcpPrecheckMinCandidates` / `TCP_PRECHECK_MIN_CANDIDATES`, `TcpPrecheckTimeoutMs` / `TCP_PRECHECK_TIMEOUT_MS`, `TcpPrecheckThreads` / `TCP_PRECHECK_THREADS`, and `TcpPrecheckMaxCandidates` / `TCP_PRECHECK_MAX_CANDIDATES`.

### Debugging

If download tests fail or report zero, inspect `bestcf-probe-diagnostics.csv`. It records a separate status, HTTP response, confirmed country/Colo, transferred byte count, duration, and measured speed for every probed candidate. CFST debug remains useful for the preceding latency stage:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\windows\Invoke-CFOptAutoPush.ps1" -Force -CfstDebug
```

```bash
FORCE=1 CFST_DEBUG=1 ./scripts/linux/invoke-cfopt-auto-push-linux.sh
```

### Country Download Speed Floors

The default country download-speed floors are `JP=10,US=2,KR=3,HK=2,DE=5,GB=3,SG=5`. TW has no country speed floor by default. Use the Windows `CountryMinSpeedMBPerSec` parameter or the Linux `COUNTRY_MIN_SPEED_MB_PER_SEC` environment variable. Values use CFST raw `MB/s`, not Mbps. A value greater than or equal to the floor passes, and passing nodes are preferred. Only when a region has fewer than the default 10 nodes does the runner fill it with the lowest-latency candidates that passed receive, loss, and latency checks, regardless of download speed.

The default focus scope is `SG,HK,TW,JP,KR,US,DE,GB`; TW and US are benchmarked as dedicated focus scopes. The runner first deduplicates each country/IP to its fastest current measurement, then applies the country floor. Old and new candidates compete equally. The final CSV city field shows one-decimal measured speed instead of source, for example `DE [CD#01 13.1MB/s]`.

Override Windows floors:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\windows\Invoke-CFOptAutoPush.ps1" -Force -CountryMinSpeedMBPerSec "JP=12,US=6,KR=4,HK=3,DE=6,GB=4,SG=6"
```

Disable Windows country floors:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\windows\Invoke-CFOptAutoPush.ps1" -Force -CountryMinSpeedMBPerSec ""
```

Override Linux floors:

```bash
FORCE=1 COUNTRY_MIN_SPEED_MB_PER_SEC='JP=12,US=6,KR=4,HK=3,DE=6,GB=4,SG=6' ./scripts/linux/invoke-cfopt-auto-push-linux.sh
```

Disable Linux country floors:

```bash
FORCE=1 COUNTRY_MIN_SPEED_MB_PER_SEC='' ./scripts/linux/invoke-cfopt-auto-push-linux.sh
```

The default outer CFST concurrency is one process (`MaxParallelCfst=1` / `MAX_PARALLEL_CFST=1`). BestCF download probes use four workers by default (`BestCfProbeConcurrency=4` / `BESTCF_PROBE_CONCURRENCY=4`); increase that only when the runner has enough spare bandwidth.
