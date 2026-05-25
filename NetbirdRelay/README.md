# NetBird Relay / STUN（1Panel 本地应用）

在**独立公网 VPS** 上仅部署 [NetBird 外部 Relay](https://docs.netbird.io/selfhosted/maintenance/scaling/set-up-external-relays)（`netbirdio/relay` + 内置 STUN），**不**包含 Management、Dashboard、Signal 或数据库。

客户端仍连接主控域名（如 `https://netbird.example.com`）；主控通过 `config.yaml` 下发本节点的 `rels://` 与 `stun:` 地址。

## 架构

```text
主控 VPS（Netbird 应用）          Relay VPS（本应用）
netbird.example.com              relay-cn.example.com
├─ management / signal           ├─ netbirdio/relay (:443 TLS)
├─ dashboard                     └─ STUN UDP 3478（宿主机直连）
└─ 在 config.yaml 登记 ─────────────► rels:// + stun:
```

## 前置条件

| 项目 | 要求 |
|------|------|
| 服务器 | ≥ 1 CPU / 1 GB 内存，公网 IP |
| 域名 | Relay 专用域名解析到本机（如 `relay-cn.example.com`） |
| 防火墙 | **TCP 443**、**UDP 3478**；`letsencrypt_builtin` 模式另需 **TCP 80** |
| 主 NetBird | 已安装并记录 `data/config.yaml` 中的 `authSecret` |
| Docker | Compose v2 |

## 安装步骤

### 1. 放入本地应用目录

```text
/opt/1panel/resource/apps/local/NetbirdRelay
```

执行仓库根目录 `install.sh` 或手动复制 `NetbirdRelay/` 后，在 **应用商店 → 更新应用列表** 安装 **NetBird Relay latest**。

### 2. 填写安装表单

| 字段 | 说明 |
|------|------|
| Relay 公网域名 | 仅主机名，如 `relay-cn.example.com` |
| Relay 认证密钥 | **必填**，与主 NetBird `config.yaml` 的 `authSecret` 完全一致 |
| TLS 模式 | `openresty_cert`（默认）、`letsencrypt_builtin`、`custom_cert` |
| Relay 本机端口 | 默认 `33080`（`openresty_cert` / `custom_cert` 时绑定 `127.0.0.1`） |
| rels:// 对外端口 | 默认 `443` |
| STUN UDP 端口 | 默认 `3478` |

### 3. TLS 模式说明

#### openresty_cert（推荐，配合 1Panel OpenResty）

1. **先**在 1Panel 为 Relay 域名建站并申请 HTTPS。
2. 再安装本应用；`init.sh` 挂载 `www/sites/<域名>/ssl/` 下的 `fullchain.pem` / `privkey.pem`。
3. 将 `data/openresty-relay-stream.conf` 并入 OpenResty **stream** 配置（见 [docs/openresty/relay/](../docs/openresty/relay/README.md)），执行 `openresty -t && openresty -s reload`。

Relay 容器只监听 `127.0.0.1:33080`；公网 **443** 由 OpenResty `ssl_preread` 透传到 relay。

#### letsencrypt_builtin

Relay 容器自行申请证书，占用宿主机 **80/443**。适用于未安装 1Panel OpenResty 的裸 VPS。需填写 Let's Encrypt 邮箱。

#### custom_cert

填写宿主机上的证书与私钥绝对路径，挂载进容器；端口行为同 `openresty_cert`（本机端口 + 可选 stream）。

### 4. 主 NetBird 登记（必做）

安装成功后查看应用数据目录中的 `data/main-server-config-snippet.yaml`，将内容合并到**主控** `config.yaml`：

- 删除或注释 `server.authSecret` 与 `server.stunPorts`（启用外部 relay 后内置 relay/STUN 会关闭）。
- 添加 `stuns` 与 `relays`（多节点时追加多个 `uri` / `addresses`）。
- `relays.secret` 必须与所有 Relay 的 `NB_AUTH_SECRET` 相同。

详细说明见 [Netbird/README.md](../Netbird/README.md#扩展外部-relay--stun)。

重启主控 `netbird-server` 容器后，客户端执行 `netbird status -d` 应显示外部 Relay/STUN 为 Available。

### 5. 验证

```bash
# TLS（404 可接受）
curl -vk "https://relay-cn.example.com/"

# 容器日志
docker logs "${CONTAINER_NAME}"
# 应看到 relay 与 STUN 启动信息
```

## 与主控 HTTP `/relay` 的区别

| 路径 | 服务 |
|------|------|
| 主控 `https://netbird.example.com/relay` | 主 `netbird-server` 的 WebSocket（OpenResty HTTP 反代） |
| `rels://relay-cn.example.com:443` | 独立 `netbirdio/relay`（需 stream 或容器直连 443） |

**勿**将主控的 `netbird-server.conf` 复制到 Relay 节点使用。

## 多区域

每台 Relay 一台 VPS、一个 1Panel 应用实例、一个域名；主控 `config.yaml` 的 `relays.addresses` 与 `stuns` 列出全部节点，**secret 相同**。

## 升级 / 卸载

- 应用商店升级，或运行 `scripts/upgrade.sh` 拉取 `netbirdio/relay:latest` 后重启。
- 卸载默认保留 `data/`；彻底删除：`REMOVE_DATA=1 bash scripts/uninstall.sh`。

## 参考

- [Set Up External Relay Servers](https://docs.netbird.io/selfhosted/maintenance/scaling/set-up-external-relays)
- [Environment Variables](https://docs.netbird.io/selfhosted/environment-variables)
- [OpenResty stream 配置](../docs/openresty/relay/README.md)
