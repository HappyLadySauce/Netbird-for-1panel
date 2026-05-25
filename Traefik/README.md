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

在 **应用商店 → 更新应用列表** 后安装 **Traefik 3.3.4**。

或使用仓库安装脚本（与 NetBird 一并安装）：

```bash
sh install.sh
# 或: PANEL_1PANEL_SOURCE=$(pwd) sh install.sh
```

### 2. 填写安装表单

| 字段 | 说明 |
|------|------|
| Dashboard 本机端口 | 默认 `8088`，仅 `127.0.0.1` |
| HTTP 宿主机端口 | 默认 `8880`（勿与 OpenResty 的 80 冲突） |
| HTTPS 宿主机端口 | 默认 `8443`（勿与 OpenResty 的 443 冲突） |
| Dashboard 用户名 | 默认 `admin` |
| Dashboard 密码 | 可留空，由 `init.sh` 自动生成 |
| ACME 邮箱 | 留空关闭 Let's Encrypt；填写则启用 HTTP-01 |

### 3. 访问 Dashboard

```text
http://127.0.0.1:<Dashboard端口>/dashboard/
```

用户名/密码见 `data/credentials.env`。

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
| Dashboard `502` | 上述两项未修复时，8080 上无有效路由 | 修好配置并 `docker restart <容器名>`；访问 `http://127.0.0.1:<Dashboard端口>/dashboard/`（账号见 `data/credentials.env`） |

**已安装实例快速修复**（在 1Panel 应用目录，如 `/opt/1panel/apps/local/Traefik/Traefik/3.3.4/`）：

```bash
cd /opt/1panel/apps/local/Traefik/Traefik/3.3.4   # 路径以面板实际为准
bash scripts/init.sh
docker compose pull && docker compose up -d
```

## 参考

- https://doc.traefik.io/traefik/
- https://doc.traefik.io/traefik/providers/docker/
