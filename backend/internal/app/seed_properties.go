package app

import (
	"context"
	"embed"
	"fmt"

	"github.com/google/uuid"

	"ivia/backend/internal/platform/storage"
	"ivia/backend/internal/properties"
)

// Photos des biens : Wikimedia Commons (CC BY-SA 4.0 et CC0), crédits dans
// seedassets/credits_properties_food.json.
//
//go:embed seedassets/properties/*.jpg
var propertyPhotos embed.FS

var demoProperties = []struct {
	title, kind, ptype, hood, addr, desc string
	price                                int64
	beds, surface                        int32
	lat, lng                             float64
	photo                                string
}{
	{"Villa 4 chambres avec jardin", "sale", "villa", "Kégué", "Kégué, près du stade", "Villa récente, 4 chambres dont 2 autonomes, salon spacieux, cuisine équipée, jardin et garage 2 voitures.", 85_000_000, 4, 450, 6.1712, 1.2598, "a9e8410584046090.jpg"},
	{"Maison 3 chambres à louer", "rent", "house", "Tokoin", "Tokoin Wuiti", "Maison de plain-pied, 3 chambres, salon, cour carrelée, eau et électricité. Caution 3 mois.", 250_000, 3, 220, 6.1503, 1.2131, "ef9826f7e5564824.jpg"},
	{"Maison familiale sur 2 lots", "sale", "house", "Nyékonakpoè", "Nyékonakpoè, rue des Hôpitaux", "Grande maison familiale, 5 chambres, dépendances, titre foncier.", 60_000_000, 5, 600, 6.1318, 1.2085, "64bf18c01754c595.jpg"},
	{"Maison de ville à Kodjoviakopé", "rent", "house", "Kodjoviakopé", "Kodjoviakopé, à 300 m de la plage", "Maison à étage, 2 chambres, terrasse, quartier calme proche de la mer.", 180_000, 2, 150, 6.1268, 1.1979, "fe176ddb3785749a.jpg"},
	{"Villa Providence meublée", "rent", "villa", "Baguida", "Baguida, route d'Aného", "Villa meublée haut standing, 3 chambres climatisées, piscine, gardiennage.", 650_000, 3, 380, 6.1598, 1.3185, "30557972b428b8e7.jpg"},
	{"Villa contemporaine 5 chambres", "sale", "villa", "Agoè", "Agoè Cacaveli", "Villa contemporaine, 5 chambres, bureau, grand salon double hauteur, groupe électrogène.", 120_000_000, 5, 520, 6.2342, 1.2038, "224e582961b8123f.jpg"},
	{"Duplex moderne à Adidogomé", "sale", "house", "Adidogomé", "Adidogomé Soviépé", "Duplex neuf, 4 chambres, toit-terrasse, quartier en plein développement.", 72_000_000, 4, 300, 6.1748, 1.1612, "971a9fedcbd12adc.jpg"},
	{"Appartement 2 pièces à Avédji", "rent", "apartment", "Avédji", "Avédji Limousine", "Appartement au 1er étage, 1 chambre, salon, cuisine, parking dans la cour.", 95_000, 1, 70, 6.1852, 1.1848, "701d960b77a3f58a.jpg"},
}

// seedDemoProperties publie les annonces de démonstration (relançable sans doublon).
func (a *App) seedDemoProperties(ctx context.Context, svc *properties.Service) (int, error) {
	n := 0
	for _, d := range demoProperties {
		data, err := propertyPhotos.ReadFile("seedassets/properties/" + d.photo)
		if err != nil {
			return n, err
		}
		key := "properties/" + uuid.NewString() + ".jpg"
		if err := a.LocalStore.Write(storage.Public, key, data); err != nil {
			return n, fmt.Errorf("photo du bien : %w", err)
		}
		if _, err := svc.Seed(ctx, properties.Seed{
			Title: d.title, Kind: d.kind, PropertyType: d.ptype, PriceXof: d.price, Bedrooms: d.beds, SurfaceM2: d.surface,
			Neighborhood: d.hood, AddressText: d.addr, Lat: d.lat, Lng: d.lng, Description: d.desc,
			PhotoKeys: []string{key}, ContactName: "Agence ivia Immo", ContactPhone: "+22899309945",
		}); err != nil {
			return n, err
		}
		n++
	}
	return n, nil
}
