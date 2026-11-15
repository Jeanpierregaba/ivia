package promo

import (
	"net/http"
	"time"

	"ivia/backend/internal/platform/apperr"
	"ivia/backend/internal/platform/httpapi"
	"ivia/backend/internal/platform/identity"
	"ivia/backend/internal/platform/ratelimit"
)

// Lome : fuseau des périodes de statistiques.
var Lome = func() *time.Location {
	loc, err := time.LoadLocation("Africa/Lome")
	if err != nil {
		return time.FixedZone("Africa/Lome", 0)
	}
	return loc
}()

// Limites des routes publiques, par adresse IP.
const (
	FeedPerIPPerMinute   = 60
	EventsPerIPPerMinute = 60
)

// Handler expose les routes de la publicité.
type Handler struct {
	svc    *Service
	feed   *ratelimit.Limiter
	events *ratelimit.Limiter
}

// NewHandler crée le handler.
func NewHandler(svc *Service) *Handler {
	return &Handler{svc: svc, feed: ratelimit.New(FeedPerIPPerMinute, time.Minute), events: ratelimit.New(EventsPerIPPerMinute, time.Minute)}
}

// Register enregistre les routes.
func (h *Handler) Register(rt *httpapi.Router) {
	rt.Public("GET /v1/promo/feed", h.getFeed)
	rt.Public("POST /v1/promo/events", h.postEvents)

	rt.Roles("GET /v1/admin/promo/visuals", h.listVisuals, identity.RoleAdmin)
	rt.Roles("POST /v1/admin/promo/visuals", h.createVisual, identity.RoleAdmin)
	rt.Roles("GET /v1/admin/promo/visuals/{id}", h.getVisual, identity.RoleAdmin)
	rt.Roles("PATCH /v1/admin/promo/visuals/{id}", h.updateVisual, identity.RoleAdmin)
	rt.Roles("DELETE /v1/admin/promo/visuals/{id}", h.deleteVisual, identity.RoleAdmin)
	rt.Roles("GET /v1/admin/promo/settings", h.getSettings, identity.RoleAdmin)
	rt.Roles("PUT /v1/admin/promo/settings", h.putSettings, identity.RoleAdmin)
	rt.Roles("GET /v1/admin/promo/stats", h.stats, identity.RoleAdmin)
}

func principal(r *http.Request) identity.Principal { return identity.MustFromContext(r.Context()) }

func limit(l *ratelimit.Limiter, r *http.Request) error {
	if ok, retry := l.Allow(httpapi.ClientIP(r.Context())); !ok {
		return apperr.TooManyRequests("rate_limited", "Trop de requêtes. Patientez un instant.", retry)
	}
	return nil
}

func (h *Handler) getFeed(w http.ResponseWriter, r *http.Request) error {
	if err := limit(h.feed, r); err != nil {
		return err
	}
	q := httpapi.NewQuery(r)
	app := q.Enum("app", "buyer", Apps...)
	if err := q.Err(); err != nil {
		return err
	}
	f, err := h.svc.Feed(r.Context(), app)
	if err != nil {
		return err
	}
	return httpapi.OK(w, f)
}

func (h *Handler) postEvents(w http.ResponseWriter, r *http.Request) error {
	if err := limit(h.events, r); err != nil {
		return err
	}
	var in struct {
		App       string  `json:"app"`
		SessionID string  `json:"session_id"`
		Events    []Event `json:"events"`
	}
	if err := httpapi.Decode(r, &in); err != nil {
		return err
	}
	n, err := h.svc.RecordEvents(r.Context(), in.App, in.SessionID, in.Events)
	if err != nil {
		return err
	}
	return httpapi.OK(w, map[string]any{"recorded": n})
}

func (h *Handler) listVisuals(w http.ResponseWriter, r *http.Request) error {
	items, err := h.svc.ListVisuals(r.Context())
	if err != nil {
		return err
	}
	return httpapi.OK(w, map[string]any{"items": items})
}

func (h *Handler) getVisual(w http.ResponseWriter, r *http.Request) error {
	id, err := httpapi.PathUUID(r, "id")
	if err != nil {
		return err
	}
	v, err := h.svc.GetVisual(r.Context(), id)
	if err != nil {
		return err
	}
	return httpapi.OK(w, v)
}

func (h *Handler) createVisual(w http.ResponseWriter, r *http.Request) error {
	var in VisualInput
	if err := httpapi.Decode(r, &in); err != nil {
		return err
	}
	v, err := h.svc.CreateVisual(r.Context(), principal(r).UserID, in)
	if err != nil {
		return err
	}
	return httpapi.Created(w, v)
}

func (h *Handler) updateVisual(w http.ResponseWriter, r *http.Request) error {
	id, err := httpapi.PathUUID(r, "id")
	if err != nil {
		return err
	}
	var in VisualInput
	if err := httpapi.Decode(r, &in); err != nil {
		return err
	}
	v, err := h.svc.UpdateVisual(r.Context(), principal(r).UserID, id, in)
	if err != nil {
		return err
	}
	return httpapi.OK(w, v)
}

func (h *Handler) deleteVisual(w http.ResponseWriter, r *http.Request) error {
	id, err := httpapi.PathUUID(r, "id")
	if err != nil {
		return err
	}
	if err := h.svc.DeleteVisual(r.Context(), principal(r).UserID, id); err != nil {
		return err
	}
	return httpapi.NoContent(w)
}

func (h *Handler) getSettings(w http.ResponseWriter, r *http.Request) error {
	s, err := h.svc.GetSettings(r.Context())
	if err != nil {
		return err
	}
	return httpapi.OK(w, s)
}

func (h *Handler) putSettings(w http.ResponseWriter, r *http.Request) error {
	var in Settings
	if err := httpapi.Decode(r, &in); err != nil {
		return err
	}
	s, err := h.svc.UpdateSettings(r.Context(), principal(r).UserID, in)
	if err != nil {
		return err
	}
	return httpapi.OK(w, s)
}

// stats : période en dates de Lomé (from et to inclus), 30 derniers jours par défaut.
func (h *Handler) stats(w http.ResponseWriter, r *http.Request) error {
	q := httpapi.NewQuery(r)
	from, to := q.Date("from"), q.Date("to")
	if err := q.Err(); err != nil {
		return err
	}
	now := time.Now().In(Lome)
	today := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, Lome)
	start, end := today.AddDate(0, 0, -29), today
	if from != nil {
		start = time.Date(from.Year(), from.Month(), from.Day(), 0, 0, 0, 0, Lome)
	}
	if to != nil {
		end = time.Date(to.Year(), to.Month(), to.Day(), 0, 0, 0, 0, Lome)
	}
	if end.Before(start) || end.Sub(start) > 366*24*time.Hour {
		return apperr.Validation(map[string]string{"to": "Période invalide (un an au plus)."})
	}
	st, err := h.svc.Stats(r.Context(), start, end.AddDate(0, 0, 1))
	if err != nil {
		return err
	}
	return httpapi.OK(w, st)
}
