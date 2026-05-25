# 1Panel / OpenResty 反向代理配置

NetBird 自建控制面 **不能** 只在 1Panel 面板里配置「网站 → 反向代理 → 127.0.0.1:8080」。  
面板 UI **不支持** 配置 gRPC，也无法正确拆分 `/api`、`/oauth2`、Signal/Management 等路径，客户端会无法注册。

**必须** 在宿主机上手动维护 OpenResty 配置文件。本项目已提供可直接使用的片段：

| 仓库路径 | 复制到 1Panel（宿主机） |
|----------|-------------------------|
| [proxy/netbird-server.conf](proxy/netbird-server.conf) | `/opt/1panel/www/sites/<你的域名>/proxy/netbird-server.conf`（**新建**） |
| [proxy/root.conf](proxy/root.conf) | `/opt/1panel/www/sites/<你的域名>/proxy/root.conf`（**覆盖**） |

详细说明与一键命令见：[proxy/README.md](proxy/README.md)。

---

## 配置前准备

| 项目 | 说明 |
|------|------|
| 站点域名 | 与安装 NetBird 时 `NETBIRD_DOMAIN` 一致，如 `netbird.example.com` |
| Dashboard | 默认 `127.0.0.1:8080` |
| Server（API / gRPC / OAuth2） | 默认 `127.0.0.1:8081` |
| HTTPS | 在 1Panel **网站** 中照常申请证书（可用 443） |
| UDP 3478 | 防火墙放行 STUN，**不经过** Nginx |

若安装表单使用了非默认端口，请先改 [proxy/](proxy/) 内文件中的 `8080` / `8081`，再复制覆盖。

---

## 推荐流程（3 步）

### 1. 在 1Panel 创建网站（仅基础项）

- **网站** → 创建站点 → 域名 = `NETBIRD_DOMAIN`
- 申请 **HTTPS** / Let's Encrypt（可用默认 443）
- **不要** 依赖面板「反向代理」向导代替下文文件；最多用于生成站点目录结构

### 2. 覆盖 `proxy/` 目录（必做）

在服务器上（仓库克隆目录或下载压缩包均可）：

```bash
DOMAIN="netbird.example.com"   # 改成你的域名
PANEL_WWW="/opt/1panel/www"    # 1Panel 默认；安装路径不同请自行修改

install -d "${PANEL_WWW}/sites/${DOMAIN}/proxy"
cp -f docs/openresty/proxy/netbird-server.conf "${PANEL_WWW}/sites/${DOMAIN}/proxy/"
cp -f docs/openresty/proxy/root.conf "${PANEL_WWW}/sites/${DOMAIN}/proxy/"
```

即：**新建** `netbird-server.conf`，**覆盖** `root.conf`，内容与仓库 [proxy/](proxy/) 一致即可生效。

### 3. 主站点 `conf.d` 增加长连接超时（建议）

**文件**：`/opt/1panel/www/conf.d/<你的域名>.conf`  
在 `include /www/sites/<域名>/proxy/*.conf;` **之前** 加入：

```nginx
client_header_timeout 1d;
client_body_timeout 1d;
```

可在 1Panel → 网站 → **配置文件** 中编辑保存；保存后执行重载（见下文）。

---

## 文件与路由说明

### `proxy/netbird-server.conf`（新建）

| 路径 | 协议 | 上游 |
|------|------|------|
| `/relay*`、`/ws-proxy/*` | WebSocket | `http://127.0.0.1:8081` |
| `/signalexchange.SignalExchange/*`、`/management.ManagementService/*` | **gRPC** | `grpc://127.0.0.1:8081` |
| `/api/*`、`/oauth2/*` | HTTP | `http://127.0.0.1:8081` |

参考：[NetBird 外部反向代理文档](https://docs.netbird.io/selfhosted/external-reverse-proxy)

### `proxy/root.conf`（覆盖）

| 项目 | 要求 |
|------|------|
| `location` | 必须为 `location /`，**不能** 使用 `location ^~ /` |
| 上游 | `http://127.0.0.1:8080`（Dashboard） |

**原因**：`^~ /` 会优先匹配所有路径，导致 `netbird-server.conf` 中的 `/api`、`gRPC` 等规则失效。

### 路由示意

```text
https://<域名>
        │
        ▼ OpenResty (443/80)
        ├─ /api, /oauth2, /relay, /ws-proxy, gRPC → 127.0.0.1:8081
        └─ 其余路径 → 127.0.0.1:8080 (Dashboard)
```

OpenResty 容器一般为 `network_mode: host`，宿主机路径：

- `/opt/1panel/www/conf.d/` → 容器 `conf.d`
- `/opt/1panel/www/sites/<域名>/proxy/` → 站点代理片段

---

## 重载与验证

```bash
OR=$(docker ps --format '{{.Names}}' | grep -i openresty | head -1)
docker exec "$OR" openresty -t
docker exec "$OR" openresty -s reload

curl -sk "https://<你的域名>/oauth2/.well-known/openid-configuration" | head
curl -sk -o /dev/null -w '%{http_code}\n' "https://<你的域名>/api/instance"
```

站点日志：`/opt/1panel/www/sites/<域名>/log/`

浏览器访问：`https://<你的域名>/setup` 创建首个管理员。

---

## 为何不能只用面板？

| 1Panel 面板操作 | 结果 |
|-----------------|------|
| 只配根路径反代到 8080 | Dashboard 可开，**Agent 无法连接**（无 gRPC） |
| 在「自定义」里随便粘贴几段 | 易漏路径或 `location` 优先级错误 |
| **使用 [proxy/](proxy/) 覆盖** | 与官方外部反代要求一致，**推荐** |

安装应用后生成的 `data/openresty-snippet.conf` 仅作参考；**以本仓库 `docs/openresty/proxy/` 为准**。

---

## 回滚

1. 删除 `sites/<域名>/proxy/netbird-server.conf`
2. 从 1Panel 备份或重新生成 `proxy/root.conf`（恢复面板默认根反代）
3. 删除 `conf.d` 中两行 `client_*_timeout`（可选）
4. `openresty -t && openresty -s reload`

---

## 相关文档

- 应用安装：[../../Netbird/README.md](../../Netbird/README.md)
- 代理文件目录：[proxy/README.md](proxy/README.md)
