package main

import (
	"bufio"
	"crypto/rand"
	"embed"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

const (
	AppName       = "Kwekha Web Panel"
	ConfPath      = "/etc/kwekha/web.conf"
	LogDirDefault = "/var/log/kwekha"
	SvcPrefix     = "gost-kwekha-"
)

//go:embed ui/*
var uiFS embed.FS

type Config struct {
	Port   int
	Token  string
	LogDir string
	Bind   string
}

func main() {
	// CLI helpers
	if len(os.Args) > 1 {
		switch os.Args[1] {
		case "token":
			cfg, err := loadConfig()
			exitIf(err)
			fmt.Println(cfg.Token)
			return
		case "gen-token":
			t, err := genToken25Digits()
			exitIf(err)
			fmt.Println(t)
			return
		case "print-config":
			cfg, err := loadConfig()
			exitIf(err)
			b, _ := json.MarshalIndent(cfg, "", "  ")
			fmt.Println(string(b))
			return
		}
	}

	cfg, err := loadConfig()
	exitIf(err)

	mux := http.NewServeMux()

	// UI
	mux.HandleFunc("/", serveFile("ui/index.html", "text/html; charset=utf-8"))
	mux.HandleFunc("/static/app.js", serveFile("ui/app.js", "application/javascript; charset=utf-8"))
	mux.HandleFunc("/static/app.css", serveFile("ui/app.css", "text/css; charset=utf-8"))
	mux.HandleFunc("/static/logo.svg", serveFile("ui/logo.svg", "image/svg+xml"))

	// API
	mux.HandleFunc("/api/health", apiHealth(cfg))
	mux.HandleFunc("/api/services", auth(cfg, apiServices(cfg)))
	mux.HandleFunc("/api/service/action", auth(cfg, apiServiceAction(cfg)))
	mux.HandleFunc("/api/service/status", auth(cfg, apiServiceStatus(cfg)))
	mux.HandleFunc("/api/service/logs", auth(cfg, apiServiceLogs(cfg)))
	mux.HandleFunc("/api/tunnel/preview", auth(cfg, apiTunnelPreview(cfg)))
	mux.HandleFunc("/api/tunnel/create", auth(cfg, apiTunnelCreate(cfg)))
	mux.HandleFunc("/api/stats", auth(cfg, apiStats(cfg)))
	mux.HandleFunc("/api/healthcheck/get", auth(cfg, apiHealthCheckGet(cfg)))
	mux.HandleFunc("/api/healthcheck/set", auth(cfg, apiHealthCheckSet(cfg)))
	mux.HandleFunc("/api/healthcheck/run", auth(cfg, apiHealthCheckRun(cfg)))

	addr := net.JoinHostPort(cfg.Bind, strconv.Itoa(cfg.Port))
	fmt.Printf("%s listening on http://%s\n", AppName, addr)

	srv := &http.Server{
		Addr:              addr,
		Handler:           securityHeaders(mux),
		ReadHeaderTimeout: 10 * time.Second,
	}
	exitIf(srv.ListenAndServe())
}

func exitIf(err error) {
	if err == nil {
		return
	}
	fmt.Fprintln(os.Stderr, "ERROR:", err)
	os.Exit(1)
}

// ---------- UI ----------
func serveFile(path, contentType string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		f, err := uiFS.Open(path)
		if err != nil {
			http.Error(w, "missing asset", 500)
			return
		}
		defer f.Close()
		w.Header().Set("Content-Type", contentType)
		io.Copy(w, f)
	}
}

// ---------- Middleware ----------
func securityHeaders(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("X-Frame-Options", "DENY")
		w.Header().Set("Referrer-Policy", "no-referrer")
		w.Header().Set("Content-Security-Policy", "default-src 'self'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; script-src 'self'")
		next.ServeHTTP(w, r)
	})
}

func auth(cfg Config, next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		h := r.Header.Get("Authorization")
		const pfx = "Bearer "
		if !strings.HasPrefix(h, pfx) || strings.TrimSpace(strings.TrimPrefix(h, pfx)) != cfg.Token {
			http.Error(w, "Unauthorized", http.StatusUnauthorized)
			return
		}
		next(w, r)
	}
}

