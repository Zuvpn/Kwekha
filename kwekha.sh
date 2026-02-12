\
#!/usr/bin/env bash
# KWEKHA - gost tunnel manager (CLI)
# Repo: https://github.com/Zuvpn/Kwekha
set -euo pipefail

APP_NAME="Kwekha"
VERSION="1.6.0-merged-speedtest"

BASE_DIR="/etc/kwekha"
SVC_DIR="$BASE_DIR/services"
LOG_DIR="/var/log/kwekha"
CERT_DIR="$BASE_DIR/certs"
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
  echo -e "${CYAN}${APP_NAME} | gost tunnel manager • wizard • autotest • speedtest${NC}"
  echo -e "${CYAN}Version: ${VERSION}${NC}"
  echo
}

need_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    echo -e "${RED}❌ لطفاً با دسترسی root اجرا کن (یا با sudo).${NC}"
    exit 1
  fi
}

ensure_dirs() {
  mkdir -p "$BASE_DIR" "$SVC_DIR" "$LOG_DIR" "$BASE_DIR/exports" "$CERT_DIR"
}

pause() { read -r -p "Enter to continue..." _; }

have_cmd() { command -v "$1" >/dev/null 2>&1; }

ensure_deps_basic() {
  if ! have_cmd ss; then
    apt-get update -y >/dev/null 2>&1 || true
    apt-get install -y iproute2 >/dev/null 2>&1 || true
  fi
  if ! have_cmd curl; then
    apt-get update -y >/dev/null 2>&1 || true
    apt-get install -y curl >/dev/null 2>&1 || true
  fi
}

