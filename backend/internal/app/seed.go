package app

import (
	"context"
	"errors"
	"fmt"
	"strings"

	"github.com/google/uuid"

	"ivia/backend/internal/catalog"
	"ivia/backend/internal/delivery"
	"ivia/backend/internal/geo"
	"ivia/backend/internal/shops"
	"ivia/backend/internal/users"
)

// GrantAdmin donne le rôle admin à un compte (créé s'il n'existe pas). Utilisé par la ligne de
// commande pour créer le premier admin ; journalisé comme une action du système.
func (a *App) GrantAdmin(ctx context.Context, email string) (users.User, error) {
	u, _, err := a.Users.FindOrCreateByEmail(ctx, strings.ToLower(strings.TrimSpace(email)))
	if err != nil {
		return users.User{}, err
	}
	return a.Users.AdminGrantAdmin(ctx, nil, u.ID, "Attribution par la ligne de commande d'administration.")
}

// SeedSummary décrit les comptes de démonstration créés.
type SeedSummary struct {
	AdminEmail, SellerEmail, BuyerEmail, DriverEmail string
	ShopID                                           uuid.UUID
}

// lomeNeighborhoods : quartiers de démonstration pour le développement local. La liste officielle
// reste à fournir par le porteur du projet (TASKS.md) ; l'admin la gère depuis le back-office.
var lomeNeighborhoods = []struct {
	name     string
	lat, lng float64
}{
	{"Bè", 6.1430, 1.2370}, {"Tokoin", 6.1480, 1.2150}, {"Adidogomé", 6.1750, 1.1600},
	{"Agoè", 6.2350, 1.2050}, {"Nyékonakpoè", 6.1300, 1.2050}, {"Kodjoviakopé", 6.1260, 1.1980},
	{"Hédzranawoé", 6.1630, 1.2400}, {"Baguida", 6.1600, 1.3200}, {"Djidjolé", 6.1600, 1.1950},
	{"Amoutiévé", 6.1330, 1.2250}, {"Avédji", 6.1850, 1.1850}, {"Kégué", 6.1700, 1.2600},
}

var demoCategories = []string{"Alimentation", "Boissons", "Mode", "Beauté", "Maison", "Électronique", "Téléphonie"}

