package app_test

import (
	"net/http"
	"testing"
	"time"
)

// Alerte médicament sans aucune simulation : seules les vraies pharmacies du rayon la reçoivent
// (en direct dans leur app), le client ne voit que les réponses réellement envoyées, et la route
// qui inventait des réponses n'existe plus.
func TestPharmacyAlertOnlyRealResponses(t *testing.T) {
	requireApp(t)
	// Quartier à l'écart des autres tests : seules nos trois pharmacies sont autour.
	lat, lng := 6.402, 1.081
	near1, _ := newPharmacy(t, "Pharmacie Réelle Un", lat+0.004, lng)
	near2, _ := newPharmacy(t, "Pharmacie Réelle Deux", lat-0.006, lng+0.003)
	far, _ := newPharmacy(t, "Pharmacie Hors Rayon", lat+0.08, lng) // ~9 km
	b := newBuyer(t, lat, lng)

	ws1, c1 := openEvents(t, near1, "pharmacy", true)
	ws2, c2 := openEvents(t, near2, "pharmacy", false)

	alert := mustStatus(t, call(t, b.token, "POST", "/v1/medicine-alerts", map[string]any{
		"items":            []map[string]any{{"name": "Paracétamol 1000 mg", "form": "Comprimés", "quantity": 1}},
		"generic_accepted": true, "radius_m": 5000, "location": map[string]float64{"lat": lat, "lng": lng},
	}), http.StatusCreated)
	alertID := alert.str("id")
	if n := num(alert.Body["stats"].(map[string]any)["notified"]); n != 2 {
		t.Fatalf("pharmacies alertées : %v, attendu 2 (la troisième est hors du rayon)", n)
	}

	// Chaque pharmacie du rayon est prévenue en direct dans son app, et l'alerte est dans sa boîte.
	byAlert := func(e liveEvent) bool { return e.Data["alert_id"] == alertID }
	waitEvent(t, ws1, c1, "pharmacy_alert", byAlert)
	waitEvent(t, ws2, c2, "pharmacy_alert", byAlert)
	for _, tok := range []string{near1, near2} {
		if inbox := items(mustStatus(t, call(t, tok, "GET", "/v1/pharmacy/inbox", nil), http.StatusOK)); len(inbox) != 1 || inbox[0]["alert_id"] != alertID {
			t.Fatalf("boîte d'une pharmacie du rayon : %v", inbox)
		}
	}
	if inbox := items(mustStatus(t, call(t, far, "GET", "/v1/pharmacy/inbox", nil), http.StatusOK)); len(inbox) != 0 {
		t.Fatalf("pharmacie hors rayon sollicitée : %v", inbox)
	}

	// Personne n'a répondu : aucune réponse, même après quelques secondes.
	time.Sleep(3 * time.Second)
	got := mustStatus(t, call(t, b.token, "GET", "/v1/medicine-alerts/"+alertID, nil), http.StatusOK)
	if r := list(got.Body["responses"]); len(r) != 0 || num(got.Body["stats"].(map[string]any)["responded"]) != 0 {
		t.Fatalf("réponses inventées : %v", got.Body["responses"])
	}
	// La route qui faisait répondre des pharmacies de démonstration n'existe plus.
	if r := call(t, b.token, "POST", "/v1/dev/medicine-alerts/"+alertID+"/auto-respond", nil); r.Status != http.StatusNotFound && r.Status != http.StatusMethodNotAllowed {
		t.Fatalf("réponse automatique encore exposée : %d", r.Status)
	}

	// Une vraie pharmacie vérifie son stock et répond : le client voit cette réponse, et elle seule.
	itemID := list(alert.Body["items"])[0]["id"]
	mustStatus(t, call(t, near1, "POST", "/v1/pharmacy/inbox/"+alertID+"/respond", map[string]any{
		"lines": []map[string]any{{"alert_item_id": itemID, "available": true, "unit_price_xof": 1350}},
	}), http.StatusOK)
	got = mustStatus(t, call(t, b.token, "GET", "/v1/medicine-alerts/"+alertID, nil), http.StatusOK)
	resps := list(got.Body["responses"])
	if len(resps) != 1 || num(got.Body["stats"].(map[string]any)["responded"]) != 1 {
		t.Fatalf("réponses vues par le client : %v", got.Body["responses"])
	}
	lines := list(resps[0]["lines"])
	if len(lines) != 1 || num(lines[0]["unit_price_xof"]) != 1350 {
		t.Fatalf("prix de la réponse : %v", resps[0])
	}
}
