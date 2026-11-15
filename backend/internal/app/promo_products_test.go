package app_test

import (
	"net/http"
	"testing"
)

// Codes promo limités à certains produits (spec 041) : la réduction ne porte que sur leurs lignes.
func TestPromoCodeLimitedToProducts(t *testing.T) {
	requireApp(t)
	s := newSeller(t, 10)
	b := newBuyer(t, s.lat, s.lng)

	// Un seul produit visé : 20 % de ses lignes seulement.
	one := mustStatus(t, call(t, s.token, "POST", "/v1/seller/shops/"+s.shopID+"/promo-codes", map[string]any{
		"code": "UNSEUL" + uniquePhone()[8:], "kind": "percent", "value": 20, "product_ids": []string{s.trackedID},
	}), http.StatusCreated)
	if one.str("scope") != "products" {
		t.Fatalf("portée : %s", one.Raw)
	}
	if ps, _ := one.Body["products"].([]any); len(ps) != 1 || ps[0].(map[string]any)["name"] != "Produit suivi" {
		t.Fatalf("produits du code : %s", one.Raw)
	}

	// Panier : 2 × produit suivi (5 000) + 1 × produit libre (5 000).
	mustStatus(t, call(t, b.token, "PUT", "/v1/cart/items", map[string]any{"product_id": s.trackedID, "quantity": 2, "replace_cart": true}), http.StatusOK)
	mustStatus(t, call(t, b.token, "PUT", "/v1/cart/items", map[string]any{"product_id": s.untrackedID, "quantity": 1}), http.StatusOK)
	q := mustStatus(t, call(t, b.token, "POST", "/v1/orders/quote", map[string]any{
		"fulfillment": "pickup", "promo_code": one.str("code"),
	}), http.StatusOK)
	if d, _ := q.Body["discount_xof"].(float64); d != 2000 {
		t.Fatalf("20 %% de 10 000 F (produit visé seulement) : %v, %s", d, q.Raw)
	}

	// Code visant un produit absent du panier : refusé.
	other := mustStatus(t, call(t, s.token, "POST", "/v1/seller/shops/"+s.shopID+"/promo-codes", map[string]any{
		"code": "GROS" + uniquePhone()[8:], "kind": "fixed", "value": 1000, "product_ids": []string{s.largeID},
	}), http.StatusCreated)
	r := call(t, b.token, "POST", "/v1/orders/quote", map[string]any{"fulfillment": "pickup", "promo_code": other.str("code")})
	if r.Status != http.StatusConflict || r.code() != "promo_not_applicable" {
		t.Fatalf("produit visé absent du panier : %d %s", r.Status, r.Raw)
	}

	// Toute la boutique (sans product_ids) : comme avant.
	all := mustStatus(t, call(t, s.token, "POST", "/v1/seller/shops/"+s.shopID+"/promo-codes", map[string]any{
		"code": "TOUT" + uniquePhone()[8:], "kind": "percent", "value": 10,
	}), http.StatusCreated)
	if all.str("scope") != "shop" {
		t.Fatalf("portée boutique : %s", all.Raw)
	}
	q = mustStatus(t, call(t, b.token, "POST", "/v1/orders/quote", map[string]any{
		"fulfillment": "pickup", "promo_code": all.str("code"),
	}), http.StatusOK)
	if d, _ := q.Body["discount_xof"].(float64); d != 1500 {
		t.Fatalf("10 %% de 15 000 F : %v", d)
	}

	// Produit d'une autre boutique : refusé à la création.
	stranger := newSeller(t, 1)
	r = call(t, s.token, "POST", "/v1/seller/shops/"+s.shopID+"/promo-codes", map[string]any{
		"code": "AUTRUI" + uniquePhone()[8:], "kind": "percent", "value": 10, "product_ids": []string{stranger.trackedID},
	})
	if r.Status != http.StatusBadRequest {
		t.Fatalf("produit d'autrui : %d %s", r.Status, r.Raw)
	}
}
