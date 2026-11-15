package app_test

import (
	"net/http"
	"testing"
)

// Le marchand déplace sa boutique (lieu cherché ou position du téléphone) ; le reste ne change pas.
func TestShopLocationUpdate(t *testing.T) {
	requireApp(t)
	s := newSeller(t, 1)
	before := mustStatus(t, call(t, s.token, "GET", "/v1/seller/shops/"+s.shopID, nil), http.StatusOK)

	r := mustStatus(t, call(t, s.token, "PUT", "/v1/seller/shops/"+s.shopID+"/location", map[string]any{
		"location": map[string]float64{"lat": s.lat + 0.002, "lng": s.lng - 0.001}, "address_text": "Grand Marché, porte 3",
	}), http.StatusOK)
	loc := r.Body["location"].(map[string]any)
	if d := loc["lat"].(float64) - (s.lat + 0.002); d > 1e-6 || d < -1e-6 {
		t.Fatalf("position : %s", r.Raw)
	}
	if r.str("address_text") != "Grand Marché, porte 3" || r.str("name") != before.str("name") || r.str("phone") != before.str("phone") {
		t.Fatalf("seule la position et l'adresse changent : %s", r.Raw)
	}
	// Sans adresse écrite : elle reste.
	r = mustStatus(t, call(t, s.token, "PUT", "/v1/seller/shops/"+s.shopID+"/location", map[string]any{
		"location": map[string]float64{"lat": s.lat, "lng": s.lng},
	}), http.StatusOK)
	if r.str("address_text") != "Grand Marché, porte 3" {
		t.Fatalf("adresse gardée : %s", r.Raw)
	}
	// Boutique d'autrui : 404 ; coordonnées hors limites : 400.
	other := newSeller(t, 1)
	mustStatus(t, call(t, other.token, "PUT", "/v1/seller/shops/"+s.shopID+"/location", map[string]any{
		"location": map[string]float64{"lat": s.lat, "lng": s.lng},
	}), http.StatusNotFound)
	mustStatus(t, call(t, s.token, "PUT", "/v1/seller/shops/"+s.shopID+"/location", map[string]any{
		"location": map[string]float64{"lat": 120, "lng": 1},
	}), http.StatusBadRequest)
}
