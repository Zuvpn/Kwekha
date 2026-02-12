#!/usr/bin/env bash
set -euo pipefail

REPO_OWNER="Zuvpn"
REPO_NAME="Kwekha"
BRANCH="${KWEKHA_BRANCH:-main}"

RAW_BASE="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${BRANCH}"
GIT_URL="https://github.com/${REPO_OWNER}/${REPO_NAME}.git"

need_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    echo "❌ لطفاً با دسترسی root اجرا کن (یا با sudo)."
    exit 1
  fi
}

install_deps() {
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

build_and_install_webpanel() {
  echo "🌐 Installing Kwekha Web Panel..."
  TMP_DIR="$(mktemp -d)"
  trap 'rm -rf "$TMP_DIR"' EXIT

  git clone --depth 1 -b "${BRANCH}" "${GIT_URL}" "${TMP_DIR}/repo" >/dev/null 2>&1
  cd "${TMP_DIR}/repo/webpanel"
  go build -o kwekha-web .

  install -m 755 kwekha-web /usr/local/bin/kwekha-web
  echo "✅ Web binary installed: /usr/local/bin/kwekha-web"
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

  # IMPORTANT: single-quoted heredoc so ${PORT}/${TOKEN} are read from EnvironmentFile at runtime.
  cat > /etc/systemd/system/kwekha-web.service <<'EOF'
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

  systemctl daemon-reload
  systemctl enable --now kwekha-web >/dev/null 2>&1

  IP="$(curl -fsSL ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')"

  echo ""
  echo "✅ Full installation complete!"
  echo "📟 CLI:  kwekha"
  echo "🌐 Web:  http://${IP}:${PORT}"
  echo "🔐 Token: ${TOKEN}"
  echo ""
  echo "🔁 Recover token later:"
  echo "sudo cat /etc/kwekha/web.conf | grep TOKEN="
}

main() {
  need_root
  install_deps
  install_cli
  build_and_install_webpanel
  setup_webpanel_service
}

main "$@"