// ---------- API ----------
func apiHealth(cfg Config) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, map[string]any{
			"ok":         true,
			"app":        AppName,
			"bind":       fmt.Sprintf("%s:%d", cfg.Bind, cfg.Port),
			"auth":       cfg.Token != "",
			"log_dir":    cfg.LogDir,
			"svc_prefix": SvcPrefix,
		})
	}
}

func apiServices(cfg Config) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		out, err := run("systemctl", "list-units", "--type=service", "--all", "--no-legend")
		if err != nil {
			http.Error(w, err.Error(), 500)
			return
		}
		type Svc struct {
			Name    string `json:"name"`
			Unit    string `json:"unit"`
			Active  string `json:"active"`
			Enabled string `json:"enabled"`
		}
		svcs := make([]Svc, 0)
		for _, line := range strings.Split(out, "\n") {
			fields := strings.Fields(line)
			if len(fields) == 0 {
				continue
			}
			unit := fields[0]
			if strings.HasPrefix(unit, SvcPrefix) && strings.HasSuffix(unit, ".service") {
				name := strings.TrimSuffix(strings.TrimPrefix(unit, SvcPrefix), ".service")
				active, _ := run("systemctl", "is-active", unit)
				enabled, _ := run("systemctl", "is-enabled", unit)
				svcs = append(svcs, Svc{
					Name:    name,
					Unit:    unit,
					Active:  strings.TrimSpace(active),
					Enabled: strings.TrimSpace(enabled),
				})
			}
		}
		writeJSON(w, map[string]any{"services": svcs})
	}
}

func apiServiceAction(cfg Config) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			http.Error(w, "Method Not Allowed", 405)
			return
		}
		name := r.URL.Query().Get("name")
		action := r.URL.Query().Get("action")
		if name == "" || action == "" {
			http.Error(w, "missing name/action", 400)
			return
		}
		if !validName(name) {
			http.Error(w, "invalid service name", 400)
			return
		}
		switch action {
		case "start", "stop", "restart", "enable", "disable":
		default:
			http.Error(w, "invalid action", 400)
			return
		}
		unit := SvcPrefix + name + ".service"
		if _, err := run("systemctl", action, unit); err != nil {
			http.Error(w, err.Error(), 500)
			return
		}
		writeJSON(w, map[string]any{"ok": true})
	}
}

func apiServiceStatus(cfg Config) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		name := r.URL.Query().Get("name")
		if name == "" || !validName(name) {
			http.Error(w, "invalid name", 400)
			return
		}
		unit := SvcPrefix + name + ".service"
		out, _ := run("systemctl", "status", unit, "--no-pager")
		w.Header().Set("Content-Type", "text/plain; charset=utf-8")
		fmt.Fprint(w, out)
	}
}

func apiServiceLogs(cfg Config) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		name := r.URL.Query().Get("name")
		if name == "" || !validName(name) {
			http.Error(w, "invalid name", 400)
			return
		}
		lines := 200
		if ls := r.URL.Query().Get("lines"); ls != "" {
			if n, err := strconv.Atoi(ls); err == nil {
				if n < 10 {
					n = 10
				}
				if n > 2000 {
					n = 2000
				}
				lines = n
			}
		}
		logfile := filepath.Join(cfg.LogDir, name+".log")
		if _, err := os.Stat(logfile); err == nil {
			out, err := run("bash", "-lc", fmt.Sprintf("tail -n %d %s", lines, shellEscape(logfile)))
			if err != nil {
				http.Error(w, err.Error(), 500)
				return
			}
			w.Header().Set("Content-Type", "text/plain; charset=utf-8")
			fmt.Fprint(w, out)
			return
		}
		unit := SvcPrefix + name + ".service"
		out, _ := run("journalctl", "-u", unit, "-n", fmt.Sprintf("%d", lines), "--no-pager")
		w.Header().Set("Content-Type", "text/plain; charset=utf-8")
		fmt.Fprint(w, out)
	}
}



