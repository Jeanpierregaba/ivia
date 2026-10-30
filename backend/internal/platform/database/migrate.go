package database

import (
	"context"
	"fmt"
	"io/fs"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/jackc/pgx/v5/stdlib"
	"github.com/pressly/goose/v3"

	"ivia/backend/db"
)

// Migrate applique les migrations goose qui ne l'ont pas encore été.
func Migrate(ctx context.Context, pool *pgxpool.Pool) error {
	migrations, err := fs.Sub(db.Migrations, "migrations")
	if err != nil {
		return fmt.Errorf("lecture des migrations : %w", err)
	}

	sqlDB := stdlib.OpenDBFromPool(pool)
	defer sqlDB.Close()

	provider, err := goose.NewProvider(goose.DialectPostgres, sqlDB, migrations)
	if err != nil {
		return fmt.Errorf("préparation des migrations : %w", err)
	}
	if _, err := provider.Up(ctx); err != nil {
		return fmt.Errorf("application des migrations : %w", err)
	}
	return nil
}
