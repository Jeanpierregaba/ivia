package database

import (
	"context"
	"os"
	"testing"
)

func TestMigrate(t *testing.T) {
	url := os.Getenv("DATABASE_URL")
	if url == "" {
		t.Skip("DATABASE_URL non définie : lancer `docker compose up -d --wait` et exporter DATABASE_URL")
	}
	ctx := context.Background()

	pool, err := Open(ctx, url)
	if err != nil {
		t.Fatalf("Open : %v", err)
	}
	defer pool.Close()

	// Deux passages : le second ne doit rien faire ni échouer.
	for i := range 2 {
		if err := Migrate(ctx, pool); err != nil {
			t.Fatalf("Migrate (passage %d) : %v", i+1, err)
		}
	}

	for _, ext := range []string{"postgis", "pg_trgm", "unaccent"} {
		var found bool
		err := pool.QueryRow(ctx, "SELECT EXISTS (SELECT 1 FROM pg_extension WHERE extname = $1)", ext).Scan(&found)
		if err != nil {
			t.Fatalf("requête : %v", err)
		}
		if !found {
			t.Errorf("extension %s absente", ext)
		}
	}
}
