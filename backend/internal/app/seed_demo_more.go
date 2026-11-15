package app

import (
	"fmt"
	"strings"
)

// Boutiques supplémentaires de démonstration (local uniquement) : plusieurs boutiques par
// catégorie, réparties dans les quartiers de Lomé, avec les vraies photos du catalogue de base
// (un même article peut se vendre dans plusieurs boutiques, à un prix un peu différent).
var demoBranches = []struct {
	name, base, hood, addr string
	lat, lng               float64
}{
	{"Superette Nyékonakpoè", "Le Comptoir Gourmand", "Nyékonakpoè", "Rue du Commerce, Nyékonakpoè", 6.1305, 1.2060},
	{"Marché Frais d'Agoè", "Le Comptoir Gourmand", "Agoè", "Carrefour Agoè-Assiyéyé", 6.2340, 1.2040},
	{"Épicerie Mama Adjo", "Le Comptoir Gourmand", "Adidogomé", "Marché d'Adidogomé", 6.1745, 1.1610},
	{"Mini-market Avédji", "Le Comptoir Gourmand", "Avédji", "Avédji, face à la station", 6.1855, 1.1860},
	{"Boulangerie Le Fournil", "Délices de Lomé", "Tokoin", "Boulevard du 13 Janvier, Tokoin", 6.1470, 1.2160},
	{"Pâtisserie La Gourmandise", "Délices de Lomé", "Djidjolé", "Djidjolé, rue 105", 6.1605, 1.1955},
	{"Douceurs d'Agoè", "Délices de Lomé", "Agoè", "Agoè Zongo", 6.2360, 1.2070},
	{"Jus Tropical Kégué", "Fresh Bar Lomé", "Kégué", "Kégué, près du stade", 6.1705, 1.2610},
	{"Smoothie Corner Adidogomé", "Fresh Bar Lomé", "Adidogomé", "Adidogomé Sagbado", 6.1760, 1.1590},
	{"Boutique Élégance Tokoin", "Atelier Wax Couture", "Tokoin", "Tokoin Hôpital", 6.1490, 1.2140},
	{"Wax & Co Agoè", "Atelier Wax Couture", "Agoè", "Agoè Cacaveli", 6.2330, 1.2030},
	{"Kente Style Avédji", "Atelier Wax Couture", "Avédji", "Avédji Limousine", 6.1840, 1.1840},
	{"Maroquinerie du Golfe", "Concept store Afi", "Kodjoviakopé", "Kodjoviakopé, bord de mer", 6.1265, 1.1990},
	{"Chaussures Djidjolé", "Sneakers Club", "Djidjolé", "Djidjolé, rue des écoles", 6.1595, 1.1945},
	{"Street Shoes Agoè", "Sneakers Club", "Agoè", "Agoè Nyivé", 6.2350, 1.2060},
	{"Beauté Divine Hédzranawoé", "Éclat Beauté", "Hédzranawoé", "Hédzranawoé, rue 210", 6.1635, 1.2410},
	{"Cosmétique Adidogomé", "Éclat Beauté", "Adidogomé", "Adidogomé Soviépé", 6.1740, 1.1620},
	{"Phone Center Agoè", "Tech Avenue", "Agoè", "Agoè Démakpoè", 6.2345, 1.2045},
	{"Digital Store Kodjoviakopé", "Tech Avenue", "Kodjoviakopé", "Kodjoviakopé, avenue de la Libération", 6.1255, 1.1975},
	{"Déco Avédji", "Maison Déco Lomé", "Avédji", "Avédji, rue 32", 6.1850, 1.1855},
	{"Maison & Cuisine Baguida", "Maison Déco Lomé", "Baguida", "Baguida plage", 6.1605, 1.3205},
}

// withDemoBranches ajoute les boutiques supplémentaires au catalogue de base.
func withDemoBranches(base []demoShop) []demoShop {
	byName := map[string]demoShop{}
	for _, s := range base {
		byName[s.Name] = s
	}
	out := append([]demoShop{}, base...)
	for i, b := range demoBranches {
		src, ok := byName[b.base]
		if !ok {
			continue
		}
		d := src
		d.Key = fmt.Sprintf("%s-%d", src.Key, i+1)
		d.Name, d.Neighborhood, d.Address, d.Lat, d.Lng = b.name, b.hood, b.addr, b.lat, b.lng
		slug := strings.NewReplacer(" ", ".", "'", "", "&", "et").Replace(strings.ToLower(asciiFold(b.name)))
		d.Owner.Email = slug + "@ivia.local"
		d.Owner.Phone = fmt.Sprintf("+2289170%04d", 1000+i)
		d.Owner.First = strings.Fields(b.name)[0]
		d.Owner.Last = "Démo"
		d.Products = make([]demoProduct, len(src.Products))
		for j, p := range src.Products {
			// Prix légèrement différents d'une boutique à l'autre, arrondis à 50 F.
			pct := int64(92 + (i*7+j*3)%17)
			p.PriceXOF = (p.PriceXOF*pct/100 + 25) / 50 * 50
			p.Badges = nil
			d.Products[j] = p
		}
		out = append(out, d)
	}
	return out
}

func asciiFold(s string) string {
	return strings.NewReplacer("é", "e", "è", "e", "ê", "e", "à", "a", "ô", "o", "ç", "c", "É", "E", "—", "-").Replace(s)
}
