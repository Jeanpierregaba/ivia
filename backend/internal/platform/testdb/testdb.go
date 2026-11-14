// Package testdb fournit aux tests une base PostgreSQL + PostGIS dédiée et migrée.
//
// Chaque paquet de tests crée sa propre base (ivia_test_<aléatoire>) au démarrage et la supprime
// à la fin : les paquets tournent en parallèle sans se gêner. Sans DATABASE_URL, les tests qui en
// ont besoin sont ignorés.
//
//	var testDB *database.DB
//
//	func TestMain(m *testing.M) { os.Exit(testdb.Main(m, &testDB)) }
//
//	func TestX(t *testing.T) { db := testdb.Require(t, testDB) ... }
package testdb

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"net/url"
	"os"
	"testing"

	"github.com/jackc/pgx/v5"

	"ivia/backend/internal/platform/database"
)

// Setup prépare le paquet une fois la base prête (ex. assembler l'application) et retourne sa
// fonction de nettoyage.
type Setup func() (cleanup func(), err error)

// Main crée la base du paquet, lance les tests puis supprime la base. Retourne le code de sortie.
func Main(m *testing.M, dst **database.DB, setups ...Setup) int {
	adminURL := os.Getenv("DATABASE_URL")
	if adminURL == "" {
		return m.Run()
	}
	ctx := context.Background()

	b := make([]byte, 6)
	_, _ = rand.Read(b)
	name := "ivia_test_" + hex.EncodeToString(b)

	if err := execAdmin(ctx, adminURL, fmt.Sprintf("CREATE DATABASE %s", pgx.Identifier{name}.Sanitize())); err != nil {
		fmt.Fprintf(os.Stderr, "testdb : création de la base : %v\n", err)
		return 1
	}
	defer func() {
		_ = execAdmin(ctx, adminURL, fmt.Sprintf("DROP DATABASE IF EXISTS %s WITH (FORCE)", pgx.Identifier{name}.Sanitize()))
	}()

	u, err := url.Parse(adminURL)
	if err != nil {
		fmt.Fprintf(os.Stderr, "testdb : DATABASE_URL invalide : %v\n", err)
		return 1
	}
	u.Path = "/" + name
	pool, err := database.Open(ctx, u.String())
	if err != nil {
		fmt.Fprintf(os.Stderr, "testdb : connexion : %v\n", err)
		return 1
	}
	defer pool.Close()
	if err := database.Migrate(ctx, pool); err != nil {
		fmt.Fprintf(os.Stderr, "testdb : migrations : %v\n", err)
		return 1
	}
	*dst = database.New(pool)
	for _, setup := range setups {
		cleanup, err := setup()
		if err != nil {
			fmt.Fprintf(os.Stderr, "testdb : préparation : %v\n", err)
			return 1
		}
		defer cleanup()
	}
	return m.Run()
}

// Require retourne la base du paquet, ou ignore le test si aucune base n'est configurée.
func Require(t testing.TB, db *database.DB) *database.DB {
	t.Helper()
	if db == nil {
		t.Skip("DATABASE_URL non définie : lancer `docker compose up -d --wait` et exporter DATABASE_URL")
	}
	return db
}

func execAdmin(ctx context.Context, adminURL, sql string) error {
	conn, err := pgx.Connect(ctx, adminURL)
	if err != nil {
		return err
	}
	defer conn.Close(ctx)
	_, err = conn.Exec(ctx, sql)
	return err
}
