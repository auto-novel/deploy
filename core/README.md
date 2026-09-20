# Core 部署

本目录包含 Core 服务器独立部署所需的初始化脚本和配置副本。

## 首次初始化服务器

在本目录执行：

```bash
SSH_PORT=12345 ./bootstrap.sh
```

脚本会配置软件源和 Docker、Cloudflared、Tailscale 与 nftables，必要时要求完成 Tailscale 登录；随后同步配置并安装、启用 Core 定时服务。

## 日常同步配置

拉取仓库更新后执行：

```bash
./apply.sh
```

该脚本只同步登录环境、主机名、仓库配置文件和 Core 定时服务，不会更新软件包、配置防火墙或触发 Tailscale 登录。
