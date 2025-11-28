#!/bin/bash

# Core Server Setup Script
# This script is idempotent - it can be run multiple times safely.
# Based on the setup instructions from README.md

set -e

# Colors for output
GREEN="\e[1;32m"
YELLOW="\e[1;33m"
RED="\e[1;31m"
RESET="\e[0m"

# Configuration variables (can be overridden by environment)
SSH_PORT="${SSH_PORT:-47679}"
HOSTNAME="${HOSTNAME:-core}"
AUTO_NOVEL_DIR="${AUTO_NOVEL_DIR:-/root/auto-novel}"

log_info() {
    echo -e "${GREEN}[INFO]${RESET} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${RESET} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${RESET} $1"
}

#######################################
# System Update and Basic Packages
#######################################
setup_basic_packages() {
    log_info "Updating system and installing basic packages..."
    apt-get update -qq
    apt-get upgrade -y -qq
    apt-get install -y -qq vim ca-certificates curl gnupg
    log_info "Basic packages installed."
}

#######################################
# SSH Configuration
#######################################
setup_ssh() {
    log_info "Configuring SSH..."
    local sshd_config="/etc/ssh/sshd_config"
    local needs_restart=false

    # Configure SSH port
    if grep -q "^Port ${SSH_PORT}$" "$sshd_config"; then
        log_info "SSH port already set to ${SSH_PORT}."
    else
        if grep -q "^Port " "$sshd_config"; then
            sed -i "s/^Port .*/Port ${SSH_PORT}/" "$sshd_config"
        elif grep -q "^#Port " "$sshd_config"; then
            sed -i "s/^#Port .*/Port ${SSH_PORT}/" "$sshd_config"
        else
            echo "Port ${SSH_PORT}" >> "$sshd_config"
        fi
        log_info "SSH port configured to ${SSH_PORT}."
        needs_restart=true
    fi

    # Disable password authentication
    if grep -q "^PasswordAuthentication no$" "$sshd_config"; then
        log_info "Password authentication already disabled."
    else
        if grep -q "^PasswordAuthentication " "$sshd_config"; then
            sed -i "s/^PasswordAuthentication .*/PasswordAuthentication no/" "$sshd_config"
        elif grep -q "^#PasswordAuthentication " "$sshd_config"; then
            sed -i "s/^#PasswordAuthentication .*/PasswordAuthentication no/" "$sshd_config"
        else
            echo "PasswordAuthentication no" >> "$sshd_config"
        fi
        log_info "Password authentication disabled."
        needs_restart=true
    fi

    if [ "$needs_restart" = true ]; then
        systemctl restart sshd
        log_info "SSH service restarted."
    fi
}

#######################################
# Login Display Configuration (MOTD)
#######################################
setup_motd() {
    log_info "Configuring login display..."

    # Clear default motd
    if [ -s /etc/motd ]; then
        true > /etc/motd
        log_info "Default motd cleared."
    else
        log_info "Default motd already empty."
    fi

    # Install sysinfo.sh to profile.d
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local sysinfo_src="${script_dir}/profile.d/sysinfo.sh"
    local sysinfo_dst="/etc/profile.d/sysinfo.sh"

    if [ -f "$sysinfo_src" ]; then
        if [ -f "$sysinfo_dst" ] && cmp -s "$sysinfo_src" "$sysinfo_dst"; then
            log_info "sysinfo.sh already installed."
        else
            cp "$sysinfo_src" "$sysinfo_dst"
            chmod +x "$sysinfo_dst"
            log_info "sysinfo.sh installed to /etc/profile.d/."
        fi
    else
        log_warn "sysinfo.sh not found at ${sysinfo_src}, skipping."
    fi
}

#######################################
# Hostname Configuration
#######################################
setup_hostname() {
    log_info "Configuring hostname..."
    local current_hostname
    current_hostname=$(hostname)

    if [ "$current_hostname" = "$HOSTNAME" ]; then
        log_info "Hostname already set to ${HOSTNAME}."
    else
        hostnamectl set-hostname "$HOSTNAME"
        log_info "Hostname set to ${HOSTNAME}."
    fi
}

#######################################
# Bashrc Configuration
#######################################
setup_bashrc() {
    log_info "Configuring bashrc..."
    local bashrc="/root/.bashrc"
    local marker="# Configured by setup-core.sh"

    if grep -q "$marker" "$bashrc" 2>/dev/null; then
        log_info "Bashrc already configured."
        return
    fi

    cat > "$bashrc" << 'EOF'
# ~/.bashrc: executed by bash(1) for non-login shells.
# Configured by setup-core.sh

PS1='\[\e[35;1m\][\u@\h \[\e[94;1m\]\w\[\e[35;1m\]]\$\[\e[m\] '

export LS_OPTIONS='--color=auto'
eval "$(dircolors)"
alias ls='ls $LS_OPTIONS'
alias ll='ls $LS_OPTIONS -l'
alias l='ls $LS_OPTIONS -lA'

alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'
EOF
    log_info "Bashrc configured."
}

