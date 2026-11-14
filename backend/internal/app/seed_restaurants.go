package app

import "fmt"

// Restaurants de démonstration (local uniquement) : boutiques de la catégorie « Restauration »,
// plats locaux photographiés (Wikimedia Commons, licences libres, crédits ci-dessous et dans
// seedassets/credits_properties_food.json).

type demoDish struct {
	name, desc string
	price      int64
	file       string
	author     string
	license    string
	source     string
}

var (
	dishFufu     = demoDish{"Foufou sauce arachide", "Pâte d'igname pilée, sauce arachide et viande de bœuf.", 2500, "67930bbe6c559d90.jpg", "SebEsteban", "CC BY-SA 4.0", "https://commons.wikimedia.org/wiki/File:Fufu_(Lom%C3%A9,_Togo).jpg"}
	dishAttieke  = demoDish{"Attiéké poisson fumé", "Semoule de manioc, poisson fumé, piment et oignons.", 2000, "f4f093c2ab10cfc8.jpg", "Samigolden07", "CC0", "https://commons.wikimedia.org/wiki/File:Atti%C3%A9k%C3%A9_poisson_fum%C3%A9.jpg"}
	dishTilapia  = demoDish{"Tilapia braisé", "Tilapia entier grillé au feu de bois, akpan ou alloco.", 4500, "4d7c575d1c4282ae.jpg", "Amuzujoe", "CC BY-SA 4.0", "https://commons.wikimedia.org/wiki/File:Grilled_Tilapia_001.jpg"}
	dishJollof   = demoDish{"Riz jollof aux légumes", "Riz cuisiné à la tomate, légumes et poulet.", 2500, "43eda7f934cc7198.jpg", "Segun Famisa", "CC BY-SA 4.0", "https://commons.wikimedia.org/wiki/File:Jollof_rice_with_vegetable.jpg"}
	dishKedjenou = demoDish{"Kédjénou de poulet", "Poulet mijoté à l'étouffée, légumes et épices.", 3500, "469568008ab0ed61.jpg", "African Hope", "CC BY-SA 4.0", "https://commons.wikimedia.org/wiki/File:Kedjenou_poulet_sauce_claire.JPG"}
	dishIgname   = demoDish{"Foufou d'igname sauce gombo", "Foufou maison, sauce gombo et poisson.", 2500, "05a51781ff57ed41.jpg", "Ubkoumbogny", "CC BY-SA 4.0", "https://commons.wikimedia.org/wiki/File:P%C3%A2te_d%27ignames_(Fufu)_18.jpg"}
)

// Photos des lieux (salle, terrasse, façade) : la photo de la boutique ; les plats se voient en
// entrant dans le restaurant. Wikimedia Commons, crédits dans credits_properties_food.json.
var demoRestaurantVenues = []string{"venue-1.jpg", "venue-2.jpg", "venue-3.jpg", "venue-4.jpg", "venue-5.jpg", "venue-6.jpg"}

var demoRestaurantDefs = []struct {
	name, desc, hood, addr string
	lat, lng               float64
	dishes                 []demoDish
}{
	{"Le Bistro du Port", "Grillades et poissons du jour, face à la mer.", "Kodjoviakopé", "Boulevard de la République, Kodjoviakopé", 6.1262, 1.1995, []demoDish{dishTilapia, dishAttieke, dishJollof}},
	{"Chez Tantie Akossiwa", "Cuisine togolaise familiale, foufou pilé minute.", "Tokoin", "Tokoin Doumassessé", 6.1485, 1.2175, []demoDish{dishFufu, dishIgname, dishKedjenou}},
	{"Maquis La Terrasse", "Kédjénou, attiéké et grillades sous la paillote.", "Bè", "Bè Kpota, rue 120", 6.1415, 1.2390, []demoDish{dishKedjenou, dishAttieke, dishTilapia}},
	{"Saveurs d'Agoè", "Plats du jour à petits prix, livrés chauds.", "Agoè", "Agoè Assiyéyé", 6.2338, 1.2048, []demoDish{dishJollof, dishFufu, dishIgname}},
	{"Grill Adidogomé", "Poisson braisé et poulet bicyclette.", "Adidogomé", "Adidogomé Sagbado", 6.1752, 1.1598, []demoDish{dishTilapia, dishKedjenou, dishJollof}},
	{"Lomé Food Corner", "Street-food togolaise revisitée.", "Avédji", "Avédji Limousine", 6.1848, 1.1845, []demoDish{dishAttieke, dishFufu, dishTilapia}},
}

// withDemoRestaurants ajoute les restaurants au catalogue de démonstration.
func withDemoRestaurants(shops []demoShop) []demoShop {
	for i, r := range demoRestaurantDefs {
		var d demoShop
		d.Key = fmt.Sprintf("resto-%d", i+1)
		d.Name, d.Description, d.Category = r.name, r.desc, "Restauration"
		d.Neighborhood, d.Address, d.Lat, d.Lng = r.hood, r.addr, r.lat, r.lng
		d.Owner.Email = fmt.Sprintf("restaurant%d@ivia.local", i+1)
		d.Owner.Phone = fmt.Sprintf("+2289171%04d", 2000+i)
		d.Owner.First, d.Owner.Last = "Chef", r.name
		if i < len(demoRestaurantVenues) {
			d.Venue = demoRestaurantVenues[i]
		}
		for j, dish := range r.dishes {
			stock := int32(30)
			d.Products = append(d.Products, demoProduct{
				Name: dish.name, Description: dish.desc, Category: "Plats cuisinés",
				PriceXOF: dish.price + int64((i+j)%3)*250, ParcelSize: "small", Stock: &stock,
				Images: []demoImage{{File: dish.file, Source: dish.source, Author: dish.author, License: dish.license}},
			})
		}
		shops = append(shops, d)
	}
	return shops
}
