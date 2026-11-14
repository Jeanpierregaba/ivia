package geo

import (
	"net/http"

	"ivia/backend/internal/platform/httpapi"
	"ivia/backend/internal/platform/identity"
)

// Handler expose les routes des quartiers.
type Handler struct {
	svc *Service
}

// NewHandler crée le handler.
func NewHandler(svc *Service) *Handler { return &Handler{svc: svc} }

// Register enregistre les routes.
func (h *Handler) Register(rt *httpapi.Router) {
	rt.Public("GET /v1/neighborhoods", h.list)
	rt.Roles("GET /v1/admin/neighborhoods", h.listAll, identity.RoleAdmin)
	rt.Roles("POST /v1/admin/neighborhoods", h.create, identity.RoleAdmin)
	rt.Roles("PATCH /v1/admin/neighborhoods/{id}", h.update, identity.RoleAdmin)
}

func (h *Handler) list(w http.ResponseWriter, r *http.Request) error {
	items, err := h.svc.List(r.Context(), false)
	if err != nil {
		return err
	}
	return httpapi.OK(w, map[string]any{"items": items})
}

func (h *Handler) listAll(w http.ResponseWriter, r *http.Request) error {
	items, err := h.svc.List(r.Context(), true)
	if err != nil {
		return err
	}
	return httpapi.OK(w, map[string]any{"items": items})
}

func (h *Handler) create(w http.ResponseWriter, r *http.Request) error {
	var in NeighborhoodInput
	if err := httpapi.Decode(r, &in); err != nil {
		return err
	}
	n, err := h.svc.Create(r.Context(), identity.MustFromContext(r.Context()).UserID, in)
	if err != nil {
		return err
	}
	return httpapi.Created(w, n)
}

func (h *Handler) update(w http.ResponseWriter, r *http.Request) error {
	id, err := httpapi.PathUUID(r, "id")
	if err != nil {
		return err
	}
	var in NeighborhoodInput
	if err := httpapi.Decode(r, &in); err != nil {
		return err
	}
	n, err := h.svc.Update(r.Context(), identity.MustFromContext(r.Context()).UserID, id, in)
	if err != nil {
		return err
	}
	return httpapi.OK(w, n)
}
