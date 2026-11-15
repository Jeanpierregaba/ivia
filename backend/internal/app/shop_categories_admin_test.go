package app_test

import (
	"bytes"
	"fmt"
	"net/http"
	"testing"
)

// Gestion des catégories de boutique par l'admin : création, modification, désactivation, journal.
func TestAdminManagesShopCategories(t *testing.T) {
	requireApp(t)
	name := fmt.Sprintf("Quincaillerie %d", seq.Add(1))
	body := map[string]any{"name": name, "position": 500}

	if r := call(t, login(t, uniqueEmail("seller")), "POST", "/v1/admin/shop-categories", body); r.Status != http.StatusForbidden {
		t.Fatalf("route réservée aux admins : %d", r.Status)
	}
	c := mustStatus(t, call(t, admin(t), "POST", "/v1/admin/shop-categories", body), http.StatusCreated)
	id := c.str("id")
	if r := call(t, admin(t), "POST", "/v1/admin/shop-categories", body); r.code() != "shop_category_exists" {
		t.Fatalf("nom en double : %s", r.Raw)
	}
	if r := call(t, admin(t), "POST", "/v1/admin/shop-categories", map[string]any{"name": ""}); r.code() != "validation_failed" {
		t.Fatalf("nom obligatoire : %s", r.Raw)
	}
	if !bytes.Contains(call(t, "", "GET", "/v1/shop-categories", nil).Raw, []byte(id)) {
		t.Fatal("une catégorie active est proposée aux marchands")
	}

	// Désactivée : retirée des choix, refusée à la création d'une boutique, gardée dans la liste admin.
	mustStatus(t, call(t, admin(t), "PATCH", "/v1/admin/shop-categories/"+id, map[string]any{"name": name, "position": 500, "is_active": false}), http.StatusOK)
	if bytes.Contains(call(t, "", "GET", "/v1/shop-categories", nil).Raw, []byte(id)) {
		t.Fatal("une catégorie désactivée n'est plus proposée")
	}
	if !bytes.Contains(mustStatus(t, call(t, admin(t), "GET", "/v1/admin/shop-categories", nil), http.StatusOK).Raw, []byte(id)) {
		t.Fatal("l'admin voit aussi les catégories désactivées")
	}
	tok := login(t, uniqueEmail("seller"))
	completeProfile(t, tok, "Afi")
	lat, lng := zone()
	r := call(t, tok, "POST", "/v1/shops", map[string]any{
		"name": "Boutique", "phone": uniquePhone(), "address_text": "Rue", "category_id": id,
		"location": map[string]float64{"lat": lat, "lng": lng},
	})
	if r.code() != "validation_failed" {
		t.Fatalf("catégorie désactivée à la création : %s", r.Raw)
	}
	if r := call(t, admin(t), "PATCH", "/v1/admin/shop-categories/00000000-0000-0000-0000-000000000000", map[string]any{"name": "x"}); r.Status != http.StatusNotFound {
		t.Fatalf("catégorie inconnue : %d", r.Status)
	}
	audit := mustStatus(t, call(t, admin(t), "GET", "/v1/admin/audit-log?target_type=shop_category&target_id="+id, nil), http.StatusOK)
	if !bytes.Contains(audit.Raw, []byte("shop_category.create")) || !bytes.Contains(audit.Raw, []byte("shop_category.update")) {
		t.Fatal("les actions sur les catégories sont journalisées")
	}
}

// La catégorie de boutique apparaît sur la fiche publique et filtre la recherche.
func TestShopCategoryInPublicViewAndSearch(t *testing.T) {
	requireApp(t)
	s := newSeller(t, 5)
	pub := mustStatus(t, call(t, "", "GET", "/v1/shops/"+s.shopID, nil), http.StatusOK)
	catID := pub.str("category_id")
	if catID == "" || pub.str("category_name") == "" {
		t.Fatalf("catégorie absente de la fiche publique : %s", pub.Raw)
	}

	near := "lat=" + ftoa(s.lat) + "&lng=" + ftoa(s.lng) + "&radius_m=2000"
	shops := mustStatus(t, call(t, "", "GET", "/v1/search/shops?"+near+"&shop_category_id="+catID, nil), http.StatusOK)
	if !bytes.Contains(shops.Raw, []byte(s.shopID)) || !bytes.Contains(shops.Raw, []byte(pub.str("category_name"))) {
		t.Fatalf("recherche de boutiques par catégorie : %s", shops.Raw)
	}
	products := mustStatus(t, call(t, "", "GET", "/v1/search/products?"+near+"&shop_category_id="+catID, nil), http.StatusOK)
	if !bytes.Contains(products.Raw, []byte(s.trackedID)) {
		t.Fatalf("recherche de produits par catégorie de boutique : %s", products.Raw)
	}

	other := mustStatus(t, call(t, admin(t), "POST", "/v1/admin/shop-categories", map[string]any{"name": fmt.Sprintf("Vide %d", seq.Add(1)), "position": 600}), http.StatusCreated).str("id")
	for _, path := range []string{"/v1/search/shops?", "/v1/search/products?"} {
		r := mustStatus(t, call(t, "", "GET", path+near+"&shop_category_id="+other, nil), http.StatusOK)
		if len(r.Body["items"].([]any)) != 0 {
			t.Errorf("%s : une autre catégorie ne doit rien renvoyer : %s", path, r.Raw)
		}
	}
}
