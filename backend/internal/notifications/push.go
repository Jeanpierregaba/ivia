package notifications

import (
	"bytes"
	"context"
	"crypto"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/url"
	"os"
	"strings"
	"sync"
	"time"
)

// LogPush affiche les push dans les journaux (développement local).
type LogPush struct {
	Logger *slog.Logger
}

// Send implémente PushSender. Le jeton de l'appareil n'est pas journalisé.
func (p LogPush) Send(_ context.Context, _ string, title, _ string, data map[string]string, sound bool) error {
	p.Logger.Info("[DEV] push", "title", title, "kind", data["kind"], "sound", sound)
	return nil
}

// FCM envoie les push par l'API HTTP v1 de Firebase Cloud Messaging, authentifiée par le compte
// de service (jeton OAuth 2 obtenu par assertion JWT signée RS256).
type FCM struct {
	projectID   string
	clientEmail string
	tokenURI    string
	key         *rsa.PrivateKey
	client      *http.Client
	// endpoint de base (remplacé dans les tests).
	endpoint string

	mu          sync.Mutex
	accessToken string
	expiresAt   time.Time
}

type serviceAccount struct {
	ProjectID   string `json:"project_id"`
	ClientEmail string `json:"client_email"`
	PrivateKey  string `json:"private_key"`
	TokenURI    string `json:"token_uri"`
}

// NewFCMFromFile lit le fichier JSON du compte de service Firebase.
func NewFCMFromFile(path string) (*FCM, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("lecture du compte de service FCM : %w", err)
	}
	return NewFCM(raw)
}

// NewFCM crée le client à partir du contenu JSON du compte de service.
func NewFCM(serviceAccountJSON []byte) (*FCM, error) {
	var sa serviceAccount
	if err := json.Unmarshal(serviceAccountJSON, &sa); err != nil {
		return nil, fmt.Errorf("compte de service FCM invalide : %w", err)
	}
	if sa.ProjectID == "" || sa.ClientEmail == "" || sa.PrivateKey == "" {
		return nil, errors.New("compte de service FCM incomplet")
	}
	block, _ := pem.Decode([]byte(sa.PrivateKey))
	if block == nil {
		return nil, errors.New("clé privée FCM illisible")
	}
	parsed, err := x509.ParsePKCS8PrivateKey(block.Bytes)
	if err != nil {
		return nil, fmt.Errorf("clé privée FCM : %w", err)
	}
	key, ok := parsed.(*rsa.PrivateKey)
	if !ok {
		return nil, errors.New("clé privée FCM : RSA attendue")
	}
	if sa.TokenURI == "" {
		sa.TokenURI = "https://oauth2.googleapis.com/token"
	}
	return &FCM{
		projectID: sa.ProjectID, clientEmail: sa.ClientEmail, tokenURI: sa.TokenURI, key: key,
		client: &http.Client{Timeout: 10 * time.Second}, endpoint: "https://fcm.googleapis.com",
	}, nil
}

// fcmMessage construit le message. Urgent (données « urgent » = « true ») : sans bloc notification sur
// Android, l'app est réveillée et fait sonner l'alerte elle-même ; sur iOS, notification sensible au
// temps, le seul plein écran permis n'existant pas, avec le son sauf si la sonnerie des alertes est
// coupée sur ce téléphone (sound faux ; sur Android, l'app applique elle-même son réglage).
func fcmMessage(token, title, body string, data map[string]string, sound bool) map[string]any {
	if data["urgent"] != "true" {
		return map[string]any{
			"token":        token,
			"notification": map[string]string{"title": title, "body": body},
			"data":         data,
			"android":      map[string]any{"priority": "high"},
		}
	}
	full := make(map[string]string, len(data)+2)
	for k, v := range data {
		full[k] = v
	}
	full["title"], full["body"] = title, body
	aps := map[string]any{
		"alert":              map[string]string{"title": title, "body": body},
		"interruption-level": "time-sensitive",
	}
	if sound {
		aps["sound"] = "default"
	}
	return map[string]any{
		"token":   token,
		"data":    full,
		"android": map[string]any{"priority": "high", "ttl": "600s"},
		"apns": map[string]any{
			"headers": map[string]string{"apns-priority": "10", "apns-push-type": "alert", "apns-expiration": "0"},
			"payload": map[string]any{"aps": aps},
		},
	}
}

