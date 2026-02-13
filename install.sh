#!/usr/bin/env bash
set -euo pipefail

REPO_OWNER="Zuvpn"
REPO_NAME="Kwekha"
BRANCH="main"

CLI_URL="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${BRANCH}/kwekha.sh"
WEB_BIN_URL="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${BRANCH}/kwekha-web"

# Make prompts work even when user runs: curl ... | sudo bash
TTY="/dev/tty"
if [[ -r "$TTY" ]]; then
  exec <"$TTY"
fi

need_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    echo "❌ Please run as root (use sudo)."
    exit 1
  fi
}

gen_token_25() {
  # 25 digits
  tr -dc '0-9' </dev/urandom | head -c 25
}

need_root

echo "📦 Installing Kwekha CLI..."
tmp_cli="$(mktemp)"
curl -fsSL "$CLI_URL" -o "$tmp_cli"
sed -i 's/\r$//' "$tmp_cli"
sed -i '1{/^\\$/d;}' "$tmp_cli"
head -n 1 "$tmp_cli" | grep -qE '^#!/usr/bin/env bash|^#!/bin/bash' || { echo "❌ CLI file invalid"; exit 1; }
install -m 755 "$tmp_cli" /usr/local/bin/kwekha
rm -f "$tmp_cli"
echo "✅ CLI installed: /usr/local/bin/kwekha"

echo "🌐 Installing Kwekha Web Panel..."
tmp_web="$(mktemp)"
if curl -fsSL "$WEB_BIN_URL" -o "$tmp_web"; then
  install -m 755 "$tmp_web" /usr/local/bin/kwekha-web
  echo "✅ Web binary installed: /usr/local/bin/kwekha-web"
else
  echo "❌ Web binary not found in repo (kwekha-web)."
  echo "   Expected: $WEB_BIN_URL"
  rm -f "$tmp_web"
  exit 1
fi
rm -f "$tmp_web"

mkdir -p /etc/kwekha /etc/kwekha/services /etc/kwekha/exports /var/log/kwekha

# Create or update web.conf interactively
conf="/etc/kwekha/web.conf"
default_port="8787"
default_bind="0.0.0.0"

current_port=""
current_bind=""
current_token=""
if [[ -f "$conf" ]]; then
  current_port="$(grep -E '^PORT=' "$conf" | head -n1 | cut -d= -f2- || true)"
  current_bind="$(grep -E '^BIND=' "$conf" | head -n1 | cut -d= -f2- || true)"
  current_token="$(grep -E '^TOKEN=' "$conf" | head -n1 | cut -d= -f2- || true)"
fi

read -r -p "🌐 Web panel port (default ${current_port:-$default_port}): " WEB_PORT
WEB_PORT="${WEB_PORT:-${current_port:-$default_port}}"
if ! [[ "$WEB_PORT" =~ ^[0-9]{2,5}$ ]] || (( WEB_PORT < 1 || WEB_PORT > 65535 )); then
  echo "❌ Invalid port: $WEB_PORT"
  exit 1
fi

read -r -p "🌐 Web panel bind (default ${current_bind:-$default_bind}): " WEB_BIND
WEB_BIND="${WEB_BIND:-${current_bind:-$default_bind}}"

WEB_TOKEN="${current_token:-}"
if [[ -z "$WEB_TOKEN" ]]; then
  WEB_TOKEN="$(gen_token_25)"
fi

cat >"$conf" <<EOF
PORT=${WEB_PORT}
BIND=${WEB_BIND}
TOKEN=${WEB_TOKEN}
LOG_DIR=/var/log/kwekha
EOF
chmod 600 "$conf"

# Install/repair systemd service to always use web.conf (no mismatch)
cat >/etc/systemd/system/kwekha-web.service <<'EOF'
[Unit]
Description=Kwekha Web Panel
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
EnvironmentFile=/etc/kwekha/web.conf
ExecStart=/usr/local/bin/kwekha-web --bind ${BIND} --port ${PORT} --token ${TOKEN}
Restart=always
RestartSec=2
WorkingDirectory=/etc/kwekha
StandardOutput=append:/var/log/kwekha/webpanel.log
StandardError=append:/var/log/kwekha/webpanel.log

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload >/dev/null 2>&1 || true
systemctl enable --now kwekha-web >/dev/null 2>&1 || true

echo
echo "✅ Done."
echo "CLI:    kwekha"
echo "Web:    http://<SERVER_IP>:${WEB_PORT}"
echo "Token:  ${WEB_TOKEN}"
echo
echo "🔐 Recover token later:"
echo "cat /etc/kwekha/web.conf | grep '^TOKEN='"
