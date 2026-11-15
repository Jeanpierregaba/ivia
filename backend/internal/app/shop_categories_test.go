package app_test

import (
	"context"
	"net/http"
	"testing"
)

func TestShopCategories(t *testing.T) {
	requireApp(t)
	r := mustStatus(t, call(t, "", "GET", "/v1/shop-categories", nil), http.StatusOK)
	items, _ := r.Body["items"].([]any)
	if len(items) < 7 {
		t.Fatalf("catégories de boutique : %d", len(items))
	}
	first, _ := items[0].(map[string]any)
	if first["name"] != "Alimentation" {
		t.Fatalf("première catégorie : %v", first["name"])
	}
}

func TestShopCategoryRequiredAtCreation(t *testing.T) {
	requireApp(t)
	tok := login(t, uniqueEmail("shopcat"))
	lat, lng := zone()
	body := map[string]any{
		"name": "Chez Afi", "phone": uniquePhone(), "address_text": "Rue 248, Tokoin",
		"location": map[string]float64{"lat": lat, "lng": lng},
	}

	if r := call(t, tok, "POST", "/v1/shops", body); r.code() != "validation_failed" || !hasField(r, "category_id") {
		t.Fatalf("sans catégorie : code %q (statut %d)", r.code(), r.Status)
	}

	body["category_id"] = "7d5c1d38-3c1b-4b8f-9a77-1f2e3d4c5b6a"
	if r := call(t, tok, "POST", "/v1/shops", body); r.code() != "validation_failed" || !hasField(r, "category_id") {
		t.Fatalf("catégorie inconnue : code %q (statut %d)", r.code(), r.Status)
	}

	body["category_id"] = shopCategory(t)
	shop := mustStatus(t, call(t, tok, "POST", "/v1/shops", body), http.StatusCreated)
	if shop.str("category_name") != "Alimentation" || shop.str("category_id") != body["category_id"] {
		t.Fatalf("catégorie renvoyée : %q / %q", shop.str("category_id"), shop.str("category_name"))
	}

	// Modification sans catégorie : elle est conservée.
	upd := mustStatus(t, call(t, tok, "PATCH", "/v1/seller/shops/"+shop.str("id"), map[string]any{
		"name": "Chez Afi et fils", "phone": uniquePhone(), "address_text": "Rue 248, Tokoin",
		"location": map[string]float64{"lat": lat, "lng": lng},
	}), http.StatusOK)
	if upd.str("category_name") != "Alimentation" {
		t.Fatalf("catégorie perdue à la modification : %q", upd.str("category_name"))
	}
}

// hasField indique si une erreur de validation porte sur ce champ.
func hasField(r resp, field string) bool {
	errBody, _ := r.Body["error"].(map[string]any)
	fields, _ := errBody["fields"].(map[string]any)
	_, ok := fields[field]
	return ok
}

func TestInactiveShopCategory(t *testing.T) {
	a := requireApp(t)
	// Catégorie désactivée (le back-office le fera plus tard) : écrite directement en base.
	var id string
	err := a.DB.Pool.QueryRow(context.Background(),
		`INSERT INTO shop_categories (name, position, is_active) VALUES ($1, 99, false) RETURNING id`,
		"Inactive "+uniqueEmail("cat")).Scan(&id)
	if err != nil {
		t.Fatalf("catégorie inactive : %v", err)
	}

	r := mustStatus(t, call(t, "", "GET", "/v1/shop-categories", nil), http.StatusOK)
	for _, item := range r.Body["items"].([]any) {
		if item.(map[string]any)["id"] == id {
			t.Fatal("catégorie inactive listée")
		}
	}

	tok := login(t, uniqueEmail("inactivecat"))
	lat, lng := zone()
	created := call(t, tok, "POST", "/v1/shops", map[string]any{
		"name": "Chez Afi", "phone": uniquePhone(), "address_text": "Rue 248",
		"location": map[string]float64{"lat": lat, "lng": lng}, "category_id": id,
	})
	if created.code() != "validation_failed" || !hasField(created, "category_id") {
		t.Fatalf("catégorie inactive acceptée : code %q (statut %d)", created.code(), created.Status)
	}
}