// ---------- Tunnel Create ----------
type CreateReq struct {
	Name     string `json:"name"`
	Role     string `json:"role"`      // client|server
	Scheme   string `json:"scheme"`    // e.g. relay+wss or tunnel+tcp
	Peer     string `json:"peer"`      // ip:port (client target) OR ":port" for server listen
	PortsCSV string `json:"ports_csv"` // "80,443,2053"
	DestMode string `json:"dest_mode"` // local|remote
	DestHost string `json:"dest_host"` // required if remote
	TunnelID string `json:"tunnel_id"` // UUID
}

func apiTunnelPreview(cfg Config) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			http.Error(w, "Method Not Allowed", 405)
			return
		}
		var req CreateReq
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			http.Error(w, "bad json", 400)
			return
		}
		plan, err := buildPlan(req)
		if err != nil {
			http.Error(w, err.Error(), 400)
			return
		}
		writeJSON(w, plan)
	}
}

func apiTunnelCreate(cfg Config) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			http.Error(w, "Method Not Allowed", 405)
			return
		}
		var req CreateReq
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			http.Error(w, "bad json", 400)
			return
		}
		plan, err := buildPlan(req)
		if err != nil {
			http.Error(w, err.Error(), 400)
			return
		}

		// Write /etc/kwekha/services/<name>.conf
		confDir := "/etc/kwekha/services"
		if err := os.MkdirAll(confDir, 0755); err != nil {
			http.Error(w, "mkdir conf: "+err.Error(), 500)
			return
		}
		confPath := filepath.Join(confDir, req.Name+".conf")
		confBody := fmt.Sprintf(`# Kwekha service config: %s
MODE=WIZARD_%s
TUNNEL_ID=%s
TUNNEL_SCHEME=%s
SERVER=%s
PORTS=simple:%s
DEST_MODE=%s
DEST_HOST=%s
ARGS=%s
`, req.Name, strings.ToUpper(req.Role), plan["tunnel_id"], plan["scheme"], plan["peer"], req.PortsCSV, plan["dest_mode"], plan["dest_host"], plan["args"])

		if err := os.WriteFile(confPath, []byte(confBody), 0644); err != nil {
			http.Error(w, "write conf: "+err.Error(), 500)
			return
		}

		// Write systemd unit
		unitName := SvcPrefix + req.Name + ".service"
		unitPath := filepath.Join("/etc/systemd/system", unitName)
		unit := fmt.Sprintf(`[Unit]
Description=Kwekha Gost Service (%s)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/gost %s
Restart=always
RestartSec=2
LimitNOFILE=1048576
WorkingDirectory=/etc/kwekha
StandardOutput=append:%s
StandardError=append:%s

[Install]
WantedBy=multi-user.target
`, req.Name, plan["gost_args"], filepath.Join(cfg.LogDir, req.Name+".log"), filepath.Join(cfg.LogDir, req.Name+".log"))

		if err := os.MkdirAll(cfg.LogDir, 0755); err != nil {
			http.Error(w, "mkdir log: "+err.Error(), 500)
			return
		}
		if err := os.WriteFile(unitPath, []byte(unit), 0644); err != nil {
			http.Error(w, "write unit: "+err.Error(), 500)
			return
		}

		// Reload + enable + start
		if _, err := run("systemctl", "daemon-reload"); err != nil {
			http.Error(w, err.Error(), 500)
			return
		}
		_, _ = run("systemctl", "enable", unitName)
		if _, err := run("systemctl", "restart", unitName); err != nil {
			http.Error(w, err.Error(), 500)
			return
		}
		writeJSON(w, map[string]any{"ok": true, "unit": unitName, "plan": plan})
	}
}

