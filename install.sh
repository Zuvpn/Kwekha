#!/usr/bin/env bash
set -euo pipefail

install -m 0755 -D bin/kwekha-telegram /usr/local/bin/kwekha-telegram
install -m 0644 -D systemd/kwekha-telegram.service /etc/systemd/system/kwekha-telegram.service

mkdir -p /etc/kwekha
if [[ ! -f /etc/kwekha/telegram.env ]]; then
  cp systemd/telegram.env.example /etc/kwekha/telegram.env
  chmod 600 /etc/kwekha/telegram.env
  echo "Created /etc/kwekha/telegram.env (edit BOT_TOKEN)"
fi

systemctl daemon-reload
systemctl enable --now kwekha-telegram
systemctl restart kwekha-telegram
