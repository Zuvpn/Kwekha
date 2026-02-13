#!/usr/bin/env bash
set -euo pipefail

APP_BIN="/usr/local/bin/kwekha-web"
CONF_DIR="/etc/kwekha"
CONF_FILE="$CONF_DIR/web.conf"
SVC_FILE="/etc/systemd/system/kwekha-web.service"

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "Please run as root: sudo $0"
  exit 1
fi

mkdir -p "$CONF_DIR"

read -rp "🌐 Panel port (default 8787): " PORT
PORT="${PORT:-8787}"

TOKEN="$(tr -dc '0-9' </dev/urandom | head -c 25)"
BIND="0.0.0.0"

cat > "$CONF_FILE" <<EOF
# Kwekha Web config
PORT=$PORT
BIND=$BIND
TOKEN=$TOKEN
LOG_DIR=/var/log/kwekha
EOF
chmod 600 "$CONF_FILE"

echo "==> Installing binary to $APP_BIN"
if [[ -f "./kwekha-web" ]]; then
  install -m 755 ./kwekha-web "$APP_BIN"
else
  echo "Binary ./kwekha-web not found in current directory."
  echo "Build it first:"
  echo "  cd webpanel && go build -o kwekha-web ."
  exit 1
fi

cat > "$SVC_FILE" <<'EOF'
[Unit]
Description=Kwekha Web Panel
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/kwekha-web
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now kwekha-web.service

echo
echo "✅ Kwekha Web is running on: http://$BIND:$PORT"
echo "🔐 Your 25-digit token (save it): $TOKEN"
echo "📌 Recover later:"
echo "   sudo cat $CONF_FILE | grep TOKEN="
echo "   sudo kwekha-web token"
echo
echo "⚠️ Security:"
echo " - Exposed on 0.0.0.0:$PORT"
echo " - Use firewall to allow only your IP, or put behind Nginx+TLS."
