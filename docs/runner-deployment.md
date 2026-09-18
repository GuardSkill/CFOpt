# CFOpt self-hosted runner 部署指南

## 1. 架构

GitHub Actions 只负责调度，测速实际发生在自己的机器上：

| 位置 | 平台 | Workflow job | 输出 |
| --- | --- | --- | --- |
| 成都 | Windows x64 | `windows-cd` | 自动识别后写入 `CTC_CD.csv` 或 `CMCC_CD.csv` |
| 北京 | Linux x64 | `linux-bj` | `CMCC_BJ.csv` |

两个 job 由 `.github/workflows/update-csv.yml` 定义。workflow 会下载当前 CFST Windows/Linux x64 版本，运行仓库脚本，并用本次 Actions job 的短期 `GITHUB_TOKEN` 更新 CSV。runner 本机不需要保存 GitHub PAT。

## 2. 前置条件

### 四川移动配置（德阳测点，待部署）

新机器使用独立 runner 名称（例如 `cfopt-sc-deyang`），注册标签设为 `cfopt,sichuan,cmcc`，不要设置 `chengdu` 或 `beijing`。Windows 安装方式与下文成都步骤相同，替换名称、标签和工作目录即可。

首次测试选择 **Actions → Update Sichuan CMCC CSV → Run workflow**。该流程先检查直连线路必须为中国移动，再以 `DY` 测点标记发布到 `CMCC_SC.csv`；原有三个 CSV 不受影响。目前不启用该配置的定时调度，以免未安装 runner 时产生排队任务。

Windows EXE 安装器源码与构建脚本已提供，见 [EXE 安装步骤](windows-runner-installer.md)。漏跑补测尚未实现。注册令牌仍由仓库管理员临时提供，不向朋友分发个人 PAT。

- runner 只注册到 `GuardSkill/CFOpt`，不要继续注册到旧的 `GuardSkill/CFIP`。
- runner 能访问 GitHub、CFST release、候选来源和下载测速地址。
- Windows 需要 PowerShell 5.1、Git 和可写的工作盘。
- Linux 需要 Bash、Git、curl、tar、Python 3 和常用 GNU 工具。
- 只把 self-hosted runner 用于可信仓库；workflow 能在该机器执行代码。

## 3. 获取注册命令

打开 GitHub 仓库：

1. 进入 **Settings → Actions → Runners**。
2. 选择 **New self-hosted runner**。
3. 选择对应操作系统和 `x64`。
4. 使用页面当时生成的下载地址和短期 registration token。

registration token 有时效，不能写入脚本、README、日志或提交到仓库。

## 4. 成都 Windows runner

建议使用独立目录和工作目录，例如：

```powershell
New-Item -ItemType Directory -Force C:\actions-runner-cfopt
New-Item -ItemType Directory -Force H:\ActionsWork\CFOpt
Set-Location C:\actions-runner-cfopt
```

按 GitHub 页面给出的命令下载并解压 runner。以管理员 PowerShell 注册为系统服务是最稳定的方式：

```powershell
.\config.cmd --unattended `
  --url https://github.com/GuardSkill/CFOpt `
  --token <REGISTRATION_TOKEN> `
  --name Win3080-CFOpt `
  --work H:\ActionsWork\CFOpt `
  --labels cfopt,chengdu `
  --replace `
  --runasservice `
  --windowslogonaccount "NT AUTHORITY\NETWORK SERVICE"
