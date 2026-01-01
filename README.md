# Deploy 服务器部署手册

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

### 配置防火墙

```bash
# Core
sed -i 's/12345/${PORT}/g' ./linux/etc/nftables.core.conf
cp -n ./linux/etc/nftables.core.conf /etc/nftables.conf
systemctl restart nftable

# Shield
sed -i 's/12345/${PORT}/g' ./linux/etc/nftables.shd.conf
cp -n ./linux/etc/nftables.shd.conf /etc/nftables.conf
systemctl restart nftable
```

## 部署 Shield

```bash
./setup.sh shield
```

部署服务：

- [Status](https://github.com/auto-novel/status)

## 部署 Core

```bash
./setup.sh core
make install-service
```

部署服务：

- [Monitor](https://github.com/auto-novel/monitor)
- [Auth](https://github.com/auto-novel/auth)
- [AutoNovel](https://github.com/auto-novel/auto-novel)

## 运维

备份 auto-novel:

```bash
rsync -avhzP core:/root/auto-novel/data/files-extra ./
rsync -avhzP core:/root/auto-novel/data/files-wenku ./
rsync -avhzP core:/root/auto-novel/data/db.backup ./
```
