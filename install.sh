#!/usr/bin/env bash
set -euo pipefail

REPO="Zuvpn/Kwekha"
BRANCH="main"
RAW_BASE="https://raw.githubusercontent.com/${REPO}/${BRANCH}"
TMP_DIR="$(mktemp -d)"
cleanup(){ rm -rf "$TMP_DIR"; }
trap cleanup EXIT

need_root(){
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    echo "❌ Run as root (or with sudo)."
    exit 1
  fi
}

install_deps(){
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y >/dev/null
  apt-get install -y curl ca-certificates git >/dev/null
}

install_cli(){
  echo "📦 Installing Kwekha CLI..."
  curl -fsSL "${RAW_BASE}/kwekha.sh" -o "$TMP_DIR/kwekha"
  # remove accidental leading "\" line if present
  sed -i '1{/^\\$/d;}' "$TMP_DIR/kwekha"
  chmod +x "$TMP_DIR/kwekha"
  install -m 755 "$TMP_DIR/kwekha" /usr/local/bin/kwekha
  echo "✅ CLI installed: /usr/local/bin/kwekha"
}

ensure_dirs(){
  mkdir -p /etc/kwekha/services /etc/kwekha/exports /var/log/kwekha
  chmod 700 /etc/kwekha
}

rand_token_25(){
  # 25 digits
  tr -dc '0-9' </dev/urandom | head -c 25
}

ask_port(){
  local p="${1:-}"
  while true; do
    read -rp "🌐 Web panel port (default 8787): " p
    p="${p:-8787}"
    if [[ "$p" =~ ^[0-9]+$ ]] && (( p>=1 && p<=65535 )); then
      # avoid currently in use ports
      if ss -lnt 2>/dev/null | awk '{print $4}' | grep -qE "[:.]${p}$"; then
        echo "⚠️ Port $p is already in use. Choose another."
        continue
      fi
      echo "$p"
      return 0
    fi
    echo "❌ Invalid port."
  done
}

write_web_conf(){
  local port="$1"
  local token="$2"
  cat > /etc/kwekha/web.conf <<EOF
PORT=${port}
BIND=0.0.0.0
TOKEN=${token}
LOG_DIR=/var/log/kwekha
EOF
  chmod 600 /etc/kwekha/web.conf
}

write_systemd_unit(){
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
  systemctl enable --now kwekha-web.service >/dev/null
}

install_webpanel_from_source(){
  echo "🌐 Installing Kwekha Web Panel..."
  # Web source must exist in repo under /webpanel
  if ! curl -fsSL "${RAW_BASE}/webpanel/main.go" -o /dev/null; then
    echo "⚠️ webpanel source not found in repo (skipped)."
    return 0
  fi

  # ensure Go is installed
  if ! command -v go >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get install -y golang-go >/dev/null
  fi

  git clone --depth 1 --branch "${BRANCH}" "https://github.com/${REPO}.git" "$TMP_DIR/src" >/dev/null 2>&1 || {
    echo "❌ Failed to clone repo. Check network/GitHub access."
    exit 1
  }

  if [[ ! -f "$TMP_DIR/src/webpanel/go.mod" ]]; then
    echo "❌ webpanel/go.mod not found. Can't build web panel."
    exit 1
  fi

  (cd "$TMP_DIR/src/webpanel" && go build -trimpath -ldflags "-s -w" -o "$TMP_DIR/kwekha-web" .)
  install -m 755 "$TMP_DIR/kwekha-web" /usr/local/bin/kwekha-web
  echo "✅ Web binary installed: /usr/local/bin/kwekha-web"

  ensure_dirs
  local port token
  port="$(ask_port)"
  token="$(rand_token_25)"
  write_web_conf "$port" "$token"
  write_systemd_unit

  local ip
  ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  echo
  echo "✅ Full installation complete!"
  echo "CLI:   kwekha"
  echo "Web:   http://${ip:-YOUR_SERVER_IP}:${port}"
  echo "Token: ${token}"
  echo
  echo "Recover token later:"
  echo "  sudo cat /etc/kwekha/web.conf | grep '^TOKEN='"
}

main(){
  need_root
  install_deps
  install_cli
  install_webpanel_from_source
}
main "$@"
