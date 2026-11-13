package httpapi

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/google/uuid"

	"ivia/backend/internal/platform/apperr"
	"ivia/backend/internal/platform/identity"
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

type fakeAuth struct{}

func (fakeAuth) Authenticate(_ context.Context, token string) (identity.Principal, error) {
	switch token {
	case "buyer":
		return identity.Principal{UserID: uuid.New(), Roles: []identity.Role{identity.RoleBuyer}}, nil
	case "admin":
		return identity.Principal{UserID: uuid.New(), Roles: []identity.Role{identity.RoleAdmin}, MFA: true, AdminRole: "super_admin"}, nil
	case "admin-carte":
		return identity.Principal{UserID: uuid.New(), Roles: []identity.Role{identity.RoleAdmin}, MFA: true, AdminRole: "map"}, nil
	case "admin-sans-code":
		return identity.Principal{UserID: uuid.New(), Roles: []identity.Role{identity.RoleAdmin}}, nil
	}
	return identity.Principal{}, apperr.Unauthorized("invalid_session", "Session expirée.")
}

func newTestRouter(db Pinger) *Router {
	return NewRouter(Options{Logger: slog.New(slog.NewTextHandler(io.Discard, nil)), DB: db, Auth: fakeAuth{}, MaxBodyBytes: 64})
}

func do(t *testing.T, h http.Handler, method, path, token, body string) (*httptest.ResponseRecorder, map[string]any) {
	t.Helper()
	req := httptest.NewRequest(method, path, strings.NewReader(body))
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	var out map[string]any
	_ = json.Unmarshal(rec.Body.Bytes(), &out)
	return rec, out
}

func errorCode(body map[string]any) string {
	e, _ := body["error"].(map[string]any)
	code, _ := e["code"].(string)
	return code
}

func TestHealthDoesNotUseDatabase(t *testing.T) {
	db := &fakeDB{err: errors.New("connexion refusée")}
	rec, body := do(t, newTestRouter(db).Handler(), http.MethodGet, "/health", "", "")
	if rec.Code != http.StatusOK || body["status"] != "ok" {
		t.Fatalf("got %d %v, attendu 200 ok", rec.Code, body)
	}
	if db.pinged {
		t.Fatal("/health ne doit pas interroger la base")
	}
	if rec.Header().Get("X-Request-Id") == "" {
		t.Fatal("chaque réponse doit porter un identifiant de requête")
	}
}

func TestReady(t *testing.T) {
	db := &fakeDB{}
	rec, body := do(t, newTestRouter(db).Handler(), http.MethodGet, "/ready", "", "")
	if rec.Code != http.StatusOK || body["status"] != "ok" {
		t.Fatalf("got %d %v", rec.Code, body)
	}
	if !db.hasDeadline {
		t.Fatal("le ping de la base doit avoir un délai maximal")
	}
}

func TestReadyDatabaseDown(t *testing.T) {
	rec, body := do(t, newTestRouter(&fakeDB{err: errors.New("down")}).Handler(), http.MethodGet, "/ready", "", "")
	if rec.Code != http.StatusServiceUnavailable || body["status"] != "unavailable" {
		t.Fatalf("got %d %v", rec.Code, body)
	}
}

func TestMethodAndUnknownRoute(t *testing.T) {
	h := newTestRouter(&fakeDB{}).Handler()
	if rec, _ := do(t, h, http.MethodPost, "/health", "", ""); rec.Code != http.StatusMethodNotAllowed {
		t.Fatalf("POST /health : %d", rec.Code)
	}
	if rec, _ := do(t, h, http.MethodGet, "/inconnu", "", ""); rec.Code != http.StatusNotFound {
		t.Fatalf("route inconnue : %d", rec.Code)
	}
}

func TestAuthAndRoles(t *testing.T) {
	rt := newTestRouter(&fakeDB{})
	ok := func(w http.ResponseWriter, r *http.Request) error {
		return OK(w, map[string]string{"user": identity.MustFromContext(r.Context()).UserID.String()})
	}
	rt.Auth("GET /v1/me", ok)
	rt.Roles("GET /v1/admin/x", ok, identity.RoleAdmin)
	h := rt.Handler()

	cases := []struct {
		path, token string
		status      int
		code        string
	}{
		{"/v1/me", "", http.StatusUnauthorized, "unauthenticated"},
		{"/v1/me", "inconnu", http.StatusUnauthorized, "invalid_session"},
		{"/v1/me", "buyer", http.StatusOK, ""},
		{"/v1/admin/x", "buyer", http.StatusForbidden, "forbidden"},
		{"/v1/admin/x", "admin", http.StatusOK, ""},
		{"/v1/admin/x", "admin-carte", http.StatusForbidden, "admin_scope"},
		// Mot de passe seul : la double vérification par code est exigée (ADR 0011).
		{"/v1/admin/x", "admin-sans-code", http.StatusForbidden, "mfa_required"},
		{"/v1/me", "admin-sans-code", http.StatusOK, ""},
	}
	for _, c := range cases {
		rec, body := do(t, h, http.MethodGet, c.path, c.token, "")
		if rec.Code != c.status || errorCode(body) != c.code {
			t.Errorf("%s avec %q : %d %q, attendu %d %q", c.path, c.token, rec.Code, errorCode(body), c.status, c.code)
		}
	}
}

