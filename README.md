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

### 配置登录显示

```shell
> /etc/motd     # 清空默认的今日消息
```

> https://github.com/yboetz/motd

### 配置 bashrc

修改hostname

```shell
hostname xxx
```

覆盖 bashrc

```shell
# ~/.bashrc: executed by bash(1) for non-login shells.

PS1='\[\e[35;1m\][\u@core \[\e[94;1m\]\w\[\e[35;1m\]]\$\[\e[m\] '

export LS_OPTIONS='--color=auto'
eval "$(dircolors)"
alias ls='ls $LS_OPTIONS'
alias ll='ls $LS_OPTIONS -l'
alias l='ls $LS_OPTIONS -lA'

alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'
```

### 配置防火墙

注意要改 ssh 的端口号

```
#!/usr/sbin/nft -f

flush ruleset

table inet filter {
        chain input {
                type filter hook input priority 0; policy drop;
                ct state invalid counter drop comment "early drop of invalid packets"
                ct state {established, related} counter accept comment "accept all connections related to connections made by us"
                iif lo accept comment "accept loopback"
                iif != lo ip daddr 127.0.0.1/8 counter drop comment "drop connections to loopback not coming from loopback"
                iif != lo ip6 daddr ::1/128 counter drop comment "drop connections to loopback not coming from loopback"
                ip protocol icmp counter accept comment "accept all ICMP types"
                meta l4proto ipv6-icmp counter accept comment "accept all ICMP types"
                udp dport mdns ip daddr 224.0.0.251 counter accept comment "IPv4 mDNS"
                udp dport mdns ip6 daddr ff02::fb counter accept comment "IPv6 mDNS"
                tcp dport 47679 counter accept comment "accept SSH"
                counter comment "count dropped packets"
        }

        chain forward {
                type filter hook forward priority 0; policy accept;
        }

        chain postrouting {
                type nat hook postrouting priority srcnat; policy accept;
                iifname "docker0" masquerade
                iifname "br-*" masquerade
        }
}
```

```bash
vim /etc/nftables.conf
systemctl restart nftable
```

## 安装软件

### 安装 docker

```bash
# Add Docker's official GPG key:
apt-get update
apt-get install ca-certificates curl
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources:
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update

# Install the Docker packages:
apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

### 安装 Cloudflared

```bash
# Add Cloudflare's package signing key:
mkdir -p --mode=0755 /usr/share/keyrings
curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null

# Add Cloudflare's apt repo to your apt repositories:
echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main" | tee /etc/apt/sources.list.d/cloudflared.list

# Update repositories and install cloudflared:
apt-get update && apt-get install cloudflared
```

### 安装 tailscale

```shell
# Add Tailscale's package signing key and repository:
curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.noarmor.gpg | tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.tailscale-keyring.list | tee /etc/apt/sources.list.d/tailscale.list

# Install Tailscale:
apt-get update
apt-get install tailscale

# Connect your machine to your Tailscale network and authenticate in your browser:
tailscale up
```

## 部署 Shield

- [Status](https://github.com/auto-novel/status)

## 部署 Core

### 安装 ES 插件

```
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
systemctl enable auto-novel-updater.timer
systemctl start auto-novel-updater.timer
```