func buildPlan(req CreateReq) (map[string]string, error) {
	req.Name = strings.TrimSpace(req.Name)
	if !validName(req.Name) {
		return nil, errors.New("invalid name (use a-z 0-9 - _)")
	}
	req.Role = strings.ToLower(strings.TrimSpace(req.Role))
	if req.Role != "client" && req.Role != "server" {
		return nil, errors.New("invalid role")
	}
	req.Scheme = strings.TrimSpace(req.Scheme)
	if req.Scheme == "" {
		return nil, errors.New("scheme required")
	}
	req.Peer = strings.TrimSpace(req.Peer)
	if req.Peer == "" {
		return nil, errors.New("peer required")
	}
	req.PortsCSV = strings.TrimSpace(req.PortsCSV)
	if req.PortsCSV == "" {
		return nil, errors.New("ports required")
	}
	req.DestMode = strings.ToLower(strings.TrimSpace(req.DestMode))
	if req.DestMode == "" { req.DestMode = "local" }
	if req.DestMode != "local" && req.DestMode != "remote" {
		return nil, errors.New("dest_mode must be local|remote")
	}
	destHost := "127.0.0.1"
	if req.DestMode == "remote" {
		req.DestHost = strings.TrimSpace(req.DestHost)
		if req.DestHost == "" {
			return nil, errors.New("dest_host required when dest_mode=remote")
		}
		destHost = req.DestHost
	}

	// tunnel id must be UUID to avoid gost errors
	tid := strings.TrimSpace(req.TunnelID)
	if tid == "" {
		nt, err := genUUIDv4()
		if err != nil { return nil, err }
		tid = nt
	}
	if !looksLikeUUID(tid) {
		return nil, errors.New("tunnel_id must be valid UUID")
	}

	// Build port mappings: tcp:PORT -> destHost:PORT
	ports := splitCSVInts(req.PortsCSV)
	if len(ports) == 0 {
		return nil, errors.New("invalid ports")
	}
	var Ls []string
	for _, p := range ports {
		Ls = append(Ls, fmt.Sprintf("-L tcp://:%d/%s:%d", p, destHost, p))
	}
	Lpart := strings.Join(Ls, " ")

	// Build forward(-F) or listen, depending role
	// Server: only -L on peer listen and accept tunnels? For simplicity we always use -F with peer.
	// Client: -F <scheme>://peer?tunnel.id=UUID
	F := fmt.Sprintf("-F %s://%s?tunnel.id=%s", req.Scheme, strings.TrimPrefix(req.Peer, "tcp://"), tid)
	args := strings.TrimSpace(Lpart + " " + F)

	return map[string]string{
		"name": req.Name,
		"role": req.Role,
		"scheme": req.Scheme,
		"peer": req.Peer,
		"ports_csv": req.PortsCSV,
		"dest_mode": req.DestMode,
		"dest_host": destHost,
		"tunnel_id": tid,
		"gost_args": args,
		"args": args,
	}, nil
}

func splitCSVInts(s string) []int {
	parts := strings.Split(s, ",")
	var out []int
	seen := map[int]bool{}
	for _, p := range parts {
		p = strings.TrimSpace(p)
		if p == "" { continue }
		n, err := strconv.Atoi(p)
		if err != nil || n < 1 || n > 65535 { continue }
		if !seen[n] {
			seen[n] = true
			out = append(out, n)
		}
	}
	return out
}

func looksLikeUUID(s string) bool {
	s = strings.ToLower(strings.TrimSpace(s))
	if len(s) != 36 { return false }
	for i, ch := range s {
		switch i {
		case 8,13,18,23:
			if ch != '-' { return false }
		default:
			if (ch >= '0' && ch <= '9') || (ch >= 'a' && ch <= 'f') {
				continue
			}
			return false
		}
	}
	return true
}

func genUUIDv4() (string, error) {
	b := make([]byte, 16)
	if _, err := rand.Read(b); err != nil { return "", err }
	b[6] = (b[6] & 0x0f) | 0x40
	b[8] = (b[8] & 0x3f) | 0x80
	return fmt.Sprintf("%x-%x-%x-%x-%x", b[0:4], b[4:6], b[6:8], b[8:10], b[10:16]), nil
}

// ---------- Stats ----------
func apiStats(cfg Config) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		cpuPct, cpuRaw := cpuUsage()
		memUsed, memTotal := memUsage()
		rx, tx := netUsage()
		conns := connCount()

		writeJSON(w, map[string]any{
			"cpu_percent": cpuPct,
			"cpu_raw": cpuRaw,
			"mem_used_mb": memUsed,
			"mem_total_mb": memTotal,
			"net_rx_mb": rx,
			"net_tx_mb": tx,
			"connections": conns,
		})
	}
}

