#!/usr/bin/env bash
# SOCKS5 proxy auto-installer for Ubuntu 24.04
# Usage:
#   curl -fsSL <URL> | sudo bash
#   sudo bash install-proxy.sh
# Optional env vars:
#   PROXY_USER=myuser PROXY_PASS=mypass PROXY_PORT=1080 sudo -E bash install-proxy.sh

set -euo pipefail

# ---------- root check ----------
if [[ $EUID -ne 0 ]]; then
    echo "[!] Run as root: sudo bash $0"
    exit 1
fi

# ---------- config ----------
PROXY_PORT="${PROXY_PORT:-1080}"
# openssl is preinstalled on Ubuntu; avoids SIGPIPE issues with `tr | head`
command -v openssl >/dev/null || apt-get install -yqq openssl
PROXY_USER="${PROXY_USER:-user$(openssl rand -hex 2)}"
PROXY_PASS="${PROXY_PASS:-$(openssl rand -hex 8)}"
THREEPROXY_VER="0.9.5"

log() { echo -e "\033[1;32m[+]\033[0m $*"; }
err() { echo -e "\033[1;31m[!]\033[0m $*" >&2; }

# ---------- system update & deps ----------
log "Updating system & installing dependencies..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get upgrade -yqq
apt-get install -yqq --no-install-recommends \
    build-essential wget curl ca-certificates ufw

# ---------- build 3proxy ----------
if ! [[ -x /usr/local/bin/3proxy ]]; then
    log "Building 3proxy ${THREEPROXY_VER}..."
    cd /tmp
    rm -rf 3proxy-${THREEPROXY_VER}
    wget -q "https://github.com/3proxy/3proxy/archive/refs/tags/${THREEPROXY_VER}.tar.gz" -O 3proxy.tar.gz
    tar -xzf 3proxy.tar.gz
    cd "3proxy-${THREEPROXY_VER}"
    make -f Makefile.Linux -j"$(nproc)" >/dev/null
    install -m 755 bin/3proxy /usr/local/bin/3proxy
    cd / && rm -rf /tmp/3proxy-${THREEPROXY_VER} /tmp/3proxy.tar.gz
else
    log "3proxy already installed, skipping build"
fi

# ---------- config files ----------
log "Writing 3proxy config..."
mkdir -p /etc/3proxy /var/log/3proxy

cat >/etc/3proxy/3proxy.cfg <<EOF
# 3proxy config - SOCKS5 only (runs in foreground, managed by systemd)
nserver 1.1.1.1
nserver 8.8.8.8
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
log /var/log/3proxy/3proxy.log D
logformat "- +_L%t.%. %N.%p %E %U %C:%c %R:%r %O %I %h %T"
rotate 7

users ${PROXY_USER}:CL:${PROXY_PASS}

auth strong
allow ${PROXY_USER}
maxconn 1024
socks -p${PROXY_PORT}
EOF

chmod 600 /etc/3proxy/3proxy.cfg

# ---------- user for daemon ----------
if ! id -u proxy3 >/dev/null 2>&1; then
    useradd -r -s /usr/sbin/nologin -d /nonexistent proxy3
fi
chown -R proxy3:proxy3 /var/log/3proxy

# ---------- systemd service ----------
log "Creating systemd service..."
cat >/etc/systemd/system/3proxy.service <<'EOF'
[Unit]
Description=3proxy SOCKS5 proxy server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/3proxy /etc/3proxy/3proxy.cfg
Restart=always
RestartSec=3
LimitNOFILE=65536
User=proxy3
Group=proxy3
AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now 3proxy.service

# ---------- firewall ----------
log "Configuring firewall (UFW)..."
if command -v ufw >/dev/null 2>&1; then
    ufw --force enable >/dev/null
    ufw allow OpenSSH >/dev/null || ufw allow 22/tcp >/dev/null
    ufw allow "${PROXY_PORT}/tcp" >/dev/null
fi

# ---------- kernel tuning for proxy ----------
log "Applying kernel tweaks..."
cat >/etc/sysctl.d/99-proxy.conf <<EOF
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_tw_reuse = 1
net.ipv4.ip_local_port_range = 10000 65535
fs.file-max = 1000000
EOF
sysctl --system >/dev/null

# ---------- get public IP ----------
PUB_IP="$(curl -fsSL --max-time 5 https://api.ipify.org || curl -fsSL --max-time 5 https://ifconfig.me || hostname -I | awk '{print $1}')"

# ---------- final output ----------
sleep 1
if systemctl is-active --quiet 3proxy.service; then
    cat <<EOF

==================================================
  SOCKS5 proxy is running!
--------------------------------------------------
  Server : ${PUB_IP}
  Port   : ${PROXY_PORT}
  User   : ${PROXY_USER}
  Pass   : ${PROXY_PASS}
  Type   : SOCKS5
--------------------------------------------------
  Connection string:
    socks5://${PROXY_USER}:${PROXY_PASS}@${PUB_IP}:${PROXY_PORT}

  Test from another machine:
    curl --socks5 ${PROXY_USER}:${PROXY_PASS}@${PUB_IP}:${PROXY_PORT} https://api.ipify.org

  Manage:
    systemctl status 3proxy
    systemctl restart 3proxy
    nano /etc/3proxy/3proxy.cfg
==================================================

EOF
else
    err "3proxy failed to start. Check: journalctl -u 3proxy -n 50"
    exit 1
fi
