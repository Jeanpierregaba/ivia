package app_test

import (
	"net/http"
	"testing"
)

// Tableau de bord du marchand (spec 042) : chiffres tirés des commandes payées.
func TestSellerStats(t *testing.T) {
	requireApp(t)
	s := newSeller(t, 10)
	b := newBuyer(t, s.lat, s.lng)

	empty := mustStatus(t, call(t, s.token, "GET", "/v1/seller/shops/"+s.shopID+"/stats", nil), http.StatusOK)
	if series, _ := empty.Body["series"].([]any); len(series) != 7 {
		t.Fatalf("7 jours attendus : %s", empty.Raw)
	}
	if hours, _ := empty.Body["hours"].([]any); len(hours) != 24 {
		t.Fatalf("24 heures attendues : %s", empty.Raw)
	}

	// Une commande payée : 2 × 5 000 F.
	o := order(t, b, s.trackedID, 2, "pickup")
	pay(t, b, o.str("id"))
	eventually(t, "commande payée", func() bool { return orderStatus(t, b.token, o.str("id")) != "pending_payment" })

	r := mustStatus(t, call(t, s.token, "GET", "/v1/seller/shops/"+s.shopID+"/stats?days=30", nil), http.StatusOK)
	totals := r.Body["totals"].(map[string]any)
	if totals["orders"] != float64(1) || totals["sales_xof"] != float64(10000) || totals["avg_basket_xof"] != float64(10000) {
		t.Fatalf("totaux : %s", r.Raw)
	}
	series := r.Body["series"].([]any)
	if len(series) != 30 || series[29].(map[string]any)["sales_xof"] != float64(10000) {
		t.Fatalf("aujourd'hui en dernier : %s", r.Raw)
	}
	top := r.Body["top_products"].([]any)
	if len(top) != 1 || top[0].(map[string]any)["quantity"] != float64(2) {
		t.Fatalf("meilleur produit : %s", r.Raw)
	}

	// Boutique d'autrui : 404 ; période inconnue : 400.
	other := newSeller(t, 1)
	mustStatus(t, call(t, other.token, "GET", "/v1/seller/shops/"+s.shopID+"/stats", nil), http.StatusNotFound)
	mustStatus(t, call(t, s.token, "GET", "/v1/seller/shops/"+s.shopID+"/stats?days=12", nil), http.StatusBadRequest)
}
