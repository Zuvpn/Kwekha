
#!/usr/bin/env bash
set -euo pipefail

VERSION="1.5.0-speedtest"
BASE_DIR="/etc/kwekha"
LOG_DIR="/var/log/kwekha"
GOST_BIN="/usr/local/bin/gost"

need_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    echo "Run as root."
    exit 1
  fi
}

ensure_deps() {
  apt-get update -y >/dev/null 2>&1 || true
  apt-get install -y iproute2 curl netcat-openbsd iperf3 bc >/dev/null 2>&1 || true
}

recommended_schemes() {
  printf "%s\n"     "relay+wss"     "relay+tls"     "relay+ws"     "grpc"     "h2"     "tcp"
}

gen_uuid() {
  cat /proc/sys/kernel/random/uuid
}

speedtest_server() {
  ensure_deps
  read -rp "Base port (default 40000): " base
  base="${base:-40000}"
  uuid="$(gen_uuid)"

  echo "Starting iperf3 server (localhost:5201)..."
  iperf3 -s -D

  args=""
  i=0
  while read -r s; do
    port=$((base + i))
    args+=" -L ${s}://:${port}/127.0.0.1:5201?tunnel.id=${uuid}"
    i=$((i+1))
  done <<< "$(recommended_schemes)"

  echo "Tunnel ID: $uuid"
  echo "Base port: $base"
  echo "Keep this terminal open."
  exec ${GOST_BIN} ${args}
}

speedtest_client() {
  ensure_deps
  read -rp "Remote IP: " rip
  read -rp "Base port (default 40000): " base
  base="${base:-40000}"
  read -rp "Tunnel ID: " uuid

  echo
  printf "+----------------+--------+-----------+--------+\n"
  printf "| %-14s | %-6s | %-9s | %-6s |\n" "scheme" "OK?" "Mbps(8s)" "MB/s"
  printf "+----------------+--------+-----------+--------+\n"

  i=0
  while read -r s; do
    port=$((base + i))
    lport=$((50000 + i))
    i=$((i+1))

    cmd="${GOST_BIN} -L tcp://127.0.0.1:${lport}/127.0.0.1:1 -F ${s}://${rip}:${port}?tunnel.id=${uuid}"
    (nohup bash -c "$cmd" >/dev/null 2>&1) &
    pid=$!
    sleep 0.5

    if iperf3 -c 127.0.0.1 -p ${lport} -t 8 -f m > /tmp/kwekha_speed 2>/dev/null; then
      mbps=$(grep -Eo "[0-9]+\.?[0-9]* Mbits/sec" /tmp/kwekha_speed | tail -1 | awk '{print $1}')
      mbs=$(echo "$mbps / 8" | bc 2>/dev/null || echo "-")
      printf "| %-14s | %-6s | %-9s | %-6s |\n" "$s" "YES" "$mbps" "$mbs"
    else
      printf "| %-14s | %-6s | %-9s | %-6s |\n" "$s" "NO" "-" "-"
    fi

    kill "$pid" >/dev/null 2>&1 || true
  done <<< "$(recommended_schemes)"

  printf "+----------------+--------+-----------+--------+\n"
  echo "Dataset test (1000MB) running..."
  dd if=/dev/zero bs=1M count=1000 2>/dev/null | nc 127.0.0.1 1 >/dev/null 2>&1 || true
}

menu() {
  while true; do
    clear
    echo "K W E K H A SpeedTest Edition v${VERSION}"
    echo
    echo "1) SpeedTest Server (Abroad)"
    echo "2) SpeedTest Client (Iran)"
    echo "0) Exit"
    read -rp "Select: " sel
    case "$sel" in
      1) need_root; speedtest_server ;;
      2) need_root; speedtest_client ;;
      0) exit 0 ;;
    esac
  done
}

menu
