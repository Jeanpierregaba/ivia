package auth

import (
	"context"
	"crypto"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"math/big"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestPasswordHashRoundTrip(t *testing.T) {
	h := newPasswordHasher()
	enc, err := h.hash("cheval-batterie-agrafe")
	if err != nil {
		t.Fatal(err)
	}
	if !strings.HasPrefix(enc, "$argon2id$v=19$m=19456,t=2,p=1$") {
		t.Fatalf("format PHC inattendu : %s", enc)
	}
	if ok, err := h.verify("cheval-batterie-agrafe", enc); err != nil || !ok {
		t.Fatalf("bon mot de passe refusé : %v %v", ok, err)
	}
	if ok, _ := h.verify("cheval-batterie-agrafE", enc); ok {
		t.Fatal("mauvais mot de passe accepté")
	}
	other, _ := h.hash("cheval-batterie-agrafe")
	if other == enc {
		t.Fatal("deux hachages du même mot de passe doivent différer (sel)")
	}
	if _, err := h.verify("x", "$bcrypt$abc"); !errors.Is(err, errBadHash) {
		t.Fatalf("empreinte illisible : %v", err)
	}
}

func TestPasswordRules(t *testing.T) {
	for pw, ok := range map[string]bool{
		"court":                    false,
		"motdepasse123":            false,
		"AZERTYUIOP":               false,
		"kossi.agbeko@ivia.tg":     false,
		"kossiagbeko2026":          false,
		"une phrase assez longue":  true,
		"Tr0p-de-pagnes-a-Lome!":   true,
		strings.Repeat("é", 128):   true,
		strings.Repeat("a1", 65):   false,
		"kossiagbeko-et-ses-amis!": true,
	} {
		err := checkPassword(pw, "kossi.agbeko@ivia.tg")
		if (err == nil) != ok {
			t.Errorf("checkPassword(%q) = %v, attendu accepté=%v", pw, err, ok)
		}
	}
}

// googleFixture : clé RSA de test, serveur de clés publiques et fabrique de jetons signés.
type googleFixture struct {
	key *rsa.PrivateKey
	srv *httptest.Server
	v   *googleVerifier
}

func newGoogleFixture(t *testing.T) *googleFixture {
	t.Helper()
	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatal(err)
	}
	f := &googleFixture{key: key}
	f.srv = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Cache-Control", "public, max-age=3600")
		_ = json.NewEncoder(w).Encode(map[string]any{"keys": []map[string]string{{
			"kid": "k1", "kty": "RSA", "alg": "RS256",
			"n": base64.RawURLEncoding.EncodeToString(key.N.Bytes()),
			"e": base64.RawURLEncoding.EncodeToString(big.NewInt(int64(key.E)).Bytes()),
		}}})
	}))
	t.Cleanup(f.srv.Close)
	f.v = newGoogleVerifier([]string{"app-android.apps.googleusercontent.com", "app-ios.apps.googleusercontent.com"})
	f.v.certsURL = f.srv.URL
	return f
}

func (f *googleFixture) token(t *testing.T, header, claims map[string]any) string {
	t.Helper()
	enc := func(v any) string {
		b, _ := json.Marshal(v)
		return base64.RawURLEncoding.EncodeToString(b)
	}
	signing := enc(header) + "." + enc(claims)
	digest := sha256.Sum256([]byte(signing))
	sig, err := rsa.SignPKCS1v15(rand.Reader, f.key, crypto.SHA256, digest[:])
	if err != nil {
		t.Fatal(err)
	}
	return signing + "." + base64.RawURLEncoding.EncodeToString(sig)
}

func goodClaims() map[string]any {
	now := time.Now().Unix()
	return map[string]any{
		"iss": "https://accounts.google.com", "aud": "app-android.apps.googleusercontent.com",
		"sub": "1234567890", "email": "Afi@Gmail.com", "email_verified": true,
		"iat": now, "exp": now + 3600,
	}
}

func TestGoogleTokenVerification(t *testing.T) {
	f := newGoogleFixture(t)
	ctx := context.Background()
	header := map[string]any{"alg": "RS256", "kid": "k1", "typ": "JWT"}

	id, err := f.v.verify(ctx, f.token(t, header, goodClaims()))
	if err != nil || id.Subject != "1234567890" || id.Email != "Afi@Gmail.com" {
		t.Fatalf("jeton valide refusé : %+v %v", id, err)
	}

	bad := map[string]func(c map[string]any){
		"autre application":  func(c map[string]any) { c["aud"] = "pirate.apps.googleusercontent.com" },
		"autre émetteur":     func(c map[string]any) { c["iss"] = "https://evil.example" },
		"expiré":             func(c map[string]any) { c["exp"] = time.Now().Add(-time.Hour).Unix() },
		"e-mail non vérifié": func(c map[string]any) { c["email_verified"] = false },
		"sans identifiant":   func(c map[string]any) { c["sub"] = "" },
		"émis dans le futur": func(c map[string]any) { c["iat"] = time.Now().Add(time.Hour).Unix() },
	}
	for name, mutate := range bad {
		c := goodClaims()
		mutate(c)
		if _, err := f.v.verify(ctx, f.token(t, header, c)); !errors.Is(err, errGoogleToken) {
			t.Errorf("%s : jeton accepté (%v)", name, err)
		}
	}
	// email_verified transmis comme chaîne : accepté.
	c := goodClaims()
	c["email_verified"] = "true"
	if _, err := f.v.verify(ctx, f.token(t, header, c)); err != nil {
		t.Errorf("email_verified en chaîne refusé : %v", err)
	}

	// Algorithme imposé : « none » ou HS256 sont refusés, signature falsifiée aussi.
	for _, alg := range []string{"none", "HS256"} {
		if _, err := f.v.verify(ctx, f.token(t, map[string]any{"alg": alg, "kid": "k1"}, goodClaims())); !errors.Is(err, errGoogleToken) {
			t.Errorf("alg %s accepté", alg)
		}
	}
	tok := f.token(t, header, goodClaims())
	parts := strings.Split(tok, ".")
	forged := map[string]any{"email": "admin@ivia.tg"}
	for k, v := range goodClaims() {
		if _, set := forged[k]; !set {
			forged[k] = v
		}
	}
	b, _ := json.Marshal(forged)
	if _, err := f.v.verify(ctx, parts[0]+"."+base64.RawURLEncoding.EncodeToString(b)+"."+parts[2]); !errors.Is(err, errGoogleToken) {
		t.Error("contenu modifié après signature accepté")
	}
	if _, err := f.v.verify(ctx, f.token(t, map[string]any{"alg": "RS256", "kid": "inconnue"}, goodClaims())); !errors.Is(err, errGoogleToken) {
		t.Error("clé inconnue acceptée")
	}
	if _, err := f.v.verify(ctx, "pas.un.jeton"); !errors.Is(err, errGoogleToken) {
		t.Error("jeton illisible accepté")
	}
}

func TestGoogleDisabledWithoutClientIDs(t *testing.T) {
	if newGoogleVerifier(nil).enabled() {
		t.Fatal("sans identifiants, la connexion Google doit être désactivée")
	}
}
