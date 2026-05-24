# NetBird for 1Panel

1Panel 本地应用包：一键部署 [NetBird](https://netbird.io/) 自建控制面（嵌入式 IdP + OpenResty 反代）。

## 目录结构

```text
netbird/                 # 复制到 /opt/1panel/resource/apps/local/netbird
reference/golden/        # 官方脚本生成的参考配置
```

## 快速开始

1. 将 `netbird/` 复制到 1Panel `resource/apps/local/`
2. 应用商店 → 更新应用列表 → 安装 NetBird
3. 按 [netbird/README.md](netbird/README.md) 配置 OpenResty 与 `/setup`

## 许可证

应用包为社区维护；NetBird 本身遵循其上游许可证。
