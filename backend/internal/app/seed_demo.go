package app

import (
	"context"
	"crypto/sha1"
	"embed"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"slices"
	"time"

	"github.com/google/uuid"

	"ivia/backend/internal/catalog"
	"ivia/backend/internal/delivery"
	"ivia/backend/internal/geo"
	"ivia/backend/internal/orders"
	"ivia/backend/internal/payments"
	"ivia/backend/internal/platform/storage"
	"ivia/backend/internal/promo"
	"ivia/backend/internal/shops"
	"ivia/backend/internal/users"
)

// Jeu de démonstration complet (local uniquement) : marchands et boutiques dans plusieurs
// quartiers, catalogue photographié, boutique officielle IVI, visuels publicitaires, acheteurs
// avec adresses, livreurs répartis par zone, commandes à tous les statuts. Tout passe par les
// services (mêmes règles que les apps) ; relançable sans doublon.

//go:embed seedassets/demo_catalog.json
var demoCatalogJSON []byte

//go:embed seedassets/ivi/*.jpg
var iviAssets embed.FS

// Photos du catalogue, redimensionnées et embarquées : le jeu se crée sans connexion.
//
//go:embed seedassets/demo/*.jpg
var demoPhotos embed.FS

type demoImage struct {
	// File : photo embarquée (seedassets/demo) ; URL, Source, Author, License : crédits.
	File    string `json:"file"`
	URL     string `json:"url"`
	Source  string `json:"source"`
	Author  string `json:"author"`
	License string `json:"license"`
}

type demoProduct struct {
	Name          string      `json:"name"`
	Description   string      `json:"description"`
	Category      string      `json:"category"`
	PriceXOF      int64       `json:"price_xof"`
	ParcelSize    string      `json:"parcel_size"`
	Stock         *int32      `json:"stock"`
	Images        []demoImage `json:"images"`
	PromoPriceXOF *int64      `json:"promo_price_xof"`
	Badges        []string    `json:"badges"`
}

type demoShop struct {
	Key          string  `json:"key"`
	Name         string  `json:"name"`
	Category     string  `json:"category"`
	Description  string  `json:"description"`
	Neighborhood string  `json:"neighborhood"`
	Address      string  `json:"address"`
	Lat          float64 `json:"lat"`
	Lng          float64 `json:"lng"`
	Owner        struct {
		First string `json:"first"`
		Last  string `json:"last"`
		Email string `json:"email"`
		Phone string `json:"phone"`
	} `json:"owner"`
	Products []demoProduct `json:"products"`
}

// Sous-catégories de produits (catégorie parente → sous-catégories).
var demoSubcategories = []struct {
	parent string
	names  []string
}{
	{"Alimentation", []string{"Pâtisserie", "Épicerie fine"}},
	{"Boissons", []string{"Eaux minérales", "Jus et smoothies"}},
	{"Mode", []string{"Vêtements", "Maroquinerie", "Accessoires", "Chaussures"}},
	{"Beauté", []string{"Parfums", "Soins", "Maquillage"}},
	{"Maison", []string{"Décoration", "Arts de la table"}},
	{"Électronique", []string{"Audio", "Informatique", "Objets connectés"}},
}

// Catégorie de boutique selon la catégorie principale du catalogue.
var demoShopCategory = map[string]string{
	"Alimentation": "Alimentation", "Boissons": "Alimentation", "Mode": "Mode et beauté",
	"Beauté": "Mode et beauté", "Maison": "Maison", "Électronique": "Électronique et téléphonie",
}

// Marchands de la première version du jeu (catalogue trop ordinaire), suspendus à la relance.
var legacyDemoMerchants = []string{
	"dzidudu@ivia.local", "mawuli@ivia.local", "fournil@ivia.local", "golfe@ivia.local", "tata@ivia.local",
	"akpene@ivia.local", "yawa@ivia.local", "kodjo@ivia.local", "tech@ivia.local",
}

var demoBuyers = []struct{ first, last, email, phone, hood, address string }{
	{"Kossi", "Agbeko", "acheteur@ivia.local", "+22890000102", "Tokoin", "Près de la pharmacie, Tokoin"},
	{"Afi", "Mensah", "afi.mensah@ivia.local", "+22890000301", "Bè", "Rue Bè-Kpota, portail bleu"},
	{"Yao", "Akakpo", "yao.akakpo@ivia.local", "+22890000302", "Adidogomé", "Adidogomé Sagbado, après l'école"},
	{"Ama", "Dogbé", "ama.dogbe@ivia.local", "+22890000303", "Agoè", "Agoè Nyivé, maison à étage"},
	{"Komlan", "Ayité", "komlan.ayite@ivia.local", "+22890000304", "Nyékonakpoè", "Rue du lycée, Nyékonakpoè"},
	{"Esse", "Amouzou", "esse.amouzou@ivia.local", "+22890000305", "Kodjoviakopé", "Près de l'ambassade, Kodjoviakopé"},
	{"Délali", "Tsogbé", "delali.tsogbe@ivia.local", "+22890000306", "Hédzranawoé", "Derrière le marché, Hédzranawoé"},
	{"Sena", "Kudjo", "sena.kudjo@ivia.local", "+22890000307", "Baguida", "Baguida plage, villa 12"},
	{"Edem", "Gbadoé", "edem.gbadoe@ivia.local", "+22890000308", "Djidjolé", "Carrefour Djidjolé, immeuble vert"},
	{"Mawuena", "Klu", "mawuena.klu@ivia.local", "+22890000309", "Amoutiévé", "Amoutiévé, rue de l'église"},
	{"Kafui", "Adzo", "kafui.adzo@ivia.local", "+22890000310", "Avédji", "Avédji Limousine, portail noir"},
	{"Elom", "Sossou", "elom.sossou@ivia.local", "+22890000311", "Kégué", "Kégué, face au stade"},
}

