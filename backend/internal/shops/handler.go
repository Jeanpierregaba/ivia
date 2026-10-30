package shops

import (
	"net/http"

	"ivia/backend/internal/platform/httpapi"
	"ivia/backend/internal/platform/identity"
)

// Handler expose les routes des boutiques.
type Handler struct {
	svc *Service
}

// NewHandler crée le handler.
func NewHandler(svc *Service) *Handler { return &Handler{svc: svc} }

// Register enregistre les routes.
func (h *Handler) Register(rt *httpapi.Router) {
	rt.Public("GET /v1/shops/{id}", h.getPublic)
	rt.Auth("POST /v1/shops", h.create)
	rt.Roles("GET /v1/seller/shops", h.listMine, identity.RoleSeller)
	rt.Roles("GET /v1/seller/shops/{id}", h.getMine, identity.RoleSeller)
	rt.Roles("PATCH /v1/seller/shops/{id}", h.update, identity.RoleSeller)

	rt.Roles("GET /v1/admin/shops", h.adminList, identity.RoleAdmin)
	rt.Roles("GET /v1/admin/shops/{id}", h.adminGet, identity.RoleAdmin)
	for _, d := range []string{"approve", "reject", "suspend", "reinstate"} {
		rt.Roles("POST /v1/admin/shops/{id}/"+d, h.review(d), identity.RoleAdmin)
	}
}

func (h *Handler) getPublic(w http.ResponseWriter, r *http.Request) error {
	id, err := httpapi.PathUUID(r, "id")
	if err != nil {
		return err
	}
	shop, err := h.svc.RequirePublished(r.Context(), id)
	if err != nil {
		return err
	}
	return httpapi.OK(w, shop.Public())
}

func (h *Handler) create(w http.ResponseWriter, r *http.Request) error {
	var in Input
	if err := httpapi.Decode(r, &in); err != nil {
		return err
	}
	shop, err := h.svc.Create(r.Context(), identity.MustFromContext(r.Context()).UserID, in)
	if err != nil {
		return err
	}
	return httpapi.Created(w, shop)
}

func (h *Handler) listMine(w http.ResponseWriter, r *http.Request) error {
	items, err := h.svc.ListMine(r.Context(), identity.MustFromContext(r.Context()).UserID)
	if err != nil {
		return err
	}
	return httpapi.OK(w, map[string]any{"items": items})
}

func (h *Handler) getMine(w http.ResponseWriter, r *http.Request) error {
	id, err := httpapi.PathUUID(r, "id")
	if err != nil {
		return err
	}
	shop, err := h.svc.Get(r.Context(), id)
	if err != nil {
		return err
	}
	if shop.OwnerID != identity.MustFromContext(r.Context()).UserID {
		return errNotFound
	}
	return httpapi.OK(w, shop)
}

func (h *Handler) update(w http.ResponseWriter, r *http.Request) error {
	id, err := httpapi.PathUUID(r, "id")
	if err != nil {
		return err
	}
	var in Input
	if err := httpapi.Decode(r, &in); err != nil {
		return err
	}
	shop, err := h.svc.Update(r.Context(), identity.MustFromContext(r.Context()).UserID, id, in)
	if err != nil {
		return err
	}
	return httpapi.OK(w, shop)
}

func (h *Handler) adminList(w http.ResponseWriter, r *http.Request) error {
	q := httpapi.NewQuery(r)
	page := q.Page()
	status := Status(q.Enum("status", "", "pending_review", "published", "rejected", "suspended"))
	search := q.String("q", 100)
	if err := q.Err(); err != nil {
		return err
	}
	items, err := h.svc.AdminList(r.Context(), status, search, page.FetchLimit(), int32(page.Offset))
	if err != nil {
		return err
	}
	return httpapi.OK(w, httpapi.NewList(items, page))
}

func (h *Handler) adminGet(w http.ResponseWriter, r *http.Request) error {
	id, err := httpapi.PathUUID(r, "id")
	if err != nil {
		return err
	}
	shop, err := h.svc.Get(r.Context(), id)
	if err != nil {
		return err
	}
	return httpapi.OK(w, shop)
}

func (h *Handler) review(decision string) httpapi.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) error {
		id, err := httpapi.PathUUID(r, "id")
		if err != nil {
			return err
		}
		var in struct {
			Reason string `json:"reason"`
		}
		if err := httpapi.Decode(r, &in); err != nil {
			return err
		}
		shop, err := h.svc.Review(r.Context(), identity.MustFromContext(r.Context()).UserID, id, decision, in.Reason)
		if err != nil {
			return err
		}
		return httpapi.OK(w, shop)
	}
}
