package main

import (
	"embed"
	"flag"
	"fmt"
	"io"
	"io/fs"
	"log"
	"net"
	"net/http"
	"os"
	"path"
	"strings"
	"time"
)

// -----------------------------------------------------------------------------
// UI (Embedded)
// -----------------------------------------------------------------------------
//
// Expected layout inside repo:
// webpanel/ui/index.html
// webpanel/ui/assets/*
// webpanel/ui/favicon.ico
//
//go:embed ui/*
var uiEmbedFS embed.FS

func mustUISubFS() fs.FS {
	sub, err := fs.Sub(uiEmbedFS, "ui")
	if err != nil {
		panic(err)
	}
	return sub
}

// -----------------------------------------------------------------------------
// Auth (Token)
// -----------------------------------------------------------------------------

func withTokenAuth(token string, next http.Handler) http.Handler {
	token = strings.TrimSpace(token)
	// If token empty, allow local-only access (optional). You can change this behavior.
	// For production you probably want to require token always.
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// healthz always allowed
		if r.URL.Path == "/healthz" {
			next.ServeHTTP(w, r)
			return
		}

		// If token is empty: allow from localhost only (safe fallback)
		if token == "" {
			host, _, _ := net.SplitHostPort(r.RemoteAddr)
			if host == "127.0.0.1" || host == "::1" {
				next.ServeHTTP(w, r)
				return
			}
			http.Error(w, "Unauthorized", http.StatusUnauthorized)
			return
		}

		// Token can be sent as:
		// - Header: X-Auth-Token: <token>
		// - Query:  ?token=<token>
		// - Cookie: kwekha_token=<token>
		got := strings.TrimSpace(r.Header.Get("X-Auth-Token"))
		if got == "" {
			got = strings.TrimSpace(r.URL.Query().Get("token"))
		}
		if got == "" {
			if c, err := r.Cookie("kwekha_token"); err == nil {
				got = strings.TrimSpace(c.Value)
			}
		}

		if got != token {
			http.Error(w, "Unauthorized", http.StatusUnauthorized)
			return
		}

		next.ServeHTTP(w, r)
	})
}

// -----------------------------------------------------------------------------
// Static + SPA fallback
// -----------------------------------------------------------------------------

func isAssetPath(p string) bool {
	return strings.HasPrefix(p, "/assets/") || p == "/favicon.ico"
}

func fileExists(fsys fs.FS, p string) bool {
	p = strings.TrimPrefix(p, "/")
	if p == "" {
		p = "index.html"
	}
	_, err := fs.Stat(fsys, p)
	return err == nil
}

func serveSPA(fsys fs.FS) http.Handler {
	fileServer := http.FileServer(http.FS(fsys))

	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Serve real static assets (do NOT fallback to index.html)
		if isAssetPath(r.URL.Path) {
			// if asset doesn't exist, return 404 (not index.html)
			if !fileExists(fsys, r.URL.Path) {
				http.NotFound(w, r)
				return
			}
			fileServer.ServeHTTP(w, r)
			return
		}

		// If request is for a real file, serve it
		if r.URL.Path != "/" && fileExists(fsys, r.URL.Path) {
			fileServer := http.FileServer(http.FS(fsys))
			fileServer.ServeHTTP(w, r)
			return
		}

		// Otherwise fallback to index.html (SPA routes)
		r2 := *r
		r2.URL = newCopyURL(r.URL)
		r2.URL.Path = "/index.html"
		fileServer.ServeHTTP(w, &r2)
	})
}

func newCopyURL(u *http.URL) *http.URL {
	u2 := *u
	return &u2
}

// -----------------------------------------------------------------------------
// Minimal API (optional)
// -----------------------------------------------------------------------------

func healthz(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	io.WriteString(w, "ok\n")
}

// -----------------------------------------------------------------------------
// Main
// -----------------------------------------------------------------------------

func main() {
	var (
		bind  = flag.String("bind", "0.0.0.0", "bind address")
		port  = flag.Int("port", 8787, "listen port")
		token = flag.String("token", "", "panel token (required for remote access)")
	)
	flag.Parse()

	// Logging
	log.SetFlags(log.LstdFlags | log.Lmicroseconds)

	// Embedded UI filesystem
	uiFS := mustUISubFS()

	// Basic sanity: require index.html present
	if !fileExists(uiFS, "/index.html") {
		log.Println("❌ ui/index.html not found in embedded FS.")
		log.Println("   Ensure webpanel/ui/index.html exists and is committed.")
		os.Exit(1)
	}

	mux := http.NewServeMux()

	// healthz
	mux.HandleFunc("/healthz", healthz)

	// NOTE: Your API routes can be under /api/
	// mux.HandleFunc("/api/...", ...)

	// UI + static + SPA fallback
	mux.Handle("/", serveSPA(uiFS))

	// Security headers (simple)
	handler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// strict but workable CSP (adjust if needed)
		w.Header().Set("Content-Security-Policy", "default-src 'self'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; script-src 'self'")
		w.Header().Set("X-Frame-Options", "DENY")
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("Referrer-Policy", "no-referrer")
		mux.ServeHTTP(w, r)
	})

	// Token auth wrapper
	finalHandler := withTokenAuth(*token, handler)

	addr := fmt.Sprintf("%s:%d", *bind, *port)

	srv := &http.Server{
		Addr:              addr,
		Handler:           finalHandler,
		ReadHeaderTimeout: 10 * time.Second,
	}

	log.Printf("Kwekha Web Panel listening on http://%s\n", addr)

	// Start server
	if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		log.Fatalf("server error: %v", err)
	}
}

// Optional helper: for correct path cleaning if you need later
func cleanURLPath(p string) string {
	p = path.Clean("/" + p)
	return p
}