func cpuUsage() (float64, map[string]uint64) {
	// Single-sample approximate: use /proc/stat and short sleep
	read := func() (idle, total uint64) {
		b, err := os.ReadFile("/proc/stat")
		if err != nil { return 0, 0 }
		line := strings.SplitN(string(b), "\n", 2)[0]
		f := strings.Fields(line)
var vals []uint64
		for _, x := range f[1:] {
			v, _ := strconv.ParseUint(x, 10, 64)
			vals = append(vals, v)
		}
		for _, v := range vals { total += v }
		if len(vals) >= 4 { idle = vals[3] }
		if len(vals) >= 5 { idle += vals[4] } // iowait
		return
	}
	idle1, total1 := read()
	time.Sleep(120 * time.Millisecond)
	idle2, total2 := read()
	if total2 <= total1 { return 0, map[string]uint64{"idle": idle2, "total": total2} }
	idleDelta := float64(idle2 - idle1)
	totalDelta := float64(total2 - total1)
	used := (totalDelta - idleDelta) / totalDelta * 100.0
	return used, map[string]uint64{"idle": idle2, "total": total2}
}

func memUsage() (usedMB, totalMB int) {
	b, err := os.ReadFile("/proc/meminfo")
	if err != nil { return 0, 0 }
	var total, avail uint64
	for _, line := range strings.Split(string(b), "\n") {
		if strings.HasPrefix(line, "MemTotal:") {
			f := strings.Fields(line); if len(f) >= 2 { total, _ = strconv.ParseUint(f[1],10,64) }
		}
		if strings.HasPrefix(line, "MemAvailable:") {
			f := strings.Fields(line); if len(f) >= 2 { avail, _ = strconv.ParseUint(f[1],10,64) }
		}
	}
	if total == 0 { return 0, 0 }
	used := total - avail
	return int(used/1024), int(total/1024)
}

func netUsage() (rxMB, txMB float64) {
	b, err := os.ReadFile("/proc/net/dev")
	if err != nil { return 0, 0 }
	var rx, tx uint64
	for _, line := range strings.Split(string(b), "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.Contains(line, "Inter-|") || strings.Contains(line, "face |") { continue }
		parts := strings.Fields(strings.ReplaceAll(line, ":", " "))
		if len(parts) < 17 { continue }
		iface := parts[0]
		if iface == "lo" { continue }
		r, _ := strconv.ParseUint(parts[1],10,64)
		t, _ := strconv.ParseUint(parts[9],10,64)
		rx += r; tx += t
	}
	return float64(rx)/1024.0/1024.0, float64(tx)/1024.0/1024.0
}

func connCount() int {
	// Count TCP connections with process name gost (best-effort)
	out, err := run("bash", "-lc", "ss -Htanp | grep -i gost | wc -l")
	if err != nil { return 0 }
	n, _ := strconv.Atoi(strings.TrimSpace(out))
	return n
}

// ---------- Healthcheck (systemd timer) ----------
func apiHealthCheckGet(cfg Config) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		interval := getHealthCheckInterval()
		writeJSON(w, map[string]any{"interval_min": interval})
	}
}

func apiHealthCheckSet(cfg Config) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			http.Error(w, "Method Not Allowed", 405); return
		}
		var body struct{ IntervalMin int `json:"interval_min"` }
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			http.Error(w, "bad json", 400); return
		}
		if body.IntervalMin != 0 && (body.IntervalMin < 1 || body.IntervalMin > 60) {
			http.Error(w, "interval must be 0 or 1..60", 400); return
		}
		if err := setHealthCheckInterval(body.IntervalMin); err != nil {
			http.Error(w, err.Error(), 500); return
		}
		writeJSON(w, map[string]any{"ok": true, "interval_min": body.IntervalMin})
	}
}

func apiHealthCheckRun(cfg Config) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			http.Error(w, "Method Not Allowed", 405); return
		}
		out, _ := run("systemctl", "start", "kwekha-healthcheck.service")
		writeJSON(w, map[string]any{"ok": true, "output": out})
	}
}

