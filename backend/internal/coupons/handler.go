package coupons

import (
	"net/http"

	"github.com/google/uuid"

	"ivia/backend/internal/platform/httpapi"
	"ivia/backend/internal/platform/identity"
)

// Handler expose les codes promo.
type Handler struct {
	svc *Service
}

// NewHandler crée le handler.
func NewHandler(svc *Service) *Handler { return &Handler{svc: svc} }

// Register enregistre les routes.
func (h *Handler) Register(rt *httpapi.Router) {
	rt.Roles("GET /v1/me/coupons", h.mine, identity.RoleBuyer)

	rt.Roles("GET /v1/seller/shops/{id}/promo-codes", h.sellerList, identity.RoleSeller)
	rt.Roles("POST /v1/seller/shops/{id}/promo-codes", h.sellerCreate, identity.RoleSeller)
	rt.Roles("POST /v1/seller/promo-codes/{id}/{action}", h.sellerAction, identity.RoleSeller)

	rt.Roles("GET /v1/admin/promo-codes", h.adminList, identity.RoleAdmin)
	rt.Roles("POST /v1/admin/promo-codes", h.adminCreate, identity.RoleAdmin)
	rt.Roles("POST /v1/admin/promo-codes/{id}/{action}", h.adminAction, identity.RoleAdmin)
	rt.Roles("GET /v1/admin/coupon-settings", h.settings, identity.RoleAdmin)
	rt.Roles("PUT /v1/admin/coupon-settings", h.updateSettings, identity.RoleAdmin)
}

func who(r *http.Request) uuid.UUID { return identity.MustFromContext(r.Context()).UserID }

func (h *Handler) mine(w http.ResponseWriter, r *http.Request) error {
	items, err := h.svc.ListForUser(r.Context(), who(r))
	if err != nil {
		return err
	}
	return httpapi.OK(w, map[string]any{"items": items})
}

func (h *Handler) sellerList(w http.ResponseWriter, r *http.Request) error {
	shopID, err := httpapi.PathUUID(r, "id")
	if err != nil {
		return err
	}
	q := httpapi.NewQuery(r)
	page := q.Page()
	if err := q.Err(); err != nil {
		return err
	}
	items, err := h.svc.ListForShop(r.Context(), who(r), shopID, page.FetchLimit(), int32(page.Offset))
	if err != nil {
		return err
	}
	return httpapi.OK(w, httpapi.NewList(items, page))
}

func (h *Handler) sellerCreate(w http.ResponseWriter, r *http.Request) error {
	shopID, err := httpapi.PathUUID(r, "id")
	if err != nil {
		return err
	}
	var in Input
	if err := httpapi.Decode(r, &in); err != nil {
		return err
	}
	c, err := h.svc.CreateForShop(r.Context(), who(r), shopID, in)
	if err != nil {
		return err
	}
	return httpapi.Created(w, c)
}

func (h *Handler) sellerAction(w http.ResponseWriter, r *http.Request) error {
	id, err := httpapi.PathUUID(r, "id")
	if err != nil {
		return err
	}
	c, err := h.svc.SellerAction(r.Context(), who(r), id, r.PathValue("action"))
	if err != nil {
		return err
	}
	return httpapi.OK(w, c)
}

func (h *Handler) adminList(w http.ResponseWriter, r *http.Request) error {
	q := httpapi.NewQuery(r)
	page := q.Page()
	shopID := q.UUID("shop_id")
	welcome := q.Enum("welcome", "false", "true", "false") == "true"
	if err := q.Err(); err != nil {
		return err
	}
	items, err := h.svc.AdminList(r.Context(), shopID, welcome, page.FetchLimit(), int32(page.Offset))
	if err != nil {
		return err
	}
	return httpapi.OK(w, httpapi.NewList(items, page))
}

func (h *Handler) adminCreate(w http.ResponseWriter, r *http.Request) error {
	var in Input
	if err := httpapi.Decode(r, &in); err != nil {
		return err
	}
	c, err := h.svc.AdminCreate(r.Context(), who(r), in)
	if err != nil {
		return err
	}
	return httpapi.Created(w, c)
}

func (h *Handler) adminAction(w http.ResponseWriter, r *http.Request) error {
	id, err := httpapi.PathUUID(r, "id")
	if err != nil {
		return err
	}
	var in struct {
		Reason string `json:"reason"`
	}
	if r.ContentLength > 0 {
		if err := httpapi.Decode(r, &in); err != nil {
			return err
		}
	}
	c, err := h.svc.AdminAction(r.Context(), who(r), id, r.PathValue("action"), in.Reason)
	if err != nil {
		return err
	}
	return httpapi.OK(w, c)
}

func (h *Handler) settings(w http.ResponseWriter, r *http.Request) error {
	s, err := h.svc.Settings(r.Context())
	if err != nil {
		return err
	}
	return httpapi.OK(w, s)
}

func (h *Handler) updateSettings(w http.ResponseWriter, r *http.Request) error {
	var in Settings
	if err := httpapi.Decode(r, &in); err != nil {
		return err
	}
	s, err := h.svc.UpdateSettings(r.Context(), who(r), in)
	if err != nil {
		return err
	}
	return httpapi.OK(w, s)
}