// Livreurs : zone de travail, véhicule et état (online, offline, pending : dossier à valider).
var demoDrivers = []struct{ first, last, email, phone, hood, vehicle, plate, state string }{
	{"Yao", "Kpatcha", "livreur@ivia.local", "+22890000103", "Tokoin", "motorbike", "TG-1234-AB", "online"},
	{"Kodjo", "Abalo", "kodjo.abalo@ivia.local", "+22890000401", "Bè", "motorbike", "TG-2101-AC", "online"},
	{"Essowè", "Tchalla", "essowe.tchalla@ivia.local", "+22890000402", "Hédzranawoé", "motorbike", "TG-2102-AC", "online"},
	{"Komi", "Djobo", "komi.djobo@ivia.local", "+22890000403", "Djidjolé", "car", "TG-2103-AD", "online"},
	{"Atsu", "Kokou", "atsu.kokou@ivia.local", "+22890000404", "Nyékonakpoè", "motorbike", "TG-2104-AD", "online"},
	{"Fofana", "Issa", "issa.fofana@ivia.local", "+22890000405", "Agoè", "motorbike", "TG-2105-AE", "offline"},
	{"Paul", "Edoh", "paul.edoh@ivia.local", "+22890000406", "Adidogomé", "car", "TG-2106-AE", "offline"},
	{"Kossivi", "Akué", "kossivi.akue@ivia.local", "+22890000407", "Baguida", "motorbike", "TG-2107-AF", "offline"},
	{"Sélom", "Ahadji", "selom.ahadji@ivia.local", "+22890000408", "Kégué", "motorbike", "TG-2108-AF", "pending"},
	{"Tchilabalo", "Bassah", "tchila.bassah@ivia.local", "+22890000409", "Avédji", "car", "TG-2109-AG", "pending"},
}

// IVI : boutique officielle et premiers produits (photos fournies par la marque), en vente et
// en tête de toutes les listes. Les prix sont des PRIX DE DÉMONSTRATION (jeu local uniquement),
// à remplacer par les vrais prix dans le back-office (Produits IVI) ; en production, les produits
// IVI sont créés par l'admin avec les prix réels.
var iviProducts = []struct {
	name, description string
	images            []string
	rank              int32
	price             int64
	promo             *int64
	badges            []string
}{
	{"AWU IVI 1,5 L", "Eau minérale naturelle AWU IVI, bouteille de 1,5 L. Le choix naturel pour une vie meilleure.",
		[]string{"awu-ivi-150-1.jpg", "awu-ivi-150-2.jpg"}, 1, 500, ptr64(400), []string{"promotion", "best_seller"}},
	{"Paquet IVI 30 sachets × 500 ml", "Eau minérale naturelle IVI en sachets de 500 ml, paquet de 30 : la réserve de la maison.",
		[]string{"ivi-paquet-sachets-1.jpg", "ivi-paquet-sachets-2.jpg"}, 2, 750, ptr64(650), []string{"special_offer"}},
	{"AWU IVI 0,5 L", "Eau minérale naturelle AWU IVI, bouteille de 0,5 L, à emporter partout.",
		[]string{"awu-ivi-050-1.jpg", "awu-ivi-050-2.jpg"}, 3, 250, nil, []string{"featured", "best_seller"}},
	{"Bonbonne IVI", "Eau minérale naturelle IVI en bonbonne, pour la maison et le bureau.",
		[]string{"ivi-bonbonne-1.jpg", "ivi-bonbonne-2.jpg"}, 4, 3000, ptr64(2500), []string{"promotion"}},
	{"AWU IVI 0,33 L", "Eau minérale naturelle AWU IVI, petite bouteille de 0,33 L.",
		[]string{"awu-ivi-033-1.jpg", "awu-ivi-033-2.jpg"}, 5, 200, nil, []string{"featured"}},
}

func ptr64(v int64) *int64 { return &v }

func imageKeysOf(p catalog.Product) []string {
	keys := make([]string, len(p.Images))
	for i, img := range p.Images {
		keys[i] = img.ObjectKey
	}
	return keys
}

// Mentions lues sur les emballages et la communication de la marque.
var iviFeatures = []string{
	"Eau minérale naturelle", "Au goût agréable", "Autorisée par le ministère de la Santé",
	"Produite à Lomé par OBEDJI BLESS SARL", "Numéro consommateur : 93 54 73 73",
}

// IVIOfficialURL : site officiel de la marque (modifiable dans les réglages de la publicité).
const IVIOfficialURL = "https://www.eaumineraleivi.com"

// DemoSummary décrit le jeu de démonstration.
type DemoSummary struct {
	SeedSummary
	Shops, Products, Photos, Buyers, Drivers, Visuals, Orders int
	PhotoErrors                                               int
	payPhone                                                  int
}

