# OpenResty 代理片段（可直接覆盖）

本目录提供 **已调好路由优先级** 的 Nginx/OpenResty 配置，供 1Panel 站点使用。

> **不要** 仅在 1Panel 面板里点「反向代理」填 `127.0.0.1:8080` 了事——那样 **没有 gRPC**，客户端无法连接。必须把本目录文件 **复制到站点 `proxy/` 目录**（见 [../1panel-openresty.md](../1panel-openresty.md)）。

## 文件说明

| 文件 | 作用 |
|------|------|
| [netbird-server.conf](netbird-server.conf) | **新建**：`/api`、`/oauth2`、WebSocket、`gRPC` → `127.0.0.1:8081` |
| [root.conf](root.conf) | **覆盖**：其余路径 → Dashboard `127.0.0.1:8080`（`location /`，非 `^~ /`） |

默认上游端口与 NetBird 应用安装表单一致：**8080**（Dashboard）、**8081**（Server）。若安装时改了端口，请先编辑本目录两个文件中的 `8080` / `8081` 再复制。

## 一键覆盖（推荐）

将 `YOUR_DOMAIN` 换成 1Panel 网站主域名（与安装 NetBird 时填的 `NETBIRD_DOMAIN` 一致）：

```bash
DOMAIN="netbird.example.com"
PANEL_WWW="/opt/1panel/www"

install -d "${PANEL_WWW}/sites/${DOMAIN}/proxy"
cp -f docs/openresty/proxy/netbird-server.conf "${PANEL_WWW}/sites/${DOMAIN}/proxy/"
cp -f docs/openresty/proxy/root.conf "${PANEL_WWW}/sites/${DOMAIN}/proxy/"

docker exec "$(docker ps --format '{{.Names}}' | grep -i openresty | head -1)" openresty -t \
  && docker exec "$(docker ps --format '{{.Names}}' | grep -i openresty | head -1)" openresty -s reload
```

在仓库根目录执行；若已在别处的克隆目录，把 `docs/openresty/proxy/` 换成实际路径。

## 与 1Panel 面板的关系

| 方式 | 是否可行 |
|------|----------|
| 面板仅添加「网站 → 反向代理 → 根目录 → 8080」 | **不可行**（缺 gRPC / 路径分流） |
| 用本目录文件覆盖 `sites/<域名>/proxy/` | **推荐** |
| 面板「自定义」里手写全部 `location` | 可行，但易错；建议以本目录为准 |

完整步骤（含 `conf.d` 超时、`openresty -t` 验证）：[../1panel-openresty.md](../1panel-openresty.md)。
