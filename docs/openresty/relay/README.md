# NetBird 外部 Relay — OpenResty stream 配置（可选）

独立 Relay 使用 `rels://` 协议，**不能**使用主控 HTTP 片段 [`../proxy/netbird-server.conf`](../proxy/netbird-server.conf)。

## 何时需要 stream

安装 **NetBird Relay** 时 TLS 模式为 **`custom_cert`**（默认）：

1. 在表单填写宿主机上的 **证书**、**私钥** 绝对路径（可自行从 1Panel 站点目录复制，例如 `/opt/1panel/www/sites/<域名>/ssl/fullchain.pem`）。
2. Relay 容器只监听 `127.0.0.1:<本机端口>`（默认 `33080`）。
3. 若本机 **443 已由 1Panel OpenResty 占用**，需把 `data/openresty-relay-stream.conf` 放入 OpenResty 的 **stream** 段，将公网 443 **透传**到 relay（`ssl_preread`）。

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
