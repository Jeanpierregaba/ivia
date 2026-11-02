package app_test

import (
	"net/http"
	"testing"
)

// Les raisons d'une ligne de panier bloquée (`issue`) sont affichées telles quelles par l'app
// acheteur, qui lit aussi le stock restant dans « Plus que N en stock. » pour proposer
// « Ajuster à N » (mobile/packages/api_client, CartItem.stockLeft). Changer ces textes casse
// l'app : ce test les fige.
func TestCartIssueTexts(t *testing.T) {
	requireApp(t)
	s := newSeller(t, 5)
	b := newBuyer(t, s.lat, s.lng)
	mustStatus(t, call(t, b.token, "PUT", "/v1/cart/items", map[string]any{"product_id": s.trackedID, "quantity": 3}), http.StatusOK)
	mustStatus(t, call(t, b.token, "PUT", "/v1/cart/items", map[string]any{"product_id": s.untrackedID, "quantity": 1}), http.StatusOK)

	issues := func() []string {
		t.Helper()
		r := mustStatus(t, call(t, b.token, "GET", "/v1/cart", nil), http.StatusOK)
		var out []string
		for _, it := range r.Body["items"].([]any) {
			out = append(out, it.(map[string]any)["issue"].(string))
		}
		return out
	}

	exec(t, "UPDATE stock_levels SET quantity = 2 WHERE product_id = $1", s.trackedID)
	if got := issues(); got[0] != "Plus que 2 en stock." || got[1] != "" {
		t.Fatalf("raisons après baisse du stock : %q", got)
	}
	exec(t, "UPDATE products SET is_active = false, withdrawn_at = now() WHERE id = $1", s.untrackedID)
	if got := issues(); got[1] != "Ce produit n'est plus disponible." {
		t.Fatalf("raison d'un produit retiré : %q", got)
	}
}
