# NetBird for 1Panel

1Panel 本地应用包：一键部署 [NetBird](https://netbird.io/) 自建控制面（嵌入式 IdP + OpenResty 反代）。

## 目录结构

```text
netbird/                 # 复制到 /opt/1panel/resource/apps/local/netbird
reference/golden/        # 官方脚本生成的参考配置
```

## 快速开始

### 一键安装到 1Panel 本地应用目录

在服务器上执行（需已安装 1Panel，默认路径 `/opt/1panel`）：

```bash
curl -fsSL https://raw.githubusercontent.com/HappyLadySauce/Netbird-for-1panel/main/install.sh | sh
```

也可在 **计划任务** 中新建 Shell 脚本任务，将上述命令或仓库中的 `install.sh` 内容粘贴执行（用户 `root`，宿主机执行，勿勾选「在容器中执行」）。

自定义 1Panel 目录：

```bash
export ONEPANEL_ROOT=/your/1panel/path
sh install.sh
```

### 手动安装

1. 将 `netbird/` 复制到 1Panel `resource/apps/local/`
2. 应用商店 → 更新应用列表 → 安装 NetBird
3. 按 [netbird/README.md](netbird/README.md) 配置 OpenResty 与 `/setup`

## 许可证

应用包为社区维护；NetBird 本身遵循其上游许可证。