func getHealthCheckInterval() int {
	out, err := run("bash", "-lc", "systemctl show -p OnUnitActiveSec kwekha-healthcheck.timer 2>/dev/null | cut -d= -f2")
	if err != nil { return 0 }
	out = strings.TrimSpace(out)
	if out == "" || out == "0" { return 0 }
	// parse "5min" etc (best-effort)
	if strings.HasSuffix(out, "min") {
		v := strings.TrimSuffix(out, "min")
		n, _ := strconv.Atoi(v)
		return n
	}
	if strings.HasSuffix(out, "h") {
		v := strings.TrimSuffix(out, "h")
		n, _ := strconv.Atoi(v)
		return n*60
	}
	return 0
}

func setHealthCheckInterval(min int) error {
	unitDir := "/etc/systemd/system"
	servicePath := filepath.Join(unitDir, "kwekha-healthcheck.service")
	timerPath := filepath.Join(unitDir, "kwekha-healthcheck.timer")

	service := `[Unit]
Description=Kwekha healthcheck (restart failed gost-kwekha services)
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/kwekha healthcheck-run
`
	if err := os.WriteFile(servicePath, []byte(service), 0644); err != nil { return err }

	if min == 0 {
		// disable timer
		_, _ = run("systemctl", "disable", "--now", "kwekha-healthcheck.timer")
		_, _ = run("systemctl", "daemon-reload")
		return nil
	}

	timer := fmt.Sprintf(`[Unit]
Description=Kwekha healthcheck timer

[Timer]
OnBootSec=30s
OnUnitActiveSec=%dmin
Unit=kwekha-healthcheck.service

[Install]
WantedBy=timers.target
`, min)
	if err := os.WriteFile(timerPath, []byte(timer), 0644); err != nil { return err }
	if _, err := run("systemctl", "daemon-reload"); err != nil { return err }
	_, _ = run("systemctl", "enable", "--now", "kwekha-healthcheck.timer")
	return nil
}

// ---------- Helpers ----------
func writeJSON(w http.ResponseWriter, v any) {
	w.Header().Set("Content-Type", "application/json")
	enc := json.NewEncoder(w)
	enc.SetEscapeHTML(true)
	_ = enc.Encode(v)
}

func run(cmd string, args ...string) (string, error) {
	c := exec.Command(cmd, args...)
	b, err := c.CombinedOutput()
	out := string(b)
	if err != nil {
		return out, fmt.Errorf("%s %v failed: %s", cmd, args, strings.TrimSpace(out))
	}
	return out, nil
}

func validName(s string) bool {
	if s == "" || len(s) > 64 {
		return false
	}
	for _, ch := range s {
		if (ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9') || ch == '-' || ch == '_' {
			continue
		}
		return false
	}
	return true
}

func shellEscape(p string) string {
	return "'" + strings.ReplaceAll(p, "'", "'\\''") + "'"
}

func loadConfig() (Config, error) {
	cfg := Config{
		Port:   8787,
		Bind:   "0.0.0.0",
		LogDir: LogDirDefault,
	}
	f, err := os.Open(ConfPath)
	if err != nil {
		return cfg, err
	}
	defer f.Close()

	sc := bufio.NewScanner(f)
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		parts := strings.SplitN(line, "=", 2)
		if len(parts) != 2 {
			continue
		}
		k := strings.TrimSpace(parts[0])
		v := strings.TrimSpace(parts[1])
		switch k {
		case "PORT":
			if p, err := strconv.Atoi(v); err == nil {
				cfg.Port = p
			}
		case "BIND":
			if v != "" {
				cfg.Bind = v
			}
		case "TOKEN":
			cfg.Token = v
		case "LOG_DIR":
			if v != "" {
				cfg.LogDir = v
			}
		}
	}
	if cfg.Token == "" {
		return cfg, errors.New("TOKEN missing in " + ConfPath)
	}
	if cfg.Port < 1 || cfg.Port > 65535 {
		return cfg, errors.New("invalid PORT in " + ConfPath)
	}
	return cfg, nil
}

func genToken25Digits() (string, error) {
	const digits = "0123456789"
	rb := make([]byte, 25)
	if _, err := rand.Read(rb); err != nil {
		return "", err
	}
	out := make([]byte, 25)
	for i := range out {
		out[i] = digits[int(rb[i])%10]
	}
	return string(out), nil
}
