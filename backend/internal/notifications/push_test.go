package notifications

import (
	"context"
	"crypto"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestFCMSendsWithSignedOAuthToken(t *testing.T) {
	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatal(err)
	}
	der, _ := x509.MarshalPKCS8PrivateKey(key)
	pemKey := string(pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: der}))

	var tokenCalls int
	mux := http.NewServeMux()
	srv := httptest.NewServer(mux)
	defer srv.Close()

	mux.HandleFunc("POST /token", func(w http.ResponseWriter, r *http.Request) {
		tokenCalls++
		_ = r.ParseForm()
		parts := strings.Split(r.Form.Get("assertion"), ".")
		if len(parts) != 3 {
			http.Error(w, "jwt", 400)
			return
		}
		sig, _ := base64.RawURLEncoding.DecodeString(parts[2])
		sum := sha256.Sum256([]byte(parts[0] + "." + parts[1]))
		if err := rsa.VerifyPKCS1v15(&key.PublicKey, crypto.SHA256, sum[:], sig); err != nil {
			http.Error(w, "signature", 401)
			return
		}
		_ = json.NewEncoder(w).Encode(map[string]any{"access_token": "at-1", "expires_in": 3600})
	})
	mux.HandleFunc("POST /v1/projects/proj/messages:send", func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Authorization") != "Bearer at-1" {
			http.Error(w, "auth", 401)
			return
		}
		var body struct {
			Message struct {
				Token string `json:"token"`
			} `json:"message"`
		}
		_ = json.NewDecoder(r.Body).Decode(&body)
		if body.Message.Token == "mort" {
			w.WriteHeader(http.StatusNotFound)
			_, _ = w.Write([]byte(`{"error":{"status":"NOT_FOUND","details":[{"errorCode":"UNREGISTERED"}]}}`))
			return
		}
		_, _ = w.Write([]byte(`{"name":"projects/proj/messages/1"}`))
	})

	sa, _ := json.Marshal(map[string]string{
		"project_id": "proj", "client_email": "svc@proj.iam.gserviceaccount.com",
		"private_key": pemKey, "token_uri": srv.URL + "/token",
	})
	f, err := NewFCM(sa)
	if err != nil {
		t.Fatal(err)
	}
	f.endpoint = srv.URL
	ctx := context.Background()

	if err := f.Send(ctx, "jeton-ok", "Titre", "Corps", map[string]string{"kind": "x"}); err != nil {
		t.Fatalf("envoi : %v", err)
	}
	if err := f.Send(ctx, "jeton-ok", "Titre", "Corps", nil); err != nil {
		t.Fatalf("second envoi : %v", err)
	}
	if tokenCalls != 1 {
		t.Fatalf("le jeton OAuth doit être réutilisé : %d appels", tokenCalls)
	}
	if err := f.Send(ctx, "mort", "Titre", "Corps", nil); !errors.Is(err, ErrInvalidToken) {
		t.Fatalf("jeton désinstallé : %v, attendu ErrInvalidToken", err)
	}
}
