#!/usr/bin/env bash
set -euo pipefail

# =========================
#        K W E K H A
# =========================
# Repo: https://github.com/Zuvpn/Kwekha
# This script manages gost services via systemd and provides a guided wizard.

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
  # soft dependency check (no hard fail to keep it easy)
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
  # Official installer supports --install (latest) or interactive select
  bash <(curl -fsSL https://github.com/go-gost/gost/raw/master/install.sh) --install

  if [[ ! -x "$GOST_BIN" ]]; then
    echo "❌ gost نصب نشد یا در $GOST_BIN پیدا نشد."
    exit 1
  fi

  echo "✅ gost installed: $GOST_BIN"
  "$GOST_BIN" -V || true
}

update_gost() {
  echo "⬆️ Updating gost via official install.sh (latest)..."
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
    local n u st
    n="$(basename "$f" .conf)"
    u="$(svc_unit_name "$n")"
    st="$(systemctl is-active "$u" 2>/dev/null || true)"
    echo " - $n | unit=$u | status=$st | log=$(svc_log_path "$n")"
  done
}

start_service() {
  local name="$1"
  systemctl enable --now "$(svc_unit_name "$name")"
  echo "✅ started: $(svc_unit_name "$name")"
}
stop_service() {
  local name="$1"
  systemctl stop "$(svc_unit_name "$name")" || true
  echo "🛑 stopped: $(svc_unit_name "$name")"
}
restart_service() {
  local name="$1"
  systemctl restart "$(svc_unit_name "$name")"
  echo "🔁 restarted: $(svc_unit_name "$name")"
}
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
  echo "🧹 Removing ALL Kwekha services..."
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
  echo "انتخاب ترنسپورت (scheme):"
  cat <<'EOF'
  1) relay
  2) relay+tls
  3) relay+ws
  4) relay+wss
  5) relay+quic
  6) grpc
  7) h2
  8) quic
  9) CUSTOM
EOF
  read -rp "شماره: " c
  case "$c" in
    1) echo "relay" ;;
    2) echo "relay+tls" ;;
    3) echo "relay+ws" ;;
    4) echo "relay+wss" ;;
    5) echo "relay+quic" ;;
    6) echo "grpc" ;;
    7) echo "h2" ;;
    8) echo "quic" ;;
    9) read -rp "scheme سفارشی (مثلاً relay+wss): " s; echo "$s" ;;
    *) echo "relay+wss" ;;
  esac
}

# Advanced mapping: tcp:2222->127.0.0.1:22,udp:53->8.8.8.8:53
parse_ports_advanced() {
  local raw="$1"
  IFS=',' read -ra items <<< "$raw"
  for it in "${items[@]}"; do
    it="$(echo "$it" | xargs)"
    [[ -z "$it" ]] && continue

    local proto="tcp"
    if [[ "$it" =~ ^(tcp|udp):(.+)$ ]]; then
      proto="${BASH_REMATCH[1]}"
      it="${BASH_REMATCH[2]}"
    fi

    if [[ ! "$it" =~ ^([0-9]+)->([^:]+):([0-9]+)$ ]]; then
      echo "❌ فرمت اشتباه: $it"
      echo "مثال: tcp:80->127.0.0.1:80,udp:53->8.8.8.8:53"
      exit 1
    fi

    local lport="${BASH_REMATCH[1]}"
    local host="${BASH_REMATCH[2]}"
    local rport="${BASH_REMATCH[3]}"

    if [[ "$proto" == "tcp" ]]; then
      echo "tcp://:${lport}/${host}:${rport}"
    else
      echo "udp://:${lport}/${host}:${rport}"
    fi
  done
}

# Simple ports: 80,443,2053  -> defaults to tcp://:p/127.0.0.1:p
parse_ports_simple() {
  local raw="$1"
  raw="$(echo "$raw" | tr -d ' ')"
  IFS=',' read -ra ports <<< "$raw"
  for p in "${ports[@]}"; do
    [[ -z "$p" ]] && continue
    if [[ ! "$p" =~ ^[0-9]{1,5}$ ]]; then
      echo "❌ پورت نامعتبر: $p"
      exit 1
    fi
    echo "tcp://:${p}/127.0.0.1:${p}"
  done
}

