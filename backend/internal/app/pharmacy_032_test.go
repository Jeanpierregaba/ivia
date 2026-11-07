package app_test

import (
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"testing"
)

// Spec 032 : numéro court d'alerte et quartier du client.
func TestPharmacyAlertNumberAndNeighborhood(t *testing.T) {
	requireApp(t)
	lat, lng := zone()
	ph, _ := newPharmacy(t, "Pharmacie du Numéro", lat, lng)
	b := newBuyer(t, lat, lng)
	hood := fmt.Sprintf("Quartier-%d", seq.Add(1))
	mustStatus(t, call(t, admin(t), "POST", "/v1/admin/neighborhoods", map[string]any{
		"name": hood, "city": "Lomé", "center": map[string]float64{"lat": lat + 0.003, "lng": lng},
	}), http.StatusCreated)

	alert := func(dLat float64) string {
		return mustStatus(t, call(t, b.token, "POST", "/v1/medicine-alerts", map[string]any{
			"items":    []map[string]any{{"name": "Paracétamol 1000 mg", "quantity": 1}},
			"radius_m": 5000, "location": map[string]float64{"lat": lat + dLat, "lng": lng},
		}), http.StatusCreated).str("number")
	}
	n1, n2 := alert(0.002), alert(0.002)
	parse := func(s string) int {
		if !strings.HasPrefix(s, "A-") {
			t.Fatalf("numéro d'alerte : %q", s)
		}
		v, err := strconv.Atoi(strings.TrimPrefix(s, "A-"))
		if err != nil {
			t.Fatalf("numéro d'alerte : %q", s)
		}
		return v
	}
	if parse(n2) != parse(n1)+1 {
		t.Fatalf("numéros non consécutifs : %s puis %s", n1, n2)
	}

	inbox := items(mustStatus(t, call(t, ph, "GET", "/v1/pharmacy/inbox", nil), http.StatusOK))
	if len(inbox) != 2 || inbox[0]["number"] != n2 || inbox[1]["number"] != n1 {
		t.Fatalf("numéros dans la boîte : %v", inbox)
	}
	if inbox[0]["client_neighborhood"] != hood {
		t.Fatalf("quartier du client : %v", inbox[0]["client_neighborhood"])
	}
	for _, forbidden := range []string{"location", "lat", "lng", "buyer_id"} {
		if _, ok := inbox[0][forbidden]; ok {
			t.Fatalf("position du client exposée : %s", forbidden)
		}
	}
	id := inbox[0]["alert_id"].(string)
	d := mustStatus(t, call(t, ph, "GET", "/v1/pharmacy/inbox/"+id, nil), http.StatusOK)
	if d.str("number") != n2 || d.str("client_neighborhood") != hood {
		t.Fatalf("détail : %v", d.Body)
	}
	if a := mustStatus(t, call(t, admin(t), "GET", "/v1/admin/medicine-alerts/"+id, nil), http.StatusOK); a.str("number") != n2 {
		t.Fatalf("numéro au back-office : %v", a.Body["number"])
	}

	// Loin de tout quartier connu : pas de quartier.
	// (dans le rayon de la pharmacie, à plus de 4 km du centre du quartier).
	far := alert(-0.04)
	found := false
	for _, it := range items(call(t, ph, "GET", "/v1/pharmacy/inbox", nil)) {
		if it["number"] == far {
			found = true
			if it["client_neighborhood"] != nil {
				t.Fatalf("quartier trop loin : %v", it["client_neighborhood"])
			}
		}
	}
	if !found {
		t.Fatal("alerte lointaine absente de la boîte")
	}
}
