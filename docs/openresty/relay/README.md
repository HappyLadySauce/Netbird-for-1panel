# NetBird 外部 Relay — OpenResty stream 配置（可选）

独立 Relay 使用 `rels://` 协议，**不能**使用主控 HTTP 片段 [`../proxy/netbird-server.conf`](../proxy/netbird-server.conf)。

## 何时需要 stream

安装 **NetBird Relay** 时 TLS 模式为 **`custom_cert`**（默认）：

1. 在表单填写宿主机上的 **证书**、**私钥** 绝对路径（可自行从 1Panel 站点目录复制，例如 `/opt/1panel/www/sites/<域名>/ssl/fullchain.pem`）。
2. **默认**：Docker 将表单中的 Relay TCP 端口 1:1 暴露（如 `1443:1443`），无需 OpenResty 即可从公网访问 Relay。
3. **仅当** 希望由 OpenResty 占用对外端口、且不让 Docker 绑定该端口时：把 `data/openresty-relay-stream.conf` 放入 OpenResty **stream** 段，并避免与 Docker 映射同一公网端口。

若使用 **`letsencrypt_builtin`**，relay 容器直接占用 80/443，一般**不需要** stream 配置。

## stream 配置位置

OpenResty 主配置需有 `stream { ... }`，例如：

```text
/opt/1panel/openresty/nginx/conf/stream.d/netbird-relay.conf
```

安装后应用会生成带真实域名与端口的 `data/openresty-relay-stream.conf`，也可参考本目录 `relay-stream.conf` 模板。

## 验证

```bash
curl -vk "https://<relay-domain>/"
```

TLS 成功即可（`404` 正常）。STUN 为 **UDP 3478**，由 Docker 映射，不经 OpenResty。

## 主控登记

见 [NetbirdRelay/README.md](../../../NetbirdRelay/README.md)。
