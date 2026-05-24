# NetBird for 1Panel

1Panel 本地应用包：一键部署 [NetBird](https://netbird.io/) 自建控制面（嵌入式 IdP + OpenResty 反代）。

## 目录结构

```text
Netbird/                      # 复制到 /opt/1panel/resource/apps/local/Netbird
docs/
  1panel-openresty.md         # OpenResty 必用手动配置说明（必读）
  proxy/                      # 可直接覆盖到 1Panel 站点的代理文件
reference/golden/             # 官方脚本生成的参考配置
```

## 快速开始

### 1. 安装应用

在服务器上执行（需已安装 1Panel，默认路径 `/opt/1panel`）：

```bash
curl -fsSL https://raw.githubusercontent.com/HappyLadySauce/Netbird-for-1panel/main/install.sh | sh
```

也可在 **计划任务** 中新建 Shell 脚本任务执行上述命令（用户 `root`，宿主机执行，勿勾选「在容器中执行」）。

`install.sh` 会**先删除** `/opt/1panel/resource/apps/local/Netbird`（及旧目录 `netbird`）再写入新文件。若需保留可设：`NETBIRD_INSTALL_SKIP_CLEANUP=1`。

然后在 **应用商店 → 更新应用列表** 中安装 NetBird，并按 [Netbird/README.md](Netbird/README.md) 填写安装表单。

### 2. 配置 OpenResty（必做，不能只在面板里点反代）

![openresty](docs/images/openresty.png)

**不能** 仅在 1Panel 网站面板中添加「反向代理到 8080」。必须将 [docs/proxy/](docs/proxy/) 中的文件复制到站点目录：

```bash
DOMAIN="www.example.com"
cp -f docs/proxy/netbird-server.conf /opt/1panel/www/sites/${DOMAIN}/proxy/
cp -f docs/proxy/root.conf /opt/1panel/www/sites/${DOMAIN}/proxy/
```

完整步骤、验证命令与 `conf.d` 超时配置见：**[docs/1panel-openresty.md](docs/1panel-openresty.md)**。

### 3. 初始化

浏览器访问 `https://<你的域名>/setup` 创建管理员。

## 手动安装应用包

1. 将 `Netbird/` 复制到 1Panel `resource/apps/local/`
2. 应用商店 → 更新应用列表 → 安装 NetBird
3. 按 [docs/1panel-openresty.md](docs/1panel-openresty.md) 配置反向代理

## 许可证

应用包为社区维护；NetBird 本身遵循其上游许可证。
