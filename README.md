# Deploy

[![GPL-3.0](https://img.shields.io/github/license/auto-novel/deploy)](https://github.com/auto-novel/deploy#license)

## 配置服务器

### 安装 Debian OS

```shell
curl -O https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh || wget -O reinstall.sh $_
bash reinstall.sh debian 12 --password "password"
```

```shell
apt update
apt upgrade
apt install vim
```

### 关闭 ssh 密码登录

```shell
shuf -i 10000-60000 -n 1 # 生成随机端口

vim /etc/ssh/sshd_config
# Port 47679
# PasswordAuthentication no

systemctl restart sshd
```

使用以下命令测试：

```shell
ssh xxx -o PubkeyAuthentication=no -o PreferredAuthentications=password
```

## 部署 Shield

### 运行配置脚本

```bash
./setup.sh shield

# 配置防火墙
cp -n ./etc/nftables.conf /etc/nftables.conf
systemctl restart nftable
```

# 启动服务

- [Status](https://github.com/auto-novel/status)

## 部署 Core

### 运行配置脚本

```bash
./setup.sh core

# 配置防火墙
cp -n ./etc/nftables.conf /etc/nftables.conf
systemctl restart nftable
```

### 安装 ES 插件

```bash
cd auto-novel
mkdir -p data/es/plugins
chmod 777 -R data/es/plugins
chmod 777 -R data/es/data
docker run --rm -it --entrypoint bash -v ${PWD}/data/es/plugins:/usr/share/elasticsearch/plugins elasticsearch:8.6.1

# In container
bin/elasticsearch-plugin install analysis-icu
```

### 启动网站

```bash
cd auto-novel
vim docker-compose.yml
vim .env
docker-compose up -d
```

使用以下命令测试：

```bash
curl http://127.0.0.1
```

### 配置运维脚本

```bash
cp -n ./etc/systemd/system/auto-novel-updater.service /etc/systemd/system/auto-novel-updater.service
cp -n ./etc/systemd/system/auto-novel-updater.timer /etc/systemd/system/auto-novel-updater.timer
systemctl enable auto-novel-updater.timer
systemctl start auto-novel-updater.timer
```
