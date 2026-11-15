package app_test

import (
	"net/http"
	"testing"
)

// Tableau de bord de la pharmacie (spec 042) : alertes reçues et répondues, réelles.
func TestPharmacyStats(t *testing.T) {
	requireApp(t)
	// Quartier à l'écart des autres tests.
	lat, lng := 6.431, 1.162
	tok, _ := newPharmacy(t, "Pharmacie Statistiques", lat+0.003, lng)
	b := newBuyer(t, lat, lng)

	empty := mustStatus(t, call(t, tok, "GET", "/v1/pharmacy/stats", nil), http.StatusOK)
	if series, _ := empty.Body["series"].([]any); len(series) != 7 {
		t.Fatalf("7 jours : %s", empty.Raw)
	}

	alert := mustStatus(t, call(t, b.token, "POST", "/v1/medicine-alerts", map[string]any{
		"items":            []map[string]any{{"name": "Amoxicilline 500 mg", "form": "Gélules", "quantity": 1}},
		"generic_accepted": true, "radius_m": 5000, "location": map[string]float64{"lat": lat, "lng": lng},
	}), http.StatusCreated)
	itemID := list(alert.Body["items"])[0]["id"]
	mustStatus(t, call(t, tok, "POST", "/v1/pharmacy/inbox/"+alert.str("id")+"/respond", map[string]any{
		"lines": []map[string]any{{"alert_item_id": itemID, "available": true, "unit_price_xof": 2500}},
	}), http.StatusOK)

	r := mustStatus(t, call(t, tok, "GET", "/v1/pharmacy/stats?days=30", nil), http.StatusOK)
	totals := r.Body["totals"].(map[string]any)
	if totals["received"] != float64(1) || totals["responded"] != float64(1) || totals["response_rate"] != float64(100) {
		t.Fatalf("totaux : %s", r.Raw)
	}
	series := r.Body["series"].([]any)
	if len(series) != 30 || series[29].(map[string]any)["received"] != float64(1) {
		t.Fatalf("aujourd'hui en dernier : %s", r.Raw)
	}
	if top := list(r.Body["top_medicines"]); len(top) != 1 || top[0]["responses"] != float64(1) {
		t.Fatalf("médicaments : %s", r.Raw)
	}
	// Un client n'y a pas accès.
	if r := call(t, b.token, "GET", "/v1/pharmacy/stats", nil); r.Status != http.StatusForbidden {
		t.Fatalf("client : %d", r.Status)
	}
}