#######################################
# Firewall Configuration (nftables)
#######################################
setup_firewall() {
    log_info "Configuring firewall (nftables)..."
    local nft_config="/etc/nftables.conf"

    # Install nftables if not installed
    if ! command -v nft &> /dev/null; then
        apt-get install -y -qq nftables
        log_info "nftables installed."
    fi

    # Generate nftables configuration
    local nft_content
    nft_content=$(cat << EOF
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
                tcp dport ${SSH_PORT} counter accept comment "accept SSH"
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
EOF
)

    if [ -f "$nft_config" ] && [ "$(cat "$nft_config")" = "$nft_content" ]; then
        log_info "nftables configuration already up to date."
    else
        echo "$nft_content" > "$nft_config"
        systemctl enable nftables
        systemctl restart nftables
        log_info "nftables configured and restarted."
    fi
}

#######################################
# Docker Installation
#######################################
setup_docker() {
    log_info "Setting up Docker..."

    if command -v docker &> /dev/null; then
        log_info "Docker already installed."
    else
        # Add Docker's official GPG key
        install -m 0755 -d /etc/apt/keyrings
        if [ ! -f /etc/apt/keyrings/docker.asc ]; then
            curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
            chmod a+r /etc/apt/keyrings/docker.asc
            log_info "Docker GPG key installed."
        fi

        # Add the repository to Apt sources
        local docker_list="/etc/apt/sources.list.d/docker.list"
        if [ ! -f "$docker_list" ]; then
            echo \
              "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
              $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
              tee "$docker_list" > /dev/null
            apt-get update -qq
            log_info "Docker repository added."
        fi

        # Install Docker packages
        apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        log_info "Docker installed."
    fi

    # Ensure Docker service is enabled and running
    systemctl enable docker
    if ! systemctl is-active --quiet docker; then
        systemctl start docker
    fi
    log_info "Docker service is running."
}

#######################################
# Cloudflared Installation
#######################################
setup_cloudflared() {
    log_info "Setting up Cloudflared..."

    if command -v cloudflared &> /dev/null; then
        log_info "Cloudflared already installed."
    else
        # Add Cloudflare's package signing key
        mkdir -p /usr/share/keyrings
        chmod 0755 /usr/share/keyrings
        if [ ! -f /usr/share/keyrings/cloudflare-main.gpg ]; then
            curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null
            log_info "Cloudflare GPG key installed."
        fi

        # Add Cloudflare's apt repo
        local cf_list="/etc/apt/sources.list.d/cloudflared.list"
        if [ ! -f "$cf_list" ]; then
            echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main" | tee "$cf_list" > /dev/null
            log_info "Cloudflare repository added."
        fi

        # Install cloudflared
        apt-get update -qq
        apt-get install -y -qq cloudflared
        log_info "Cloudflared installed."
    fi
}

#######################################
# Tailscale Installation
#######################################
setup_tailscale() {
    log_info "Setting up Tailscale..."

    if command -v tailscale &> /dev/null; then
        log_info "Tailscale already installed."
    else
        # Add Tailscale's package signing key and repository
        mkdir -p /usr/share/keyrings
        chmod 0755 /usr/share/keyrings
        if [ ! -f /usr/share/keyrings/tailscale-archive-keyring.gpg ]; then
            curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.noarmor.gpg | tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
            log_info "Tailscale GPG key installed."
        fi

        local ts_list="/etc/apt/sources.list.d/tailscale.list"
        if [ ! -f "$ts_list" ]; then
            curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.tailscale-keyring.list | tee "$ts_list" > /dev/null
            log_info "Tailscale repository added."
        fi

        # Install Tailscale
        apt-get update -qq
        apt-get install -y -qq tailscale
        log_info "Tailscale installed."
    fi

    # Enable tailscaled service
    systemctl enable tailscaled
    if ! systemctl is-active --quiet tailscaled; then
        systemctl start tailscaled
    fi
    log_info "Tailscale service is running."
    log_warn "Run 'tailscale up' manually to authenticate."
}

