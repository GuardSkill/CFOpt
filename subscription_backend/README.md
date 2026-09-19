# CFOpt Subscription Backend

为 Mihomo/Clash 生成动态 VLESS 订阅的轻量后端。它可以：

- 从一个或多个 CFOpt CSV 选择入口 IP；
- 根据请求者运营商和地区选择 CSV；
- 根据 Cloudflare UsagePanel 用量动态分配多个 Host；
- 从远程 subconverter INI 编译规则和策略组；
- 从 `proxyip-best.txt` 生成国家 ProxyIP 链式节点；
- 在可视化后台管理配置和订阅文件名。

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

升级镜像不会覆盖 `data/`。迁移到另一台设备时，先安全复制现有 `data/` 并保持目录仅管理员可读；不要公开其中的订阅 Token、节点 URI、UsagePanel Cookie 或代理认证。

## GHCR 可见性

首次发布后可在 GitHub Packages 设置镜像可见性：

- Public：NAS 可以匿名拉取；
- Private：在 NAS 使用仅授予 `read:packages` 的 PAT 执行 `docker login ghcr.io`。

发布工作流只监听 `subscription_backend/server.py`、Dockerfile 和工作流自身。它不运行 CFOpt 测速脚本，也不修改 CSV、`proxyip-best.txt` 或现有测速工作流。

## 本地测试

```sh
python -m unittest discover -s subscription_backend -p test_server.py
```

## 安全边界

`.dockerignore` 只允许 `server.py` 和 Dockerfile 进入镜像构建上下文；`.gitignore` 排除 `data/`、配置、访问凭据、生成订阅、备份和探测结果。公网部署时仍应使用 HTTPS，并为 `/admin` 增加额外访问控制。
