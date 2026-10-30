// Package httpapi assemble le routeur HTTP de l'API : middlewares communs, authentification,
// contrôle des rôles, format des erreurs et routes transverses (santé).
package httpapi

import (
	"context"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"ivia/backend/internal/platform/apperr"
	"ivia/backend/internal/platform/identity"
)

// HandlerFunc est un handler qui retourne une erreur, traduite en réponse JSON par le routeur.
type HandlerFunc func(w http.ResponseWriter, r *http.Request) error

// Pinger vérifie qu'une dépendance (la base de données) répond.
type Pinger interface {
	Ping(ctx context.Context) error
}

// Authenticator retrouve l'utilisateur à partir d'un jeton de session (module auth).
type Authenticator interface {
	Authenticate(ctx context.Context, token string) (identity.Principal, error)
}

// Options du routeur.
type Options struct {
	Logger            *slog.Logger
	DB                Pinger
	Auth              Authenticator
	TrustProxyHeaders bool
	// MaxBodyBytes : taille maximale du corps d'une requête (1 Mo par défaut).
	MaxBodyBytes int64
}

// Router enregistre les routes des modules et applique les middlewares.
type Router struct {
	mux  *http.ServeMux
	opts Options
}

// NewRouter crée le routeur avec les routes de santé.
func NewRouter(opts Options) *Router {
	if opts.MaxBodyBytes == 0 {
		opts.MaxBodyBytes = 1 << 20
	}
	rt := &Router{mux: http.NewServeMux(), opts: opts}
	rt.mux.HandleFunc("GET /health", handleHealth)
	rt.mux.HandleFunc("GET /ready", handleReady(opts.Logger, opts.DB))
	return rt
}

// Handler retourne le handler HTTP complet, middlewares compris.
func (rt *Router) Handler() http.Handler {
	var h http.Handler = rt.mux
	h = rt.limitBody(h)
	h = rt.recoverPanics(h)
	h = rt.logRequests(h)
	h = rt.withClientIP(h)
	h = withRequestID(h)
	return h
}

// Logger retourne le logger du routeur.
func (rt *Router) Logger() *slog.Logger { return rt.opts.Logger }

// Public enregistre une route accessible sans authentification.
func (rt *Router) Public(pattern string, h HandlerFunc) {
	rt.mux.Handle(pattern, rt.wrap(h))
}

// Auth enregistre une route réservée aux utilisateurs connectés, quel que soit leur rôle.
func (rt *Router) Auth(pattern string, h HandlerFunc) {
	rt.mux.Handle(pattern, rt.wrap(rt.requireAuth(nil, h)))
}

// Roles enregistre une route réservée aux utilisateurs ayant au moins un des rôles.
func (rt *Router) Roles(pattern string, h HandlerFunc, roles ...identity.Role) {
	if len(roles) == 0 {
		panic("httpapi: Roles sans rôle pour " + pattern)
	}
	rt.mux.Handle(pattern, rt.wrap(rt.requireAuth(roles, h)))
}

// Raw enregistre un handler standard (webhooks, fichiers locaux) sans traduction d'erreur.
func (rt *Router) Raw(pattern string, h http.Handler) {
	rt.mux.Handle(pattern, h)
}

func (rt *Router) wrap(h HandlerFunc) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if err := h(w, r); err != nil {
			WriteError(w, r, rt.opts.Logger, err)
		}
	})
}

func (rt *Router) requireAuth(roles []identity.Role, next HandlerFunc) HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) error {
		token, ok := bearerToken(r)
		if !ok {
			return apperr.Unauthorized("unauthenticated", "Connectez-vous pour continuer.")
		}
		principal, err := rt.opts.Auth.Authenticate(r.Context(), token)
		if err != nil {
			return err
		}
		if len(roles) > 0 && !principal.HasRole(roles...) {
			return apperr.Forbidden("forbidden", "Votre compte n'a pas accès à cette fonctionnalité.")
		}
		return next(w, r.WithContext(identity.WithPrincipal(r.Context(), principal)))
	}
}

func bearerToken(r *http.Request) (string, bool) {
	h := r.Header.Get("Authorization")
	const prefix = "Bearer "
	if len(h) <= len(prefix) || !strings.EqualFold(h[:len(prefix)], prefix) {
		return "", false
	}
	token := strings.TrimSpace(h[len(prefix):])
	return token, token != ""
}

// handleHealth indique que le processus répond, sans solliciter la base.
func handleHealth(w http.ResponseWriter, _ *http.Request) {
	WriteJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

// handleReady indique que l'API peut servir des requêtes : la base doit répondre.
func handleReady(logger *slog.Logger, db Pinger) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
		defer cancel()
		if err := db.Ping(ctx); err != nil {
			logger.Error("base de données injoignable", "err", err)
			WriteJSON(w, http.StatusServiceUnavailable, map[string]string{"status": "unavailable"})
			return
		}
		WriteJSON(w, http.StatusOK, map[string]string{"status": "ok"})
	}
}
