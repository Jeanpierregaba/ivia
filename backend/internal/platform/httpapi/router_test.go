package httpapi

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"testing"
)

type fakeDB struct {
	err         error
	pinged      bool
	hasDeadline bool
}

func (f *fakeDB) Ping(ctx context.Context) error {
	f.pinged = true
	_, f.hasDeadline = ctx.Deadline()
	return f.err
}

func newTestHandler(db Pinger) http.Handler {
	return New(slog.New(slog.NewTextHandler(io.Discard, nil)), db)
}

func get(t *testing.T, h http.Handler, path string) (int, string) {
	t.Helper()
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, path, nil))
	if ct := rec.Header().Get("Content-Type"); ct != "application/json" {
		t.Fatalf("Content-Type = %q, attendu application/json", ct)
	}
	var body map[string]string
	if err := json.NewDecoder(rec.Body).Decode(&body); err != nil {
		t.Fatalf("corps JSON invalide : %v", err)
	}
	return rec.Code, body["status"]
}

func TestHealthDoesNotUseDatabase(t *testing.T) {
	db := &fakeDB{err: errors.New("connexion refusée")}
	code, status := get(t, newTestHandler(db), "/health")

	if code != http.StatusOK || status != "ok" {
		t.Fatalf("got %d %q, attendu 200 \"ok\"", code, status)
	}
	if db.pinged {
		t.Fatal("/health ne doit pas interroger la base")
	}
}

func TestReady(t *testing.T) {
	db := &fakeDB{}
	code, status := get(t, newTestHandler(db), "/ready")

	if code != http.StatusOK || status != "ok" {
		t.Fatalf("got %d %q, attendu 200 \"ok\"", code, status)
	}
	if !db.hasDeadline {
		t.Fatal("le ping de la base doit avoir un délai maximal")
	}
}

func TestReadyDatabaseDown(t *testing.T) {
	code, status := get(t, newTestHandler(&fakeDB{err: errors.New("connexion refusée")}), "/ready")

	if code != http.StatusServiceUnavailable || status != "unavailable" {
		t.Fatalf("got %d %q, attendu 503 \"unavailable\"", code, status)
	}
}

func TestHealthRejectsOtherMethods(t *testing.T) {
	rec := httptest.NewRecorder()
	newTestHandler(&fakeDB{}).ServeHTTP(rec, httptest.NewRequest(http.MethodPost, "/health", nil))

	if rec.Code != http.StatusMethodNotAllowed {
		t.Fatalf("status = %d, attendu %d", rec.Code, http.StatusMethodNotAllowed)
	}
}

func TestUnknownRoute(t *testing.T) {
	rec := httptest.NewRecorder()
	newTestHandler(&fakeDB{}).ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/inconnu", nil))

	if rec.Code != http.StatusNotFound {
		t.Fatalf("status = %d, attendu %d", rec.Code, http.StatusNotFound)
	}
}
