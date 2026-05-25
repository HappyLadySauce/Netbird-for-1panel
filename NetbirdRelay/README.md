# NetBird Relay / STUN（1Panel 本地应用）

在**独立公网 VPS** 上仅部署 [NetBird 外部 Relay](https://docs.netbird.io/selfhosted/maintenance/scaling/set-up-external-relays)（`netbirdio/relay` + 内置 STUN），**不**包含 Management、Dashboard、Signal 或数据库。

## 安装表单

| 字段 | 说明 |
|------|------|
| Relay 公网域名 | 如 `relay-cn.example.com` |
| Relay 认证密钥 | 与主 NetBird `config.yaml` 的 `authSecret` **完全一致**（支持 base64，可含 `/+=`） |
| TLS 模式 | **`custom_cert`**（默认）：自填证书路径；**`letsencrypt_builtin`**：容器申请证书 |
| TLS 证书 / 私钥路径 | `custom_cert` 时必填，宿主机绝对路径 |
| Relay 容器内端口 | 默认 `33080`（容器内监听） |
| rels:// 对外端口 | 默认 `443`（宿主机 TCP 映射并写入 `rels://` URL） |
| STUN UDP | 默认 `3478` |

### custom_cert（默认）

1. 准备证书与私钥文件（例如从 1Panel 网站 SSL 目录复制路径）：
   - `/opt/1panel/www/sites/<域名>/ssl/fullchain.pem`
   - `/opt/1panel/www/sites/<域名>/ssl/privkey.pem`
2. 安装本应用，在表单中填写上述路径。
3. **Docker 会直接暴露** `rels://` 中的公网 TCP 端口（例如 `1443:33080`）。防火墙需放行该 TCP 端口与 STUN UDP。
4. **若公网端口已被占用**（如 443 被 OpenResty 占用）：将「对外端口」改为可用端口（如 `1443`），勿与 OpenResty 同时监听同一端口。
5. **可选 OpenResty stream**：仅当需要由 OpenResty 做 TLS 透传且不让 Docker 占用该公网端口时使用 `data/openresty-relay-stream.conf`（见 [docs/openresty/relay/](../docs/openresty/relay/README.md)）；公网端口与容器端口不一致时，会额外映射 `127.0.0.1:<容器端口>` 供 stream 后端使用。

### letsencrypt_builtin

Relay 容器自行申请 Let's Encrypt，占用宿主机 **80/443**。填写 LE 邮箱即可，无需证书路径。适用于无 OpenResty 的裸 VPS。

## 主 NetBird 登记

安装后查看 `data/main-server-config-snippet.yaml`，合并到主控 `config.yaml`（删除 `authSecret` / `stunPorts`，添加 `stuns` / `relays`）。详见 [Netbird/README.md](../Netbird/README.md#扩展外部-relay--stun)。

## 与主控 `/relay` 的区别

| 路径 | 用途 |
|------|------|
| 主控 `https://.../relay` | 主 `netbird-server` WebSocket |
| `rels://relay.example.com:443` | 独立 `netbirdio/relay` |

勿将主控 `netbird-server.conf` 用于 Relay 域名。

## 参考

- [Set Up External Relay Servers](https://docs.netbird.io/selfhosted/maintenance/scaling/set-up-external-relays)
- [OpenResty stream（可选）](../docs/openresty/relay/README.md)
