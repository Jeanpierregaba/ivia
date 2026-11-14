package app_test

import (
	"crypto/hmac"
	"crypto/sha1" //nolint:gosec // TOTP (RFC 6238)
	"encoding/base32"
	"encoding/binary"
	"fmt"
	"net/http"
	"strings"
	"testing"
	"time"
)

// device : identifiant d'installation tiré par l'app (un par test).
func device(name string) map[string]any {
	return map[string]any{"device_id": fmt.Sprintf("dev-%s-%d", name, seq.Add(1)), "device_name": name, "app": "buyer"}
}

// olderCodes vieillit les codes d'un numéro de deux minutes (limite d'un code par minute).
func olderCodes(t *testing.T, phone string) {
	t.Helper()
	if _, err := testApp.DB.Pool.Exec(t.Context(), `UPDATE otp_codes SET created_at = created_at - interval '2 minutes' WHERE recipient = $1`, phone); err != nil {
		t.Fatal(err)
	}
}

func with(base map[string]any, kv ...any) map[string]any {
	out := map[string]any{}
	for k, v := range base {
		out[k] = v
	}
	for i := 0; i+1 < len(kv); i += 2 {
		out[kv[i].(string)] = kv[i+1]
	}
	return out
}

// phoneLogin fait le parcours complet d'un nouveau numéro et retourne la session.
func phoneLogin(t *testing.T, phone string, dev map[string]any) resp {
	t.Helper()
	sent := mustStatus(t, call(t, "", "POST", "/v1/auth/phone/code", with(dev, "phone", phone)), http.StatusAccepted)
	if sent.str("channel") != "whatsapp" || sent.Body["expires_in_seconds"] != float64(300) {
		t.Fatalf("envoi : %v", sent.Body)
	}
	v := mustStatus(t, call(t, "", "POST", "/v1/auth/phone/verify", with(dev, "phone", phone, "code", lastCode(t, phone))), http.StatusOK)
	switch v.str("status") {
	case "signed_in":
		return resp{Status: http.StatusOK, Body: v.Body["session"].(map[string]any)}
	case "signup_required":
		return mustStatus(t, call(t, "", "POST", "/v1/auth/phone/signup", with(dev,
			"signup_token", v.str("signup_token"), "first_name", "Awa", "last_name", "Mensah", "accept_privacy_policy", true,
		)), http.StatusCreated)
	}
	t.Fatalf("vérification : %v", v.Body)
	return resp{}
}

