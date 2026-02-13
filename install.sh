#!/usr/bin/env bash
set -euo pipefail

REPO_OWNER="Zuvpn"
REPO_NAME="Kwekha"
BRANCH="main"

CLI_URL="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${BRANCH}/kwekha.sh"
WEB_BIN_URL="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${BRANCH}/kwekha-web"

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
curl -fsSL "$WEB_BIN_URL" -o "$tmp_web" || true
if [[ -s "$tmp_web" ]]; then
  install -m 755 "$tmp_web" /usr/local/bin/kwekha-web
  rm -f "$tmp_web"
  echo "✅ Web binary installed: /usr/local/bin/kwekha-web"
else
  rm -f "$tmp_web"
  echo "⚠️ Web binary not found in repo (skipped)."
fi

mkdir -p /etc/kwekha /var/log/kwekha

# Ensure web.conf exists (panel should run even with 0 tunnels)
if [[ ! -f /etc/kwekha/web.conf ]]; then
  token="$(LC_ALL=C tr -dc '0-9' </dev/urandom | head -c 25)"
  cat >/etc/kwekha/web.conf <<EOF
PORT=9910
BIND=0.0.0.0
TOKEN=${token}
LOG_DIR=/var/log/kwekha
EOF
fi

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
echo "CLI:  kwekha"
echo "Web:  http://<SERVER_IP>:$(grep '^PORT=' /etc/kwekha/web.conf | cut -d= -f2)"
echo "Token: $(grep '^TOKEN=' /etc/kwekha/web.conf | cut -d= -f2)"
