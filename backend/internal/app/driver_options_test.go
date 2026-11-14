package app_test

import (
	"encoding/json"
	"net/http"
	"testing"
)

// Spec 033 : le livreur lit les zones de travail dans les options du dossier (zones desservies
// actives seulement), pour choisir la sienne avant l'envoi.
func TestDriverOptionsListWorkZones(t *testing.T) {
	requireApp(t)
	ad := admin(t)
	square := json.RawMessage(`{"type":"Polygon","coordinates":[[[1.20,6.12],[1.24,6.12],[1.24,6.16],[1.20,6.16],[1.20,6.12]]]}`)
	zone := func(name, kind string, active bool) string {
		t.Helper()
		return mustStatus(t, call(t, ad, "POST", "/v1/admin/zones", map[string]any{
			"name": name, "type": kind, "is_active": active, "geojson": square,
		}), http.StatusCreated).str("id")
	}
	suffix := uniquePhone()
	work := zone("Tokoin "+suffix, "service_area", true)
	off := zone("Bè fermée "+suffix, "service_area", false)
	pricing := zone("Tarif aéroport "+suffix, "pricing", true)

	tok := login(t, uniqueEmail("driver-options"))
	r := mustStatus(t, call(t, tok, "GET", "/v1/driver/options", nil), http.StatusOK)
	if len(list(r.Body["activities"])) == 0 {
		t.Fatalf("activités absentes : %v", r.Body)
	}
	seen := map[string]string{}
	for _, z := range list(r.Body["zones"]) {
		id, _ := z["id"].(string)
		name, _ := z["name"].(string)
		seen[id] = name
		if _, extra := z["geojson"]; extra {
			t.Fatalf("contour de zone exposé au livreur : %v", z)
		}
	}
	if seen[work] != "Tokoin "+suffix {
		t.Fatalf("zone desservie active absente : %v", seen)
	}
	if _, ok := seen[off]; ok {
		t.Fatal("zone inactive proposée")
	}
	if _, ok := seen[pricing]; ok {
		t.Fatal("zone de tarif proposée comme zone de travail")
	}
}
