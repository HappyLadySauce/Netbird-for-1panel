# NetBird 外部 Relay — OpenResty stream 配置

独立 Relay 节点使用 `rels://` 协议，**不能**使用主控面的 HTTP 反代片段 [`../proxy/netbird-server.conf`](../proxy/netbird-server.conf)（其中的 `/relay` 是给主 `netbird-server` 用的）。

## 推荐方式（openresty_cert）

1. 在 Relay VPS 的 1Panel 为 Relay 域名创建网站并申请 HTTPS（证书在 `www/sites/<域名>/ssl/`）。
2. 安装 **NetBird Relay** 应用（TLS 模式 `openresty_cert`），`init.sh` 会把证书挂载进 relay 容器。
3. 将应用生成的 `data/openresty-relay-stream.conf`（或本目录 `relay-stream.conf` 替换占位符后）放入 OpenResty 的 **stream** 配置并 reload。

## stream 块示例

OpenResty 主配置需有 `stream { ... }` 段。可把生成的配置放到例如：

```text
/opt/1panel/openresty/nginx/conf/stream.d/netbird-relay.conf
```

并在 `nginx.conf` 的 `stream` 中 `include` 该文件。

## 验证

```bash
curl -vk "https://relay-cn.example.com/"
```

TLS 握手成功即可（返回 `404` 属正常，见 [官方文档](https://docs.netbird.io/selfhosted/maintenance/scaling/set-up-external-relays)）。

STUN 使用 **UDP 3478**，由 Docker 直接映射，不经 OpenResty。

## 主控登记

在主 NetBird 的 `config.yaml` 增加 `stuns` / `relays`，并与所有 Relay 节点共用同一 `NB_AUTH_SECRET`。详见 [NetbirdRelay/README.md](../../../NetbirdRelay/README.md) 与 [Netbird/README.md](../../../Netbird/README.md)。
