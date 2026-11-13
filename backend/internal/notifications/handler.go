package notifications

import (
	"net/http"

	"ivia/backend/internal/platform/apperr"
	"ivia/backend/internal/platform/httpapi"
	"ivia/backend/internal/platform/identity"
)

// Handler expose la liste des notifications.
type Handler struct {
	svc *Service
}

// NewHandler crée le handler.
func NewHandler(svc *Service) *Handler { return &Handler{svc: svc} }

// Register enregistre les routes.
func (h *Handler) Register(rt *httpapi.Router) {
	rt.Auth("GET /v1/notifications", h.list)
	rt.Auth("POST /v1/notifications/{id}/read", h.markRead)
	rt.Auth("POST /v1/notifications/read-all", h.markAllRead)
	rt.Auth("DELETE /v1/notifications/{id}", h.delete)
	rt.Auth("DELETE /v1/notifications", h.deleteAll)
	rt.Auth("GET /v1/ws/events", h.events)
	rt.Roles("GET /v1/admin/stream", h.adminStream, identity.RoleAdmin)
}

// appParam lit l'app concernée et vérifie que l'utilisateur a le rôle correspondant.
func appParam(r *http.Request, q *httpapi.Query) (App, error) {
	app := App(q.Enum("app", "buyer", "buyer", "seller", "driver", "admin", "pharmacy"))
	if err := q.Err(); err != nil {
		return "", err
	}
	p := identity.MustFromContext(r.Context())
	required := map[App]identity.Role{
		AppBuyer: identity.RoleBuyer, AppSeller: identity.RoleSeller,
		AppDriver: identity.RoleDriver, AppAdmin: identity.RoleAdmin, AppPharmacy: identity.RolePharmacist,
	}[app]
	if !p.HasRole(required) {
		return "", apperr.Forbidden("forbidden", "Votre compte n'a pas accès à cette fonctionnalité.")
	}
	return app, nil
}

func (h *Handler) list(w http.ResponseWriter, r *http.Request) error {
	q := httpapi.NewQuery(r)
	page := q.Page()
	app, err := appParam(r, q)
	if err != nil {
		return err
	}
	items, unread, err := h.svc.List(r.Context(), identity.MustFromContext(r.Context()).UserID, app, page.FetchLimit(), int32(page.Offset))
	if err != nil {
		return err
	}
	l := httpapi.NewList(items, page)
	return httpapi.OK(w, map[string]any{"items": l.Items, "next_offset": l.NextOffset, "unread_count": unread})
}

func (h *Handler) markRead(w http.ResponseWriter, r *http.Request) error {
	id, err := httpapi.PathUUID(r, "id")
	if err != nil {
		return err
	}
	if err := h.svc.MarkRead(r.Context(), identity.MustFromContext(r.Context()).UserID, id); err != nil {
		return err
	}
	return httpapi.NoContent(w)
}

func (h *Handler) delete(w http.ResponseWriter, r *http.Request) error {
	id, err := httpapi.PathUUID(r, "id")
	if err != nil {
		return err
	}
	if err := h.svc.Delete(r.Context(), identity.MustFromContext(r.Context()).UserID, id); err != nil {
		return err
	}
	return httpapi.NoContent(w)
}

func (h *Handler) deleteAll(w http.ResponseWriter, r *http.Request) error {
	app, err := appParam(r, httpapi.NewQuery(r))
	if err != nil {
		return err
	}
	if err := h.svc.DeleteAll(r.Context(), identity.MustFromContext(r.Context()).UserID, app); err != nil {
		return err
	}
	return httpapi.NoContent(w)
}

func (h *Handler) markAllRead(w http.ResponseWriter, r *http.Request) error {
	app, err := appParam(r, httpapi.NewQuery(r))
	if err != nil {
		return err
	}
	if err := h.svc.MarkAllRead(r.Context(), identity.MustFromContext(r.Context()).UserID, app); err != nil {
		return err
	}
	return httpapi.NoContent(w)
}
