# CFOpt Subscription Backend

为 Mihomo/Clash 生成动态 VLESS 订阅的轻量后端。它可以：

- 从一个或多个 CFOpt CSV 选择入口 IP；
- 根据请求者运营商和地区选择 CSV；
- 根据 Cloudflare UsagePanel 用量动态分配多个 Host；
- 从远程 subconverter INI 编译规则和策略组；
- 从 `proxyip-best.txt` 生成国家 ProxyIP 链式节点；
- 在可视化后台管理配置和订阅文件名。
- 在独立的“自建节点订阅”页面维护一个或多个 VLESS WS TLS 基础节点：合并配置的 CFOpt CSV，分别从 JP、KR、HK、SG、TW 选出 2 个入口。优先选择下载速度大于配置阈值（默认 10 MB/s）且延迟最低的入口；达标入口不足 2 个时回退为该地区延迟最低的 2 个。
- 自建节点订阅沿用远程 INI 的域名/IP 分流规则，但不复制国家 Pool 或 `url-test`。规则涉及的每个业务组均为手动 `select`，直接提供生成节点和 `DIRECT`；固定槽位名称不包含 IP、延迟或速度，CSV 更新不会因为改名而丢失 Clash 的组选择。
- 将 UsagePanel 请求次数通过 `Subscription-Userinfo` 映射到 Clash Party 的流量卡片；默认 1000 次代表 1 KB，所以 70 万次显示为 700 KB。该数值表示请求额度，不是真实网络流量。
- 新订阅链接使用 `/admin/sub/<token>/<ISP>/<style>` 路径式路由，以兼容只转发 `/admin*` 的反向代理；旧的 `/sub?token=...` 地址仍兼容。

## 镜像

GitHub Actions 在后台代码变化时执行回归测试并发布 linux/amd64 镜像：

```text
ghcr.io/guardskill/cfopt-sub:latest
ghcr.io/guardskill/cfopt-sub:sha-<commit>
```

`latest` 适合手动更新；生产环境建议使用 `sha-...` 标签锁定版本。

## NAS 部署

容器以 UID/GID 1000 非 root 用户运行，根文件系统只读。运行前需要准备 `data/`，其中的 `config.json` 和 `template.json` 属于私密运行数据，不应提交到 Git。

```sh
cd /vol1/1000/cfopt-sub
sudo docker compose -f compose.ghcr.yaml pull
sudo docker compose -f compose.ghcr.yaml up -d
sudo docker compose -f compose.ghcr.yaml ps
```

默认绑定 `192.168.0.122:19090`。复制 `.env.example` 为 `.env` 可修改绑定地址和端口。

登录 `/admin` 后可在左侧切换：

- “动态 EdgeTunnel”：原有 Host 用量、ProxyIP、按运营商 CSV 订阅；
- “自建节点订阅”：填写基础节点名称、UUID、SNI/Host 和 WebSocket Path，配置 CSV、速度阈值、规则地址和文件名，并复制单独的订阅地址。

基础节点原始 `server` 和 `port` 不需要填写，因为订阅生成时会由所选 CF 优选入口替换；TLS 出口域名、UUID 和 WS Path 保持基础节点配置。

升级镜像不会覆盖 `data/`。迁移到另一台设备时，先安全复制现有 `data/` 并保持目录仅管理员可读；不要公开其中的订阅 Token、节点 URI、UsagePanel Cookie 或代理认证。

## GHCR 可见性

`ghcr.io/guardskill/cfopt-sub` 当前为 Public，NAS 可以匿名拉取，不需要 GitHub PAT 或 `docker login`。镜像只包含服务程序，不包含 `data/`、密码、订阅 Token、节点 UUID、UsagePanel Cookie 或代理认证。

发布工作流只监听 `subscription_backend/server.py`、Dockerfile 和工作流自身。它不运行 CFOpt 测速脚本，也不修改 CSV、`proxyip-best.txt` 或现有测速工作流。

## 本地测试

```sh
python -m unittest discover -s subscription_backend -p test_server.py
```

## 安全边界

用量 API 和账户信息成功响应缓存 1 小时，失败后至少等待 5 分钟再尝试；并发请求共用刷新结果。缓存保存在服务进程内，重启会清空。无人请求订阅或管理验证时不会主动轮询。CSV 和规则缓存不受此设置影响。

`.dockerignore` 只允许 `server.py` 和 Dockerfile 进入镜像构建上下文；`.gitignore` 排除 `data/`、配置、访问凭据、生成订阅、备份和探测结果。公网部署时仍应使用 HTTPS，并为 `/admin` 增加额外访问控制。
