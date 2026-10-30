// Package server expose l'API HTTP du backend.
package server

import (
	"context"
	"encoding/json"
	"log/slog"
	"net/http"
	"time"
)

// Pinger vérifie qu'une dépendance (la base de données) répond.
type Pinger interface {
	Ping(ctx context.Context) error
}

// New retourne le routeur HTTP de l'API.
func New(logger *slog.Logger, db Pinger) http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /health", handleHealth)
	mux.HandleFunc("GET /ready", handleReady(logger, db))
	return logRequests(logger, mux)
}

// handleHealth indique que le processus répond, sans solliciter la base.
func handleHealth(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

// handleReady indique que l'API peut servir des requêtes : la base doit répondre.
func handleReady(logger *slog.Logger, db Pinger) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
		defer cancel()
		if err := db.Ping(ctx); err != nil {
			logger.Error("base de données injoignable", "err", err)
			writeJSON(w, http.StatusServiceUnavailable, map[string]string{"status": "unavailable"})
			return
		}
		writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
	}
}

func writeJSON(w http.ResponseWriter, status int, body any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(body)
}

func logRequests(logger *slog.Logger, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		next.ServeHTTP(w, r)
		logger.Info("request", "method", r.Method, "path", r.URL.Path)
	})
}
