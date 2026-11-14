package auth

import (
	"context"
	"crypto"
	"crypto/rsa"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math/big"
	"net/http"
	"slices"
	"strconv"
	"strings"
	"sync"
	"time"
)

// Vérification des jetons d'identité Google (« Sign in with Google ») envoyés par les apps : le
// serveur ne fait confiance qu'à un jeton signé par Google (RS256, clés publiques de Google),
// émis pour une de nos applications (aud), non expiré, avec une adresse e-mail vérifiée.
// https://developers.google.com/identity/sign-in/android/backend-auth

const googleCertsURL = "https://www.googleapis.com/oauth2/v3/certs"

var googleIssuers = []string{"accounts.google.com", "https://accounts.google.com"}

// googleIdentity est ce que l'on retient d'un jeton Google valide.
type googleIdentity struct {
	Subject string // identifiant stable du compte Google
	Email   string
}

type googleVerifier struct {
	clientIDs []string
	certsURL  string
	client    *http.Client
	now       func() time.Time

	mu      sync.Mutex
	keys    map[string]*rsa.PublicKey
	expires time.Time
}

func newGoogleVerifier(clientIDs []string) *googleVerifier {
	return &googleVerifier{
		clientIDs: clientIDs,
		certsURL:  googleCertsURL,
		client:    &http.Client{Timeout: 5 * time.Second},
		now:       time.Now,
	}
}

func (g *googleVerifier) enabled() bool { return len(g.clientIDs) > 0 }

var errGoogleToken = errors.New("jeton Google invalide")

// verify contrôle le jeton et retourne l'identité Google. Toute anomalie donne errGoogleToken
// (détail dans l'erreur enveloppée, jamais montré à l'app).
func (g *googleVerifier) verify(ctx context.Context, token string) (googleIdentity, error) {
	parts := strings.Split(token, ".")
	if len(parts) != 3 || len(token) > 8192 {
		return googleIdentity{}, errGoogleToken
	}
	var header struct {
		Alg string `json:"alg"`
		Kid string `json:"kid"`
	}
	if err := decodeSegment(parts[0], &header); err != nil || header.Alg != "RS256" || header.Kid == "" {
		return googleIdentity{}, errGoogleToken
	}
	key, err := g.key(ctx, header.Kid)
	if err != nil {
		return googleIdentity{}, err
	}
	sig, err := base64.RawURLEncoding.DecodeString(parts[2])
	if err != nil {
		return googleIdentity{}, errGoogleToken
	}
	digest := sha256.Sum256([]byte(parts[0] + "." + parts[1]))
	if err := rsa.VerifyPKCS1v15(key, crypto.SHA256, digest[:], sig); err != nil {
		return googleIdentity{}, fmt.Errorf("%w : signature", errGoogleToken)
	}

	var claims struct {
		Iss           string          `json:"iss"`
		Aud           string          `json:"aud"`
		Sub           string          `json:"sub"`
		Email         string          `json:"email"`
		EmailVerified json.RawMessage `json:"email_verified"`
		Exp           int64           `json:"exp"`
		Iat           int64           `json:"iat"`
	}
	if err := decodeSegment(parts[1], &claims); err != nil {
		return googleIdentity{}, errGoogleToken
	}
	now := g.now()
	const leeway = 60 // secondes : horloges légèrement décalées
	switch {
	case !slices.Contains(googleIssuers, claims.Iss):
		return googleIdentity{}, fmt.Errorf("%w : émetteur", errGoogleToken)
	case !slices.Contains(g.clientIDs, claims.Aud):
		return googleIdentity{}, fmt.Errorf("%w : application", errGoogleToken)
	case claims.Exp == 0 || now.Unix() > claims.Exp+leeway:
		return googleIdentity{}, fmt.Errorf("%w : expiré", errGoogleToken)
	case claims.Iat > now.Unix()+leeway:
		return googleIdentity{}, fmt.Errorf("%w : émis dans le futur", errGoogleToken)
	case claims.Sub == "" || len(claims.Sub) > 255 || claims.Email == "":
		return googleIdentity{}, fmt.Errorf("%w : identité incomplète", errGoogleToken)
	}
	// email_verified est un booléen, parfois transmis comme chaîne.
	if v := strings.Trim(string(claims.EmailVerified), `"`); v != "true" {
		return googleIdentity{}, fmt.Errorf("%w : e-mail non vérifié", errGoogleToken)
	}
	return googleIdentity{Subject: claims.Sub, Email: claims.Email}, nil
}

func decodeSegment(seg string, v any) error {
	b, err := base64.RawURLEncoding.DecodeString(seg)
	if err != nil {
		return err
	}
	return json.Unmarshal(b, v)
}

// key retourne la clé publique de Google d'identifiant kid, en relisant les clés quand le cache
// a expiré (Cache-Control de Google) ou qu'une clé inconnue apparaît (rotation).
func (g *googleVerifier) key(ctx context.Context, kid string) (*rsa.PublicKey, error) {
	g.mu.Lock()
	defer g.mu.Unlock()
	if k, ok := g.keys[kid]; ok && g.now().Before(g.expires) {
		return k, nil
	}
	if err := g.refresh(ctx); err != nil {
		return nil, err
	}
	if k, ok := g.keys[kid]; ok {
		return k, nil
	}
	return nil, fmt.Errorf("%w : clé inconnue", errGoogleToken)
}

func (g *googleVerifier) refresh(ctx context.Context) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, g.certsURL, nil)
	if err != nil {
		return err
	}
	resp, err := g.client.Do(req)
	if err != nil {
		return fmt.Errorf("clés Google : %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("clés Google : statut %d", resp.StatusCode)
	}
	var set struct {
		Keys []struct {
			Kid string `json:"kid"`
			Kty string `json:"kty"`
			N   string `json:"n"`
			E   string `json:"e"`
		} `json:"keys"`
	}
	if err := json.NewDecoder(io.LimitReader(resp.Body, 1<<20)).Decode(&set); err != nil {
		return fmt.Errorf("clés Google : %w", err)
	}
	keys := map[string]*rsa.PublicKey{}
	for _, k := range set.Keys {
		if k.Kty != "RSA" {
			continue
		}
		n, err1 := base64.RawURLEncoding.DecodeString(k.N)
		e, err2 := base64.RawURLEncoding.DecodeString(k.E)
		if err1 != nil || err2 != nil || len(e) > 4 {
			continue
		}
		keys[k.Kid] = &rsa.PublicKey{N: new(big.Int).SetBytes(n), E: int(new(big.Int).SetBytes(e).Int64())}
	}
	if len(keys) == 0 {
		return errors.New("clés Google : aucune clé RSA")
	}
	g.keys = keys
	g.expires = g.now().Add(cacheDuration(resp.Header.Get("Cache-Control")))
	return nil
}

// cacheDuration lit max-age (1 h par défaut, entre 5 min et 24 h).
func cacheDuration(cc string) time.Duration {
	d := time.Hour
	for _, part := range strings.Split(cc, ",") {
		if v, ok := strings.CutPrefix(strings.TrimSpace(part), "max-age="); ok {
			if secs, err := strconv.Atoi(v); err == nil {
				d = time.Duration(secs) * time.Second
			}
		}
	}
	return min(max(d, 5*time.Minute), 24*time.Hour)
}