// Inscription par numéro : aucun compte avant le nom ; ensuite connexion directe, alerte si
// l'appareil est nouveau, et le back-office est prévenu du nouvel acheteur.
func TestPhoneSignupThenLogin(t *testing.T) {
	requireApp(t)
	adminTok := admin(t) // admin existant avant l'inscription : il reçoit l'alerte
	phone := uniquePhone()
	dev := device("Tecno Spark")

	mustStatus(t, call(t, "", "POST", "/v1/auth/phone/code", with(dev, "phone", strings.TrimPrefix(phone, "+228"))), http.StatusAccepted)
	// Un code par minute.
	if r := call(t, "", "POST", "/v1/auth/phone/code", with(dev, "phone", phone)); r.code() != "otp_rate_limited" {
		t.Fatalf("second code immédiat : %d %s", r.Status, r.code())
	}
	v := mustStatus(t, call(t, "", "POST", "/v1/auth/phone/verify", with(dev, "phone", phone, "code", lastCode(t, phone))), http.StatusOK)
	if v.str("status") != "signup_required" || v.str("signup_token") == "" || v.Body["session"] != nil {
		t.Fatalf("nouveau numéro : %v", v.Body)
	}
	// Nom manquant : refusé, l'inscription reste valable.
	if r := call(t, "", "POST", "/v1/auth/phone/signup", with(dev, "signup_token", v.str("signup_token"), "first_name", "", "last_name", "Mensah", "accept_privacy_policy", true)); r.code() != "validation_failed" {
		t.Fatalf("prénom vide : %d %s", r.Status, r.code())
	}
	s := mustStatus(t, call(t, "", "POST", "/v1/auth/phone/signup", with(dev,
		"signup_token", v.str("signup_token"), "first_name", "Awa", "last_name", "Mensah", "accept_privacy_policy", true,
	)), http.StatusCreated)
	if s.Body["is_new_user"] != true || s.str("refresh_token") == "" || s.str("access_expires_at") == "" {
		t.Fatalf("inscription : %v", s.Body)
	}
	user := s.Body["user"].(map[string]any)
	if user["phone"] != phone || user["phone_verified"] != true || user["profile_complete"] != true {
		t.Fatalf("profil : %v", user)
	}
	// Jeton d'inscription à usage unique.
	if r := call(t, "", "POST", "/v1/auth/phone/signup", with(dev, "signup_token", v.str("signup_token"), "first_name", "Awa", "last_name", "M", "accept_privacy_policy", true)); r.code() != "signup_expired" {
		t.Fatalf("jeton réutilisé : %d %s", r.Status, r.code())
	}

	// Le back-office est prévenu.
	notes := mustStatus(t, call(t, adminTok, "GET", "/v1/notifications?app=admin", nil), http.StatusOK)
	if !strings.Contains(string(notes.Raw), `"new_buyer"`) {
		t.Fatalf("notification admin absente : %s", notes.Raw)
	}

	// Le numéro vérifié ne se change pas par le profil.
	if r := call(t, s.str("token"), "PATCH", "/v1/me", map[string]any{"phone": uniquePhone()}); r.code() != "validation_failed" {
		t.Fatalf("changement de numéro sans code : %d %s", r.Status, r.code())
	}

	// Nouvel appareil, une minute plus tard : connexion directe et alerte « nouvelle connexion ».
	olderCodes(t, phone)
	other := device("iPhone")
	again := phoneLogin(t, phone, other)
	if again.Body["is_new_user"] != false || again.str("token") == "" {
		t.Fatalf("reconnexion : %v", again.Body)
	}
	list := mustStatus(t, call(t, again.str("token"), "GET", "/v1/notifications?app=buyer", nil), http.StatusOK)
	if !strings.Contains(string(list.Raw), `"new_device_login"`) {
		t.Fatalf("alerte nouvel appareil absente : %s", list.Raw)
	}

	// Appareils connectés : deux sessions ; l'iPhone déconnecte le Tecno.
	sessions := mustStatus(t, call(t, again.str("token"), "GET", "/v1/me/sessions", nil), http.StatusOK)
	items := sessions.Body["items"].([]any)
	if len(items) != 2 {
		t.Fatalf("sessions : %s", sessions.Raw)
	}
	var tecno string
	for _, it := range items {
		m := it.(map[string]any)
		if m["device_name"] == "Tecno Spark" && m["current"] == false {
			tecno = m["id"].(string)
		}
	}
	mustStatus(t, call(t, again.str("token"), "DELETE", "/v1/me/sessions/"+tecno, nil), http.StatusNoContent)
	if r := call(t, s.str("token"), "GET", "/v1/me", nil); r.Status != http.StatusUnauthorized {
		t.Fatalf("session déconnectée encore valable : %d", r.Status)
	}
}

// 5 codes faux : code annulé et numéro verrouillé 15 minutes, même le bon code est refusé.
func TestPhoneLockAfterWrongCodes(t *testing.T) {
	requireApp(t)
	phone := uniquePhone()
	dev := device("Itel")
	mustStatus(t, call(t, "", "POST", "/v1/auth/phone/code", with(dev, "phone", phone)), http.StatusAccepted)
	good := lastCode(t, phone)
	wrong := "000000"
	if good == wrong {
		wrong = "111111"
	}
	for i := range 4 {
		if r := call(t, "", "POST", "/v1/auth/phone/verify", with(dev, "phone", phone, "code", wrong)); r.code() != "otp_invalid" {
			t.Fatalf("essai %d : %d %s", i+1, r.Status, r.code())
		}
	}
	if r := call(t, "", "POST", "/v1/auth/phone/verify", with(dev, "phone", phone, "code", wrong)); r.code() != "phone_locked" {
		t.Fatalf("5e essai : %d %s", r.Status, r.code())
	}
	if r := call(t, "", "POST", "/v1/auth/phone/verify", with(dev, "phone", phone, "code", good)); r.code() != "phone_locked" {
		t.Fatalf("bon code pendant le verrou : %d %s", r.Status, r.code())
	}
	if r := call(t, "", "POST", "/v1/auth/phone/code", with(dev, "phone", phone)); r.code() != "phone_locked" {
		t.Fatalf("nouveau code pendant le verrou : %d %s", r.Status, r.code())
	}
}