// SeedDemo crée le jeu de démonstration complet (local uniquement). logf reçoit l'avancement.
func (a *App) SeedDemo(ctx context.Context, logf func(format string, args ...any)) (DemoSummary, error) {
	var out DemoSummary
	if a.Config.IsProduction() {
		return out, errors.New("données de démonstration interdites hors local")
	}
	if a.LocalStore == nil {
		return out, errors.New("STORAGE=local requis pour les photos de démonstration")
	}
	base, err := a.SeedDev(ctx)
	if err != nil {
		return out, err
	}
	out.SeedSummary = base
	adminUser, err := a.Users.FindByEmail(ctx, base.AdminEmail)
	if err != nil {
		return out, err
	}
	adminID := adminUser.ID

	// Quartiers et catégories.
	hoods, err := a.Geo.List(ctx, true)
	if err != nil {
		return out, err
	}
	hood := map[string]geo.Neighborhood{}
	for _, n := range hoods {
		hood[n.Name] = n
	}
	cats, err := a.ensureSubcategories(ctx, adminID)
	if err != nil {
		return out, err
	}
	shopCats, err := a.Shops.ListCategories(ctx)
	if err != nil {
		return out, err
	}
	shopCat := map[string]uuid.UUID{}
	for _, c := range shopCats {
		shopCat[c.Name] = c.ID
	}

	var catalogDef struct {
		Shops []demoShop `json:"shops"`
	}
	if err := json.Unmarshal(demoCatalogJSON, &catalogDef); err != nil {
		return out, fmt.Errorf("catalogue de démonstration : %w", err)
	}
	catalogDef.Shops = withDemoBranches(catalogDef.Shops)

	// Marchands, boutiques et produits.
	type seededShop struct {
		ownerID, shopID uuid.UUID
		products        []catalog.Product
	}
	var seeded []seededShop
	for _, def := range catalogDef.Shops {
		owner, err := a.demoProfile(ctx, def.Owner.Email, def.Owner.First, def.Owner.Last, def.Owner.Phone)
		if err != nil {
			return out, fmt.Errorf("marchand %s : %w", def.Name, err)
		}
		n := hood[def.Neighborhood]
		catID := shopCat[demoShopCategory[def.Category]]
		input := shops.Input{
			Name: def.Name, Description: def.Description, Phone: def.Owner.Phone, AddressText: def.Address,
			NeighborhoodID: &n.ID, Location: geo.Point{Lat: def.Lat, Lng: def.Lng}, CategoryID: &catID,
		}
		// Photo de la boutique : la première photo de ses articles.
		shopLogo := func() *string {
			for _, p := range def.Products {
				for _, img := range p.Images {
					if img.File == "" {
						continue
					}
					if data, err := demoPhotos.ReadFile("seedassets/demo/" + img.File); err == nil {
						k := "shops/" + owner.ID.String() + "/" + uuid.NewString() + ".jpg"
						if a.LocalStore.Write(storage.Public, k, data) == nil {
							return &k
						}
					}
				}
			}
			return nil
		}
		if mine, _ := a.Shops.ListMine(ctx, owner.ID); len(mine) == 0 {
			input.LogoKey = shopLogo()
		}
		shopID, err := a.demoShop(ctx, adminID, owner.ID, input)
		if err != nil {
			return out, fmt.Errorf("boutique %s : %w", def.Name, err)
		}
		// Boutique d'un seed précédent : nom, présentation et photo du catalogue actuel.
		if cur, err := a.Shops.Get(ctx, shopID); err == nil && (cur.Name != def.Name || cur.LogoURL == nil) {
			if cur.LogoURL == nil {
				input.LogoKey = shopLogo()
			}
			if _, err := a.Shops.Update(ctx, owner.ID, shopID, input); err != nil {
				return out, fmt.Errorf("boutique %s : %w", def.Name, err)
			}
		}
		out.Shops++
		existing, err := a.Catalog.AdminList(ctx, &shopID, "", 100, 0)
		if err != nil {
			return out, err
		}
		// Produits d'un seed précédent absents du catalogue actuel : retirés de la vente.
		for _, e := range existing {
			if !e.IsActive || slices.ContainsFunc(def.Products, func(p demoProduct) bool { return p.Name == e.Name }) {
				continue
			}
			off := false
			if _, err := a.Catalog.Update(ctx, owner.ID, e.ID, catalog.ProductInput{
				CategoryID: e.CategoryID, Name: e.Name, Description: e.Description, PriceXOF: e.PriceXOF,
				ParcelSize: e.ParcelSize, IsActive: &off, ImageKeys: imageKeysOf(e),
			}); err != nil {
				logf("  produit %s non retiré : %v", e.Name, err)
			}
		}
		for _, p := range def.Products {
			if slices.ContainsFunc(existing, func(e catalog.Product) bool { return e.Name == p.Name }) {
				continue
			}
			keys := []string{}
			for _, img := range p.Images {
				data, err := demoPhotos.ReadFile("seedassets/demo/" + img.File)
				if err != nil || img.File == "" {
					data, err = demoPhoto(ctx, img.URL)
				}
				if err != nil {
					out.PhotoErrors++
					logf("  photo indisponible (%s) : %v", p.Name, err)
					continue
				}
				key := "products/" + owner.ID.String() + "/" + uuid.NewString() + ".jpg"
				if err := a.LocalStore.Write(storage.Public, key, data); err != nil {
					return out, err
				}
				keys = append(keys, key)
				out.Photos++
			}
			in := catalog.ProductInput{
				CategoryID: cats[p.Category], Name: p.Name, Description: p.Description, PriceXOF: p.PriceXOF,
				ParcelSize: catalog.ParcelSize(p.ParcelSize), StockMode: catalog.StockUntracked, ImageKeys: keys,
			}
			if p.Stock != nil {
				in.StockMode, in.StockQuantity = catalog.StockTracked, p.Stock
			}
			created, err := a.Catalog.Create(ctx, owner.ID, shopID, in)
			if err != nil {
				return out, fmt.Errorf("produit %s : %w", p.Name, err)
			}
			if p.PromoPriceXOF != nil || len(p.Badges) > 0 {
				end := time.Now().AddDate(0, 0, 21)
				var ends *time.Time
				if p.PromoPriceXOF != nil {
					ends = &end
				}
				if _, err := a.Catalog.SetMarketing(ctx, adminID, created.ID, catalog.MarketingInput{
					PromoPriceXOF: p.PromoPriceXOF, PromoEndsAt: ends, Badges: p.Badges,
				}); err != nil {
					return out, fmt.Errorf("promotion %s : %w", p.Name, err)
				}
			}
			out.Products++
			logf("  %s — %s", def.Name, p.Name)
		}
		products, err := a.Catalog.AdminList(ctx, &shopID, "", 100, 0)
		if err != nil {
			return out, err
		}
		seeded = append(seeded, seededShop{ownerID: owner.ID, shopID: shopID, products: products})
	}

	// Boutiques de la première version du jeu de démonstration : suspendues (leurs commandes
	// restent consultables), remplacées par le catalogue actuel.
	for _, email := range legacyDemoMerchants {
		u, err := a.Users.FindByEmail(ctx, email)
		if err != nil {
			continue
		}
		mine, err := a.Shops.ListMine(ctx, u.ID)
		if err != nil {
			return out, err
		}
		for _, sh := range mine {
			if sh.Status == shops.StatusPublished {
				if _, err := a.Shops.Review(ctx, adminID, sh.ID, "suspend", "Boutique de démonstration remplacée."); err != nil {
					logf("  boutique %s non suspendue : %v", sh.Name, err)
				}
			}
		}
	}

	// Boutique officielle IVI et visuels publicitaires.
	iviProductIDs, err := a.seedIVI(ctx, adminID, hood, shopCat, cats, &out)
	if err != nil {
		return out, fmt.Errorf("IVI : %w", err)
	}
	if err := a.seedPromoVisuals(ctx, adminID, iviProductIDs, &out); err != nil {
		return out, fmt.Errorf("visuels : %w", err)
	}

	// Acheteurs et adresses.
	type buyer struct {
		id, addressID uuid.UUID
		phone         string
	}
	var buyers []buyer
	for _, b := range demoBuyers {
		u, err := a.demoProfile(ctx, b.email, b.first, b.last, b.phone)
		if err != nil {
			return out, fmt.Errorf("acheteur %s : %w", b.email, err)
		}
		addrs, err := a.Users.ListAddresses(ctx, u.ID)
		if err != nil {
			return out, err
		}
		if len(addrs) == 0 {
			n := hood[b.hood]
			ad, err := a.Users.CreateAddress(ctx, u.ID, users.AddressInput{
				Label: "Maison", AddressText: b.address, NeighborhoodID: &n.ID,
				Location:     geo.Point{Lat: n.Center.Lat + 0.004, Lng: n.Center.Lng - 0.003},
				Instructions: "Appeler en arrivant.",
			})
			if err != nil {
				return out, fmt.Errorf("adresse de %s : %w", b.email, err)
			}
			addrs = append(addrs, ad)
		}
		buyers = append(buyers, buyer{id: u.ID, addressID: addrs[0].ID, phone: b.phone})
		out.Buyers++
	}

	// Livreurs par zone.
	type driver struct {
		id     uuid.UUID
		online bool
		at     geo.Point
	}
	var drivers []driver
	for _, d := range demoDrivers {
		u, err := a.demoProfile(ctx, d.email, d.first, d.last, d.phone)
		if err != nil {
			return out, fmt.Errorf("livreur %s : %w", d.email, err)
		}
		n := hood[d.hood]
		if err := a.demoDriver(ctx, adminID, u.ID, d.vehicle, d.plate, d.state != "pending"); err != nil {
			return out, fmt.Errorf("livreur %s : %w", d.email, err)
		}
		dr := driver{id: u.ID, at: geo.Point{Lat: n.Center.Lat, Lng: n.Center.Lng}}
		if d.state != "pending" {
			dr.online = d.state == "online"
			// Relance : un livreur en course garde sa disponibilité (refus attendu, ignoré).
			if _, err := a.Delivery.SetAvailability(ctx, u.ID, dr.online); err != nil {
				logf("  disponibilité de %s inchangée : %v", d.email, err)
			}
		}
		drivers = append(drivers, dr)
		out.Drivers++
	}

	// Commandes : chaque scénario a un identifiant de requête fixe (création idempotente) et
	// avance pas à pas depuis son statut actuel jusqu'au statut visé : relancer le seed complète
	// ce qui manque sans rien dupliquer. Les tâches de fond (paiement, attribution) tournent ici.
	if err := a.Start(ctx); err != nil {
		return out, err
	}
	defer func() {
		stopCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		_ = a.Stop(stopCtx)
	}()
	fake, ok := a.Payments.Provider().(*payments.FakeProvider)
	if !ok {
		return out, errors.New("commandes de démonstration : prestataire de paiement factice requis (PAYMENT_PROVIDER=fake)")
	}

	type scenario struct {
		target string
		mode   orders.Fulfillment
	}
	D, P := orders.FulfillmentDelivery, orders.FulfillmentPickup
	scenarios := []scenario{
		{"delivered", D}, {"delivered", D}, {"delivered", D}, {"delivered", D}, {"delivered", D},
		{"completed", P}, {"completed", P}, {"completed", P}, {"completed", P},
		{"picked_up", D}, {"driver_assigned", D},
		{"ready_for_pickup", P}, {"ready_for_pickup", P},
		{"preparing", D}, {"preparing", P}, {"accepted", D}, {"accepted", P},
		{"awaiting_seller", D}, {"awaiting_seller", P}, {"awaiting_seller", D},
		{"rejected", P}, {"refunded", D}, {"cancelled_by_buyer", P},
		{"pending_payment", D}, {"pending_payment", P}, {"pending_payment", P},
		{"awaiting_driver", D},
	}
	refresh := func() {
		for _, d := range drivers {
			if d.online {
				_ = a.Delivery.UpdateLocation(ctx, d.id, delivery.LocationInput{Lat: d.at.Lat, Lng: d.at.Lng})
			}
		}
	}
	status := func(b buyer, id uuid.UUID) (orders.BuyerOrder, error) { return a.Orders.GetForBuyer(ctx, b.id, id) }
	waitStatus := func(b buyer, id uuid.UUID, from orders.Status) (orders.BuyerOrder, error) {
		deadline := time.Now().Add(20 * time.Second)
		for {
			o, err := status(b, id)
			if err != nil || o.Status != from || time.Now().After(deadline) {
				return o, err
			}
			time.Sleep(150 * time.Millisecond)
		}
	}
	// mission retrouve la course d'une commande et son livreur.
	mission := func(orderID uuid.UUID) (uuid.UUID, *delivery.Mission) {
		for _, d := range drivers {
			if m, err := a.Delivery.CurrentMission(ctx, d.id); err == nil && m != nil && m.OrderID == orderID {
				return d.id, m
			}
		}
		return uuid.Nil, nil
	}
	waitOffer := func(orderID uuid.UUID) (uuid.UUID, uuid.UUID, error) {
		deadline := time.Now().Add(25 * time.Second)
		for time.Now().Before(deadline) {
			for _, d := range drivers {
				if !d.online {
					continue
				}
				if off, err := a.Delivery.CurrentOffer(ctx, d.id); err == nil && off != nil && off.OrderID == orderID {
					return d.id, off.ID, nil
				}
			}
			time.Sleep(200 * time.Millisecond)
		}
		return uuid.Nil, uuid.Nil, errors.New("aucun livreur n'a reçu la course")
	}

	for i, sc := range scenarios {
		b := buyers[(i+1)%len(buyers)]
		s := seeded[i%len(seeded)]
		// Produits relus à chaque commande : le stock baisse au fil des commandes.
		fresh, err := a.Catalog.AdminList(ctx, &s.shopID, "", 100, 0)
		if err != nil {
			return out, err
		}
		avail := slices.DeleteFunc(fresh, func(p catalog.Product) bool {
			return !p.IsActive || !p.Available || (p.StockQuantity != nil && *p.StockQuantity < 2)
		})
		if len(avail) == 0 {
			continue
		}
		reqID := uuid.NewSHA1(uuid.NameSpaceURL, fmt.Appendf(nil, "ivia-demo-order-v2-%d", i))
		o, err := func() (orders.BuyerOrder, error) {
			for j := 0; j < 1+i%2; j++ {
				p := avail[(i+j)%len(avail)]
				qty := int32(1 + (i+j)%3)
				if p.StockQuantity != nil && *p.StockQuantity < qty+3 {
					qty = 1 // stock faible : une unité
				}
				if _, err := a.Cart.SetItem(ctx, b.id, p.ID, qty, j == 0); err != nil {
					return orders.BuyerOrder{}, fmt.Errorf("panier : %w", err)
				}
			}
			in := orders.CheckoutInput{Fulfillment: sc.mode, ClientRequestID: &reqID}
			if sc.mode == D {
				in.AddressID = &b.addressID
			}
			// Commande déjà créée (relance) : Checkout la renvoie telle quelle ; le panier est vidé.
			o, err := a.Orders.Checkout(ctx, b.id, in)
			if err == nil {
				_ = a.Cart.Clear(ctx, b.id)
			}
			return o, err
		}()
		if err != nil {
			logf("  commande %d ignorée : %v", i+1, err)
			continue
		}
		out.Orders++
		fail := func(err error) { logf("  commande %s (%s → %s) : %v", o.Reference, o.Status, sc.target, err) }
		for guard := 0; guard < 12; guard++ {
			var err error
			progressed := true
			switch o.Status {
			case orders.StatusPendingPayment:
				if sc.target == "pending_payment" {
					progressed = false
					break
				}
				out.payPhone++
				var p payments.Payment
				if p, err = a.Payments.Initiate(ctx, b.id, o.ID, payments.OperatorFlooz, fmt.Sprintf("+2289%07d", 1000000+out.payPhone)); err != nil {
					break
				}
				var ap payments.AdminPayment
				if ap, err = a.Payments.AdminGet(ctx, p.ID); err != nil {
					break
				}
				header, body, e := fake.Simulate(ap.Reference, payments.ProviderSucceeded, -1)
				if e != nil {
					err = e
					break
				}
				ev, e := fake.ParseWebhook(header, body)
				if e != nil {
					err = e
					break
				}
				if err = a.Payments.HandleWebhook(ctx, ev); err == nil {
					o, err = waitStatus(b, o.ID, orders.StatusPendingPayment)
					continue
				}
			case orders.StatusAwaitingSeller:
				switch sc.target {
				case "awaiting_seller":
					progressed = false
				case "cancelled_by_buyer":
					_, err = a.Orders.CancelByBuyer(ctx, b.id, o.ID)
				case "rejected", "refunded":
					_, err = a.Orders.Reject(ctx, s.ownerID, o.ID, "Produit en rupture, désolé.")
				default:
					_, err = a.Orders.Accept(ctx, s.ownerID, o.ID)
				}
			case orders.StatusAccepted:
				if progressed = sc.target != "accepted"; progressed {
					_, err = a.Orders.StartPreparing(ctx, s.ownerID, o.ID)
				}
			case orders.StatusPreparing:
				if progressed = sc.target != "preparing"; progressed {
					if sc.target != "awaiting_driver" {
						refresh()
					}
					_, err = a.Orders.MarkReady(ctx, s.ownerID, o.ID)
				}
			case orders.StatusReadyForPickup:
				if progressed = sc.target == "completed" && o.HandoverCode != nil; progressed {
					_, err = a.Orders.CompletePickup(ctx, s.ownerID, o.ID, *o.HandoverCode)
				}
			case orders.StatusAwaitingDriver:
				if progressed = sc.target != "awaiting_driver"; progressed {
					refresh()
					driverID, offerID, e := waitOffer(o.ID)
					if err = e; err == nil {
						_, err = a.Delivery.AcceptOffer(ctx, driverID, offerID)
					}
				}
			case orders.StatusDriverAssigned:
				if progressed = sc.target != "driver_assigned"; progressed {
					driverID, m := mission(o.ID)
					if m == nil {
						err = errors.New("course introuvable")
						break
					}
					if _, err = a.Delivery.ArrivedAtShop(ctx, driverID, m.ID); err == nil {
						_, err = a.Delivery.PickedUp(ctx, driverID, m.ID)
					}
				}
			case orders.StatusPickedUp:
				if progressed = sc.target != "picked_up" && o.HandoverCode != nil; progressed {
					driverID, m := mission(o.ID)
					if m == nil {
						err = errors.New("course introuvable")
						break
					}
					if _, err = a.Delivery.ArrivedAtCustomer(ctx, driverID, m.ID); err == nil {
						_, err = a.Delivery.Deliver(ctx, driverID, m.ID, *o.HandoverCode)
					}
				}
			case orders.StatusCancelled:
				if sc.target == "refunded" {
					// Remboursement par l'admin (file des remboursements) ; déjà fait : ignoré.
					_, _ = a.Payments.RefundOrder(ctx, adminID, o.ID, "Commande refusée par la boutique.")
				}
				progressed = false
			default:
				progressed = false
			}
			if err != nil {
				fail(err)
				break
			}
			if !progressed {
				break
			}
			if o, err = status(b, o.ID); err != nil {
				fail(err)
				break
			}
		}
	}

	// Paniers en cours (sans commande), pour quelques acheteurs.
	for i, b := range buyers[8:] {
		s := seeded[(i+3)%len(seeded)]
		avail := slices.DeleteFunc(slices.Clone(s.products), func(p catalog.Product) bool { return !p.IsActive || !p.Available })
		if len(avail) == 0 {
			continue
		}
		if c, err := a.Cart.Get(ctx, b.id); err == nil && len(c.Items) == 0 {
			_, _ = a.Cart.SetItem(ctx, b.id, avail[0].ID, 2, true)
		}
	}

	// Pharmacies de garde autour de Tokoin (alerte médicament).
	n, err := a.seedDemoPharmacies(ctx)
	if err != nil {
		return out, err
	}
	logf("pharmacies de démonstration : %d", n)
	return out, nil
}

