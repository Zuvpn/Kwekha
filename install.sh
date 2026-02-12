#!/usr/bin/env bash
set -euo pipefail

REPO_OWNER="Zuvpn"
REPO_NAME="Kwekha"
BRANCH="${KWEKHA_BRANCH:-main}"
RAW_BASE="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${BRANCH}"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

need_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    echo "❌ لطفاً با دسترسی root اجرا کن (یا با sudo)."
    exit 1
  fi
}

ensure_pkgs() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y >/dev/null 2>&1 || true
  apt-get install -y curl git golang >/dev/null 2>&1
}

install_cli() {
  echo "📦 Installing Kwekha CLI..."
  curl -fsSL "${RAW_BASE}/kwekha.sh" -o /usr/local/bin/kwekha
  chmod +x /usr/local/bin/kwekha
  echo "✅ CLI installed: /usr/local/bin/kwekha"
}

build_webpanel() {
  echo "🌐 Installing Kwekha Web Panel..."
  git clone --depth 1 -b "${BRANCH}" "https://github.com/${REPO_OWNER}/${REPO_NAME}.git" "$TMP_DIR/repo" >/dev/null 2>&1
  cd "$TMP_DIR/repo/webpanel"
  go build -o kwekha-web .
  install -m 755 kwekha-web /usr/local/bin/kwekha-web
}

setup_webpanel_service() {
  mkdir -p /etc/kwekha /var/log/kwekha

  read -rp "🌐 Web panel port (default 8787): " PORT
  PORT="${PORT:-8787}"

  # 25-digit numeric token
  TOKEN="$(tr -dc '0-9' </dev/urandom | head -c 25)"

  cat > /etc/kwekha/web.conf <<EOF
PORT=${PORT}
BIND=0.0.0.0
TOKEN=${TOKEN}
LOG_DIR=/var/log/kwekha
EOF

  cat > /etc/systemd/system/kwekha-web.service <<EOF
[Unit]
Description=Kwekha Web Panel
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
EnvironmentFile=/etc/kwekha/web.conf
ExecStart=/usr/local/bin/kwekha-web --bind ${BIND:-0.0.0.0} --port ${PORT:-8787} --token ${TOKEN:-0000000000000000000000000}
Restart=always
RestartSec=2
WorkingDirectory=/etc/kwekha
StandardOutput=append:/var/log/kwekha/webpanel.log
StandardError=append:/var/log/kwekha/webpanel.log

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable --now kwekha-web.service >/dev/null 2>&1 || true

  IP="$(curl -fsSL ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')"

  echo ""
  echo "✅ Full installation complete!"
  echo "📟 CLI: run -> kwekha"
  echo "🌐 Web Panel: http://${IP}:${PORT}"
  echo "🔐 Token: ${TOKEN}"
  echo ""
  echo "🔁 Recover token later:"
  echo "sudo cat /etc/kwekha/web.conf | grep TOKEN="
}

main() {
  need_root
  ensure_pkgs
  install_cli
  build_webpanel
  setup_webpanel_service
}

main "$@"