ensure_deps_test() {
  ensure_deps_basic
  if ! have_cmd nc; then
    apt-get update -y >/dev/null 2>&1 || true
    apt-get install -y netcat-openbsd >/dev/null 2>&1 || true
  fi
  if ! have_cmd iperf3; then
    apt-get update -y >/dev/null 2>&1 || true
    apt-get install -y iperf3 >/dev/null 2>&1 || true
  fi
  if ! have_cmd bc; then
    apt-get update -y >/dev/null 2>&1 || true
    apt-get install -y bc >/dev/null 2>&1 || true
  fi
  if ! have_cmd openssl; then
    apt-get update -y >/dev/null 2>&1 || true
    apt-get install -y openssl >/dev/null 2>&1 || true
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

is_listening_local() {
  local port="$1"
  ss -lntp 2>/dev/null | grep -qE "[:.]${port}\b"
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

choose_destination_menu() {
  local default="2"
  echo
  echo -e "${CYAN}📌 سرویس مقصد (مثلاً Xray/Nginx/Panel) کجاست؟${NC}"
  echo "1) روی همین سرور (Localhost - 127.0.0.1)"
  echo "2) روی سرور مقابل (Remote server) ⭐ پیشنهاد برای سناریوی ایران↔خارج"
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

warn_if_local_missing() {
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
    echo -e "${YELLOW}⚠️ هشدار:${NC} روی این سرور چیزی روی این پورت‌ها گوش نمی‌دهد: ${missing[*]}"
    echo "اگر Xray/Nginx/Panel روی این سرور نیست، بهتر است مقصد را «Remote server» انتخاب کنید."
    read -r -p "آیا مقصد را به سرور مقابل تغییر بدهم؟ (y/N): " yn
    [[ "${yn,,}" == "y" ]] && return 0
    return 1
  fi
  return 1
}

gen_uuid() {
  if have_cmd uuidgen; then uuidgen; return; fi
  cat /proc/sys/kernel/random/uuid 2>/dev/null || true
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
  local role="$1" name="$2" scheme="$3" tunnel_port="$4" ports="$5" remote="$6" tid="$7"
  echo
  echo "+----------------------------------------------+"
  printf "| %-44s |\n" "Summary (کپی کن برای سرور مقابل)"
  echo "+----------------------------------------------+"
  printf "| %-12s | %-29s |\n" "Role" "$role"
  printf "| %-12s | %-29s |\n" "Service" "$name"
  printf "| %-12s | %-29s |\n" "Protocol" "$scheme"
  printf "| %-12s | %-29s |\n" "TunnelPort" "$tunnel_port"
  printf "| %-12s | %-29s |\n" "Ports" "$ports"
  printf "| %-12s | %-29s |\n" "RemoteIP" "${remote:-N/A}"
  printf "| %-12s | %-29s |\n" "TunnelID" "${tid:-N/A}"
  echo "+----------------------------------------------+"
  echo
  echo -e "${GREEN}⭐ Best:${NC} relay+wss / relay+tls / relay+ws / grpc / h2"
}

choose_scheme_menu() {
  local default="3"
  echo
  echo "K W E K H A — Protocols"
  echo "انتخاب پروتکل (فقط عدد) — ⭐ بهترین‌ها"
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
  read -r -p "شماره (پیش‌فرض: ${default}): " c
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

wizard_fast() {
  ensure_deps_basic
  ensure_dirs

  [[ -x "$GOST_BIN" ]] && echo -e "${GREEN}✅ gost already installed:${NC} $GOST_BIN" && gost_version || {
    echo -e "${YELLOW}⚠️ gost not found. Install it first (menu 1).${NC}"
  }

  echo
  echo "هدف: روی هر دو سرور (خارج و ایران) همین Wizard را اجرا کن."
  echo "(Server) خارج: تونل را گوش می‌کند"
  echo "(Client) ایران: پورت‌ها را داخل تونل می‌فرستد"
  echo

  echo "نقش این سرور چیست؟"
  echo "1) خارج (Server)"
  echo "2) ایران (Client)"
  read -r -p "انتخاب [1/2]: " role_sel
  role_sel="${role_sel:-1}"

  read -r -p "اسم سرویس (مثلاً main-tunnel): " name
  name="${name:-main-tunnel}"

  scheme="$(choose_scheme_menu)"

  read -r -p "پورت تونل روی سرور خارج (مثلاً 8443 یا 2053): " tunnel_port
  tunnel_port="${tunnel_port:-8443}"

  local tid
  tid="$(gen_uuid)"
  [[ -z "$tid" ]] && tid="$name"

  local remote_ip="" dest_mode="LOCAL" ports_csv=""

  if [[ "$role_sel" == "1" ]]; then
    local args="-L ${scheme}://:${tunnel_port}?tunnel.id=${tid}"
    make_service_files "$name" "$args" "Server(خارج)" "${scheme}" "$tunnel_port" "-" ""
    print_summary "Server(خارج)" "$name" "$scheme" "$tunnel_port" "-" "" "$tid"
    echo -e "${GREEN}✅ started:${NC} gost-kwekha-${name}.service"
    echo -e "ℹ️ نیاز: پورت ${tunnel_port} روی سرور خارج باز باشد."
  else
    read -r -p "آی‌پی/دامنه سرور خارج: " remote_ip
    [[ -z "$remote_ip" ]] && { echo -e "${RED}❌ Remote IP is required.${NC}"; return; }

    while true; do
      read -r -p "📦 پورت‌ها (مثال: 80,443,2053): " ports_in
      ports_csv="$(parse_ports_simple "$ports_in" || true)"
      [[ -n "$ports_csv" ]] && break
      echo -e "${RED}❌ فرمت پورت‌ها درست نیست.${NC}"
    done

    dest_mode="$(choose_destination_menu)"
    if [[ "$dest_mode" == "LOCAL" ]]; then
      if warn_if_local_missing "$ports_csv"; then
        dest_mode="REMOTE"
      fi
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
    args+=" -F tunnel+tcp://${remote_ip}:${tunnel_port}?tunnel.id=${tid}"

    make_service_files "$name" "$args" "Client(ایران)" "${scheme}" "$tunnel_port" "$ports_csv" "$remote_ip"
    print_summary "Client(ایران)" "$name" "$scheme" "$tunnel_port" "$ports_csv" "$remote_ip" "$tid"
    echo -e "${GREEN}✅ started:${NC} gost-kwekha-${name}.service"
  fi

  echo
  pause
}

# -----------------------------
# Speed/Quality Test (NEW, integrated)
# -----------------------------

recommended_schemes() {
  # UDP removed as requested
  printf "%s\n" \
    "relay+wss" \
    "relay+tls" \
    "relay+ws" \
    "grpc" \
    "h2" \
    "tcp"
}

scheme_star() {
  case "$1" in
    relay+wss|relay+tls|relay+ws|grpc|h2) echo "⭐" ;;
    *) echo " " ;;
  esac
}

scheme_needs_tls() {
  case "$1" in
    relay+wss|relay+tls) return 0 ;;
    *) return 1 ;;
  esac
}

ensure_test_cert() {
  local crt="$CERT_DIR/kwekha.crt"
  local key="$CERT_DIR/kwekha.key"
  if [[ -f "$crt" && -f "$key" ]]; then
    echo "$crt|$key"
    return
  fi
  echo -e "${CYAN}🔐 Generating self-signed cert for TLS/WSS tests...${NC}"
  openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
    -keyout "$key" -out "$crt" -subj "/CN=kwekha.local" >/dev/null 2>&1
  echo "$crt|$key"
}

