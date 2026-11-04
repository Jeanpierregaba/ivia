// Ligne de commande d'administration.
//
//	go run ./cmd/manage grant-admin <email>   donne le rôle admin (crée le compte au besoin)
//	go run ./cmd/manage seed-dev              données de démonstration (local uniquement)
//	go run ./cmd/manage seed-demo             jeu de démonstration complet (local uniquement)
//	go run ./cmd/manage migrate               applique les migrations sans démarrer l'API
package main

import (
	"context"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"os"
	"time"

	"ivia/backend/internal/app"
	"ivia/backend/internal/platform/config"
	"ivia/backend/internal/platform/database"
)

const usage = `usage : manage <commande>
  grant-admin <email>   donne le rôle admin (crée le compte au besoin)
  seed-dev              crée des données de démonstration (local uniquement)
  seed-demo             jeu complet : boutiques, catalogue photographié, IVI, publicité,
                        acheteurs, livreurs, commandes à tous les statuts (local uniquement)
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
	// La ligne de commande n'exécute aucune tâche de fond (elle ne fait que les créer), sauf
	// seed-demo qui fait avancer ses commandes (paiement confirmé, livreur sollicité).
	cfg.RunWorkers = args[0] == "seed-demo"
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
	case "seed-demo":
		a, err := app.New(cfg, logger, pool, app.Options{PollInterval: 100 * time.Millisecond})
		if err != nil {
			return err
		}
		s, err := a.SeedDemo(ctx, func(format string, args ...any) { fmt.Printf(format+"\n", args...) })
		if err != nil {
			return err
		}
		fmt.Println()
		fmt.Printf("Jeu de démonstration prêt : %d boutiques, %d produits ajoutés, %d photos, %d visuels, %d acheteurs, %d livreurs.\n",
			s.Shops, s.Products, s.Photos, s.Visuals, s.Buyers, s.Drivers)
		fmt.Printf("Commandes : %d (tous les statuts ; une relance complète sans doublon).\n", s.Orders)
		if s.PhotoErrors > 0 {
			fmt.Printf("Attention : %d photos n'ont pas pu être téléchargées (connexion ?). Relancez pour compléter.\n", s.PhotoErrors)
		}
		fmt.Println("Comptes (mot de passe commun :", s.Password, "— local uniquement) :")
		fmt.Println("  admin            :", s.AdminEmail)
		fmt.Println("  marchands        : marchand@ (concept store), akossiwa@, couture@, eclat@, delices@, comptoir@, fresh@, techavenue@, deco@, sneakers@, ivi@ivia.local")
		fmt.Println("  acheteurs        :", s.BuyerEmail, "et afi.mensah@, yao.akakpo@, ama.dogbe@… @ivia.local")
		fmt.Println("  livreurs         :", s.DriverEmail, "et kodjo.abalo@, essowe.tchalla@, komi.djobo@… @ivia.local")
		fmt.Println("Produits IVI : en vente et en tête des listes, avec des PRIX DE DÉMONSTRATION à remplacer dans le back-office (Produits IVI).")
		return nil
	default:
		return errors.New(usage)
	}
}
