\
#!/usr/bin/env bash
# -*- coding: utf-8 -*-
# KWEKHA - Gost Tunnel Manager (CLI)
# Repo: https://github.com/Zuvpn/Kwekha
set -euo pipefail

APP_NAME="Kwekha"
VERSION="1.3.1"

BASE_DIR="/etc/kwekha"
SVC_DIR="$BASE_DIR/services"
LOG_DIR="/var/log/kwekha"
EXPORT_DIR="$BASE_DIR/exports"
GOST_BIN="/usr/local/bin/gost"

GREEN="\033[0;32m"; YELLOW="\033[1;33m"; RED="\033[0;31m"; CYAN="\033[0;36m"; NC="\033[0m"

banner() {
  clear || true
  cat <<'EOF'
██╗  ██╗██╗    ██╗███████╗██╗  ██╗██╗  ██╗ █████╗
██║ ██╔╝██║    ██║██╔════╝██║ ██╔╝██║  ██║██╔══██╗
█████╔╝ ██║ █╗ ██║█████╗  █████╔╝ ███████║███████║
██╔═██╗ ██║███╗██║██╔══╝  ██╔═██╗ ██╔══██║██╔══██║
██║  ██╗╚███╔███╔╝███████╗██║  ██╗██║  ██║██║  ██║
╚═╝  ╚═╝ ╚══╝╚══╝ ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝
EOF
  echo -e "${CYAN}${APP_NAME} | gost tunnel manager • wizard • systemd${NC}"
  echo -e "${CYAN}Version: ${VERSION}${NC}"
  echo
}

pause() { read -r -p "Enter to continue..." _; }

need_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    echo -e "${RED}❌ لطفاً با دسترسی root اجرا کن (یا با sudo).${NC}"
    exit 1
  fi
}

have_cmd() { command -v "$1" >/dev/null 2>&1; }

ensure_dirs() {
  mkdir -p "$BASE_DIR" "$SVC_DIR" "$LOG_DIR" "$EXPORT_DIR"
}

ensure_deps() {
  export DEBIAN_FRONTEND=noninteractive
  if ! have_cmd ss; then
    apt-get update -y >/dev/null 2>&1 || true
    apt-get install -y iproute2 >/dev/null 2>&1 || true
  fi
  if ! have_cmd curl; then
    apt-get update -y >/dev/null 2>&1 || true
    apt-get install -y curl >/dev/null 2>&1 || true
  fi
  if ! have_cmd uuidgen && ! have_cmd python3; then
    apt-get update -y >/dev/null 2>&1 || true
    apt-get install -y python3 >/dev/null 2>&1 || true
  fi
}

gost_version() {
  if [[ -x "$GOST_BIN" ]]; then
    "$GOST_BIN" -V 2>/dev/null || true
  fi
}

install_gost() {
  echo -e "${CYAN}📦 Installing gost...${NC}"
  bash <(curl -fsSL https://github.com/go-gost/gost/raw/master/install.sh)
  echo -e "${GREEN}✅ gost installed: $GOST_BIN${NC}"
  gost_version || true
}

gen_uuid() {
  if have_cmd uuidgen; then
    uuidgen
    return 0
  fi
  python3 - <<'PY' 2>/dev/null
import uuid; print(uuid.uuid4())
PY
}

parse_ports_simple() {
  local raw="$1"
  raw="${raw// /}"
  [[ -z "$raw" ]] && return 1
  if ! echo "$raw" | grep -qE '^[0-9]+(,[0-9]+)*$'; then
    return 1
  fi
  echo "$raw"
}

is_listening_local() {
  local port="$1"
  ss -lntp 2>/dev/null | grep -qE "[:.]${port}\b"
}

choose_scheme_menu() {
  local default="3"
  echo
  echo "Protocols (⭐ بهترین‌ها)"
  cat <<'EOF'
1)  tcp
2)  http+tls ⭐
3)  relay+wss ⭐
4)  relay+tls ⭐
5)  relay+ws ⭐
6)  grpc ⭐
7)  h2 ⭐
8)  wss
9)  tls
10) http
EOF
  echo
  read -r -p "شماره (پیش‌فرض: 3): " c
  c="${c:-$default}"
  case "$c" in
    1) echo "tcp" ;;
    2) echo "http+tls" ;;
    3) echo "relay+wss" ;;
    4) echo "relay+tls" ;;
    5) echo "relay+ws" ;;
    6) echo "grpc" ;;
    7) echo "h2" ;;
    8) echo "wss" ;;
    9) echo "tls" ;;
    10) echo "http" ;;
    *) echo "relay+wss" ;;
  esac
}

choose_destination_menu() {
  local default="2"
  echo
  echo -e "${CYAN}📌 سرویس مقصد (مثلاً Xray/Nginx/Panel) کجاست؟${NC}"
  echo "1) روی همین سرور (Localhost - 127.0.0.1)"
  echo "2) روی سرور مقابل (Remote server) ⭐ پیشنهاد برای ایران↔خارج"
  echo "3) تنظیم دستی (Advanced mapping)"
  echo
  read -r -p "انتخاب [1/2/3] (پیش‌فرض: ${default}): " ans
  ans="${ans:-$default}"
  case "$ans" in
    1) echo "LOCAL" ;;
    2) echo "REMOTE" ;;
    3) echo "ADV" ;;
    *) echo "REMOTE" ;;
  esac
}

