# SOCKS5 Proxy Installer

One-command SOCKS5 proxy setup for Ubuntu 24.04 using [3proxy](https://github.com/3proxy/3proxy).

## Quick install

```bash
curl -fsSL https://raw.githubusercontent.com/<USER>/<REPO>/main/install-proxy.sh | sudo bash
```

With custom credentials:

```bash
curl -fsSL https://raw.githubusercontent.com/<USER>/<REPO>/main/install-proxy.sh -o install-proxy.sh
PROXY_USER=myuser PROXY_PASS=MyPass PROXY_PORT=1080 sudo -E bash install-proxy.sh
```

## What it does

- Updates the system and installs build deps
- Builds 3proxy from source
- Configures SOCKS5 with username/password auth
- Sets up a systemd service with auto-restart
- Configures UFW (allows SSH + proxy port)
- Applies kernel tweaks for high connection load
- Prints the ready-to-use connection string

## Manage

```bash
systemctl status 3proxy
systemctl restart 3proxy
nano /etc/3proxy/3proxy.cfg
```