extract_listen_ports() {
  local ports_raw="$1"
  local out=()
  IFS=',' read -ra items <<< "$ports_raw"
  for it in "${items[@]}"; do
    it="$(echo "$it" | xargs)"
    [[ -z "$it" ]] && continue
    it="${it#tcp:}"
    it="${it#udp:}"
    local left="${it%%->*}"
    if [[ "$left" =~ ^[0-9]+$ ]]; then
      out+=("$left")
    fi
  done
  printf '%s\n' "${out[@]}" | awk '!seen[$0]++'
}

# ==========================
# Quick Setup Wizard (Guided)
# ==========================
quick_setup_wizard() {
  banner
  echo "🧭 راه‌انداز سریع Kwekha"
  echo
  echo "هدف: روی هر دو سرور (خارج و ایران) همین Wizard را اجرا کن."
  echo " - روی خارج: نقش 1 را انتخاب کن (Server)"
  echo " - روی ایران: نقش 2 را انتخاب کن (Client)"
  echo
  echo "این Wizard فقط با چند ورودی ساده سرویس را می‌سازد و روشن می‌کند."
  echo

  install_gost

  echo "نقش این سرور چیست؟"
  echo "1) خارج (Server)  — تونل را گوش می‌کند و پورت‌های عمومی می‌سازد"
  echo "2) ایران (Client) — پورت‌های داخلی را داخل تونل فوروارد می‌کند"
  read -rp "انتخاب [1/2]: " role
  echo

  read -rp "اسم سرویس (مثلاً main-tunnel): " name_raw
  local name; name="$(slugify "$name_raw")"
  [[ -z "$name" ]] && { echo "❌ اسم نامعتبر"; return 1; }

  echo
  echo "📌 ترنسپورت ارتباط ایران↔خارج (پیشنهادی: relay+wss)"
  local scheme
  scheme="$(choose_scheme_menu)"
  [[ -z "$scheme" ]] && scheme="relay+wss"

  echo
  read -rp "پورت تونل روی سرور خارج (مثلاً 443 یا 8443): " tunnel_port
  [[ -z "$tunnel_port" ]] && { echo "❌ پورت تونل خالی است"; return 1; }

  echo
  read -rp "TUNNEL ID (اگر نداری Enter بزن تا بسازم): " tid
  if [[ -z "$tid" ]]; then
    tid="$(cat /proc/sys/kernel/random/uuid 2>/dev/null || true)"
    [[ -z "$tid" ]] && tid="$(date +%s)-$RANDOM-$RANDOM"
  fi

  echo
  echo "🔐 احراز هویت تونل (اختیاری)"
  read -rp "یوزرنیم (Enter = خالی): " user
  read -rp "پسورد  (Enter = خالی): " pass
  local auth=""
  if [[ -n "${user:-}" || -n "${pass:-}" ]]; then
    auth="${user:-}:${pass:-}@"
  fi

  echo
  echo "📦 پورت‌هایی که می‌خواهی منتشر شوند (فقط شماره پورت‌ها)"
  echo "مثال: 80,443,2053"
  read -rp "Ports: " ports_simple
  [[ -z "$ports_simple" ]] && { echo "❌ لیست پورت خالی است"; return 1; }

  echo
  read -rp "می‌خواهی مپینگ پیشرفته هم بدهی؟ (tcp:2222->127.0.0.1:22) (y/N): " adv
  local ports_raw=""
  if [[ "${adv,,}" == "y" ]]; then
    echo "فرمت پیشرفته: tcp:2222->127.0.0.1:22, tcp:8080->127.0.0.1:8080"
    read -rp "Advanced Ports: " ports_raw
    [[ -z "$ports_raw" ]] && { echo "❌ لیست پیشرفته خالی است"; return 1; }
  else
    # Store as "simple:" for conf readability
    ports_raw="simple:${ports_simple}"
  fi

  echo
  local kharej_host=""
  if [[ "$role" == "2" ]]; then
    read -rp "آی‌پی/دامنه سرور خارج: " kharej_host
    [[ -n "$kharej_host" ]] || { echo "❌ آی‌پی/دامنه خارج لازم است"; return 1; }
  fi

  mkdirs

  local ts="tunnel+${scheme}"

  # Build -L list
  build_Ls() {
    if [[ "$ports_raw" == simple:* ]]; then
      parse_ports_simple "${ports_raw#simple:}"
    else
      parse_ports_advanced "$ports_raw"
    fi
  }

  if [[ "$role" == "1" ]]; then
    banner
    echo "✅ نقش: خارج (Server)"
    echo
    echo "راهنما:"
    echo " - این سرور روی پورت تونل :$tunnel_port گوش می‌دهد."
    echo " - برای هر پورت شما، یک پورت عمومی روی همین سرور ایجاد می‌شود."
    echo " - سپس روی سرور ایران Wizard را اجرا کن و همین Tunnel ID را وارد کن."
    echo

    local cmd=""
    cmd+="-L ${ts}://:${tunnel_port}?tunnel.id=${tid} "

    while IFS= read -r L; do
      local p
      p="$(echo "$L" | sed -E 's#^(tcp|udp)://:([0-9]+)/.*#\2#')"
      cmd+="-L rtcp://:${p}/:0 "
    done < <(build_Ls)

    save_conf "$name" "MODE=QS_REVERSE_SERVER" "TUNNEL_ID=$tid" "TUNNEL_SCHEME=$ts" "TUNNEL_PORT=$tunnel_port" "PORTS=$ports_raw" "ARGS=$cmd"
    make_unit "$name" "$cmd"
    start_service "$name"

    echo
    echo "🎉 انجام شد."
    echo "🔑 Tunnel ID (برای سرور ایران): $tid"
    echo "✅ وضعیت: systemctl status $(svc_unit_name "$name") --no-pager"
    echo "ℹ️ نکته: پورت تونل $tunnel_port باید روی خارج باز باشد."

  elif [[ "$role" == "2" ]]; then
    banner
    echo "✅ نقش: ایران (Client)"
    echo
    echo "راهنما:"
    echo " - این سرور به خارج ${kharej_host}:${tunnel_port} وصل می‌شود."
    echo " - پورت‌های انتخابی شما را از 127.0.0.1 به تونل می‌فرستد (یا مپینگ پیشرفته)."
    echo

    local cmd=""
    while IFS= read -r L; do
      cmd+="-L $L "
    done < <(build_Ls)

    cmd+="-F ${ts}://${auth}${kharej_host}:${tunnel_port}?tunnel.id=${tid}"

    save_conf "$name" "MODE=QS_REVERSE_CLIENT" "TUNNEL_ID=$tid" "TUNNEL_SCHEME=$ts" "SERVER=${kharej_host}:${tunnel_port}" "PORTS=$ports_raw" "ARGS=$cmd"
    make_unit "$name" "$cmd"
    start_service "$name"

    echo
    echo "🎉 انجام شد."
    echo "✅ وضعیت: systemctl status $(svc_unit_name "$name") --no-pager"
    echo "🧪 تست: یکی از پورت‌ها را روی IP خارج تست کن (مثلاً https://IP_KHAREJ:443)."

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
  local ts; ts="$(date +%Y%m%d-%H%M%S)"
  local out="$EXPORT_DIR/kwekha-export-$ts.tar.gz"

  tar -czf "$out" \
    -C / \
    "etc/kwekha" \
    "etc/systemd/system" \
    "etc/cron.d/kwekha-status" \
    "usr/local/bin/kwekha-tg-status.sh" 2>/dev/null || true

  echo "✅ Export ساخته شد:"
  echo "$out"
  echo
  echo "📦 انتقال:"
  echo "scp $out root@SERVER:/root/"
}

