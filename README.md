# CFOpt

Cloudflare 优选 IP 自动测速与发布工具。脚本会下载候选 IP，按多个 Cloudflare 端口运行 `CloudflareSpeedTest`，过滤掉不可用、丢包、低速结果，并把 Edge Tunnel 可导入的 CSV 上传到 GitHub。

## 输出文件

- `CloudflareSpeedTest_CD.csv`：Windows/CD 默认输出
- `CloudflareSpeedTest_BJ.csv`：Linux/BJ 默认输出
- `CFOpt_Subconverter.ini`：Subconverter 配置
- `rules/`：分流规则

## 目录结构

- `scripts/windows/Invoke-CFOptAutoPush.ps1`：Windows 自动测速脚本
- `scripts/windows/Install-CFOptAutoPushTask.ps1`：Windows 计划任务安装脚本
- `scripts/linux/invoke-cfopt-auto-push-linux.sh`：Linux 自动测速脚本
- `scripts/linux/install-and-run-cfopt-linux.sh`：Linux 一键下载并运行脚本

根目录不再放重复脚本，只保留配置、README、CSV 和规则。

## 当前测速策略

默认候选来源仍然是：

```text
https://zip.cm.edu.kg/ip.zip
```

脚本默认测试端口：

```text
443,2053,2083,2087,2096,8443
```

为了减少“香港节点测速不充分、实际使用卡顿”的问题，脚本现在做了两层测速：

1. 全地区合并测速：按配置国家/地区一起测。
2. 重点地区单独测速：默认额外对 `HK` 单独跑一轮，避免香港候选被其它地区挤掉。

默认 CFST 参数也比原始默认值更严格：

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

含义：

- `-dn 60`：每个端口/范围下载测速 60 个，不再只测默认 10 个。
- `-dt 15`：单个 IP 下载测速最长 15 秒，减少偶发抖动。
- `-t 6`：延迟测试 6 次，比默认 4 次更稳。
- `-tlr 0`：延迟测速阶段过滤任何丢包。
- `-sl 0.01`：过滤下载速度为 0 的结果。

最终 CSV 仍然会按地区/分组保留 Top 20。

## 手动运行

Windows：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\windows\Invoke-CFOptAutoPush.ps1" -Force
```

Linux：

```bash
FORCE=1 ./scripts/linux/invoke-cfopt-auto-push-linux.sh
```

Linux 一键下载、授权、运行：

```bash
GITHUB_TOKEN_CFOPT="你的 token" bash -c "$(curl -fsSL https://raw.githubusercontent.com/GuardSkill/CFOpt/main/scripts/linux/install-and-run-cfopt-linux.sh)"
```

只生成 CSV，不上传：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\windows\Invoke-CFOptAutoPush.ps1" -Force -SkipUpload
```

```bash
FORCE=1 SKIP_UPLOAD=1 ./scripts/linux/invoke-cfopt-auto-push-linux.sh
```

查看将要运行的命令：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\windows\Invoke-CFOptAutoPush.ps1" -DryRun
```

```bash
DRY_RUN=1 ./scripts/linux/invoke-cfopt-auto-push-linux.sh
```

## 重点地区

默认额外重点测速香港：

```text
HK
```

Windows 修改重点地区：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\windows\Invoke-CFOptAutoPush.ps1" -Force -FocusCountries "HK,SG,JP"
```

Linux 修改重点地区：

```bash
FORCE=1 FOCUS_COUNTRIES_CSV="HK,SG,JP" ./scripts/linux/invoke-cfopt-auto-push-linux.sh
```

## CFST 参数调优

Windows 示例：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\windows\Invoke-CFOptAutoPush.ps1" -Force -CfstDownloadTestCount 100 -CfstDownloadTestTime 20 -CfstLossRateLimit 0
```

Linux 示例：

```bash
FORCE=1 CFST_DOWNLOAD_TEST_COUNT=100 CFST_DOWNLOAD_TEST_TIME=20 CFST_LOSS_RATE_LIMIT=0 ./scripts/linux/invoke-cfopt-auto-push-linux.sh
```

如果所有下载速度都是 `0.00 MB/s`，开启调试：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\windows\Invoke-CFOptAutoPush.ps1" -Force -CfstDebug
```

```bash
FORCE=1 CFST_DEBUG=1 ./scripts/linux/invoke-cfopt-auto-push-linux.sh
```

## vps789

`vps789` 的 `cfIpApi.data.CT` 当前只返回很少的电信候选 IP，所以默认关闭。需要时可以手动开启：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\windows\Invoke-CFOptAutoPush.ps1" -Force -EnableVps789Ct
```

```bash
FORCE=1 ENABLE_VPS789_CT=1 ./scripts/linux/invoke-cfopt-auto-push-linux.sh
```

脚本只取 `CT`，不会混入 `CU`、`CM` 或综合组。

## cf-bestip

`Zoroaaa/cf-bestip` 更适合作为“分地区候选源”：它会按地区输出 Cloudflare Anycast IPv4 候选，例如香港、美国、日本、新加坡等。它比 vps789 当前 5 条 CT 更有参考价值。

但它不应该直接替代本项目的最终测速，因为最终是否流畅取决于你运行脚本的机器/服务器到 Cloudflare 的实时线路。更稳的做法是：

1. 用 `cf-bestip` 作为候选 IP 来源。
2. 保留本项目的 CFST 多端口下载测速。
3. 最终只发布本机/本服务器实测后的 Top 结果。

后续可以把 `cf-bestip` 的分地区文件接入为可选候选源。

## GitHub Token

Windows：

```powershell
[Environment]::SetEnvironmentVariable("GITHUB_TOKEN_CFOPT", "你的 token", "User")
```

Linux：

```bash
export GITHUB_TOKEN_CFOPT="你的 token"
```
