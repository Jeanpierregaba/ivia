package app_test

import (
	"context"
	"net/http"
	"testing"
)

// Création de compte : code reçu par e-mail, puis mot de passe ; ensuite connexion par mot de passe.
func TestSignupThenPasswordLogin(t *testing.T) {
	requireApp(t)
	email := uniqueEmail("nouveau")
	mustStatus(t, call(t, "", "POST", "/v1/auth/signup/code", map[string]string{"email": email}), http.StatusAccepted)
	code := lastCode(t, email)

	// Mot de passe trop faible : refusé, le code reste valable.
	if r := call(t, "", "POST", "/v1/auth/signup", map[string]string{"email": email, "code": code, "password": "court"}); r.code() != "validation_failed" {
		t.Fatalf("mot de passe faible : %d %s", r.Status, r.code())
	}
	if r := call(t, "", "POST", "/v1/auth/signup", map[string]string{"email": email, "code": "000000", "password": testPassword}); r.Status != http.StatusUnauthorized {
		t.Fatalf("mauvais code : %d %s", r.Status, r.code())
	}
	s := mustStatus(t, call(t, "", "POST", "/v1/auth/signup", map[string]string{"email": email, "code": code, "password": testPassword}), http.StatusCreated)
	if s.Body["is_new_user"] != true || s.str("token") == "" {
		t.Fatalf("création : %v", s.Body)
	}
	// Le code ne sert qu'une fois.
	if r := call(t, "", "POST", "/v1/auth/signup", map[string]string{"email": email, "code": code, "password": testPassword}); r.Status == http.StatusCreated {
		t.Fatal("code réutilisé")
	}

	tok := mustStatus(t, call(t, "", "POST", "/v1/auth/login", map[string]string{"email": email, "password": testPassword}), http.StatusOK).str("token")
	mustStatus(t, call(t, tok, "GET", "/v1/me", nil), http.StatusOK)
	info := mustStatus(t, call(t, tok, "GET", "/v1/auth/session", nil), http.StatusOK)
	if info.Body["has_password"] != true || info.Body["mfa_verified"] != false {
		t.Fatalf("session : %v", info.Body)
	}

	// Un code par minute et par usage : une nouvelle demande immédiate est refusée.
	mustStatus(t, call(t, "", "POST", "/v1/auth/signup/code", map[string]string{"email": email}), http.StatusTooManyRequests)
}

// Le message ne dit jamais si un compte existe ; 10 échecs verrouillent le compte 15 minutes.
func TestPasswordLoginErrorsAndLockout(t *testing.T) {
	requireApp(t)
	email := uniqueEmail("verrou")
	login(t, email)

	unknown := call(t, "", "POST", "/v1/auth/login", map[string]string{"email": uniqueEmail("inconnu"), "password": testPassword})
	wrong := call(t, "", "POST", "/v1/auth/login", map[string]string{"email": email, "password": "pas-le-bon-mot-de-passe"})
	if unknown.Status != http.StatusUnauthorized || unknown.code() != "invalid_credentials" ||
		wrong.Status != unknown.Status || wrong.code() != unknown.code() || wrong.Body["error"].(map[string]any)["message"] != unknown.Body["error"].(map[string]any)["message"] {
		t.Fatalf("compte inconnu et mauvais mot de passe doivent répondre pareil : %v / %v", unknown.Body, wrong.Body)
	}
	for range 8 {
		call(t, "", "POST", "/v1/auth/login", map[string]string{"email": email, "password": "pas-le-bon-mot-de-passe"})
	}
	if r := call(t, "", "POST", "/v1/auth/login", map[string]string{"email": email, "password": "pas-le-bon-mot-de-passe"}); r.code() != "account_locked" {
		t.Fatalf("10e échec : %d %s", r.Status, r.code())
	}
	// Verrouillé : même le bon mot de passe est refusé…
	if r := call(t, "", "POST", "/v1/auth/login", map[string]string{"email": email, "password": testPassword}); r.code() != "account_locked" {
		t.Fatalf("connexion pendant le verrou : %d %s", r.Status, r.code())
	}
	// … mais « mot de passe oublié » débloque.
	mustStatus(t, call(t, "", "POST", "/v1/auth/password/forgot", map[string]string{"email": email}), http.StatusAccepted)
	mustStatus(t, call(t, "", "POST", "/v1/auth/password/reset", map[string]string{
		"email": email, "code": lastCode(t, email), "password": "un-tout-nouveau-mot-de-passe",
	}), http.StatusOK)
	mustStatus(t, call(t, "", "POST", "/v1/auth/login", map[string]string{"email": email, "password": "un-tout-nouveau-mot-de-passe"}), http.StatusOK)
}