// ensureSubcategories crée les sous-catégories manquantes et retourne nom → identifiant.
func (a *App) ensureSubcategories(ctx context.Context, adminID uuid.UUID) (map[string]uuid.UUID, error) {
	cats, err := a.Catalog.ListCategories(ctx, true)
	if err != nil {
		return nil, err
	}
	ids := map[string]uuid.UUID{}
	for _, c := range cats {
		ids[c.Name] = c.ID
	}
	for _, g := range demoSubcategories {
		parent, ok := ids[g.parent]
		if !ok {
			return nil, fmt.Errorf("catégorie %s absente", g.parent)
		}
		for i, name := range g.names {
			if _, ok := ids[name]; ok {
				continue
			}
			c, err := a.Catalog.CreateCategory(ctx, adminID, catalog.CategoryInput{Name: name, ParentID: &parent, Position: int32(i)})
			if err != nil {
				return nil, fmt.Errorf("sous-catégorie %s : %w", name, err)
			}
			ids[name] = c.ID
		}
	}
	return ids, nil
}

// demoProfile crée (ou retrouve) un compte de démonstration avec profil complet et mot de passe.
func (a *App) demoProfile(ctx context.Context, email, first, last, phone string) (users.User, error) {
	u, _, err := a.Users.FindOrCreateByEmail(ctx, email)
	if err != nil {
		return u, err
	}
	if !u.ProfileComplete {
		accept := true // compte de démonstration (local uniquement)
		if u, err = a.Users.UpdateProfile(ctx, u.ID, users.ProfileInput{
			FirstName: &first, LastName: &last, Phone: &phone, AcceptPrivacyPolicy: &accept,
		}); err != nil {
			return u, err
		}
	}
	return u, a.Auth.SetPassword(ctx, u.ID, DemoPassword)
}

