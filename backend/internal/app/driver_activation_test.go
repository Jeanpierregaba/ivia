package app_test

import (
	"net/http"
	"testing"
)

// Un candidat livreur ne peut pas travailler tant qu'un admin n'a pas validé un dossier complet.
func TestDriverMustBeValidatedByAdmin(t *testing.T) {
	requireApp(t)
	tok := login(t, uniqueEmail("candidat"))
	completeProfile(t, tok, "Kodjo")
	mustStatus(t, call(t, tok, "PUT", "/v1/driver/application", map[string]string{"vehicle_type": "motorbike", "vehicle_plate": "TG-4242"}), http.StatusOK)
	id := mustStatus(t, call(t, tok, "GET", "/v1/me", nil), http.StatusOK).str("id")

	// Candidature déposée : aucun accès aux missions (pas de rôle driver).
	work := []struct{ method, path string }{
		{"PUT", "/v1/driver/availability"},
		{"POST", "/v1/driver/location"},
		{"GET", "/v1/driver/offers/current"},
		{"GET", "/v1/driver/missions/current"},
	}
	blocked := func(when string) {
		t.Helper()
		for _, w := range work {
			var body any
			if w.method != "GET" {
				body = map[string]any{"online": true, "lat": 6.1, "lng": 1.2}
			}
			if r := call(t, tok, w.method, w.path, body); r.Status != http.StatusForbidden {
				t.Errorf("%s : %s %s → %d, attendu 403", when, w.method, w.path, r.Status)
			}
		}
	}
	blocked("candidature en attente")
	if st := mustStatus(t, call(t, tok, "GET", "/v1/driver/me", nil), http.StatusOK).str("status"); st != "pending_review" {
		t.Fatalf("statut du candidat : %s", st)
	}

	// Dossier incomplet : la validation est refusée.
	if r := call(t, admin(t), "POST", "/v1/admin/drivers/"+id+"/approve", map[string]any{}); r.code() != "driver_documents_missing" {
		t.Fatalf("validation d'un dossier vide : %s", r.Raw)
	}
	uploadDriverDocument(t, tok, "id_card")
	if r := call(t, admin(t), "POST", "/v1/admin/drivers/"+id+"/approve", map[string]any{}); r.code() != "driver_documents_missing" {
		t.Fatalf("validation sans permis : %s", r.Raw)
	}
	blocked("dossier incomplet")

	// Refus : toujours aucun accès.
	mustStatus(t, call(t, admin(t), "POST", "/v1/admin/drivers/"+id+"/reject", map[string]string{"reason": "Permis illisible"}), http.StatusOK)
	blocked("candidature refusée")

	// Dossier complété puis validé : le compte est activé.
	uploadDriverDocument(t, tok, "driving_license")
	mustStatus(t, call(t, tok, "PUT", "/v1/driver/application", map[string]string{"vehicle_type": "motorbike", "vehicle_plate": "TG-4242"}), http.StatusOK)
	adm := mustStatus(t, call(t, admin(t), "GET", "/v1/admin/drivers/"+id, nil), http.StatusOK)
	for _, d := range adm.Body["documents"].([]any) {
		if d.(map[string]any)["url"] == "" {
			t.Fatal("l'admin consulte les documents par lien temporaire")
		}
	}
	mustStatus(t, call(t, admin(t), "POST", "/v1/admin/drivers/"+id+"/approve", map[string]any{}), http.StatusOK)
	mustStatus(t, call(t, tok, "PUT", "/v1/driver/availability", map[string]bool{"online": true}), http.StatusOK)
	if st := mustStatus(t, call(t, tok, "GET", "/v1/driver/me", nil), http.StatusOK).str("status"); st != "available" {
		t.Fatalf("après validation : %s", st)
	}

	// Les documents d'un livreur ne sont jamais accessibles par un autre utilisateur.
	if r := call(t, tok, "GET", "/v1/admin/drivers/"+id, nil); r.Status != http.StatusForbidden {
		t.Fatalf("dossier livreur hors admin : %d", r.Status)
	}
}