// Mot de passe oublié : même réponse pour un compte inconnu ; la réinitialisation déconnecte les
// autres appareils et l'ancien mot de passe ne marche plus.
func TestPasswordResetRevokesSessions(t *testing.T) {
	requireApp(t)
	email := uniqueEmail("oubli")
	old := login(t, email)

	known := mustStatus(t, call(t, "", "POST", "/v1/auth/password/forgot", map[string]string{"email": email}), http.StatusAccepted)
	unknown := mustStatus(t, call(t, "", "POST", "/v1/auth/password/forgot", map[string]string{"email": uniqueEmail("personne")}), http.StatusAccepted)
	if string(known.Raw) != string(unknown.Raw) {
		t.Fatalf("réponses différentes : %s / %s", known.Raw, unknown.Raw)
	}
	fresh := mustStatus(t, call(t, "", "POST", "/v1/auth/password/reset", map[string]string{
		"email": email, "code": lastCode(t, email), "password": "nouveau-mot-de-passe-2026",
	}), http.StatusOK).str("token")

	if r := call(t, old, "GET", "/v1/me", nil); r.Status != http.StatusUnauthorized {
		t.Fatalf("ancienne session encore valide : %d", r.Status)
	}
	mustStatus(t, call(t, fresh, "GET", "/v1/me", nil), http.StatusOK)
	if r := call(t, "", "POST", "/v1/auth/login", map[string]string{"email": email, "password": testPassword}); r.code() != "invalid_credentials" {
		t.Fatalf("ancien mot de passe : %d %s", r.Status, r.code())
	}
}

// Changement de mot de passe connecté : l'actuel est exigé, les autres appareils sont déconnectés.
func TestChangePassword(t *testing.T) {
	requireApp(t)
	email := uniqueEmail("change")
	a := login(t, email)
	b := login(t, email)
	if r := call(t, a, "POST", "/v1/me/password", map[string]string{"current_password": "faux-mot-de-passe-1", "new_password": "encore-un-autre-mot"}); r.code() != "validation_failed" {
		t.Fatalf("mot de passe actuel faux : %d %s", r.Status, r.code())
	}
	mustStatus(t, call(t, a, "POST", "/v1/me/password", map[string]string{"current_password": testPassword, "new_password": "encore-un-autre-mot"}), http.StatusNoContent)
	mustStatus(t, call(t, a, "GET", "/v1/me", nil), http.StatusOK)
	if r := call(t, b, "GET", "/v1/me", nil); r.Status != http.StatusUnauthorized {
		t.Fatalf("autre appareil encore connecté : %d", r.Status)
	}
}

// Back-office : un mot de passe seul n'ouvre pas les routes admin ; le code reçu par e-mail, si.
func TestAdminRoutesRequireMFA(t *testing.T) {
	requireApp(t)
	email := uniqueEmail("admin2fa")
	if _, err := testApp.GrantAdmin(context.Background(), email); err != nil {
		t.Fatal(err)
	}
	tok := login(t, email)
	if r := call(t, tok, "GET", "/v1/admin/metrics", nil); r.Status != http.StatusForbidden || r.code() != "mfa_required" {
		t.Fatalf("admin sans code : %d %s", r.Status, r.code())
	}
	mustStatus(t, call(t, tok, "POST", "/v1/auth/mfa/code", nil), http.StatusAccepted)
	if r := call(t, tok, "POST", "/v1/auth/mfa/verify", map[string]string{"code": "000000"}); r.Status != http.StatusUnauthorized {
		t.Fatalf("mauvais code : %d %s", r.Status, r.code())
	}
	info := mustStatus(t, call(t, tok, "POST", "/v1/auth/mfa/verify", map[string]string{"code": lastCode(t, email)}), http.StatusOK)
	if info.Body["mfa_verified"] != true {
		t.Fatalf("session non vérifiée : %v", info.Body)
	}
	mustStatus(t, call(t, tok, "GET", "/v1/admin/metrics", nil), http.StatusOK)
	// Session admin plafonnée à 8 h.
	var hours float64
	if err := testDB.Pool.QueryRow(ctx(), "SELECT extract(epoch FROM expires_at - now()) / 3600 FROM sessions WHERE expires_cap IS NOT NULL ORDER BY mfa_verified_at DESC LIMIT 1").Scan(&hours); err != nil {
		t.Fatal(err)
	}
	if hours > 8.01 {
		t.Fatalf("session admin de %.1f h, plafond 8 h", hours)
	}
}

// Google : désactivé sans identifiants OAuth (le bouton est masqué dans les apps).
func TestGoogleDisabledWithoutConfiguration(t *testing.T) {
	requireApp(t)
	p := mustStatus(t, call(t, "", "GET", "/v1/auth/providers", nil), http.StatusOK)
	if p.Body["google"] != false || p.Body["password"] != true {
		t.Fatalf("fournisseurs : %v", p.Body)
	}
	if r := call(t, "", "POST", "/v1/auth/google", map[string]string{"id_token": "x.y.z"}); r.code() != "google_disabled" {
		t.Fatalf("Google sans configuration : %d %s", r.Status, r.code())
	}
}