// demoShop crée la boutique du marchand (pièces déposées, validée) ou retourne la première.
func (a *App) demoShop(ctx context.Context, adminID, ownerID uuid.UUID, in shops.Input) (uuid.UUID, error) {
	mine, err := a.Shops.ListMine(ctx, ownerID)
	if err != nil {
		return uuid.Nil, err
	}
	if len(mine) > 0 {
		return mine[0].ID, nil
	}
	shop, err := a.Shops.Create(ctx, ownerID, in)
	if err != nil {
		return uuid.Nil, err
	}
	for _, kind := range shops.RequiredDocuments {
		key := "merchants/" + ownerID.String() + "/" + uuid.NewString() + ".pdf"
		if err := a.LocalStore.Write(storage.Private, key, []byte("%PDF-1.4 document de démonstration")); err != nil {
			return uuid.Nil, err
		}
		if _, err := a.Shops.AddDocument(ctx, ownerID, kind, key); err != nil {
			return uuid.Nil, err
		}
	}
	if _, err := a.Shops.Review(ctx, adminID, shop.ID, "approve", ""); err != nil {
		return uuid.Nil, err
	}
	return shop.ID, nil
}

// demoDriver dépose le dossier d'un livreur et le valide si approve.
func (a *App) demoDriver(ctx context.Context, adminID, userID uuid.UUID, vehicle, plate string, approve bool) error {
	if _, err := a.Delivery.Me(ctx, userID); err == nil {
		return nil
	}
	if _, err := a.Delivery.Apply(ctx, userID, delivery.ApplicationInput{VehicleType: vehicle, VehiclePlate: plate}); err != nil {
		return err
	}
	for _, kind := range delivery.RequiredDocuments {
		key := "drivers/" + userID.String() + "/" + uuid.NewString() + ".pdf"
		if err := a.LocalStore.Write(storage.Private, key, []byte("%PDF-1.4 document de démonstration")); err != nil {
			return err
		}
		if _, err := a.Delivery.AddDocument(ctx, userID, kind, key); err != nil {
			return err
		}
	}
	if !approve {
		return nil
	}
	_, err := a.Delivery.Review(ctx, adminID, userID, "approve", "")
	return err
}

