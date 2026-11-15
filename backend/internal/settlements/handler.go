package settlements

import (
	"net/http"
	"time"

	"github.com/google/uuid"

	"ivia/backend/internal/platform/apperr"
	"ivia/backend/internal/platform/httpapi"
	"ivia/backend/internal/platform/identity"
)

// Handler expose les routes des relevés.
type Handler struct {
	svc *Service
}

// NewHandler crée le handler.
func NewHandler(svc *Service) *Handler { return &Handler{svc: svc} }

// Register enregistre les routes.
func (h *Handler) Register(rt *httpapi.Router) {
	rt.Roles("GET /v1/seller/shops/{id}/settlements", h.sellerList, identity.RoleSeller)
	rt.Roles("GET /v1/seller/settlements/{id}", h.sellerGet, identity.RoleSeller)

	rt.Roles("GET /v1/admin/settlements/preview", h.preview, identity.RoleAdmin)
	rt.Roles("GET /v1/admin/settlements", h.adminList, identity.RoleAdmin)
	rt.Roles("POST /v1/admin/settlements", h.create, identity.RoleAdmin)
	rt.Roles("GET /v1/admin/settlements/{id}", h.adminGet, identity.RoleAdmin)
	rt.Roles("POST /v1/admin/settlements/{id}/mark-settled", h.markSettled, identity.RoleAdmin)
	rt.Roles("DELETE /v1/admin/settlements/{id}", h.delete, identity.RoleAdmin)
}

func who(r *http.Request) uuid.UUID { return identity.MustFromContext(r.Context()).UserID }

func (h *Handler) sellerList(w http.ResponseWriter, r *http.Request) error {
	id, err := httpapi.PathUUID(r, "id")
	if err != nil {
		return err
	}
	q := httpapi.NewQuery(r)
	page := q.Page()
	if err := q.Err(); err != nil {
		return err
	}
	items, err := h.svc.ListForSeller(r.Context(), who(r), id, page.FetchLimit(), int32(page.Offset))
	if err != nil {
		return err
	}
	return httpapi.OK(w, httpapi.NewList(items, page))
}

func (h *Handler) sellerGet(w http.ResponseWriter, r *http.Request) error {
	id, err := httpapi.PathUUID(r, "id")
	if err != nil {
		return err
	}
	s, err := h.svc.GetForSeller(r.Context(), who(r), id)
	if err != nil {
		return err
	}
	return httpapi.OK(w, s)
}

func (h *Handler) preview(w http.ResponseWriter, r *http.Request) error {
	q := httpapi.NewQuery(r)
	q.Require("shop_id")
	q.Require("from")
	q.Require("to")
	shopID, from, to := q.UUID("shop_id"), q.Date("from"), q.Date("to")
	if err := q.Err(); err != nil {
		return err
	}
	s, err := h.svc.Preview(r.Context(), *shopID, *from, *to)
	if err != nil {
		return err
	}
	return httpapi.OK(w, s)
}

func (h *Handler) adminList(w http.ResponseWriter, r *http.Request) error {
	q := httpapi.NewQuery(r)
	page := q.Page()
	shopID := q.UUID("shop_id")
	status := q.Enum("status", "", "open", "settled")
	if err := q.Err(); err != nil {
		return err
	}
	items, err := h.svc.List(r.Context(), shopID, status, page.FetchLimit(), int32(page.Offset))
	if err != nil {
		return err
	}
	return httpapi.OK(w, httpapi.NewList(items, page))
}

func (h *Handler) create(w http.ResponseWriter, r *http.Request) error {
	var in struct {
		ShopID      uuid.UUID `json:"shop_id"`
		PeriodStart string    `json:"period_start"`
		PeriodEnd   string    `json:"period_end"`
		Note        string    `json:"note"`
	}
	if err := httpapi.Decode(r, &in); err != nil {
		return err
	}
	from, err1 := time.Parse(time.DateOnly, in.PeriodStart)
	to, err2 := time.Parse(time.DateOnly, in.PeriodEnd)
	if err1 != nil || err2 != nil {
		return apperr.Validation(map[string]string{"period_start": "Dates attendues au format AAAA-MM-JJ."})
	}
	s, err := h.svc.Create(r.Context(), who(r), in.ShopID, from, to, in.Note)
	if err != nil {
		return err
	}
	return httpapi.Created(w, s)
}

func (h *Handler) adminGet(w http.ResponseWriter, r *http.Request) error {
	id, err := httpapi.PathUUID(r, "id")
	if err != nil {
		return err
	}
	s, err := h.svc.Get(r.Context(), id)
	if err != nil {
		return err
	}
	return httpapi.OK(w, s)
}

func (h *Handler) markSettled(w http.ResponseWriter, r *http.Request) error {
	id, err := httpapi.PathUUID(r, "id")
	if err != nil {
		return err
	}
	var in struct {
		SettlementReference string `json:"settlement_reference"`
		Note                string `json:"note"`
	}
	if err := httpapi.Decode(r, &in); err != nil {
		return err
	}
	s, err := h.svc.MarkSettled(r.Context(), who(r), id, in.SettlementReference, in.Note)
	if err != nil {
		return err
	}
	return httpapi.OK(w, s)
}

func (h *Handler) delete(w http.ResponseWriter, r *http.Request) error {
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
	if err := h.svc.DeleteOpen(r.Context(), who(r), id, in.Reason); err != nil {
		return err
	}
	return httpapi.NoContent(w)
}
