// Ligne de commande d'administration.
//
//	go run ./cmd/manage grant-admin <email>   donne le rôle admin (crée le compte au besoin)
//	go run ./cmd/manage seed-dev              données de démonstration (local uniquement)
//	go run ./cmd/manage migrate               applique les migrations sans démarrer l'API
package main

import (
	"context"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"os"

	"ivia/backend/internal/app"
	"ivia/backend/internal/platform/config"
	"ivia/backend/internal/platform/database"
)

const usage = `usage : manage <commande>
  grant-admin <email>   donne le rôle admin (crée le compte au besoin)
  seed-dev              crée des données de démonstration (local uniquement)
  migrate               applique les migrations`

func main() {
	if err := run(os.Args[1:]); err != nil {
		fmt.Fprintln(os.Stderr, "erreur :", err)
		os.Exit(1)
	}
}

func run(args []string) error {
	if len(args) == 0 {
		return errors.New(usage)
	}
	cfg, err := config.Load(os.Getenv)
	if err != nil {
		return err
	}
	// La ligne de commande n'exécute aucune tâche de fond : elle ne fait que les créer.
	cfg.RunWorkers = false
	logger := slog.New(slog.NewTextHandler(io.Discard, nil))
	ctx := context.Background()

	pool, err := database.Open(ctx, cfg.DatabaseURL)
	if err != nil {
		return err
	}
	defer pool.Close()
	if err := database.Migrate(ctx, pool); err != nil {
		return err
	}

	switch args[0] {
	case "migrate":
		fmt.Println("Migrations appliquées.")
		return nil
	case "grant-admin":
		if len(args) != 2 {
			return errors.New(usage)
		}
		a, err := app.New(cfg, logger, pool, app.Options{})
		if err != nil {
			return err
		}
		u, err := a.GrantAdmin(ctx, args[1])
		if err != nil {
			return err
		}
		fmt.Printf("Rôle admin donné au compte %s (%s).\n", *u.Email, u.ID)
		return nil
	case "seed-dev":
		a, err := app.New(cfg, logger, pool, app.Options{})
		if err != nil {
			return err
		}
		s, err := a.SeedDev(ctx)
		if err != nil {
			return err
		}
		fmt.Println("Données de démonstration prêtes. Comptes (connexion par mot de passe ; codes dans Mailpit, http://localhost:8025) :")
		fmt.Println("  admin    :", s.AdminEmail)
		fmt.Println("  marchand :", s.SellerEmail, "— boutique", s.ShopID)
		fmt.Println("  acheteur :", s.BuyerEmail)
		fmt.Println("  livreur  :", s.DriverEmail)
		fmt.Println("  mot de passe des quatre comptes :", s.Password, "(local uniquement)")
		return nil
	default:
		return errors.New(usage)
	}
}