// seedIVI crée la boutique officielle IVI et ses produits, en vente et mis en avant.
func (a *App) seedIVI(ctx context.Context, adminID uuid.UUID, hood map[string]geo.Neighborhood, shopCat, cats map[string]uuid.UUID, out *DemoSummary) (map[string]uuid.UUID, error) {
	owner, err := a.demoProfile(ctx, "ivi@ivia.local", "IVI", "OBEDJI BLESS", "+22892042828")
	if err != nil {
		return nil, err
	}
	logoKey := ""
	if mine, _ := a.Shops.ListMine(ctx, owner.ID); len(mine) == 0 {
		data, err := iviAssets.ReadFile("seedassets/ivi/logo-awu-ivi.jpg")
		if err != nil {
			return nil, err
		}
		logoKey = "shops/" + owner.ID.String() + "/" + uuid.NewString() + ".jpg"
		if err := a.LocalStore.Write(storage.Public, logoKey, data); err != nil {
			return nil, err
		}
	}
	n := hood["Bè"]
	catID := shopCat["Alimentation"]
	in := shops.Input{
		Name: "IVI — Eau minérale naturelle", Phone: "+22892042828",
		Description: "Boutique officielle de l'eau minérale naturelle IVI et AWU IVI. Le choix naturel pour une vie meilleure.",
		AddressText: "Lomé — 03 BP 31020", NeighborhoodID: &n.ID, Location: geo.Point{Lat: 6.1371, Lng: 1.2300},
		CategoryID: &catID,
	}
	if logoKey != "" {
		in.LogoKey = &logoKey
	}
	shopID, err := a.demoShop(ctx, adminID, owner.ID, in)
	if err != nil {
		return nil, err
	}
	out.Shops++
	existing, err := a.Catalog.AdminList(ctx, &shopID, "", 100, 0)
	if err != nil {
		return nil, err
	}
	ids := map[string]uuid.UUID{}
	for _, e := range existing {
		ids[e.Name] = e.ID
	}
	stock := int32(250)
	active := true
	for _, p := range iviProducts {
		id, ok := ids[p.name]
		if !ok {
			keys := []string{}
			for _, f := range p.images {
				data, err := iviAssets.ReadFile("seedassets/ivi/" + f)
				if err != nil {
					return nil, err
				}
				key := "products/" + adminID.String() + "/" + uuid.NewString() + ".jpg"
				if err := a.LocalStore.Write(storage.Public, key, data); err != nil {
					return nil, err
				}
				keys = append(keys, key)
				out.Photos++
			}
			created, err := a.Catalog.AdminCreate(ctx, adminID, shopID, catalog.ProductInput{
				CategoryID: cats["Eaux minérales"], Name: p.name, Description: p.description, PriceXOF: p.price,
				ParcelSize: catalog.ParcelMedium, StockMode: catalog.StockTracked, StockQuantity: &stock,
				IsActive: &active, ImageKeys: keys,
			})
			if err != nil {
				return nil, fmt.Errorf("produit %s : %w", p.name, err)
			}
			id = created.ID
			ids[p.name] = id
			out.Products++
		} else if cur, err := a.Catalog.AdminGet(ctx, id); err == nil && (!cur.IsActive || cur.PriceXOF == 0) {
			// Brouillon d'un seed précédent : prix de démonstration, mise en vente, stock.
			if _, err := a.Catalog.AdminUpdate(ctx, adminID, id, catalog.ProductInput{
				CategoryID: cur.CategoryID, Name: cur.Name, Description: p.description, PriceXOF: p.price,
				ParcelSize: cur.ParcelSize, IsActive: &active, ImageKeys: imageKeysOf(cur),
			}); err != nil {
				return nil, fmt.Errorf("mise en vente %s : %w", p.name, err)
			}
			if _, err := a.Catalog.AdminSetStock(ctx, adminID, id, stock, "Jeu de démonstration"); err != nil {
				return nil, err
			}
		}
		rank := p.rank
		in := catalog.MarketingInput{Badges: p.badges, FeaturedRank: &rank, Features: iviFeatures, PromoPriceXOF: p.promo}
		if p.promo != nil {
			end := time.Now().AddDate(0, 1, 0)
			in.PromoEndsAt = &end
		}
		if _, err := a.Catalog.SetMarketing(ctx, adminID, id, in); err != nil {
			return nil, fmt.Errorf("mise en avant %s : %w", p.name, err)
		}
	}
	return ids, nil
}