warn_local_missing_and_offer_remote() {
  local ports_csv="$1"
  IFS=',' read -ra PARR <<< "$ports_csv"
  local missing=()
  for p in "${PARR[@]}"; do
    if ! is_listening_local "$p"; then
      missing+=("$p")
    fi
  done
  if (( ${#missing[@]} > 0 )); then
    echo
    echo -e "${YELLOW}⚠️ هشدار:${NC} روی این سرور چیزی روی پورت‌های زیر گوش نمی‌دهد: ${missing[*]}"
    echo "اگر Xray روی این سرور نیست، بهتر است گزینه «Remote server» را انتخاب کنید."
    read -r -p "تغییر مقصد به سرور مقابل؟ (y/N): " yn
    [[ "${yn,,}" == "y" ]] && return 0
  fi
  return 1
}

make_service_files() {
  local name="$1"
  local args="$2"
  local role="$3"
  local scheme="$4"
  local tunnel_port="$5"
  local ports_csv="$6"
  local remote_ip="$7"

  local conf="$SVC_DIR/${name}.conf"
  local unit="/etc/systemd/system/gost-kwekha-${name}.service"
  local logfile="$LOG_DIR/${name}.log"

  cat > "$conf" <<EOF
# Kwekha service config: ${name}
# generated at: $(date -Iseconds)
ROLE=${role}
SERVICE=${name}
SCHEME=${scheme}
TUNNEL_PORT=${tunnel_port}
PORTS=${ports_csv}
REMOTE_IP=${remote_ip}
ARGS=${args}
EOF

  cat > "$unit" <<EOF
[Unit]
Description=Kwekha Gost Service (${name})
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${GOST_BIN} ${args}
Restart=always
RestartSec=2
LimitNOFILE=1048576
WorkingDirectory=${BASE_DIR}
StandardOutput=append:${logfile}
StandardError=append:${logfile}

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable --now "gost-kwekha-${name}.service" >/dev/null 2>&1 || true
}

print_summary() {
  local role="$1" name="$2" scheme="$3" tunnel_port="$4" ports="$5" remote="$6"
  echo
  echo "+------------------------------+"
  printf "| %-28s |\n" "Summary (برای سرور مقابل)"
  echo "+------------------------------+"
  printf "| %-12s | %-13s |\n" "Role" "$role"
  printf "| %-12s | %-13s |\n" "Service" "$name"
  printf "| %-12s | %-13s |\n" "Protocol" "$scheme"
  printf "| %-12s | %-13s |\n" "TunnelPort" "$tunnel_port"
  printf "| %-12s | %-13s |\n" "Ports" "$ports"
  printf "| %-12s | %-13s |\n" "RemoteIP" "${remote:-N/A}"
  echo "+------------------------------+"
  echo
}

wizard_fast() {
  ensure_deps
  ensure_dirs

  if [[ ! -x "$GOST_BIN" ]]; then
    echo -e "${YELLOW}⚠️ gost نصب نیست. از منو گزینه 1 را بزنید.${NC}"
    pause
    return
  fi

  echo
  echo "این Wizard را روی هر دو سرور اجرا کن."
  echo "خارج: Server (گوش می‌کند) | ایران: Client (پورت‌ها را فوروارد می‌کند)"
  echo

  echo "نقش این سرور چیست؟"
  echo "1) خارج (Server)"
  echo "2) ایران (Client)"
  read -r -p "انتخاب [1/2]: " role_sel
  role_sel="${role_sel:-1}"

  read -r -p "اسم سرویس (مثلاً main-tunnel): " name
  name="${name:-main-tunnel}"

  scheme="$(choose_scheme_menu)"

  read -r -p "پورت تونل (روی خارج) مثل 2053/8443: " tunnel_port
  tunnel_port="${tunnel_port:-2053}"

  local uuid
  uuid="$(gen_uuid)"
  [[ -z "$uuid" ]] && uuid="$name"

  if [[ "$role_sel" == "1" ]]; then
    local args="-L ${scheme}://:${tunnel_port}?tunnel.id=${uuid}"
    make_service_files "$name" "$args" "Server(خارج)" "$scheme" "$tunnel_port" "-" ""
    print_summary "Server(خارج)" "$name" "$scheme" "$tunnel_port" "-" ""
    echo -e "${GREEN}✅ started:${NC} gost-kwekha-${name}.service"
    echo -e "ℹ️ پورت ${tunnel_port} را روی سرور خارج باز کنید."
    pause
    return
  fi

  # Client
  read -r -p "آی‌پی/دامنه سرور خارج: " remote_ip
  if [[ -z "$remote_ip" ]]; then
    echo -e "${RED}❌ Remote IP is required.${NC}"
    pause
    return
  fi

  local ports_csv=""
  while true; do
    read -r -p "📦 پورت‌ها (مثال: 80,443,2053): " ports_in
    ports_csv="$(parse_ports_simple "$ports_in" || true)"
    [[ -n "$ports_csv" ]] && break
    echo -e "${RED}❌ فرمت پورت‌ها درست نیست.${NC}"
  done

  local dest_mode
  dest_mode="$(choose_destination_menu)"

  if [[ "$dest_mode" == "LOCAL" ]]; then
    if warn_local_missing_and_offer_remote "$ports_csv"; then
      dest_mode="REMOTE"
    fi
  fi

  if [[ "$dest_mode" == "ADV" ]]; then
    echo
    echo "Advanced mapping مثال:"
    echo "tcp:2222->127.0.0.1:22, tcp:8080->127.0.0.1:8080"
    read -r -p "Mapping: " mapping
    mapping="${mapping:-}"
    if [[ -z "$mapping" ]]; then
      echo -e "${RED}❌ mapping خالی است.${NC}"
      pause
      return
    fi
    local args=""
    IFS=',' read -ra MAPS <<< "$mapping"
    for m in "${MAPS[@]}"; do
      m="${m// /}"
      if echo "$m" | grep -qE '^tcp:[0-9]+->[^:]+:[0-9]+$'; then
        local lp="${m#tcp:}"; lp="${lp%%->*}"
        local dst="${m#*->}"
        args+=" -L tcp://:${lp}/${dst}"
      fi
    done
    args+=" -F tunnel+tcp://${remote_ip}:${tunnel_port}?tunnel.id=${uuid}"
    make_service_files "$name" "$args" "Client(ایران)" "$scheme" "$tunnel_port" "advanced" "$remote_ip"
    print_summary "Client(ایران)" "$name" "$scheme" "$tunnel_port" "advanced" "$remote_ip"
    echo -e "${GREEN}✅ started:${NC} gost-kwekha-${name}.service"
    pause
    return
  fi

  local args=""
  IFS=',' read -ra PARR <<< "$ports_csv"
  for p in "${PARR[@]}"; do
    if [[ "$dest_mode" == "REMOTE" ]]; then
      args+=" -L tcp://:${p}/${remote_ip}:${p}"
    else
      args+=" -L tcp://:${p}/127.0.0.1:${p}"
    fi
  done
  args+=" -F tunnel+tcp://${remote_ip}:${tunnel_port}?tunnel.id=${uuid}"

  if echo "$ports_csv" | grep -qE '(^|,)80(,|$)'; then
    if [[ "$dest_mode" == "LOCAL" && is_listening_local 80 ]]; then
      echo
      echo -e "${YELLOW}⚠️ هشدار:${NC} پورت 80 روی این سرور در حال استفاده است."
      echo "اگر سرویس واقعی روی 80 ندارید، بهتر است مقصد را Remote انتخاب کنید."
    fi
  fi

  make_service_files "$name" "$args" "Client(ایران)" "$scheme" "$tunnel_port" "$ports_csv" "$remote_ip"
  print_summary "Client(ایران)" "$name" "$scheme" "$tunnel_port" "$ports_csv" "$remote_ip"
  echo -e "${GREEN}✅ started:${NC} gost-kwekha-${name}.service"
  pause
}

list_services() {
  ensure_dirs
  echo
  echo "Services configs:"
  ls -1 "$SVC_DIR" 2>/dev/null | sed 's/\.conf$//' || true
  echo
  echo "Active systemd units:"
  systemctl list-units --type=service --no-pager | grep -E 'gost-kwekha-' || true
  echo
  pause
}

self_update() {
  local url="https://raw.githubusercontent.com/Zuvpn/Kwekha/main/kwekha.sh"
  local tmp
  tmp="$(mktemp)"
  echo -e "${CYAN}⬇️  Downloading update...${NC}"
  curl -fsSL "$url" -o "$tmp"
  head -n 3 "$tmp" | grep -qE '^#!/usr/bin/env bash|^#!/bin/bash' || { echo -e "${RED}❌ فایل دانلودی معتبر نیست.${NC}"; rm -f "$tmp"; return 1; }
  grep -q "wizard_fast()" "$tmp" || { echo -e "${RED}❌ فایل دانلودی معتبر نیست.${NC}"; rm -f "$tmp"; return 1; }
  install -m 755 "$tmp" /usr/local/bin/kwekha
  rm -f "$tmp"
  echo -e "${GREEN}✅ Updated.${NC}"
  pause
}

menu() {
  while true; do
    banner
    echo "1) Install gost"
    echo "2) Quick Setup Wizard (FAST) ⭐"
    echo "3) List services"
    echo "11) Self-update script"
    echo "0) Exit"
    echo
    read -r -p "Select: " sel
    case "${sel:-}" in
      1) need_root; ensure_dirs; install_gost; pause ;;
      2) need_root; wizard_fast ;;
      3) need_root; list_services ;;
      11) need_root; self_update ;;
      0) exit 0 ;;
      *) ;;
    esac
  done
}

ensure_dirs
menu
