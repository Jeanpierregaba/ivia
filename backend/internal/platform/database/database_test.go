package database

import (
	"context"
	"os"
	"testing"
)

func TestOpen(t *testing.T) {
	url := os.Getenv("DATABASE_URL")
	if url == "" {
		t.Skip("DATABASE_URL non définie : lancer `docker compose up -d --wait` et exporter DATABASE_URL")
	}

	pool, err := Open(context.Background(), url)
	if err != nil {
		t.Fatalf("Open : %v", err)
	}
	defer pool.Close()

	var one int
	if err := pool.QueryRow(context.Background(), "SELECT 1").Scan(&one); err != nil {
		t.Fatalf("requête : %v", err)
	}
	if one != 1 {
		t.Fatalf("SELECT 1 = %d", one)
	}
}

func TestOpenUnreachable(t *testing.T) {
	// Port 1 : personne n'écoute, la connexion doit échouer sans paniquer.
	_, err := Open(context.Background(), "postgres://ivia@127.0.0.1:1/ivia?sslmode=disable&connect_timeout=1")
	if err == nil {
		t.Fatal("Open aurait dû échouer sur une base injoignable")
	}
}