quality_test_server() {
  ensure_deps_test
  ensure_dirs
  [[ -x "$GOST_BIN" ]] || { echo -e "${RED}❌ gost not found. Install it first (menu 1).${NC}"; return 1; }

  read -r -p "Base port for tests (default 40000): " base
  base="${base:-40000}"
  local tid
  tid="$(gen_uuid)"
  [[ -z "$tid" ]] && tid="kwekha-test"

  # iperf3 server on localhost:5201
  echo -e "${CYAN}🚀 Starting iperf3 server on 127.0.0.1:5201 ...${NC}"
  iperf3 -s -D >/dev/null 2>&1 || true

  # dataset receiver (1000MB) on localhost:5202 (nc)
  # We'll start it on-demand per run; but keep one receiver up in loop.
  echo -e "${CYAN}📦 Dataset receiver will listen on 127.0.0.1:5202 (nc) ...${NC}"
  nohup bash -c "while true; do nc -l -p 5202 >/dev/null 2>&1; done" >/dev/null 2>&1 &

  local args=""
  local i=0
  local crt="" key=""
  while IFS= read -r s; do
    local port=$((base + i))
    if scheme_needs_tls "$s"; then
      IFS='|' read -r crt key <<<"$(ensure_test_cert)"
      args+=" -L ${s}://:$(($port))/127.0.0.1:5201?tunnel.id=${tid}&tls.certFile=${crt}&tls.keyFile=${key}"
      # dataset port (base+100)
      args+=" -L ${s}://:$(($port+100))/127.0.0.1:5202?tunnel.id=${tid}&tls.certFile=${crt}&tls.keyFile=${key}"
    else
      args+=" -L ${s}://:$(($port))/127.0.0.1:5201?tunnel.id=${tid}"
      args+=" -L ${s}://:$(($port+100))/127.0.0.1:5202?tunnel.id=${tid}"
    fi
    i=$((i+1))
  done <<< "$(recommended_schemes)"

  echo
  echo -e "${GREEN}✅ Server ready.${NC}"
  echo -e "Tunnel ID : ${tid}"
  echo -e "Base port : ${base}"
  echo -e "Ports used: ${base}.. (iperf3) and ${base}+100.. (dataset)"
  echo -e "${YELLOW}این ترمینال را باز نگه دار و روی سرور ایران (Client) گزینه Quality/Speed Test را اجرا کن.${NC}"
  echo
  exec ${GOST_BIN} ${args}
}

ms_now() {
  date +%s%3N 2>/dev/null || python3 - <<'PY' 2>/dev/null
import time; print(int(time.time()*1000))
PY
}

