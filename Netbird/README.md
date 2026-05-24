# NetBird（1Panel 本地应用）

在 1Panel 中安装 **NetBird 自建控制面**（combined 架构：`netbird-server` + `dashboard`），通过 **1Panel OpenResty** 提供 HTTPS 与 gRPC 反代。安装后使用嵌入式 Dex，在 `/setup` 创建首个管理员。

> 本应用**不包含** NetBird 客户端；客户端请另装或使用官方安装包。

## 前置条件

| 项目 | 要求 |
|------|------|
| 服务器 | ≥ 1 CPU / 2 GB 内存 |
| 域名 | 公网域名已解析到本机（如 `netbird.example.com`） |
| 防火墙 | 放行 **TCP 80、443**，**UDP 3478**（STUN） |
| 1Panel | 已安装 OpenResty（网站模块） |
| Docker | Compose v2 |

## 安装步骤

### 1. 放入本地应用目录

将整个 `Netbird` 文件夹复制到 1Panel 本地应用路径（默认）：

```text
/opt/1panel/resource/apps/local/Netbird
```

在 **应用商店 → 更新应用列表** 后安装 **NetBird latest**。

### 2. 填写安装表单

| 字段 | 说明 |
|------|------|
| 公网域名 | 仅主机名，不要带 `https://` |
| Dashboard 本机端口 | 默认 `8080`，绑定 `127.0.0.1` |
| 管理/API 本机端口 | 默认 `8081`，绑定 `127.0.0.1` |
| STUN UDP 端口 | 默认 `3478` |
| 加密密钥 | 可留空，由 `init.sh` 自动生成 |

### 3. 配置 1Panel 网站（OpenResty）— 必须手动改文件

> **警告**：不能只在 1Panel 面板里配置「网站 → 反向代理 → 127.0.0.1:8080」。面板 **无法配置 gRPC**，客户端将无法连接。

请按仓库文档操作（推荐直接覆盖代理文件）：

1. **网站** → 创建站点 → 主域名 = 安装时的 `NETBIRD_DOMAIN`，并申请 **HTTPS**
2. 将仓库 **[docs/proxy/](../docs/proxy/)** 复制到 1Panel 站点目录（**覆盖** `root.conf`，**新建** `netbird-server.conf`）：

```bash
DOMAIN="<你的域名>"
cp -f docs/proxy/netbird-server.conf /opt/1panel/www/sites/${DOMAIN}/proxy/
cp -f docs/proxy/root.conf /opt/1panel/www/sites/${DOMAIN}/proxy/
```

3. 按 **[docs/1panel-openresty.md](../docs/1panel-openresty.md)** 补充 `conf.d` 超时、执行 `openresty -t` 与验证

安装后 `data/openresty-snippet.conf` 仅供参考；**以 `docs/proxy/` 为准**。

### 4. 初始化管理员

浏览器访问：

```text
https://<你的域名>/setup
```

创建首个账号（仅在没有用户时可访问）。

### 5. 验证

```bash
curl -sk "https://<你的域名>/oauth2/.well-known/openid-configuration" | head
```

应返回 JSON。也可在安装日志中查看 `init.sh` 输出。

## 架构说明

```text
Internet :443 / UDP 3478
    ↓
1Panel OpenResty (TLS + gRPC)
    ↓ 127.0.0.1:8080        ↓ 127.0.0.1:8081
dashboard 容器              netbird-server 容器
```

与官方 [Self-Hosting Quickstart](https://docs.netbird.io/selfhosted/selfhosted-quickstart) 的 **外部 Nginx/手动反代** 模式一致，**未**使用内置 Traefik（避免与 1Panel 占用 443 冲突）。

## 升级

在 1Panel 中执行应用升级，或进入版本目录运行 `scripts/upgrade.sh` 拉取镜像。重大版本请参考 [官方升级文档](https://docs.netbird.io/selfhosted/maintenance/update)。

## 卸载

卸载应用后，`data/` 目录可能仍保留 SQLite 与密钥；需彻底删除请手动清理应用数据目录。

在应用设置中卸载时会执行 `uninstall.sh`，停止容器并释放端口。若需连数据一起删除，可在宿主机应用目录执行：`REMOVE_DATA=1 bash scripts/uninstall.sh`。

## 安装失败排查

| 现象 | 处理 |
|------|------|
| 代理未运行；NetBird 首次启动会拉 GeoLite2 并因此 **FATL 退出**。应用已默认 `NB_DISABLE_GEOLOCATION=true`（关闭地理位置 posture，不影响组网）。若需 GeoIP：关掉容器代理或手动放入 MMDB，见 [官方说明](https://docs.netbird.io/selfhosted/geo-support) |
| `port is already allocated` | 在 1Panel 中**删除失败的 netbird 应用实例**（会触发卸载脚本），或执行 `docker rm -f <容器名> <容器名>-server`；安装表单改用未占用端口（默认 **8080 / 8081**） |
| 拉取镜像超时 | 在 1Panel / Docker 中配置 **镜像加速**（默认从 `docker.io` 拉取 `netbirdio/*:latest`） |
| init 成功但启动失败 | 勿重复点安装；先删除失败实例，更新本地应用包后重试 |

**说明**：1Panel 在「启动失败」时不会自动回滚，需手动删除失败的应用条目。新版 `init.sh` 会在安装前**清理同名残留容器**并**检测端口占用**，冲突时直接失败，避免拉取镜像后再报错。

## 参考

- **[1Panel OpenResty 配置（必读）](../docs/1panel-openresty.md)**
- **[docs/proxy/ 可覆盖的代理文件](../docs/proxy/README.md)**
- [NetBird 文档](https://docs.netbird.io/selfhosted/selfhosted-quickstart)
- [1Panel 自助创建应用](https://bbs.fit2cloud.com/t/topic/7409)
- 金样配置：`reference/golden/`（由官方 `getting-started.sh` 生成）

## 后续版本（未包含）

- NetBird Proxy / CrowdSec
- 外部 IdP（Auth0、Zitadel 等）
