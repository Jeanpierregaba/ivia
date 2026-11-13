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
	// Reporter : remontée des erreurs inattendues (Sentry) ; aucune si nil.
	Reporter ErrorReporter
}

// ErrorReporter signale une erreur inattendue (implémenté par errtrack).
type ErrorReporter interface {
	Report(ctx context.Context, err error, tags map[string]string)
}

func (rt *Router) report(r *http.Request, err error) {
	if rt.opts.Reporter == nil {
		return
	}
	rt.opts.Reporter.Report(r.Context(), err, map[string]string{
		"request_id": RequestID(r.Context()),
		// Motif de la route (ex. GET /v1/orders/{id}) : jamais l'URL réelle, qui peut contenir des données.
		"route": r.Pattern,
	})
}

// Router enregistre les routes des modules et applique les middlewares.
type Router struct {
	mux      *http.ServeMux
	opts     Options
	patterns []string
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

// Patterns retourne les routes enregistrées (« MÉTHODE /chemin »), pour vérifier le contrat OpenAPI.
func (rt *Router) Patterns() []string { return rt.patterns }

func (rt *Router) handle(pattern string, h http.Handler) {
	rt.patterns = append(rt.patterns, pattern)
	rt.mux.Handle(pattern, h)
}

// Logger retourne le logger du routeur.
func (rt *Router) Logger() *slog.Logger { return rt.opts.Logger }

// Public enregistre une route accessible sans authentification.
func (rt *Router) Public(pattern string, h HandlerFunc) {
	rt.handle(pattern, rt.wrap(h))
}

// Auth enregistre une route réservée aux utilisateurs connectés, quel que soit leur rôle.
func (rt *Router) Auth(pattern string, h HandlerFunc) {
	rt.handle(pattern, rt.wrap(rt.requireAuth(nil, h)))
}

// Roles enregistre une route réservée aux utilisateurs ayant au moins un des rôles.
func (rt *Router) Roles(pattern string, h HandlerFunc, roles ...identity.Role) {
	if len(roles) == 0 {
		panic("httpapi: Roles sans rôle pour " + pattern)
	}
	rt.handle(pattern, rt.wrap(rt.requireAuth(roles, h)))
}

// Raw enregistre un handler standard (webhooks, fichiers locaux) sans traduction d'erreur.
func (rt *Router) Raw(pattern string, h http.Handler) {
	rt.handle(pattern, h)
}

func (rt *Router) wrap(h HandlerFunc) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if err := h(w, r); err != nil {
			if IsInternal(r, err) {
				rt.report(r, err)
			}
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
		// Routes réservées aux admins : la session doit avoir passé la double vérification par
		// code (ADR 0011) ; un mot de passe volé ne suffit pas.
		if adminOnly(roles) && !principal.MFA {
			return apperr.Forbidden("mfa_required", "Confirmez votre connexion avec votre application d'authentification ou le code reçu par e-mail.")
		}
		return next(w, r.WithContext(identity.WithPrincipal(r.Context(), principal)))
	}
}

func adminOnly(roles []identity.Role) bool {
	return len(roles) == 1 && roles[0] == identity.RoleAdmin
}

// WSProtocol : sous-protocole WebSocket qui porte le jeton depuis un navigateur, qui ne peut pas
// envoyer d'en-tête Authorization : `new WebSocket(url, ["ivia-bearer", jeton])`. Le jeton ne passe
// jamais dans l'URL (journaux).
const WSProtocol = "ivia-bearer"

func bearerToken(r *http.Request) (string, bool) {
	if r.Header.Get("Authorization") == "" && strings.EqualFold(r.Header.Get("Upgrade"), "websocket") {
		parts := strings.Split(r.Header.Get("Sec-WebSocket-Protocol"), ",")
		if len(parts) == 2 && strings.TrimSpace(parts[0]) == WSProtocol {
			token := strings.TrimSpace(parts[1])
			return token, token != ""
		}
	}
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