import_config() {
  need_root
  read -rp "مسیر فایل export (tar.gz): " f
  [[ -f "$f" ]] || { echo "❌ فایل پیدا نشد"; exit 1; }

  echo "📥 Importing..."
  tar -xzf "$f" -C / || { echo "❌ خطا در extract"; exit 1; }

  systemctl daemon-reload

  if ls -1 "$SERVICES_DIR"/*.conf >/dev/null 2>&1; then
    for c in "$SERVICES_DIR"/*.conf; do
      n="$(basename "$c" .conf)"
      systemctl enable --now "$(svc_unit_name "$n")" || true
    done
  fi

  echo "✅ Import کامل شد."
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
        while IFS= read -r p; do
          if ss -lntp 2>/dev/null | grep -q ":${p} "; then
            echo "   ✅ tcp :$p"
          else
            echo "   ❌ tcp :$p (not listening)"
          fi
        done < <(echo "${ports_raw#simple:}" | tr ',' '\n' | tr -d ' ')
      else
        while IFS= read -r p; do
          if ss -lntp 2>/dev/null | grep -q ":${p} "; then
            echo "   ✅ tcp :$p"
          elif ss -lnup 2>/dev/null | grep -q ":${p} "; then
            echo "   ✅ udp :$p"
          else
            echo "   ❌ :$p (not listening)"
          fi
        done < <(extract_listen_ports "$ports_raw")
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
  # Telegram limit ~4096 chars, keep margin
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
  echo "✅ Telegram status+logs script ساخته شد."
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

cron_disable() {
  rm -f "$CRON_FILE"
  echo "🛑 کرون غیرفعال شد."
}

# ==========================
# Script self-update
# ==========================
get_update_url() {
  if [[ -f "$UPDATE_URL_FILE" ]]; then
    cat "$UPDATE_URL_FILE"
  else
    echo "$UPDATE_URL_DEFAULT"
  fi
}

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
  local url
  url="$(get_update_url)"
  echo "⬆️ آپدیت خودکار اسکریپت"
  echo "URL: $url"
  echo

  local self
  self="$(readlink -f "$0" 2>/dev/null || echo "$0")"
  [[ -n "$self" ]] || { echo "❌ مسیر فایل پیدا نشد"; return 1; }

  echo "در حال دانلود نسخه جدید..."
  local tmp="/tmp/kwekha.sh.$$"
  curl -fsSL "$url" -o "$tmp" || { echo "❌ دانلود ناموفق"; return 1; }

  # sanity check
  if ! head -n 5 "$tmp" | grep -qi "K W E K H A"; then
    echo "❌ فایل دانلودی معتبر نیست."
    rm -f "$tmp"
    return 1
  fi

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
  echo "⭐ پیشنهاد سریع: 16) Quick Setup Wizard"
  echo
  echo "1) Install gost (official install.sh)"
  echo "2) Update gost (latest via install.sh)"
  echo "3) Quick Setup Wizard (guided Iran/Kharej)"
  echo "4) List services"
  echo "5) Health check (systemd + listen ports)"
  echo "6) Telegram setup (status + log tail)"
  echo "7) Enable cron (hourly telegram)"
  echo "8) Disable cron"
  echo "9) Export config (tar.gz)"
  echo "10) Import config (tar.gz)"
  echo "11) Self-update script"
  echo "12) Set update URL"
  echo "13) Remove a service"
  echo "14) Restart a service"
  echo "15) Stop a service"
  echo "16) Start a service"
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
    13) read -rp "Service name: " n; remove_service "$(slugify "$n")" ;;
    14) read -rp "Service name: " n; restart_service "$(slugify "$n")" ;;
    15) read -rp "Service name: " n; stop_service "$(slugify "$n")" ;;
    16) read -rp "Service name: " n; start_service "$(slugify "$n")" ;;
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
