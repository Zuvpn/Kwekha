
# 🚀 Kwekha

Professional Gost Tunnel Manager (Iran ↔ Abroad)

## ✨ Features

- ⭐ Smart Wizard (detects if Xray is on Iran or Abroad)
- ⭐ Clean Protocol Selection (Best protocols marked)
- ⭐ Systemd auto-service creation
- ⭐ One-command install (CLI + Web Panel)
- ⭐ Self-update (CLI)
- ⭐ Service logs & management
- ⭐ Advanced mapping support

---

# 🟢 One-Line Install (Termius Safe)

```bash
curl -fsSL https://raw.githubusercontent.com/Zuvpn/Kwekha/main/install.sh -o /tmp/install.sh
sudo bash /tmp/install.sh
```

---

# 🧠 Smart Wizard

When entering ports like:

80,443,2053

Kwekha asks:

📌 Where is Xray running?

1) Localhost (Iran)
2) Remote Server (Abroad) ⭐ Recommended
3) Advanced

Prevents:
- Host Unreachable
- Port loop issues
- Wrong localhost forwarding

---

# 🔄 CLI Self Update

Inside CLI:

11) Self-update script

It downloads latest version from:

https://raw.githubusercontent.com/Zuvpn/Kwekha/main/kwekha.sh

✔ Validates script header  
✔ Replaces /usr/local/bin/kwekha  
✔ Keeps services untouched  

---

# 📟 Service Management

List services:

kwekha → 3

Check systemd:

systemctl status gost-kwekha-<name>

---

# 🌐 Web Panel

After install:

http://SERVER_IP:PORT

Recover token:

cat /etc/kwekha/web.conf | grep TOKEN=

---

# 🛡 Recommended Protocols

⭐ relay+wss  
⭐ relay+tls  
⭐ relay+ws  
⭐ grpc  
⭐ h2  

---

# 📜 License

MIT