```

确认服务已运行：

```powershell
Get-Service 'actions.runner.*'
```

如果当前没有管理员权限，去掉 `--runasservice` 和 `--windowslogonaccount` 后注册，并先运行 `.\run.cmd` 验证；长期运行时应改为服务，或创建“用户登录时”启动且隐藏窗口的计划任务。

Windows job 会调用：

```powershell
scripts\windows\Invoke-CFOptAutoPush.ps1 -Force -AutoDetectNetworkIsp
```

运营商识别成功时，中国电信发布到 `CTC_CD.csv`，中国移动发布到 `CMCC_CD.csv`；无法识别或探针冲突时拒绝发布。

## 5. 北京 Linux / UCloud runner

按 GitHub 页面给出的命令下载并解压到独立目录，例如 `/opt/actions-runner-cfopt`，然后注册：

```bash
./config.sh --unattended \
  --url https://github.com/GuardSkill/CFOpt \
  --token '<REGISTRATION_TOKEN>' \
  --name 'cfopt-bj' \
  --work '_work' \
  --labels 'cfopt,beijing,cmcc' \
  --replace
```

普通 Linux 主机使用 systemd 服务：

```bash
sudo ./svc.sh install
sudo ./svc.sh start
sudo ./svc.sh status
```

容器内没有 systemd 时，可由容器 entrypoint、supervisor 或其他进程管理器运行 `./run.sh`。不要同时启动多个 `Runner.Listener`。

北京 job 固定设置：

```text
TARGET_PATH=CMCC_BJ.csv
TEST_LOCATION_NAME=BJ
```

## 6. 从 CFIP 迁移已有 runner

先确认旧 runner 当前没有执行 job，再在旧 runner 目录停止进程或服务：

```powershell
# Windows 管理员 PowerShell
Get-Service 'actions.runner.*' | Stop-Service
.\config.cmd remove --token <CFIP_REMOVE_TOKEN>
```

```bash
# Linux
sudo ./svc.sh stop || true
sudo ./svc.sh uninstall || true
./config.sh remove --token '<CFIP_REMOVE_TOKEN>'
```

随后使用第 3 节从 `GuardSkill/CFOpt` 获取的新 registration token，按第 4/5 节重新注册。一个 repository-level runner 同一时间只能属于一个仓库。

## 7. 首次验证

1. 在 **Settings → Actions → Runners** 确认两个 runner 都显示 `Idle`：
   - Windows：`self-hosted`, `Windows`, `X64`
   - Linux：`self-hosted`, `Linux`, `X64`
2. 进入 **Actions → Update CFOpt CSVs → Run workflow**。
3. 先分别选择 `linux-bj` 和 `windows-cd`，便于独立排错；最后可选择 `all`。
4. 检查 job 是否完成候选下载、TCP 预检、CFST、合并、安全检查和上传。
5. 确认提交只更新预期的 CSV，并检查城市列位置标记：北京为 `BJ`，成都电信为 `CD`，成都移动为 `CDCM`。

workflow 使用并发锁 `cfopt-csv-publisher`。两个手动运行同时提交时，后一个会排队，避免 CSV 更新互相覆盖。

## 8. 停用旧的重复测速

只有在新 workflow 至少成功发布一次后再停用旧任务。

Windows：

```powershell
Disable-ScheduledTask -TaskName 'CFOpt Auto Push'
```

Linux：删除旧 crontab 中包含 `invoke-cfopt-auto-push-linux.sh` 的行：

```bash
crontab -l
crontab -e
```

如果曾安装 systemd timer：

```bash
systemctl --user disable --now cfopt-auto-push.timer
```

保留 Actions runner 的启动服务；它只负责等待 GitHub job，不会自行测速。

## 9. 常见故障

- **Job 一直 queued**：目标仓库没有在线且标签匹配的 runner。
- **找不到 CFST**：查看安装步骤；workflow 会递归处理 release 压缩包中的嵌套目录。
- **运营商识别失败**：在 Windows 手动运行 `Invoke-CFOptAutoPush.ps1 -DetectNetworkIspOnly`，确认直连探针没有被系统代理接管。
- **403 发布失败**：确认 workflow 顶层包含 `permissions: contents: write`，仓库 Actions 设置允许写入。
- **non-fast-forward 或并发覆盖**：不要额外启动旧 cron/计划任务；由 workflow 的并发锁统一调度。
- **偶发 DNS/下载失败**：重新运行单个 runner；旧 CSV 在完整成功前不会被替换。
