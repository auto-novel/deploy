# Deploy 服务器部署手册

[![GPL-3.0](https://img.shields.io/github/license/auto-novel/deploy)](https://github.com/auto-novel/deploy#license)

该项目是 AutoNovel 服务器部署手册，网站架构如下：

![网站架构图](https://raw.githubusercontent.com/auto-novel/deploy/refs/heads/main/image/arch.png)

## 配置服务器

### 安装 Debian OS

```shell
curl -O https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh || wget -O reinstall.sh $_
bash reinstall.sh debian 12 --password "password"
```

```shell
apt-get update
apt-get upgrade -y
apt-get install -y vim ca-certificates curl gnupg
```

### 关闭 ssh 密码登录

```shell
shuf -i 10000-60000 -n 1 # 生成随机端口

vim /etc/ssh/sshd_config
# Port 12345
# PasswordAuthentication no

systemctl restart sshd
```

使用以下命令测试：

```shell
ssh xxx -o PubkeyAuthentication=no -o PreferredAuthentications=password
```

## 部署 Shield

`host-shield` 目录包含 Shield 服务器独立部署所需的初始化脚本和配置。

首次初始化会配置软件源、Docker、Cloudflared、Tailscale 与 nftables；如有需要，脚本会要求完成 Tailscale 登录，随后同步配置：

```bash
(cd host-shield && SSH_PORT=12345 ./bootstrap.sh)
```

日常同步配置只会同步登录环境和仓库配置文件，不会更新软件包、配置防火墙或触发 Tailscale 登录：

```bash
(cd host-shield && ./apply.sh)
```

部署服务：

- [Status](https://github.com/auto-novel/status)

## 部署 Core

`host-core` 目录包含 Core 服务器独立部署所需的初始化脚本和配置副本。

首次初始化会配置软件源、Docker、Cloudflared、Tailscale 与 nftables；如有需要，脚本会要求完成 Tailscale 登录，随后同步配置并安装、启用 Core 定时服务：

```bash
(cd host-core && SSH_PORT=12345 ./bootstrap.sh)
```

部署服务：

- [Monitor](https://github.com/auto-novel/monitor)
- [Auth](https://github.com/auto-novel/auth)
- [AutoNovel](https://github.com/auto-novel/auto-novel)

Core 的 `bootstrap.sh` 会启用一个每日自动升级任务，按顺序更新 `auto-novel`、`auth` 和 `monitor`。
三个项目应分别部署在 `/root/auto-novel`、`/root/auth` 和 `/root/monitor`，并在项目根目录提供 Docker Compose 配置。
升级任务默认在每天 04:00 后的 30 分钟内随机执行；某个项目更新失败不会阻止其余项目更新，随后会清理未使用的 Docker 镜像，但任务会以失败状态结束。

查看定时任务和最近一次升级日志：

```bash
systemctl list-timers update-apps.timer
journalctl -u update-apps.service -n 100
```

拉取本仓库更新后的日常配置同步不需要重新安装依赖。Core 的同步只会同步登录环境、仓库配置文件和 Core 定时服务，不会更新软件包、配置防火墙或触发 Tailscale 登录：

```bash
(cd host-core && ./apply.sh)
```

## 更新防火墙

普通 `apply.sh` 不修改防火墙。首次初始化通过 `SSH_PORT` 指定实际的 SSH 监听端口，成功应用后会保存到 `/etc/default/deploy-firewall`（仅保存端口数字），以后更新规则无需重复指定：

```bash
# 按主机选择 host-core 或 host-shield
(cd host-core && ./apply.sh --firewall)

# SSH 端口变更时显式覆盖；此操作不会修改 sshd 配置
(cd host-core && SSH_PORT=23456 ./apply.sh --firewall)
```

更新前会运行 `nft -c` 校验，随后以一个事务替换本项目管理的表，写入 `/etc/nftables.conf` 并启用开机加载。不会重启 nftables 服务，也不会清空 Docker/Tailscale 的规则。语法校验不保证 SSH 可达；目前没有自动回滚，请保留现有 SSH 会话，并通过新连接确认，必要时使用服务器控制台恢复。

**旧版 Core 迁移注意：** 新规则使用 `inet core_filter` 表；旧版的 `inet filter` 表不会自动删除。首次迁移应在控制台检查旧表，在确认它仅属于本项目后删除，否则两套规则会同时生效，旧规则可能继续拦截新放行的端口。

## 图片构建

`script/r2.py` 将 `archive/` 中的静态图片压缩为 WebP，输出到 `dist/`，文件名带内容 hash：

```bash
pip install -r script/requirements.txt
python3 script/r2.py
```

输出目录和压缩参数在脚本开头的常量中修改，脚本不接受命令行参数。

## 运维

在本地通过 SSH 更新单个服务：

```bash
# 更新 auth
ssh core 'cd /root/auth && git pull --ff-only && docker compose pull && docker compose up -d'

# 更新 forum
ssh core 'cd /root/forum && git pull --ff-only && docker compose pull && docker compose up -d'

# 更新 auto-novel
ssh core 'cd /root/auto-novel && git pull --ff-only && docker compose pull && docker compose up -d'
```

在本地通过 SSH 重新应用 Core 配置：

```bash
ssh core 'cd /root/deploy && git pull --ff-only && (cd host-core && ./apply.sh)'
```

备份 auto-novel:

```bash
rsync -avhzP core:/root/auto-novel/data/files-extra ./
rsync -avhzP core:/root/auto-novel/data/files-wenku ./
rsync -avhzP core:/root/auto-novel/data/db.backup ./
```