// Jeton d'accès court renouvelé par le jeton de rafraîchissement, changé à chaque usage ; un
// ancien jeton réutilisé plus tard révoque la session.
func TestRefreshRotationAndReuse(t *testing.T) {
	a := requireApp(t)
	s := phoneLogin(t, uniquePhone(), device("Samsung"))
	access, refresh := s.str("token"), s.str("refresh_token")
	mustStatus(t, call(t, access, "GET", "/v1/me", nil), http.StatusOK)

	r1 := mustStatus(t, call(t, "", "POST", "/v1/auth/refresh", map[string]string{"refresh_token": refresh}), http.StatusOK)
	if r1.str("token") == access || r1.str("refresh_token") == refresh {
		t.Fatal("jetons non changés")
	}
	if r := call(t, access, "GET", "/v1/me", nil); r.Status != http.StatusUnauthorized {
		t.Fatalf("ancien jeton d'accès encore valable : %d", r.Status)
	}
	mustStatus(t, call(t, r1.str("token"), "GET", "/v1/me", nil), http.StatusOK)

	// Jeton d'accès expiré : code dédié, pour que l'app le renouvelle sans déconnecter.
	if _, err := a.DB.Pool.Exec(t.Context(), `UPDATE sessions SET access_expires_at = now() - interval '1 second' WHERE refresh_hash IS NOT NULL AND user_id = (SELECT id FROM users WHERE phone = $1)`, s.Body["user"].(map[string]any)["phone"]); err != nil {
		t.Fatal(err)
	}
	if r := call(t, r1.str("token"), "GET", "/v1/me", nil); r.code() != "access_token_expired" {
		t.Fatalf("accès expiré : %d %s", r.Status, r.code())
	}

	// Réutilisation de l'ancien jeton juste après : refusée sans révoquer (requêtes simultanées).
	if r := call(t, "", "POST", "/v1/auth/refresh", map[string]string{"refresh_token": refresh}); r.Status != http.StatusUnauthorized {
		t.Fatalf("ancien jeton : %d", r.Status)
	}
	r2 := mustStatus(t, call(t, "", "POST", "/v1/auth/refresh", map[string]string{"refresh_token": r1.str("refresh_token")}), http.StatusOK)

	// Hors du délai de grâce : la réutilisation révoque toute la session.
	if _, err := a.DB.Pool.Exec(t.Context(), `UPDATE sessions SET refreshed_at = now() - interval '5 minutes' WHERE previous_refresh_hash IS NOT NULL AND user_id = (SELECT id FROM users WHERE phone = $1)`, s.Body["user"].(map[string]any)["phone"]); err != nil {
		t.Fatal(err)
	}
	if r := call(t, "", "POST", "/v1/auth/refresh", map[string]string{"refresh_token": r1.str("refresh_token")}); r.Status != http.StatusUnauthorized {
		t.Fatalf("jeton volé : %d", r.Status)
	}
	if r := call(t, "", "POST", "/v1/auth/refresh", map[string]string{"refresh_token": r2.str("refresh_token")}); r.Status != http.StatusUnauthorized {
		t.Fatalf("session non révoquée après réutilisation : %d", r.Status)
	}
}

// Changement de numéro confirmé par un code envoyé au nouveau numéro.
func TestPhoneChangeNeedsCode(t *testing.T) {
	requireApp(t)
	s := phoneLogin(t, uniquePhone(), device("Nokia"))
	tok := s.str("token")
	next := uniquePhone()
	mustStatus(t, call(t, tok, "POST", "/v1/me/phone/code", map[string]string{"phone": next}), http.StatusAccepted)
	if r := call(t, tok, "POST", "/v1/me/phone", map[string]string{"phone": next, "code": "999999"}); r.Status != http.StatusUnauthorized && lastCode(t, next) != "999999" {
		t.Fatalf("mauvais code : %d", r.Status)
	}
	u := mustStatus(t, call(t, tok, "POST", "/v1/me/phone", map[string]string{"phone": next, "code": lastCode(t, next)}), http.StatusOK)
	if u.Body["phone"] != next || u.Body["phone_verified"] != true {
		t.Fatalf("numéro : %v", u.Body)
	}
}

func totpCode(t *testing.T, secret string, at time.Time) string {
	t.Helper()
	key, err := base32.StdEncoding.WithPadding(base32.NoPadding).DecodeString(secret)
	if err != nil {
		t.Fatal(err)
	}
	var msg [8]byte
	binary.BigEndian.PutUint64(msg[:], uint64(at.Unix()/30))
	m := hmac.New(sha1.New, key)
	m.Write(msg[:])
	sum := m.Sum(nil)
	off := sum[len(sum)-1] & 0x0f
	return fmt.Sprintf("%06d", (binary.BigEndian.Uint32(sum[off:off+4])&0x7fffffff)%1_000_000)
}

