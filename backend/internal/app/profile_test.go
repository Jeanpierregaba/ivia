package app_test

import (
	"net/http"
	"testing"
)

func TestPrivacyConsent(t *testing.T) {
	requireApp(t)
	tok := login(t, uniqueEmail("consent"))

	// Prénom et téléphone sans consentement : profil incomplet, commande refusée plus loin.
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