// Send implémente PushSender.
func (f *FCM) Send(ctx context.Context, token, title, body string, data map[string]string, sound bool) error {
	access, err := f.oauthToken(ctx)
	if err != nil {
		return err
	}
	payload, err := json.Marshal(map[string]any{"message": fcmMessage(token, title, body, data, sound)})
	if err != nil {
		return err
	}
	u := f.endpoint + "/v1/projects/" + url.PathEscape(f.projectID) + "/messages:send"
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, u, bytes.NewReader(payload))
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+access)
	req.Header.Set("Content-Type", "application/json")
	resp, err := f.client.Do(req)
	if err != nil {
		return fmt.Errorf("fcm : %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode == http.StatusOK {
		return nil
	}
	msg, _ := io.ReadAll(io.LimitReader(resp.Body, 2000))
	text := string(msg)
	if resp.StatusCode == http.StatusNotFound || strings.Contains(text, "UNREGISTERED") ||
		(resp.StatusCode == http.StatusBadRequest && strings.Contains(text, "registration token")) {
		return ErrInvalidToken
	}
	if resp.StatusCode == http.StatusUnauthorized {
		f.mu.Lock()
		f.accessToken = ""
		f.mu.Unlock()
	}
	return fmt.Errorf("fcm : statut %d", resp.StatusCode)
}

func (f *FCM) oauthToken(ctx context.Context) (string, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.accessToken != "" && time.Until(f.expiresAt) > time.Minute {
		return f.accessToken, nil
	}
	assertion, err := f.signedJWT(time.Now())
	if err != nil {
		return "", err
	}
	form := url.Values{}
	form.Set("grant_type", "urn:ietf:params:oauth:grant-type:jwt-bearer")
	form.Set("assertion", assertion)
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, f.tokenURI, strings.NewReader(form.Encode()))
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	resp, err := f.client.Do(req)
	if err != nil {
		return "", fmt.Errorf("fcm : jeton OAuth : %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("fcm : jeton OAuth : statut %d", resp.StatusCode)
	}
	var tok struct {
		AccessToken string `json:"access_token"`
		ExpiresIn   int    `json:"expires_in"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&tok); err != nil || tok.AccessToken == "" {
		return "", errors.New("fcm : réponse OAuth invalide")
	}
	f.accessToken = tok.AccessToken
	f.expiresAt = time.Now().Add(time.Duration(tok.ExpiresIn) * time.Second)
	return f.accessToken, nil
}

func (f *FCM) signedJWT(now time.Time) (string, error) {
	enc := base64.RawURLEncoding
	header := enc.EncodeToString([]byte(`{"alg":"RS256","typ":"JWT"}`))
	claims, err := json.Marshal(map[string]any{
		"iss":   f.clientEmail,
		"scope": "https://www.googleapis.com/auth/firebase.messaging",
		"aud":   f.tokenURI,
		"iat":   now.Unix(),
		"exp":   now.Add(time.Hour).Unix(),
	})
	if err != nil {
		return "", err
	}
	signingInput := header + "." + enc.EncodeToString(claims)
	sum := sha256.Sum256([]byte(signingInput))
	sig, err := rsa.SignPKCS1v15(nil, f.key, crypto.SHA256, sum[:])
	if err != nil {
		return "", fmt.Errorf("fcm : signature JWT : %w", err)
	}
	return signingInput + "." + enc.EncodeToString(sig), nil
}