// seedPromoVisuals publie les visuels IVI (bannières, fenêtre, interstitiel, bienvenue, mois).
func (a *App) seedPromoVisuals(ctx context.Context, adminID uuid.UUID, products map[string]uuid.UUID, out *DemoSummary) error {
	existing, err := a.Promo.ListVisuals(ctx)
	if err != nil {
		return err
	}
	now := time.Now().In(delivery.Lome)
	monthStart := time.Date(now.Year(), now.Month(), 1, 0, 0, 0, 0, delivery.Lome)
	monthEnd := monthStart.AddDate(0, 1, 0)
	p := func(name string) *uuid.UUID {
		if id, ok := products[name]; ok {
			return &id
		}
		return nil
	}
	all := []string{"home_hero", "home_feed", "catalog_feed"}
	visuals := []struct {
		file string
		in   promo.VisualInput
	}{
		{"banniere-3.jpg", promo.VisualInput{Kind: "banner", Title: "La gamme IVI", Subtitle: "Eau minérale naturelle au goût agréable",
			Body: "Sachet 500 ml, paquet de 30, bouteilles 0,33 L, 0,5 L et 1,5 L, bonbonne.", CTALabel: "Commander",
			ProductID: p("Paquet IVI 30 sachets × 500 ml"), Placements: all, Priority: 90, Weight: 5, ExternalURL: IVIOfficialURL}},
		{"banniere-1.jpg", promo.VisualInput{Kind: "banner", Title: "AWU IVI 1,5 L à 400 F seulement", Subtitle: "Autorisée par le ministère de la Santé",
			CTALabel: "Commander", ProductID: p("AWU IVI 1,5 L"), Placements: all, Priority: 95, Weight: 6, ExternalURL: IVIOfficialURL}},
		{"banniere-2.jpg", promo.VisualInput{Kind: "monthly", Title: "Le visuel du mois : AWU IVI", Subtitle: "Toute la gamme, de 0,33 L à la bonbonne",
			CTALabel: "Commander", ProductID: p("AWU IVI 0,5 L"), Placements: []string{"home_hero", "home_feed", "catalog_feed", "modal"},
			Priority: 80, Weight: 4, StartsAt: &monthStart, EndsAt: &monthEnd, ExternalURL: IVIOfficialURL}},
		{"banniere-4.jpg", promo.VisualInput{Kind: "welcome", Title: "Le choix naturel pour une vie meilleure", Subtitle: "Bienvenue sur ivia avec IVI",
			Body: "Hydratez-vous, vivez mieux : l'eau minérale naturelle IVI livrée chez vous.", CTALabel: "Commander maintenant",
			ProductID: p("AWU IVI 1,5 L"), ExternalURL: IVIOfficialURL, Placements: []string{"splash", "home_hero", "interstitial"}, Priority: 100, Weight: 3}},
		{"affiche-awu-portrait.jpg", promo.VisualInput{Kind: "modal", Title: "Hydratez-vous, vivez mieux !", Subtitle: "AWU IVI 1,5 L — 400 F au lieu de 500 F",
			Body: "Faites-vous livrer l'eau AWU IVI à la maison ou au bureau, en quelques clics.", CTALabel: "Commander maintenant",
			ProductID: p("AWU IVI 1,5 L"), ExternalURL: IVIOfficialURL, Placements: []string{"modal"}, Priority: 85, Weight: 5}},
		{"affiche-gamme-portrait.jpg", promo.VisualInput{Kind: "interstitial", Title: "IVI, toute la gamme livrée chez vous",
			Subtitle: "Paquet de 30 sachets à 650 F", Body: "Sachets, bouteilles et bonbonnes : faites le plein d'eau minérale naturelle.",
			CTALabel: "Commander maintenant", ProductID: p("Paquet IVI 30 sachets × 500 ml"),
			ExternalURL: IVIOfficialURL, Placements: []string{"interstitial", "modal"}, Priority: 75, Weight: 4}},
		{"ivi-bonbonne-2.jpg", promo.VisualInput{Kind: "poster", Title: "La bonbonne IVI pour la maison et le bureau",
			Subtitle: "2 500 F au lieu de 3 000 F", CTALabel: "Commander", ProductID: p("Bonbonne IVI"),
			ExternalURL: IVIOfficialURL, Placements: []string{"home_feed", "catalog_feed", "modal"}, Priority: 70, Weight: 3}},
	}
	// Ancien visuel du jeu de démonstration, remplacé.
	if i := slices.IndexFunc(existing, func(e promo.Visual) bool { return e.Title == "AWU IVI, l'eau minérale naturelle" }); i >= 0 {
		_ = a.Promo.DeleteVisual(ctx, adminID, existing[i].ID)
	}
	for _, v := range visuals {
		if i := slices.IndexFunc(existing, func(e promo.Visual) bool { return e.Title == v.in.Title }); i >= 0 {
			// Déjà publié : emplacements et textes mis à jour, image gardée.
			v.in.ImageKey = existing[i].ImageKey
			if _, err := a.Promo.UpdateVisual(ctx, adminID, existing[i].ID, v.in); err != nil {
				return fmt.Errorf("%s : %w", v.in.Title, err)
			}
			continue
		}
		data, err := iviAssets.ReadFile("seedassets/ivi/" + v.file)
		if err != nil {
			return err
		}
		key := "promo/" + adminID.String() + "/" + uuid.NewString() + ".jpg"
		if err := a.LocalStore.Write(storage.Public, key, data); err != nil {
			return err
		}
		v.in.ImageKey = key
		if _, err := a.Promo.CreateVisual(ctx, adminID, v.in); err != nil {
			return fmt.Errorf("%s : %w", v.in.Title, err)
		}
		out.Visuals++
	}
	// Réglages de diffusion de la démonstration (modifiables dans Publicité > Réglages).
	_, err = a.Promo.UpdateSettings(ctx, adminID, promo.Settings{
		Enabled: true, BannersEnabled: true, ModalEnabled: true, InterstitialEnabled: true,
		// Diffusion discrète : une fenêtre au plus toutes les 5 minutes, 2 par session.
		FirstDelaySeconds: 90, MinIntervalSeconds: 300, MaxPerSession: 2, FeedEvery: 8,
		Rotation: "weighted", OfficialURL: IVIOfficialURL,
	})
	return err
}

// demoPhoto retourne une photo du catalogue, téléchargée une fois puis lue depuis le cache local.
func demoPhoto(ctx context.Context, url string) ([]byte, error) {
	dir, err := os.UserCacheDir()
	if err != nil {
		dir = os.TempDir()
	}
	dir = filepath.Join(dir, "ivia-seed-photos")
	sum := sha1.Sum([]byte(url))
	path := filepath.Join(dir, hex.EncodeToString(sum[:])+".jpg")
	if data, err := os.ReadFile(path); err == nil {
		return data, nil
	}
	ctx, cancel := context.WithTimeout(ctx, 30*time.Second)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return nil, err
	}
	// Politique de Wikimedia : un agent identifiable.
	req.Header.Set("User-Agent", "ivia-demo-seed/1.0 (developpement local)")
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer res.Body.Close()
	if res.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("HTTP %d", res.StatusCode)
	}
	data, err := io.ReadAll(io.LimitReader(res.Body, 5<<20))
	if err != nil {
		return nil, err
	}
	if err := os.MkdirAll(dir, 0o755); err == nil {
		_ = os.WriteFile(path, data, 0o644)
	}
	return data, nil
}