quality_test_client() {
  ensure_deps_test
  ensure_dirs
  [[ -x "$GOST_BIN" ]] || { echo -e "${RED}❌ gost not found. Install it first (menu 1).${NC}"; return 1; }

  local rip="" base="" tid=""
  read -r -p "IP/دامنه سرور خارج: " rip
  [[ -z "$rip" ]] && { echo -e "${RED}❌ Remote IP required.${NC}"; return 1; }
  read -r -p "Base port (default 40000): " base
  base="${base:-40000}"
  read -r -p "Tunnel ID (نمایش داده شده روی سرور خارج): " tid
  [[ -z "$tid" ]] && { echo -e "${RED}❌ Tunnel ID required.${NC}"; return 1; }

  local DURATION=8
  local DATA_MB=1000

  echo
  echo -e "${CYAN}🧪 Quality/Speed Test${NC} (duration=${DURATION}s, dataset=${DATA_MB}MB)"
  echo -e "Remote: ${rip} | BasePort: ${base} | TunnelID: ${tid}"
  echo

  printf "+----------------+--------+-----------+--------+---------+\n"
  printf "| %-14s | %-6s | %-9s | %-6s | %-7s|\n" "scheme" "OK?" "Mbps(8s)" "MB/s" "data_s"
  printf "+----------------+--------+-----------+--------+---------+\n"

  local i=0
  while IFS= read -r s; do
    local sport=$((base + i))         # iperf3
    local dport=$((base + i + 100))   # dataset receiver
    local lport=$((51000 + i))
    local ldata=$((52000 + i))
    local cert_param=""

    # Skip verify for self-signed
    if scheme_needs_tls "$s"; then
      cert_param="&tls.skipVerify=true"
    fi

    # Start forward for iperf3
    local cmd1="${GOST_BIN} -L tcp://127.0.0.1:${lport}/127.0.0.1:1 -F ${s}://${rip}:${sport}?tunnel.id=${tid}${cert_param}"
    (nohup bash -c "$cmd1" >"$LOG_DIR/qt-${s}-${lport}.log" 2>&1) &
    local pid1=$!
    sleep 0.5

    # Start forward for dataset
    local cmd2="${GOST_BIN} -L tcp://127.0.0.1:${ldata}/127.0.0.1:1 -F ${s}://${rip}:${dport}?tunnel.id=${tid}${cert_param}"
    (nohup bash -c "$cmd2" >"$LOG_DIR/qtdata-${s}-${ldata}.log" 2>&1) &
    local pid2=$!
    sleep 0.5

    local ok="NO" mbps="-" mbs="-" datas="-"

    if iperf3 -c 127.0.0.1 -p "${lport}" -t "${DURATION}" -f m >"/tmp/kwekha_speed_${s}" 2>/dev/null; then
      mbps="$(grep -Eo "[0-9]+\.[0-9]+ Mbits/sec|[0-9]+ Mbits/sec" "/tmp/kwekha_speed_${s}" | tail -1 | awk '{print $1}')"
      if [[ -n "$mbps" ]]; then
        mbs="$(echo "scale=2; $mbps/8" | bc 2>/dev/null || echo "-")"
        ok="YES"
      fi
      # dataset 1000MB to nc receiver via tunnel (measure seconds)
      local t0 t1
      t0="$(ms_now)"
      dd if=/dev/zero bs=1M count="${DATA_MB}" 2>/dev/null | nc 127.0.0.1 "${ldata}" >/dev/null 2>&1 || true
      t1="$(ms_now)"
      local ms=$((t1 - t0))
      if (( ms > 0 )); then
        datas="$(echo "scale=2; $ms/1000" | bc 2>/dev/null || echo "-")"
      fi
    fi

    kill "$pid1" >/dev/null 2>&1 || true
    kill "$pid2" >/dev/null 2>&1 || true
    sleep 0.05

    printf "| %-14s | %-6s | %-9s | %-6s | %-7s|\n" "${s}$(scheme_star "$s")" "$ok" "${mbps:-"-"}" "${mbs:-"-"}" "${datas:-"-"}"

    i=$((i+1))
  done <<< "$(recommended_schemes)"

  printf "+----------------+--------+-----------+--------+---------+\n"
  echo -e "${GREEN}✅ Done.${NC} (اگر بعضی fail شد: فایروال/پورت‌ها/اجرای سرور تست را چک کن.)"
  echo
  pause
}

quality_test_menu() {
  echo
  echo -e "${CYAN}🧪 Quality/Speed Test (Iran↔Abroad)${NC}"
  echo "این تست: اتصال + سرعت (iperf3) + انتقال دیتای واقعی (1000MB) را می‌سنجد."
  echo "UDP تست نمی‌شود."
  echo
  echo "این سرور نقش کدام طرف تست است؟"
  echo "1) خارج (Server) — listener ها + iperf3 receiver"
  echo "2) ایران (Client) — اجرای تست و جدول نتایج"
  read -r -p "انتخاب [1/2]: " side
  side="${side:-1}"
  if [[ "$side" == "1" ]]; then
    quality_test_server
  else
    quality_test_client
  fi
}

list_services() {
  ensure_dirs
  echo
  echo "Services:"
  ls -1 "$SVC_DIR" 2>/dev/null | sed 's/\.conf$//' || true
  echo
  systemctl list-units --type=service --no-pager | grep -E 'gost-kwekha-' || true
  echo
  pause
}

self_update() {
  local url="https://raw.githubusercontent.com/Zuvpn/Kwekha/main/kwekha.sh"
  local tmp="$(mktemp)"
  echo -e "${CYAN}⬇️  Downloading update...${NC}"
  curl -fsSL "$url" -o "$tmp"
  head -n 3 "$tmp" | grep -qE '^#!/usr/bin/env bash|^#!/bin/bash' || { echo -e "${RED}❌ فایل دانلودی معتبر نیست.${NC}"; rm -f "$tmp"; return 1; }
  grep -q "menu()" "$tmp" || { echo -e "${RED}❌ فایل دانلودی معتبر نیست.${NC}"; rm -f "$tmp"; return 1; }
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
    echo "4) Quality/Speed Test (8s + 1000MB) ⭐ NEW"
    echo "11) Self-update script"
    echo "0) Exit"
    echo
    read -r -p "Select: " sel
    case "${sel:-}" in
      1) need_root; install_gost; pause ;;
      2) need_root; wizard_fast ;;
      3) need_root; list_services ;;
      4) need_root; quality_test_menu ;;
      11) need_root; self_update ;;
      0) exit 0 ;;
      *) ;;
    esac
  done
}

menu
