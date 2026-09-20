# Shield 部署

本目录包含 Shield 服务器独立部署所需的初始化脚本和配置。

## 初始化服务器

在本目录执行，参数为服务器主机名：

```bash
./setup.sh shield
```

脚本会配置登录环境、Docker、Cloudflared 和 Tailscale。

## 配置防火墙

将 SSH 端口替换为实际端口后，安装 Shield 防火墙规则：

```bash
sed -i "s/12345/${PORT}/g" ./linux/etc/nftables.conf
cp -n ./linux/etc/nftables.conf /etc/nftables.conf
systemctl restart nftables
```