#######################################
# Deploy Core (auto-novel)
#######################################
setup_auto_novel() {
    log_info "Setting up auto-novel..."

    # Create directory structure
    # Note: ES requires 777 permissions for plugins/data directories when running in Docker
    # because the elasticsearch user inside the container needs write access
    mkdir -p "${AUTO_NOVEL_DIR}/data/es/plugins"
    mkdir -p "${AUTO_NOVEL_DIR}/data/es/data"
    chmod 777 -R "${AUTO_NOVEL_DIR}/data/es/plugins"
    chmod 777 -R "${AUTO_NOVEL_DIR}/data/es/data"
    log_info "auto-novel directory structure created."

    # Check if ES plugin is installed
    if [ -d "${AUTO_NOVEL_DIR}/data/es/plugins/analysis-icu" ]; then
        log_info "ES analysis-icu plugin already installed."
    else
        log_info "Installing ES analysis-icu plugin..."
        docker run --rm --entrypoint bash \
            -v "${AUTO_NOVEL_DIR}/data/es/plugins:/usr/share/elasticsearch/plugins" \
            elasticsearch:8.6.1 \
            -c "bin/elasticsearch-plugin install analysis-icu" || {
            log_warn "ES plugin installation may require manual intervention."
            log_warn "Run: docker run --rm -it --entrypoint bash -v ${AUTO_NOVEL_DIR}/data/es/plugins:/usr/share/elasticsearch/plugins elasticsearch:8.6.1"
            log_warn "Then in container: bin/elasticsearch-plugin install analysis-icu"
        }
    fi

    # Check for docker-compose.yml and .env
    if [ ! -f "${AUTO_NOVEL_DIR}/docker-compose.yml" ]; then
        log_warn "docker-compose.yml not found in ${AUTO_NOVEL_DIR}."
        log_warn "Please create it manually before starting the service."
    fi

    if [ ! -f "${AUTO_NOVEL_DIR}/.env" ]; then
        log_warn ".env file not found in ${AUTO_NOVEL_DIR}."
        log_warn "Please create it manually before starting the service."
    fi
}

#######################################
# Systemd Services Configuration
#######################################
setup_systemd_services() {
    log_info "Setting up systemd services..."
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    # Install auto-novel-updater service
    local service_src="${script_dir}/service/auto-novel-updater.service"
    local service_dst="/etc/systemd/system/auto-novel-updater.service"

    if [ -f "$service_src" ]; then
        if [ -f "$service_dst" ] && cmp -s "$service_src" "$service_dst"; then
            log_info "auto-novel-updater.service already installed."
        else
            cp "$service_src" "$service_dst"
            systemctl daemon-reload
            log_info "auto-novel-updater.service installed."
        fi
    else
        log_warn "auto-novel-updater.service not found at ${service_src}, skipping."
    fi

    # Install auto-novel-updater timer
    local timer_src="${script_dir}/service/auto-novel-updater.timer"
    local timer_dst="/etc/systemd/system/auto-novel-updater.timer"

    if [ -f "$timer_src" ]; then
        if [ -f "$timer_dst" ] && cmp -s "$timer_src" "$timer_dst"; then
            log_info "auto-novel-updater.timer already installed."
        else
            cp "$timer_src" "$timer_dst"
            systemctl daemon-reload
            log_info "auto-novel-updater.timer installed."
        fi
    else
        log_warn "auto-novel-updater.timer not found at ${timer_src}, skipping."
    fi

    # Enable and start the timer
    systemctl enable auto-novel-updater.timer
    if ! systemctl is-active --quiet auto-novel-updater.timer; then
        systemctl start auto-novel-updater.timer
    fi
    log_info "auto-novel-updater.timer is enabled and running."
}

#######################################
# Main
#######################################
main() {
    log_info "Starting Core Server Setup..."
    echo

    # Check if running as root
    if [ "$(id -u)" -ne 0 ]; then
        log_error "This script must be run as root."
        exit 1
    fi

    setup_basic_packages
    echo
    setup_ssh
    echo
    setup_motd
    echo
    setup_hostname
    echo
    setup_bashrc
    echo
    setup_firewall
    echo
    setup_docker
    echo
    setup_cloudflared
    echo
    setup_tailscale
    echo
    setup_auto_novel
    echo
    setup_systemd_services
    echo

    log_info "Core Server Setup completed!"
    log_info ""
    log_info "Next steps:"
    log_info "  1. Run 'tailscale up' to authenticate Tailscale"
    log_info "  2. Create ${AUTO_NOVEL_DIR}/docker-compose.yml"
    log_info "  3. Create ${AUTO_NOVEL_DIR}/.env"
    log_info "  4. Run 'cd ${AUTO_NOVEL_DIR} && docker compose up -d'"
    log_info "  5. Test with 'curl http://127.0.0.1'"
}

# Allow sourcing without running main
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
