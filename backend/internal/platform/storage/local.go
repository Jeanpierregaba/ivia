package storage

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

// Local implémente ObjectStore sur le disque, pour le développement : l'API sert elle-même les
// URL signées (routes /dev/storage/...), ce qui permet de tester les apps sans compte R2.
type Local struct {
	dir     string
	baseURL string
	secret  []byte
	now     func() time.Time
}

// NewLocal crée un stockage local dans dir ; baseURL est l'adresse publique de l'API.
func NewLocal(dir, baseURL string, secret []byte) *Local {
	return &Local{dir: dir, baseURL: strings.TrimRight(baseURL, "/"), secret: secret, now: time.Now}
}

func (l *Local) sign(method string, vis Visibility, key, contentType string, size int64, expires int64) string {
	h := hmac.New(sha256.New, l.secret)
	fmt.Fprintf(h, "%s\n%s\n%s\n%s\n%d\n%d", method, vis, key, contentType, size, expires)
	return hex.EncodeToString(h.Sum(nil))
}

func (l *Local) objectURL(vis Visibility, key string) string {
	return l.baseURL + "/dev/storage/" + string(vis) + "/" + escapePath(key)
}

// PresignPut implémente ObjectStore.
func (l *Local) PresignPut(_ context.Context, vis Visibility, key, contentType string, size int64, ttl time.Duration) (PresignedRequest, error) {
	exp := l.now().Add(ttl)
	q := url.Values{}
	q.Set("expires", strconv.FormatInt(exp.Unix(), 10))
	q.Set("sig", l.sign(http.MethodPut, vis, key, contentType, size, exp.Unix()))
	return PresignedRequest{
		Method:    http.MethodPut,
		URL:       l.objectURL(vis, key) + "?" + q.Encode(),
		Headers:   map[string]string{"Content-Type": contentType, "Content-Length": strconv.FormatInt(size, 10)},
		ExpiresAt: exp,
	}, nil
}

// PresignGet implémente ObjectStore.
func (l *Local) PresignGet(_ context.Context, key string, ttl time.Duration) (string, error) {
	exp := l.now().Add(ttl).Unix()
	q := url.Values{}
	q.Set("expires", strconv.FormatInt(exp, 10))
	q.Set("sig", l.sign(http.MethodGet, Private, key, "", 0, exp))
	return l.objectURL(Private, key) + "?" + q.Encode(), nil
}

// PublicURL implémente ObjectStore.
func (l *Local) PublicURL(key string) string { return l.objectURL(Public, key) }

// Exists implémente ObjectStore.
func (l *Local) Exists(_ context.Context, vis Visibility, key string) (bool, error) {
	p, err := l.path(vis, key)
	if err != nil {
		return false, nil
	}
	_, err = os.Stat(p)
	if errors.Is(err, os.ErrNotExist) {
		return false, nil
	}
	return err == nil, err
}

// Write dépose un fichier directement (données de démonstration en local, cmd/manage seed-dev).
func (l *Local) Write(vis Visibility, key string, data []byte) error {
	p, err := l.path(vis, key)
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
		return err
	}
	return os.WriteFile(p, data, 0o644)
}

// Delete implémente ObjectStore.
func (l *Local) Delete(_ context.Context, vis Visibility, key string) error {
	p, err := l.path(vis, key)
	if err != nil {
		return err
	}
	if err := os.Remove(p); err != nil && !errors.Is(err, os.ErrNotExist) {
		return err
	}
	return nil
}

func (l *Local) path(vis Visibility, key string) (string, error) {
	if vis != Public && vis != Private {
		return "", errors.New("compartiment inconnu")
	}
	clean := filepath.Clean(filepath.FromSlash(key))
	if clean == "." || strings.HasPrefix(clean, "..") || filepath.IsAbs(clean) {
		return "", errors.New("clé invalide")
	}
	return filepath.Join(l.dir, string(vis), clean), nil
}

// Handler sert les envois (PUT) et lectures (GET) signés. Monté sur /dev/storage/ en local uniquement.
func (l *Local) Handler() http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		rest := strings.TrimPrefix(r.URL.Path, "/dev/storage/")
		visStr, key, ok := strings.Cut(rest, "/")
		vis := Visibility(visStr)
		p, err := l.path(vis, key)
		if !ok || err != nil {
			http.NotFound(w, r)
			return
		}
		exp, _ := strconv.ParseInt(r.URL.Query().Get("expires"), 10, 64)
		sig := r.URL.Query().Get("sig")
		expired := l.now().Unix() > exp

		switch r.Method {
		case http.MethodPut:
			ct := r.Header.Get("Content-Type")
			want := l.sign(http.MethodPut, vis, key, ct, r.ContentLength, exp)
			if expired || !hmac.Equal([]byte(sig), []byte(want)) {
				http.Error(w, "signature invalide ou expirée", http.StatusForbidden)
				return
			}
			if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
				http.Error(w, "écriture impossible", http.StatusInternalServerError)
				return
			}
			f, err := os.Create(p)
			if err != nil {
				http.Error(w, "écriture impossible", http.StatusInternalServerError)
				return
			}
			defer f.Close()
			if _, err := io.Copy(f, io.LimitReader(r.Body, r.ContentLength)); err != nil {
				http.Error(w, "écriture impossible", http.StatusInternalServerError)
				return
			}
			w.WriteHeader(http.StatusOK)
		case http.MethodGet, http.MethodHead:
			if vis == Private {
				want := l.sign(http.MethodGet, Private, key, "", 0, exp)
				if expired || !hmac.Equal([]byte(sig), []byte(want)) {
					http.Error(w, "signature invalide ou expirée", http.StatusForbidden)
					return
				}
			}
			http.ServeFile(w, r, p)
		default:
			http.Error(w, "méthode non permise", http.StatusMethodNotAllowed)
		}
	})
}

var _ ObjectStore = (*Local)(nil)
