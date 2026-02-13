#!/usr/bin/env bash

if [[ "${1:-}" == "healthcheck-run" ]]; then
  shift
  healthcheck_run
  exit 0
fi
set -euo pipefail

# =========================
#        K W E K H A
# =========================
# Repo: https://github.com/Zuvpn/Kwekha
# Fast wizard + systemd manager for gost.

UPDATE_URL_DEFAULT="https://raw.githubusercontent.com/Zuvpn/Kwekha/main/kwekha.sh"

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
  echo
}

print_kv_table() {
  # Usage: print_kv_table "TITLE" "Key1" "Val1" "Key2" "Val2" ...
  local title="$1"; shift
  echo
  echo "┌──────────────────────────────────────────────┐"
  printf "│ %-44s │\n" "$title"
  echo "├──────────────────────────────────────────────┤"
  while [[ $# -gt 0 ]]; do
    local k="$1"; local v="$2"; shift 2 || true
    # truncate very long values for clean display
    if [[ "${#v}" -gt 36 ]]; then v="${v:0:36}…"; fi
    printf "│ %-14s │ %-27s │\n" "$k" "$v"
  done
  echo "└──────────────────────────────────────────────┘"
  echo
}

need_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    echo "ERROR: لطفاً با sudo اجرا کن."
    exit 1
  fi
}

# Paths
BASE_DIR="/etc/kwekha"
SERVICES_DIR="$BASE_DIR/services"
LOG_DIR="/var/log/kwekha"
GOST_BIN="/usr/local/bin/gost"
TELE_ENV="$BASE_DIR/telegram.env"
TELE_SCRIPT="/usr/local/bin/kwekha-tg-status.sh"
CRON_FILE="/etc/cron.d/kwekha-status"
EXPORT_DIR="$BASE_DIR/exports"
UPDATE_URL_FILE="$BASE_DIR/update_url"

mkdirs() {
  mkdir -p "$BASE_DIR" "$SERVICES_DIR" "$LOG_DIR" "$EXPORT_DIR"
  chmod 700 "$BASE_DIR"
}

ensure_deps() {
  for cmd in curl tar sed awk; do
    command -v "$cmd" >/dev/null 2>&1 || echo "⚠️ نیاز به نصب: $cmd"
  done
}

install_gost() {
  mkdirs
  ensure_deps
  if [[ -x "$GOST_BIN" ]]; then
    echo "✅ gost already installed: $GOST_BIN"
    "$GOST_BIN" -V || true
    return 0
  fi
  echo "📦 Installing gost via official install.sh ..."
  bash <(curl -fsSL https://github.com/go-gost/gost/raw/master/install.sh) --install
  [[ -x "$GOST_BIN" ]] || { echo "❌ gost نصب نشد یا در $GOST_BIN پیدا نشد."; exit 1; }
  echo "✅ gost installed."
  "$GOST_BIN" -V || true
}

update_gost() {
  echo "⬆️ Updating gost (latest) ..."
  bash <(curl -fsSL https://github.com/go-gost/gost/raw/master/install.sh) --install
  echo "✅ gost updated."
  "$GOST_BIN" -V || true
}

uninstall_gost() {
  if [[ -x "$GOST_BIN" ]]; then
    rm -f "$GOST_BIN"
    echo "🗑️ removed: $GOST_BIN"
  else
    echo "ℹ️ gost not found at $GOST_BIN"
  fi
}

slugify() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g'
}

gen_uuid() {
  if command -v uuidgen >/dev/null 2>&1; then
    uuidgen | tr '[:upper:]' '[:lower:]'
    return
  fi
  if [[ -r /proc/sys/kernel/random/uuid ]]; then
    cat /proc/sys/kernel/random/uuid | tr '[:upper:]' '[:lower:]'
    return
  fi
  if command -v openssl >/dev/null 2>&1; then
    local hex
    hex="$(openssl rand -hex 16)"
    # RFC4122 v4-ish
    printf "%s-%s-4%s-%s%s-%s\n" "${hex:0:8}" "${hex:8:4}" "${hex:13:3}" \
      "$(printf "%x" $(( (0x${hex:16:2} & 0x3f) | 0x80 )) )" "${hex:18:2}" "${hex:20:12}"
    return
  fi
  date +%s%N | sha256sum | awk '{print $1}' | sed -E 's/^(.{8})(.{4})(.{4})(.{4})(.{12}).*/\1-\2-\3-\4-\5/'
}

check_loop_warning() {
  # جلوگیری از Loop وقتی target=localhost و خود gost روی همان پورت در حال Listen است
  # این فقط یک راهنمایی/سوال است (کانفیگ را خودکار تغییر نمی‌دهد) تا کاربر متوجه شود سرویس واقعی کجاست.
  local dest_host="$1" ports_csv="$2"
  [[ "$dest_host" == "127.0.0.1" || "$dest_host" == "localhost" ]] || return 0

  IFS=',' read -ra _ps <<< "$ports_csv"
  for p in "${_ps[@]}"; do
    p="${p// /}"
    [[ -n "$p" ]] || continue

    # اگر روی همین سرور، خود gost روی پورت مقصد Listen باشد، احتمال Loop/HostUnreachable بالاست
    if ss -lntp 2>/dev/null | grep -qE "[:.]${p}\s" && ss -lntp 2>/dev/null | grep -E "[:.]${p}\s" | grep -qi "gost"; then
      echo
      echo "⚠️ هشدار: پورت ${p} روی همین سرور (localhost) توسط خود gost در حال Listen است."
      echo "   این معمولاً یعنی شما دارید ترافیک را به خودِ تانل برمی‌گردانید (Loop)."
      echo
      echo "❓ سرویس واقعی Xray/Panel شما کجاست؟"
      echo "   1) روی ایران"
      echo "   2) روی خارج"
      echo
      local loc=""
      while true; do
        read -rp "انتخاب [1/2]: " loc
        case "$loc" in
          1|2) break ;;
          *) echo "فقط 1 یا 2 وارد کن." ;;
        esac
      done
      echo
      if [[ "$loc" == "1" ]]; then
        echo "✅ اگر Xray روی ایران است:"
        echo "   - روی ایران (Client) باید PORT ها به سرویس واقعی (xray/nginx/panel) فوروارد شوند."
        echo "   - مطمئن شو Xray روی همان PORT ها واقعاً LISTEN می‌کند (ss -lntp | grep :${p})."
        echo "   - اگر Xray روی PORT دیگری است، از Advanced Mapping استفاده کن (مثلاً tcp:${p}->127.0.0.1:8080)."
      else
        echo "✅ اگر Xray روی خارج است:"
        echo "   - روی خارج (Server) باید Xray/PANEL روی PORT مورد نظر LISTEN باشد."
        echo "   - روی ایران (Client) معمولاً فقط نقش تونل‌زن را داری و مقصد localhost:${p} نباید خود gost باشد."
        echo "   - اگر الان مقصد را 127.0.0.1:${p} گذاشتی و آنجا Xray نیست، خطای Host Unreachable می‌بینی."
      fi
      echo
      echo "🧪 تست سریع:"
      echo "   - روی سروری که Xray روش هست:   ss -lntp | grep :${p}"
      echo "   - روی سرور مقابل:              curl -I http://127.0.0.1:${p}/ (یا nc -vz 127.0.0.1 ${p})"
      echo
      break
    fi
  done
}



