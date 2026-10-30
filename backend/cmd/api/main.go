// Point d'entrée du serveur API.
package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"ivia/backend/internal/database"
	"ivia/backend/internal/server"
)

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	if err := run(logger); err != nil {
		logger.Error("arrêt du serveur", "err", err)
		os.Exit(1)
	}
}

func run(logger *slog.Logger) error {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	databaseURL := os.Getenv("DATABASE_URL")
	if databaseURL == "" {
		return errors.New("DATABASE_URL non définie (voir .env.example)")
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	db, err := database.Open(ctx, databaseURL)
	if err != nil {
		return err
	}
	defer db.Close()

	srv := &http.Server{
		Addr:              ":" + port,
		Handler:           server.New(logger, db),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       10 * time.Second,
		WriteTimeout:      10 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	errCh := make(chan error, 1)
	go func() {
		logger.Info("serveur démarré", "addr", srv.Addr)
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			errCh <- err
		}
		close(errCh)
	}()

	select {
	case err := <-errCh:
		return err
	case <-ctx.Done():
	}
	// Rétablit le comportement par défaut : un second signal force l'arrêt immédiat.
	stop()

	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	logger.Info("arrêt en cours")
	return srv.Shutdown(shutdownCtx)
}
