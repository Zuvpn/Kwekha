#!/usr/bin/env bash
set -euo pipefail

# Kwekha one-line installer (CLI + Web Panel) - build webpanel from source
# Repo: https://github.com/Zuvpn/Kwekha

REPO_OWNER="Zuvpn"
REPO_NAME="Kwekha"
BRANCH="${KWEKHA_BRANCH:-main}"

GIT_URL="https://github.com/${REPO_OWNER}/${REPO_NAME}.git"
RAW_BASE="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${BRANCH}"

CLI_PATH="/usr/local/bin/kwekha"
WEB_PATH="/usr/local/bin/kwekha-web"
CONF_DIR="/etc/kwekha"
LOG_DIR="/var/log/kwekha"
WEB_CONF="${CONF_DIR}/web.conf"
WEB_SERVICE="/etc/systemd/system/kwekha-web.service"

need_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    echo "❌ لطفاً با دسترسی root اجرا کنید (یا با sudo)."
    exit 1
  fi
}

install_deps() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y >/dev/null 2>&1 || true
  apt-get install -y curl git golang ca-certificates >/dev/null 2>&1
}

install_cli() {
  echo "📦 Installing Kwekha CLI..."
  curl -fsSL "${RAW_BASE}/kwekha.sh" -o "${CLI_PATH}"
  chmod +x "${CLI_PATH}"
  echo "✅ CLI installed: ${CLI_PATH}"
}

build_webpanel() {
  echo "🌐 Installing Kwekha Web Panel (build from source)..."
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT

  git clone --depth 1 -b "${BRANCH}" "${GIT_URL}" "$tmp/repo" >/dev/null 2>&1 || {
    echo "❌ Failed to clone repo."
    exit 1
  }

  if [[ ! -d "$tmp/repo/webpanel" ]]; then
    echo "❌ webpanel/ folder not found in repo."
    exit 1
  fi

  pushd "$tmp/repo/webpanel" >/dev/null
  GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o kwekha-web .
  popd >/dev/null

  install -m 755 "$tmp/repo/webpanel/kwekha-web" "${WEB_PATH}"
  echo "✅ Web binary installed: ${WEB_PATH}"
}

gen_token_25() {
  # pipefail-safe token generator (digits only)
  local t
  t="$(LC_ALL=C tr -dc '0-9' </dev/urandom | head -c 25 || true)"
  if [[ "${#t}" -ne 25 ]]; then
    t="$(date +%s%N | tr -dc '0-9' | head -c 25 || true)"
    t="${t:0:25}"
  fi
  echo "$t"
}

setup_webpanel_service() {
  mkdir -p "${CONF_DIR}" "${LOG_DIR}"

  read -rp "🌐 Web panel port (default 8787): " PORT
  PORT="${PORT:-8787}"

  TOKEN="$(gen_token_25)"

  cat > "${WEB_CONF}" <<EOF
PORT=${PORT}
BIND=0.0.0.0
TOKEN=${TOKEN}
LOG_DIR=${LOG_DIR}
EOF

  cat > "${WEB_SERVICE}" <<'EOF'
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
  systemctl enable --now kwekha-web >/dev/null 2>&1 || {
    echo "❌ Failed to start kwekha-web."
    systemctl status kwekha-web --no-pager || true
    echo "Logs: tail -n 120 /var/log/kwekha/webpanel.log"
    exit 1
  }

  local ip
  ip="$(curl -fsSL ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')"

  echo ""
  echo "✅ Full installation complete!"
  echo "📟 CLI:   kwekha"
  echo "🌐 Web:   http://${ip}:${PORT}"
  echo "🔐 Token: ${TOKEN}"
  echo ""
  echo "🔁 Recover token later:"
  echo "sudo cat /etc/kwekha/web.conf | grep TOKEN="
}

main() {
  need_root
  install_deps
  install_cli
  build_webpanel
  setup_webpanel_service
}

main "$@"