// SeedDev crée des données de démonstration (local uniquement) : quartiers, catégories, un admin,
// un marchand avec une boutique publiée et des produits, un acheteur avec une adresse, un livreur
// validé. Sans effet sur ce qui existe déjà (relançable).
func (a *App) SeedDev(ctx context.Context) (SeedSummary, error) {
	if a.Config.IsProduction() {
		return SeedSummary{}, errors.New("données de démonstration interdites hors local")
	}
	sum := SeedSummary{
		AdminEmail: "admin@ivia.local", SellerEmail: "marchand@ivia.local",
		BuyerEmail: "acheteur@ivia.local", DriverEmail: "livreur@ivia.local",
	}

	adminUser, err := a.GrantAdmin(ctx, sum.AdminEmail)
	if err != nil {
		return sum, fmt.Errorf("admin : %w", err)
	}
	adminID := adminUser.ID

	existing, err := a.Geo.List(ctx, true)
	if err != nil {
		return sum, err
	}
	have := map[string]geo.Neighborhood{}
	for _, n := range existing {
		have[n.Name] = n
	}
	for _, n := range lomeNeighborhoods {
		if _, ok := have[n.name]; ok {
			continue
		}
		created, err := a.Geo.Create(ctx, adminID, geo.NeighborhoodInput{Name: n.name, Center: &geo.Point{Lat: n.lat, Lng: n.lng}})
		if err != nil {
			return sum, fmt.Errorf("quartier %s : %w", n.name, err)
		}
		have[n.name] = created
	}

	cats, err := a.Catalog.ListCategories(ctx, true)
	if err != nil {
		return sum, err
	}
	catIDs := map[string]uuid.UUID{}
	for _, c := range cats {
		catIDs[c.Name] = c.ID
	}
	for i, name := range demoCategories {
		if _, ok := catIDs[name]; ok {
			continue
		}
		c, err := a.Catalog.CreateCategory(ctx, adminID, catalog.CategoryInput{Name: name, Position: int32(i)})
		if err != nil {
			return sum, fmt.Errorf("catégorie %s : %w", name, err)
		}
		catIDs[name] = c.ID
	}

	profile := func(email, first, phone string) (users.User, error) {
		u, _, err := a.Users.FindOrCreateByEmail(ctx, email)
		if err != nil {
			return u, err
		}
		if u.ProfileComplete {
			return u, nil
		}
		accept := true // comptes de démonstration (local uniquement)
		return a.Users.UpdateProfile(ctx, u.ID, users.ProfileInput{FirstName: &first, Phone: &phone, AcceptPrivacyPolicy: &accept})
	}

	seller, err := profile(sum.SellerEmail, "Afi", "+22890000101")
	if err != nil {
		return sum, fmt.Errorf("marchand : %w", err)
	}
	myShops, err := a.Shops.ListMine(ctx, seller.ID)
	if err != nil {
		return sum, err
	}
	if len(myShops) > 0 {
		sum.ShopID = myShops[0].ID
	} else {
		bè := have["Bè"]
		shop, err := a.Shops.Create(ctx, seller.ID, shops.Input{
			Name: "Boutique Afi", Description: "Épicerie et produits du quotidien.", Phone: "+22890000101",
			AddressText: "Rue du marché, Bè", NeighborhoodID: &bè.ID, Location: geo.Point{Lat: 6.1430, Lng: 1.2370},
		})
		if err != nil {
			return sum, fmt.Errorf("boutique : %w", err)
		}
		if _, err := a.Shops.Review(ctx, adminID, shop.ID, "approve", ""); err != nil {
			return sum, fmt.Errorf("validation de la boutique : %w", err)
		}
		sum.ShopID = shop.ID
		qty := int32(25)
		products := []catalog.ProductInput{
			{CategoryID: catIDs["Alimentation"], Name: "Riz parfumé 5 kg", Description: "Sac de riz long grain.", PriceXOF: 4500, ParcelSize: catalog.ParcelMedium, StockMode: catalog.StockTracked, StockQuantity: &qty},
			{CategoryID: catIDs["Boissons"], Name: "Jus de bissap 1 L", Description: "Fait maison.", PriceXOF: 800, ParcelSize: catalog.ParcelSmall, StockMode: catalog.StockUntracked},
			{CategoryID: catIDs["Maison"], Name: "Ventilateur sur pied", Description: "40 cm, 3 vitesses.", PriceXOF: 18000, ParcelSize: catalog.ParcelLarge, StockMode: catalog.StockTracked, StockQuantity: &qty},
		}
		for _, p := range products {
			if _, err := a.Catalog.Create(ctx, seller.ID, shop.ID, p); err != nil {
				return sum, fmt.Errorf("produit %s : %w", p.Name, err)
			}
		}
	}

	buyer, err := profile(sum.BuyerEmail, "Kossi", "+22890000102")
	if err != nil {
		return sum, fmt.Errorf("acheteur : %w", err)
	}
	addrs, err := a.Users.ListAddresses(ctx, buyer.ID)
	if err != nil {
		return sum, err
	}
	if len(addrs) == 0 {
		tokoin := have["Tokoin"]
		if _, err := a.Users.CreateAddress(ctx, buyer.ID, users.AddressInput{
			Label: "Maison", AddressText: "Près de la pharmacie, Tokoin", NeighborhoodID: &tokoin.ID,
			Location: geo.Point{Lat: 6.1480, Lng: 1.2150},
		}); err != nil {
			return sum, fmt.Errorf("adresse : %w", err)
		}
	}

	driver, err := profile(sum.DriverEmail, "Yao", "+22890000103")
	if err != nil {
		return sum, fmt.Errorf("livreur : %w", err)
	}
	if _, err := a.Delivery.Me(ctx, driver.ID); err != nil {
		if _, err := a.Delivery.Apply(ctx, driver.ID, delivery.ApplicationInput{VehicleType: "motorbike", VehiclePlate: "TG-1234-AB"}); err != nil {
			return sum, fmt.Errorf("candidature livreur : %w", err)
		}
		if _, err := a.Delivery.Review(ctx, adminID, driver.ID, "approve", ""); err != nil {
			return sum, fmt.Errorf("validation du livreur : %w", err)
		}
	}
	return sum, nil
}
