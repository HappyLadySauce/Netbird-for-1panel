# Traefik（1Panel 本地应用）

在 1Panel 中安装 **Traefik v3.6** 反向代理，通过 **Docker Provider** 自动发现同网络容器上的路由标签，默认与 **1Panel OpenResty** 错开端口（HTTP `8880` / HTTPS `8443`），避免占用 80/443。

## 前置条件

| 项目 | 要求 |
|------|------|
| 1Panel | 已安装 Docker / Compose v2 |
| 网络 | 存在外部网络 `1panel-network`（1Panel 应用默认） |
| 端口 | 安装表单中的端口未被占用 |

## 安装步骤

### 1. 放入本地应用目录

将 `Traefik/` 复制到：

```text
/opt/1panel/resource/apps/local/Traefik
```

在 **应用商店 → 更新应用列表** 后安装 **Traefik 3.6**。

或使用仓库安装脚本（与 NetBird 一并安装）：

```bash
sh install.sh
# 或: PANEL_1PANEL_SOURCE=$(pwd) sh install.sh
```

### 2. 填写安装表单

| 字段 | 说明 |
|------|------|
| Dashboard 监听地址 | 默认 `127.0.0.1`（仅本机）；需 Tailscale/局域网访问填 `0.0.0.0` |
| Dashboard 宿主机端口 | 默认 `8088`（映射容器 `8080`） |
| HTTP 宿主机端口 | 默认 `8880`（勿与 OpenResty 的 80 冲突） |
| HTTPS 宿主机端口 | 默认 `8443`（勿与 OpenResty 的 443 冲突） |
| Dashboard 用户名 | 默认 `admin` |
| Dashboard 密码 | 可留空，由 `init.sh` 自动生成 |
| ACME 邮箱 | 留空关闭 Let's Encrypt；填写则启用 HTTP-01 |

### 3. 访问 Dashboard

```text
http://<监听地址>:<Dashboard端口>/dashboard/
```

默认仅本机：`http://127.0.0.1:8088/dashboard/`。用户名/密码见 `data/credentials.env`（需 Basic Auth）：

```bash
source data/credentials.env
curl -u "${TRAEFIK_DASHBOARD_USER}:${TRAEFIK_DASHBOARD_PASSWORD}" -I "http://127.0.0.1:8088/dashboard/"
```

若要从 Tailscale（如 `100.100.100.10`）访问，安装时把 **Dashboard 监听地址** 设为 `0.0.0.0`，重启应用后再访问。

### 4. 为容器开启路由

```yaml
labels:
  - traefik.enable=true
  - traefik.http.routers.myapp.rule=Host(`app.example.com`)
  - traefik.http.routers.myapp.entrypoints=web
  - traefik.http.services.myapp.loadbalancer.server.port=3000
```

HTTPS + 自动证书（需填写 ACME 邮箱）：

```yaml
  - traefik.http.routers.myapp.entrypoints=websecure
  - traefik.http.routers.myapp.tls.certresolver=letsencrypt
```

## 架构

```text
Internet → :8880 / :8443 (默认)
Traefik (Docker + file provider) → 1panel-network → 带标签的容器
Dashboard → 127.0.0.1:<端口>/dashboard/
```

## 升级 / 卸载

- 升级：1Panel 应用升级或 `scripts/upgrade.sh`
- 卸载：`REMOVE_DATA=1 bash scripts/uninstall.sh` 可删除 `data/`

## 故障排查

| 现象 | 原因 | 处理 |
|------|------|------|
| `client version 1.24 is too old` / `Minimum supported API version is 1.44` | 宿主机 **Docker 29+** 提高了最低 API 版本，旧版 Traefik v3.3 无法连接 Docker | 使用本包 **traefik:v3.6** 镜像；在 1Panel 中升级应用或 `docker compose pull` 后重启 |
| `EntryPoint doesn't exist entryPointName=traefik` | 静态配置未声明 `traefik` 入口（Dashboard 端口 8080） | 重新执行安装/升级触发的 `init.sh`，或于 `data/traefik.yml` 的 `entryPoints` 下加入 `traefik: address: ":8080"` |
| Dashboard `502` / `curl` 无响应 | 8080 路由未就绪，或用非本机 IP 访问但端口只绑在 `127.0.0.1` | 先 `curl -I http://127.0.0.1:8088/dashboard/`（应 `401`）；外网/Tailscale 访问请将监听地址改为 `0.0.0.0` 并重启 |
| `curl 100.x.x.x:8088` 不通 | `ss` 显示 `127.0.0.1:8088` 时，该 IP 无法直连 Dashboard | 用 `127.0.0.1:8088` 或改绑定 `0.0.0.0` |
| 填了密码仍无法登录 | 旧版 `init.sh` 把 `$apr1$` 写成 `$$apr1$$`，哈希无效 | 更新应用包后执行 `bash scripts/init.sh`（会生成 `dynamic/.htpasswd`）并重启 |

**已安装实例快速修复**（在 1Panel 应用目录，如 `/opt/1panel/apps/local/Traefik/Traefik/3.6/`）：

```bash
cd /opt/1panel/apps/local/Traefik/Traefik/3.6   # 路径以面板实际为准
bash scripts/init.sh
docker compose pull && docker compose up -d
```

## 参考

- https://doc.traefik.io/traefik/
- https://doc.traefik.io/traefik/providers/docker/