// Admin : application d'authentification activée, puis exigée à la place du code par e-mail ; un
// code ne sert qu'une fois ; les codes de secours dépannent ; un autre admin peut réinitialiser.
func TestAdminTOTP(t *testing.T) {
	a := requireApp(t)
	email := uniqueEmail("admin-totp")
	if _, err := a.GrantAdmin(t.Context(), email); err != nil {
		t.Fatal(err)
	}
	tok := login(t, email)
	// Avant la double vérification : pas d'activation possible.
	if r := call(t, tok, "POST", "/v1/auth/mfa/totp/setup", nil); r.code() != "mfa_required" {
		t.Fatalf("activation sans vérification : %d %s", r.Status, r.code())
	}
	verifyMFA(t, tok, email)
	setup := mustStatus(t, call(t, tok, "POST", "/v1/auth/mfa/totp/setup", nil), http.StatusOK)
	secret := setup.str("secret")
	if !strings.HasPrefix(setup.str("otpauth_uri"), "otpauth://totp/") {
		t.Fatalf("lien : %v", setup.Body)
	}
	now := time.Now()
	if r := call(t, tok, "POST", "/v1/auth/mfa/totp/confirm", map[string]string{"code": "000000"}); r.code() != "otp_invalid" && totpCode(t, secret, now) != "000000" {
		t.Fatalf("mauvais code : %d %s", r.Status, r.code())
	}
	codes := mustStatus(t, call(t, tok, "POST", "/v1/auth/mfa/totp/confirm", map[string]string{"code": totpCode(t, secret, now)}), http.StatusOK)
	recovery := codes.Body["recovery_codes"].([]any)
	if len(recovery) != 10 {
		t.Fatalf("codes de secours : %v", codes.Body)
	}

	// Nouvelle connexion : plus de code par e-mail, l'application est exigée.
	tok2 := login(t, email)
	if info := mustStatus(t, call(t, tok2, "GET", "/v1/auth/session", nil), http.StatusOK); info.str("mfa_method") != "totp" {
		t.Fatalf("méthode : %v", info.Body)
	}
	if r := call(t, tok2, "POST", "/v1/auth/mfa/code", nil); r.code() != "mfa_use_totp" {
		t.Fatalf("code par e-mail après activation : %d %s", r.Status, r.code())
	}
	// Le code déjà utilisé à l'activation est refusé (anti-rejeu) ; le suivant passe.
	if r := call(t, tok2, "POST", "/v1/auth/mfa/verify", map[string]string{"code": totpCode(t, secret, now)}); r.code() != "otp_invalid" {
		t.Fatalf("code rejoué : %d %s", r.Status, r.code())
	}
	mustStatus(t, call(t, tok2, "POST", "/v1/auth/mfa/verify", map[string]string{"code": totpCode(t, secret, now.Add(30*time.Second))}), http.StatusOK)
	mustStatus(t, call(t, tok2, "GET", "/v1/admin/settings", nil), http.StatusOK)

	// Code de secours : une seule fois.
	tok3 := login(t, email)
	rc := strings.ToLower(recovery[0].(string))
	info := mustStatus(t, call(t, tok3, "POST", "/v1/auth/mfa/verify", map[string]string{"code": rc}), http.StatusOK)
	if info.Body["recovery_codes_left"] != float64(9) {
		t.Fatalf("codes restants : %v", info.Body)
	}
	tok4 := login(t, email)
	if r := call(t, tok4, "POST", "/v1/auth/mfa/verify", map[string]string{"code": rc}); r.code() != "otp_invalid" {
		t.Fatalf("code de secours réutilisé : %d %s", r.Status, r.code())
	}

	// Un autre admin réinitialise (motif obligatoire) : sessions coupées, retour au code e-mail.
	me := mustStatus(t, call(t, tok2, "GET", "/v1/me", nil), http.StatusOK)
	mustStatus(t, call(t, admin(t), "POST", "/v1/admin/users/"+me.str("id")+"/mfa/reset", map[string]string{"reason": "Téléphone perdu"}), http.StatusNoContent)
	if r := call(t, tok2, "GET", "/v1/me", nil); r.Status != http.StatusUnauthorized {
		t.Fatalf("session non coupée : %d", r.Status)
	}
	tok5 := login(t, email)
	if info := mustStatus(t, call(t, tok5, "GET", "/v1/auth/session", nil), http.StatusOK); info.str("mfa_method") != "email" {
		t.Fatalf("méthode après réinitialisation : %v", info.Body)
	}
}
