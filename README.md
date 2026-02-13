# 🚀 Kwekha

Kwekha is a **Gost tunnel manager** (Iran ↔ Abroad) with:
- CLI wizard (systemd services)
- Optional Web Panel (token auth)

## One-line install (CLI + Web Panel)
```bash
curl -fsSL https://raw.githubusercontent.com/Zuvpn/Kwekha/main/install.sh | sudo bash
```

During install, you will be asked for the **web panel port** and a **25-digit token** will be generated and shown.

### Recover panel token later
```bash
sudo cat /etc/kwekha/web.conf | grep '^TOKEN='
```

### CLI
Run:
```bash
kwekha
```

### Web Panel
Open:
`http://YOUR_SERVER_IP:PANEL_PORT`

Send token in API calls:
```bash
source /etc/kwekha/web.conf
curl -H "Authorization: Bearer $TOKEN" "http://127.0.0.1:$PORT/api/services"
```
