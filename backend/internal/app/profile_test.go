package app_test

import (
	"net/http"
	"testing"
)

func TestPrivacyConsent(t *testing.T) {
	requireApp(t)
	tok := login(t, uniqueEmail("consent"))

	// Prénom et téléphone sans consentement : profil incomplet.
	r := mustStatus(t, call(t, tok, "PATCH", "/v1/me", map[string]any{
		"first_name": "Awa", "last_name": "Mensah", "phone": uniquePhone(),
	}), http.StatusOK)
	if r.Body["profile_complete"] != false || r.Body["privacy_consent_at"] != nil {
		t.Fatalf("sans consentement : profile_complete=%v privacy_consent_at=%v", r.Body["profile_complete"], r.Body["privacy_consent_at"])
	}

	// Retirer un consentement par cette route est refusé.
	if r := call(t, tok, "PATCH", "/v1/me", map[string]any{"accept_privacy_policy": false}); r.code() != "validation_failed" {
		t.Fatalf("consentement à false : code %q (statut %d)", r.code(), r.Status)
	}

	r = mustStatus(t, call(t, tok, "PATCH", "/v1/me", map[string]any{"accept_privacy_policy": true}), http.StatusOK)
	consentAt := r.str("privacy_consent_at")
	if consentAt == "" || r.Body["profile_complete"] != true {
		t.Fatalf("avec consentement : profile_complete=%v privacy_consent_at=%q", r.Body["profile_complete"], consentAt)
	}

	// Une nouvelle acceptation, ou une modification sans le champ, ne redate pas le consentement.
	r = mustStatus(t, call(t, tok, "PATCH", "/v1/me", map[string]any{"accept_privacy_policy": true}), http.StatusOK)
	if got := r.str("privacy_consent_at"); got != consentAt {
		t.Fatalf("consentement redaté : %q puis %q", consentAt, got)
	}
	r = mustStatus(t, call(t, tok, "PATCH", "/v1/me", map[string]any{"first_name": "Awa"}), http.StatusOK)
	if got := r.str("privacy_consent_at"); got != consentAt {
		t.Fatalf("consentement perdu : %q puis %q", consentAt, got)
	}
}

// Sans consentement, le profil est incomplet : commande et candidature livreur refusées ; la
// recherche admin rapporte l'état réel.
func TestConsentRequiredToOrderAndApply(t *testing.T) {
	requireApp(t)
	seller := newSeller(t, 5)
	email := uniqueEmail("noconsent")
	tok := login(t, email)
	mustStatus(t, call(t, tok, "PATCH", "/v1/me", map[string]any{"first_name": "Kossi", "phone": uniquePhone()}), http.StatusOK)

	b := buyerFixture{token: tok}
	if r := order(t, b, seller.untrackedID, 1, "pickup"); r.code() != "profile_incomplete" {
		t.Fatalf("commande sans consentement : code %q (statut %d)", r.code(), r.Status)
	}
	if r := call(t, tok, "PUT", "/v1/driver/application", map[string]string{"vehicle_type": "motorbike", "vehicle_plate": "TG-0002"}); r.code() != "profile_incomplete" {
		t.Fatalf("candidature sans consentement : code %q (statut %d)", r.code(), r.Status)
	}

	mustStatus(t, call(t, tok, "PATCH", "/v1/me", map[string]any{"accept_privacy_policy": true}), http.StatusOK)
	if r := order(t, b, seller.untrackedID, 1, "pickup"); r.Status != http.StatusCreated {
		t.Fatalf("commande avec consentement : statut %d (%s)", r.Status, r.code())
	}

	found := mustStatus(t, call(t, admin(t), "GET", "/v1/admin/users?q="+email, nil), http.StatusOK)
	items, _ := found.Body["items"].([]any)
	if len(items) != 1 {
		t.Fatalf("recherche admin : %d résultat(s)", len(items))
	}
	u, _ := items[0].(map[string]any)
	if u["profile_complete"] != true || u["privacy_consent_at"] == nil {
		t.Fatalf("recherche admin : profile_complete=%v privacy_consent_at=%v", u["profile_complete"], u["privacy_consent_at"])
	}
}