svc_unit_name() { echo "gost-kwekha-$1.service"; }
svc_conf_path() { echo "$SERVICES_DIR/$1.conf"; }
svc_log_path() { echo "$LOG_DIR/$1.log"; }

make_unit() {
  local name="$1"
  local cmd="$2"
  local unit="/etc/systemd/system/$(svc_unit_name "$name")"

  cat > "$unit" <<EOF
[Unit]
Description=Kwekha Gost Service ($name)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$GOST_BIN $cmd
Restart=always
RestartSec=2
LimitNOFILE=1048576
WorkingDirectory=$BASE_DIR
StandardOutput=append:$(svc_log_path "$name")
StandardError=append:$(svc_log_path "$name")

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
}

save_conf() {
  local name="$1"; shift
  {
    echo "# Kwekha service config: $name"
    echo "# generated at: $(date -Is)"
    for kv in "$@"; do echo "$kv"; done
  } > "$(svc_conf_path "$name")"
  chmod 600 "$(svc_conf_path "$name")"
}

get_kv() {
  local file="$1" key="$2"
  awk -F= -v k="$key" '
    $0 ~ /^#/ {next}
    NF>=2 && $1==k { $1=""; sub(/^=/,"",$0); print $0; exit }' "$file"
}

list_services() {
  mkdirs
  echo "📋 سرویس‌های ثبت‌شده:"
  if ! ls -1 "$SERVICES_DIR"/*.conf >/dev/null 2>&1; then
    echo " - (هیچ سرویسی ندارید)"
    return 0
  fi
  for f in "$SERVICES_DIR"/*.conf; do
    n="$(basename "$f" .conf)"
    u="$(svc_unit_name "$n")"
    st="$(systemctl is-active "$u" 2>/dev/null || true)"
    echo " - $n | unit=$u | status=$st | log=$(svc_log_path "$n")"
  done
}

start_service() { systemctl enable --now "$(svc_unit_name "$1")"; echo "✅ started: $(svc_unit_name "$1")"; }
stop_service() { systemctl stop "$(svc_unit_name "$1")" || true; echo "🛑 stopped: $(svc_unit_name "$1")"; }
restart_service() { systemctl restart "$(svc_unit_name "$1")"; echo "🔁 restarted: $(svc_unit_name "$1")"; }

remove_service() {
  local name="$1"
  local unit="/etc/systemd/system/$(svc_unit_name "$name")"
  systemctl stop "$(svc_unit_name "$name")" >/dev/null 2>&1 || true
  systemctl disable "$(svc_unit_name "$name")" >/dev/null 2>&1 || true
  rm -f "$unit" "$(svc_conf_path "$name")"
  systemctl daemon-reload
  echo "🗑️ removed: $name"
}

remove_all_services() {
  if ls -1 "$SERVICES_DIR"/*.conf >/dev/null 2>&1; then
    for f in "$SERVICES_DIR"/*.conf; do
      n="$(basename "$f" .conf)"
      remove_service "$n"
    done
  fi
}

kwekha_uninstall() {
  banner
  echo "🗑️ حذف نصب Kwekha"
  echo
  echo "این کار:"
  echo " - همه سرویس‌های gost-kwekha-* را حذف می‌کند"
  echo " - cron و telegram script را حذف می‌کند"
  echo " - پوشه‌های /etc/kwekha و /var/log/kwekha را پاک می‌کند"
  echo
  read -rp "ادامه می‌دی؟ (y/N): " yn
  [[ "${yn,,}" == "y" ]] || { echo "لغو شد."; return 0; }

  remove_all_services
  rm -f "$CRON_FILE" "$TELE_SCRIPT"
  rm -rf "$BASE_DIR" "$LOG_DIR"
  systemctl daemon-reload
  echo "✅ Kwekha removed."

  read -rp "آیا gost هم حذف شود؟ (y/N): " yg
  if [[ "${yg,,}" == "y" ]]; then
    uninstall_gost
  fi
}

choose_scheme_menu() {
  # Termius + command substitution can hide menu output. We avoid $(...) and set a global var.
  CHOSEN_SCHEME="relay+wss"

  echo
  echo "K W E K H A  —  Protocols"
  echo "انتخاب ترنسپورت/پروتکل (فقط عدد وارد کن):"
  echo "★ = پیشنهادی/پرکاربرد"
  echo
  cat <<'EOF'
  1) relay                 2) relay+tls ★        3) relay+ws          4) relay+wss ★
  5) relay+quic ★          6) http               7) http+tls          8) http+ws
  9) http+wss ★           10) socks5            11) socks5+tls       12) socks5+ws
 13) socks5+wss           14) ss                15) ss+udp           16) ws
 17) wss                  18) tls               19) quic ★           20) grpc ★
 21) h2 ★                 22) h2c               23) tcp              24) udp
 25) OTHER (manual scheme)
EOF
  echo
  read -rp "شماره: " c

  case "$c" in
    1) CHOSEN_SCHEME="relay" ;;
    2) CHOSEN_SCHEME="relay+tls" ;;
    3) CHOSEN_SCHEME="relay+ws" ;;
    4) CHOSEN_SCHEME="relay+wss" ;;
    5) CHOSEN_SCHEME="relay+quic" ;;
    6) CHOSEN_SCHEME="http" ;;
    7) CHOSEN_SCHEME="http+tls" ;;
    8) CHOSEN_SCHEME="http+ws" ;;
    9) CHOSEN_SCHEME="http+wss" ;;
    10) CHOSEN_SCHEME="socks5" ;;
    11) CHOSEN_SCHEME="socks5+tls" ;;
    12) CHOSEN_SCHEME="socks5+ws" ;;
    13) CHOSEN_SCHEME="socks5+wss" ;;
    14) CHOSEN_SCHEME="ss" ;;
    15) CHOSEN_SCHEME="ss+udp" ;;
    16) CHOSEN_SCHEME="ws" ;;
    17) CHOSEN_SCHEME="wss" ;;
    18) CHOSEN_SCHEME="tls" ;;
    19) CHOSEN_SCHEME="quic" ;;
    20) CHOSEN_SCHEME="grpc" ;;
    21) CHOSEN_SCHEME="h2" ;;
    22) CHOSEN_SCHEME="h2c" ;;
    23) CHOSEN_SCHEME="tcp" ;;
    24) CHOSEN_SCHEME="udp" ;;
    25) read -rp "scheme دلخواه را بنویس (مثلاً relay+wss): " ss; CHOSEN_SCHEME="${ss:-relay+wss}" ;;
    *) CHOSEN_SCHEME="relay+wss" ;;
  esac
}

choose_dest_mode() {
  # 1 = local (default), 2 = remote
  echo
  echo "🧩 سرویس مقصد (مثل Xray/Nginx/Panel) کجاست؟"
  echo "  1) روی همین سرور (Localhost - 127.0.0.1)  [اگر Xray همینجاست]"
  echo "  2) روی سرور مقابل (Remote)               [اگر Xray روی خارج است]"
  read -rp "انتخاب [1/2]: " dm
  case "${dm:-1}" in
    2) echo "remote" ;;
    *) echo "local" ;;
  esac
}

choose_dest_host() {
  local mode="$1" default_remote="$2"
  if [[ "$mode" == "remote" ]]; then
    if [[ -z "${default_remote:-}" ]]; then
      read -rp "🌐 IP/Domain سرور مقابل: " default_remote
    fi
    read -rp "🌐 مقصد (پیش‌فرض: ${default_remote}): " dh
    echo "${dh:-$default_remote}"
  else
    echo "127.0.0.1"
  fi
}









print_summary_table() {
  local role="$1" name="$2" scheme="$3" tunnel_port="$4" ports="$5" peer="$6"
  local role_txt="Unknown"
  [[ "$role" == "1" ]] && role_txt="خارج (Server)"
  [[ "$role" == "2" ]] && role_txt="ایران (Client)"

  echo
  echo "✅ خلاصه تنظیمات انتخاب‌شده"
  echo

  # Simple ASCII table
  printf "+----------------------+------------------------------------------+
"
  printf "| %-20s | %-40s |
" "Role" "$role_txt"
  printf "+----------------------+------------------------------------------+
"
  printf "| %-20s | %-40s |
" "Service name" "$name"
  printf "| %-20s | %-40s |
" "Protocol (scheme)" "$scheme"
  printf "| %-20s | %-40s |
" "Tunnel port (Kharej)" "$tunnel_port"
  printf "| %-20s | %-40s |
" "Ports" "$ports"
  if [[ -n "${peer:-}" ]]; then
    printf "| %-20s | %-40s |
" "Kharej IP/Domain" "$peer"
  else
    printf "| %-20s | %-40s |
" "Kharej IP/Domain" "-"
  fi
  printf "+----------------------+------------------------------------------+
"
  echo
  echo "📌 راهنما برای سرور مقابل:"
  echo " - Service name / Protocol / Tunnel port / Ports باید دقیقاً یکی باشد."
  if [[ "$role" == "1" ]]; then
    echo " - روی ایران فقط IP/Domain خارج را هم وارد کن."
  fi
  echo
}

parse_ports_simple() {
  # args: ports_csv dest_host
  local dest_host="${2:-127.0.0.1}"

  local raw="$1"
  raw="$(echo "$raw" | tr -d ' ')"
  IFS=',' read -ra ports <<< "$raw"
  for p in "${ports[@]}"; do
    [[ -z "$p" ]] && continue
    [[ "$p" =~ ^[0-9]{1,5}$ ]] || { echo "❌ پورت نامعتبر: $p"; exit 1; }
    echo "tcp://:${p}/${dest_host}:${p}"
  done
}

# ==========================
# Quick Setup Wizard (FAST)
# ==========================
quick_setup_wizard() {
  banner
  echo "🧭 راه‌انداز سریع Kwekha (ساده و سریع)"
  echo
  echo "روی هر دو سرور همین Wizard را اجرا کن:"
  echo " - خارج: نقش 1 (Server)"
  echo " - ایران: نقش 2 (Client)"
  echo

  install_gost

  echo "نقش این سرور چیست؟ (فقط عدد)"
  echo "1) خارج (Server)"
  echo "2) ایران (Client)"
  read -rp "انتخاب [1/2]: " role
  echo

  read -rp "اسم سرویس (مثلاً main-tunnel): " name_raw
  local name; name="$(slugify "$name_raw")"
  [[ -n "$name" ]] || { echo "❌ اسم نامعتبر"; return 1; }

  echo
  echo "📌 ترنسپورت ارتباط ایران↔خارج"
  local scheme
  choose_scheme_menu
  scheme="${CHOSEN_SCHEME:-relay+wss}"
echo
  read -rp "پورت تونل روی سرور خارج (مثلاً 443 یا 8443): " tunnel_port
  [[ -n "$tunnel_port" ]] || { echo "❌ پورت تونل خالی است"; return 1; }

  echo
  # اگر نقش ایران است، اول IP/Domain سرور خارج را بگیر تا برای مقصد ریموت هم استفاده شود
  local kharej_host=""
  if [[ "$role" == "2" ]]; then
    read -rp "آی‌پی/دامنه سرور خارج: " kharej_host
    [[ -n "$kharej_host" ]] || { echo "❌ آی‌پی/دامنه خارج لازم است"; return 1; }
  fi

  echo
  echo "📦 پورت‌ها (فقط شماره‌ها) مثال: 80,443,2053"
  read -rp "Ports: " ports_simple
  [[ -n "$ports_simple" ]] || { echo "❌ لیست پورت خالی است"; return 1; }

  # مقصد فوروارد: فقط برای نقش ایران معنی‌دار است
  local dest_host="127.0.0.1"
  if [[ "$role" == "2" ]]; then
    local dest_mode
    dest_mode="$(choose_dest_mode)"
    dest_host="$(choose_dest_host "$dest_mode" "$kharej_host")"
    check_loop_warning "$dest_host" "$ports_simple"
  fi


  # خلاصه تنظیمات انتخاب‌شده (برای کپی روی سرور مقابل)
  local role_txt="Server(خارج)"
  [[ "$role" == "2" ]] && role_txt="Client(ایران)"
  local best_note="★ Best: relay+wss / relay+tls / relay+ws / grpc / h2"
  print_kv_table "Summary (کپی کن برای سرور مقابل)" \
    "Role" "$role_txt" \
    "Service" "$name" \
    "Protocol" "$scheme" \
    "TunnelPort" "$tunnel_port" \
    "Ports" "$ports_simple" \
    "RemoteIP" "${kharej_host:-N/A}"
  echo "$best_note"

  mkdirs

  # No UUID / no auth: tunnel.id derived from service name
  local tid
  if [[ -f "$(svc_conf_path "$name")" ]]; then
    tid="$(get_kv "$(svc_conf_path "$name")" "TUNNEL_ID" || true)"
  fi
  [[ -n "${tid:-}" ]] || tid="$(gen_uuid)"
  local ts="tunnel+${scheme}"

  if [[ "$role" == "1" ]]; then
    local cmd=""
    cmd+="-L ${ts}://:${tunnel_port}?tunnel.id=${tid} "
    while IFS= read -r L; do
      p="$(echo "$L" | sed -E 's#^(tcp|udp)://:([0-9]+)/.*#\2#')"
      cmd+="-L rtcp://:${p}/:0 "
    done < <(parse_ports_simple "$ports_simple" "$dest_host")

    save_conf "$name" "MODE=WIZARD_SERVER" "TUNNEL_ID=$tid" "TUNNEL_SCHEME=$ts" "TUNNEL_PORT=$tunnel_port" "PORTS=simple:${ports_simple}" "ARGS=$cmd"
    make_unit "$name" "$cmd"
    start_service "$name"

    echo
    echo "🎉 خارج آماده شد."
    echo "✅ روی ایران همین اسم سرویس را وارد کن: $name"
    echo "✅ وضعیت: systemctl status $(svc_unit_name "$name") --no-pager"
    echo "ℹ️ پورت تونل $tunnel_port باید روی خارج باز باشد."
print_kv_table "برای سرور ایران همین‌ها را بزن" "Role" "Client(ایران)" "Service" "$name" "Protocol" "$scheme" "TunnelPort" "$tunnel_port" "Ports" "$ports_simple" "RemoteIP" "<IP_KHAREJ>"


  elif [[ "$role" == "2" ]]; then
    local cmd=""
    while IFS= read -r L; do
      cmd+="-L $L "
    done < <(parse_ports_simple "$ports_simple" "$dest_host")
    cmd+="-F ${ts}://${kharej_host}:${tunnel_port}?tunnel.id=${tid}"

    save_conf "$name" "MODE=WIZARD_CLIENT" "TUNNEL_ID=$tid" "TUNNEL_SCHEME=$ts" "SERVER=${kharej_host}:${tunnel_port}" "PORTS=simple:${ports_simple}" "ARGS=$cmd"
    make_unit "$name" "$cmd"
    start_service "$name"

    echo
    echo "🎉 ایران آماده شد."
    echo "✅ وضعیت: systemctl status $(svc_unit_name "$name") --no-pager"
    echo "🧪 تست: یکی از پورت‌ها را روی IP خارج تست کن (مثلاً https://IP_KHAREJ:443)."
print_kv_table "یادآوری: تنظیمات باید با سرور خارج یکی باشد" "Role" "Server(خارج)" "Service" "$name" "Protocol" "$scheme" "TunnelPort" "$tunnel_port" "Ports" "$ports_simple" "RemoteIP" "${kharej_host}"

  else
    echo "❌ انتخاب نقش نامعتبر"
    return 1
  fi
}

# ==========================
# Export / Import
# ==========================
export_config() {
  mkdirs
  ts="$(date +%Y%m%d-%H%M%S)"
  out="$EXPORT_DIR/kwekha-export-$ts.tar.gz"
  tar -czf "$out" -C / "etc/kwekha" "etc/systemd/system" "etc/cron.d/kwekha-status" "usr/local/bin/kwekha-tg-status.sh" 2>/dev/null || true
  echo "✅ Export: $out"
}

import_config() {
  need_root
  read -rp "مسیر فایل export (tar.gz): " f
  [[ -f "$f" ]] || { echo "❌ فایل پیدا نشد"; exit 1; }
  tar -xzf "$f" -C / || { echo "❌ خطا در extract"; exit 1; }
  systemctl daemon-reload
  if ls -1 "$SERVICES_DIR"/*.conf >/dev/null 2>&1; then
    for c in "$SERVICES_DIR"/*.conf; do
      n="$(basename "$c" .conf)"
      systemctl enable --now "$(svc_unit_name "$n")" || true
    done
  fi
  echo "✅ Import complete."
  list_services
}

# ==========================
# Health check
# ==========================
health_check() {
  mkdirs
  echo "🩺 Health Check:"
  echo
  if ! ls -1 "$SERVICES_DIR"/*.conf >/dev/null 2>&1; then
    echo "هیچ سرویسی وجود ندارد."
    return 0
  fi
  if ! command -v ss >/dev/null 2>&1; then
    echo "⚠️ ss نصب نیست (iproute2). فقط وضعیت systemd چک می‌شود."
  fi
  for f in "$SERVICES_DIR"/*.conf; do
    n="$(basename "$f" .conf)"
    u="$(svc_unit_name "$n")"
    st="$(systemctl is-active "$u" 2>/dev/null || true)"
    echo "— $n  (systemd: $st)"
    ports_raw="$(get_kv "$f" "PORTS" || true)"
    if [[ -n "${ports_raw:-}" ]] && command -v ss >/dev/null 2>&1; then
      echo "  Listen ports:"
      if [[ "$ports_raw" == simple:* ]]; then
        echo "${ports_raw#simple:}" | tr ',' '\n' | tr -d ' ' | while read -r p; do
          [[ -z "$p" ]] && continue
          if ss -lntp 2>/dev/null | grep -q ":${p} "; then
            echo "   ✅ tcp :$p"
          else
            echo "   ❌ tcp :$p (not listening)"
          fi
        done
      fi
    fi
    echo
  done
}

# ==========================
# Telegram + cron
# ==========================
telegram_setup() {
  mkdirs
  read -rp "Telegram BOT TOKEN: " token
  read -rp "Telegram CHAT ID: " chat
  read -rp "چند خط لاگ برای هر سرویس ارسال شود؟ (پیشفرض 20): " tailn
  tailn="${tailn:-20}"

  cat > "$TELE_ENV" <<EOF
BOT_TOKEN="$token"
CHAT_ID="$chat"
TAIL_LINES="$tailn"
EOF
  chmod 600 "$TELE_ENV"

  cat > "$TELE_SCRIPT" <<'EOF'
#!/usr/bin/env bash

if [[ "${1:-}" == "healthcheck-run" ]]; then
  shift
  healthcheck_run
  exit 0
fi
set -euo pipefail
ENV_FILE="/etc/kwekha/telegram.env"
SERVICES_DIR="/etc/kwekha/services"
LOG_DIR="/var/log/kwekha"

[[ -f "$ENV_FILE" ]] || exit 0
# shellcheck disable=SC1090
source "$ENV_FILE"

TAIL_LINES="${TAIL_LINES:-20}"

send() {
  local text="$1"
  if [[ "${#text}" -gt 3500 ]]; then
    text="${text:0:3500}\n...(truncated)"
  fi
  curl -fsSL -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
    -d "chat_id=${CHAT_ID}" \
    -d "text=${text}" \
    -d "disable_web_page_preview=true" >/dev/null
}

host="$(hostname)"
now="$(date -Is)"
msg="Kwekha Status | ${host} | ${now}\n\n"

if ! ls -1 "${SERVICES_DIR}"/*.conf >/dev/null 2>&1; then
  msg+="No services.\n"
  send "$msg"
  exit 0
fi

for f in "${SERVICES_DIR}"/*.conf; do
  n="$(basename "$f" .conf)"
  u="gost-kwekha-${n}.service"
  st="$(systemctl is-active "$u" 2>/dev/null || true)"
  en="$(systemctl is-enabled "$u" 2>/dev/null || true)"
  msg+="${n} | active=${st} | enabled=${en}\n"

  log="${LOG_DIR}/${n}.log"
  if [[ -f "$log" ]]; then
    msg+="--- last ${TAIL_LINES} lines ---\n"
    msg+="$(tail -n "$TAIL_LINES" "$log" | sed 's/\r//g')\n"
    msg+="------------------------\n"
  else
    msg+="(no log)\n"
  fi
  msg+="\n"
done

send "$msg"
EOF
  chmod +x "$TELE_SCRIPT"
  echo "✅ Telegram script ساخته شد."
}

cron_enable() {
  mkdirs
  [[ -f "$TELE_ENV" ]] || { echo "❌ اول telegram setup رو انجام بده."; exit 1; }
  cat > "$CRON_FILE" <<EOF
SHELL=/bin/bash
PATH=/usr/sbin:/usr/bin:/sbin:/bin:/usr/local/bin
0 * * * * root $TELE_SCRIPT
EOF
  chmod 644 "$CRON_FILE"
  echo "✅ کرون فعال شد (هر ۱ ساعت)."
}

cron_disable() { rm -f "$CRON_FILE"; echo "🛑 کرون غیرفعال شد."; }

# ==========================
# Self-update
# ==========================
get_update_url() { [[ -f "$UPDATE_URL_FILE" ]] && cat "$UPDATE_URL_FILE" || echo "$UPDATE_URL_DEFAULT"; }

set_update_url() {
  mkdirs
  read -rp "Update URL (raw kwekha.sh): " u
  [[ -n "$u" ]] || { echo "❌ خالی است"; return 1; }
  echo "$u" > "$UPDATE_URL_FILE"
  chmod 600 "$UPDATE_URL_FILE"
  echo "✅ Saved."
}

self_update() {
  banner
  url="$(get_update_url)"
  echo "⬆️ آپدیت خودکار اسکریپت"
  echo "URL: $url"
  echo
  self="$(readlink -f "$0" 2>/dev/null || echo "$0")"
  tmp="/tmp/kwekha.sh.$$"
  curl -fsSL "$url" -o "$tmp" || { echo "❌ دانلود ناموفق"; return 1; }
  # validate downloaded script (production-safe)
head -n 3 "$tmp" | grep -qE '^#!/usr/bin/env bash|^#!/bin/bash' || { echo "❌ فایل دانلودی معتبر نیست (shebang)."; rm -f "$tmp"; return 1; }
grep -q "main_menu()" "$tmp" || { echo "❌ فایل دانلودی معتبر نیست (kwekha marker)."; rm -f "$tmp"; return 1; }
  cp -a "$self" "${self}.bak.$(date +%Y%m%d-%H%M%S)" || true
  install -m 755 "$tmp" "$self"
  rm -f "$tmp"
  echo "✅ آپدیت انجام شد."
  echo "ℹ️ دوباره اجرا کن: sudo $self"
}

# ======================
# Menu
# ======================
menu() {
  banner
  echo "⭐ پیشنهاد سریع: 3) Quick Setup Wizard"
  echo
  echo "1) Install gost"
  echo "2) Update gost (latest)"
  echo "3) Quick Setup Wizard (FAST)"
  echo "4) List services"
  echo "5) Health check"
  echo "6) Telegram setup"
  echo "7) Enable cron (hourly telegram)"
  echo "8) Disable cron"
  echo "9) Export config"
  echo "10) Import config"
  echo "11) Self-update script"
  echo "12) Set update URL"
  echo "13) Start a service"
  echo "14) Stop a service"
  echo "15) Restart a service"
  echo "16) Remove a service"
  echo "17) Uninstall Kwekha (and optional gost)"
  echo "0) Exit"
  echo
  read -rp "Select: " c
  case "$c" in
    1) install_gost ;;
    2) update_gost ;;
    3) quick_setup_wizard ;;
    4) list_services ;;
    5) health_check ;;
    6) telegram_setup ;;
    7) cron_enable ;;
    8) cron_disable ;;
    9) export_config ;;
    10) import_config ;;
    11) self_update ;;
    12) set_update_url ;;
    13) read -rp "Service name: " n; start_service "$(slugify "$n")" ;;
    14) read -rp "Service name: " n; stop_service "$(slugify "$n")" ;;
    15) read -rp "Service name: " n; restart_service "$(slugify "$n")" ;;
    16) read -rp "Service name: " n; remove_service "$(slugify "$n")" ;;
    17) kwekha_uninstall ;;
    0) exit 0 ;;
    *) echo "Invalid" ;;
  esac
}

main() {
  need_root
  mkdirs
  if [[ "${1:-}" == "" ]]; then
    while true; do
      menu
      echo
      read -rp "Enter to continue..." _
    done
  fi
}

main "$@"
