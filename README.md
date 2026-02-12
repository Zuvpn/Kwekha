
# Kwekha PRO (Scaffold Version)

This is the production architecture scaffold for Kwekha.

## Architecture

Single Binary Go WebPanel + CLI (future)

Structure:

cmd/kwekha-web          -> entrypoint
internal/auth           -> authentication logic
internal/services       -> systemd + gost management
internal/metrics        -> CPU/RAM/network collectors
internal/cron           -> internal scheduler
internal/speedtest      -> iperf3 + dataset tests
web/                    -> UI (Cyber Neon)

---

## Build

```bash
go mod tidy
go build -o kwekha-web ./cmd/kwekha-web
```

---

## Run

```bash
./kwekha-web
```

Access:

http://localhost:3300/health

---

## Deployment on Ubuntu

1. Install Go 1.21+
2. Build binary
3. Move to:

/usr/local/bin/kwekha-web

4. Create config:

/etc/kwekha/web.conf

5. Create systemd service:

/etc/systemd/system/kwekha-web.service

Example:

[Unit]
Description=Kwekha Web Panel
After=network.target

[Service]
ExecStart=/usr/local/bin/kwekha-web
Restart=always
User=root

[Install]
WantedBy=multi-user.target

Then:

```bash
systemctl daemon-reload
systemctl enable kwekha-web
systemctl start kwekha-web
```

---

## Next Steps

- Implement Auth middleware
- Add JSON state storage in /etc/kwekha
- Implement Reverse/Direct wizard logic
- Implement SpeedTest engine
- Add WebSocket metrics
- Build Cyber Neon UI
- Create installer.sh

---

This is the clean production foundation for Kwekha.
