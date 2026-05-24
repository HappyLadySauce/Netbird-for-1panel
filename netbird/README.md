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

将整个 `netbird` 文件夹复制到 1Panel 本地应用路径（默认）：

```text
/opt/1panel/resource/apps/local/netbird
```

在 **应用商店 → 更新应用列表** 后安装 **NetBird 0.71.4**。

### 2. 填写安装表单

| 字段 | 说明 |
|------|------|
| 公网域名 | 仅主机名，不要带 `https://` |
| Dashboard 本机端口 | 默认 `8080`，绑定 `127.0.0.1` |
| 管理/API 本机端口 | 默认 `8081`，绑定 `127.0.0.1` |
| STUN UDP 端口 | 默认 `3478` |
| 加密密钥 | 可留空，由 `init.sh` 自动生成 |

### 3. 配置 1Panel 网站（OpenResty）

1. **网站** → 创建站点 → 主域名填写安装时的 `NETBIRD_DOMAIN`
2. 申请 **HTTPS** 证书（Let's Encrypt）
3. 打开站点 **配置** → **自定义** / **OpenResty 配置**，追加反代规则

安装完成后，应用数据目录会生成：

```text
<应用安装路径>/data/openresty-snippet.conf
```

将其中 `location` 块粘贴到站点的 `server { ... }` 内（与 1Panel 自动生成的 SSL 块并存）。

**要点**：必须包含 **gRPC** 路径（`/management.ManagementService/`、`/signalexchange.SignalExchange/`），否则客户端无法注册。

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
| `port is already allocated` | 在 1Panel 中**删除失败的 netbird 应用实例**（会触发卸载脚本），或执行 `docker rm -f <容器名> <容器名>-server`；安装表单改用未占用端口（默认 **8080 / 8081**） |
| 拉取镜像超时 | 在 1Panel / Docker 中配置 **镜像加速**（默认从 `docker.io` 拉取 `netbirdio/*:latest`） |
| init 成功但启动失败 | 勿重复点安装；先删除失败实例，更新本地应用包后重试 |

**说明**：1Panel 在「启动失败」时不会自动回滚，需手动删除失败的应用条目。新版 `init.sh` 会在安装前**清理同名残留容器**并**检测端口占用**，冲突时直接失败，避免拉取镜像后再报错。

## 参考

- [NetBird 文档](https://docs.netbird.io/selfhosted/selfhosted-quickstart)
- [1Panel 自助创建应用](https://bbs.fit2cloud.com/t/topic/7409)
- 金样配置：`reference/golden/`（由官方 `getting-started.sh` 生成）

## 后续版本（未包含）

- NetBird Proxy / CrowdSec
- 外部 IdP（Auth0、Zitadel 等）
