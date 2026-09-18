# 四川移动 Windows EXE 安装包

## 给朋友的步骤

1. 使用 Windows 10/11 x64，先安装 [Git for Windows](https://git-scm.com/download/win)，保留默认 PATH 选项。安装 Git 后重新打开安装器。
2. 双击 `CFOpt-Runner-Setup-SC.exe`，允许管理员权限。此包目前未签名，Windows 可能提示未知发布者；仅使用仓库管理员直接提供并确认来源的文件。
3. 保留自动生成的 runner 名称，填入管理员刚提供的**临时 runner 注册令牌**，点击“安装后台服务”。不要填写个人 GitHub Token，也不需要登录管理员的 GitHub 账号。
4. 等待安装成功后关闭窗口。runner 服务随开机启动，不需要登录 Windows 或保留安装器窗口。
5. 请管理员在 GitHub 触发首次测速；完成并通过安全检查后生成 `CMCC_SC.csv`。测速必须发生在德阳移动线路上，建议不要开启会改变出口的全局 VPN/TUN。

这是联网安装包，不包含官方 runner 大型压缩包；安装时需要访问 GitHub，测速阶段还需要访问候选来源和 CFST 下载地址。仅支持固定的 `GuardSkill/CFOpt` 四川移动配置；后续其他地区需新增配置，不要给机器错误的地区标签。

## 管理员准备

在 `GuardSkill/CFOpt → Settings → Actions → Runners → New self-hosted runner` 选择 Windows x64，将页面中的临时注册令牌发给朋友。该令牌有时效，临近安装时再生成，不提交到仓库。安装器不会嵌入或保存注册令牌，但官方 runner 会保存运行所需的自身凭据，这是正常注册行为。

安装目录为 `C:\ProgramData\CFOpt\runner-sc`，runner 名称默认按机器名生成，标签固定为 `cfopt,sichuan,cmcc`。服务账号为 `NETWORK SERVICE`，仅向它授予该安装目录的修改权限。安装器不覆盖已有 runner，不使用 `--replace`。

在仓库中部署 `.github/workflows/update-sc-csv.yml` 后，选择 **Actions → Update Sichuan CMCC CSV → Run workflow**。当前流程只支持手动测速，**尚未启用每日 04:00 和漏跑补测**；开机运行的是接收任务的 runner 服务，不是连续测速程序。

仓库的 self-hosted workflow 能在朋友电脑执行代码，应仅用于可信代码，并向朋友说明这一权限。安装器无需个人 PAT；发布 CSV 使用每次 job 的短期 `GITHUB_TOKEN`。

## 故障与卸载

- 找不到 Git：安装 Git for Windows 并保留默认“命令行及第三方软件可使用 Git”选项。
- 注册令牌过期或网络下载失败：查看安装器日志，向管理员申请新令牌。为防止误覆盖，非空安装目录会被拒绝；请管理员检查失败的目录后处理，不要删除已有正常 runner。
- 日志位于安装目录的 `_diag` 中。安装器自己的令牌输出会被遮盖，分享任何日志前仍应检查敏感信息。
- 停用时，以管理员权限查看 `Get-Service 'actions.runner.*'` 并停止四川 runner 对应服务。
- 正式移除：在 GitHub 的对应 runner 页面选择 Remove，按 GitHub 给出的临时移除令牌在安装目录执行 `config.cmd remove --token <REMOVE_TOKEN>`，确认服务和注册都已移除，再按需删除这个专用安装目录。

## 从源码编译与验证

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\windows\Build-RunnerInstaller.ps1
dist\CFOpt-Runner-Setup-SC.exe --self-test
Get-FileHash dist\CFOpt-Runner-Setup-SC.exe -Algorithm SHA256
```

编译使用 Windows 自带 .NET Framework 4.x C# 编译器；输出在被 Git 忽略的 `dist/`，安装脚本作为资源嵌入 EXE。自测验证嵌入资源和界面，不会注册 runner 或安装服务。完整服务安装需在实际朋友机器上验证，不应在现有生产 runner 上重复安装。