func TestDecodeErrorsAndInternalErrors(t *testing.T) {
	rt := newTestRouter(&fakeDB{})
	rt.Public("POST /echo", func(w http.ResponseWriter, r *http.Request) error {
		var in struct {
			Name string `json:"name"`
		}
		if err := Decode(r, &in); err != nil {
			return err
		}
		return OK(w, in)
	})
	rt.Public("GET /boom", func(http.ResponseWriter, *http.Request) error {
		return errors.New("détail interne SQL")
	})
	rt.Public("GET /panic", func(http.ResponseWriter, *http.Request) error { panic("oups") })
	h := rt.Handler()

	if rec, body := do(t, h, http.MethodPost, "/echo", "", `{"name":"a","x":1}`); rec.Code != 400 || errorCode(body) != "invalid_json" {
		t.Errorf("champ inconnu : %d %v", rec.Code, body)
	}
	if rec, body := do(t, h, http.MethodPost, "/echo", "", `{"name":12}`); rec.Code != 400 || errorCode(body) != "validation_failed" {
		t.Errorf("mauvais type : %d %v", rec.Code, body)
	}
	if rec, body := do(t, h, http.MethodPost, "/echo", "", `{"name":"`+strings.Repeat("a", 100)+`"}`); rec.Code != 413 || errorCode(body) != "body_too_large" {
		t.Errorf("corps trop gros : %d %v", rec.Code, body)
	}
	rec, body := do(t, h, http.MethodGet, "/boom", "", "")
	if rec.Code != 500 || errorCode(body) != "internal_error" || strings.Contains(rec.Body.String(), "SQL") {
		t.Errorf("erreur interne : %d %s", rec.Code, rec.Body.String())
	}
	if rec, body := do(t, h, http.MethodGet, "/panic", "", ""); rec.Code != 500 || errorCode(body) != "internal_error" {
		t.Errorf("panique : %d %v", rec.Code, body)
	}
}

func TestNewList(t *testing.T) {
	l := NewList([]int{1, 2, 3}, Page{Limit: 2, Offset: 4})
	if len(l.Items) != 2 || l.NextOffset == nil || *l.NextOffset != 6 {
		t.Fatalf("page : %+v", l)
	}
	l = NewList([]int(nil), Page{Limit: 2})
	if l.Items == nil || l.NextOffset != nil {
		t.Fatalf("page vide : %+v", l)
	}
}

type fakeReporter struct {
	errs []error
	tags []map[string]string
}

func (f *fakeReporter) Report(_ context.Context, err error, tags map[string]string) {
	f.errs = append(f.errs, err)
	f.tags = append(f.tags, tags)
}

func TestUnexpectedErrorsAreReported(t *testing.T) {
	rep := &fakeReporter{}
	rt := NewRouter(Options{Logger: slog.New(slog.NewTextHandler(io.Discard, nil)), DB: &fakeDB{}, Auth: fakeAuth{}, Reporter: rep})
	rt.Public("GET /boom/{id}", func(http.ResponseWriter, *http.Request) error { return errors.New("panne SQL") })
	rt.Public("GET /metier", func(http.ResponseWriter, *http.Request) error {
		return apperr.NotFound("order_not_found", "Commande introuvable.")
	})
	rt.Public("GET /panic", func(http.ResponseWriter, *http.Request) error { panic("oups") })
	h := rt.Handler()

	do(t, h, http.MethodGet, "/metier", "", "")
	if len(rep.errs) != 0 {
		t.Fatal("une erreur métier (4xx) ne doit pas être signalée")
	}
	do(t, h, http.MethodGet, "/boom/ama@example.tg", "", "")
	do(t, h, http.MethodGet, "/panic", "", "")
	if len(rep.errs) != 2 {
		t.Fatalf("%d erreurs signalées, attendu 2 (erreur interne et panique)", len(rep.errs))
	}
	if rep.tags[0]["route"] != "GET /boom/{id}" || rep.tags[0]["request_id"] == "" {
		t.Fatalf("étiquettes : %v", rep.tags[0])
	}
	for _, tags := range rep.tags {
		for _, v := range tags {
			if strings.Contains(v, "@") {
				t.Fatalf("l'URL réelle (donnée personnelle) ne doit pas partir : %v", tags)
			}
		}
	}
}
