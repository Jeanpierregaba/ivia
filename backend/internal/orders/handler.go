package orders

import (
	"context"
	"net/http"

	"github.com/google/uuid"

	"ivia/backend/internal/platform/httpapi"
	"ivia/backend/internal/platform/identity"
	"ivia/backend/internal/platform/validate"
)

// Handler expose les routes des commandes (acheteur, marchand, admin).
type Handler struct {
	svc *Service
}

// NewHandler crée le handler.
func NewHandler(svc *Service) *Handler { return &Handler{svc: svc} }

var orderStatuses = []string{
	"pending_payment", "expired", "awaiting_seller", "accepted", "preparing", "ready_for_pickup",
	"awaiting_driver", "driver_assigned", "picked_up", "delivered", "delivery_failed",
	"returned_to_shop", "completed", "cancelled", "refunded",
}

// Register enregistre les routes.
func (h *Handler) Register(rt *httpapi.Router) {
	rt.Roles("POST /v1/orders/quote", h.quote, identity.RoleBuyer)
	rt.Roles("POST /v1/orders", h.checkout, identity.RoleBuyer)
	rt.Roles("GET /v1/orders", h.listMine, identity.RoleBuyer)
	rt.Roles("GET /v1/orders/{id}", h.getMine, identity.RoleBuyer)
	rt.Roles("POST /v1/orders/{id}/cancel", h.cancel, identity.RoleBuyer)

	rt.Roles("GET /v1/seller/orders", h.sellerList, identity.RoleSeller)
	rt.Roles("GET /v1/seller/orders/{id}", h.sellerGet, identity.RoleSeller)
	rt.Roles("POST /v1/seller/orders/{id}/accept", h.sellerSimple(h.svc.Accept), identity.RoleSeller)
	rt.Roles("POST /v1/seller/orders/{id}/reject", h.reject, identity.RoleSeller)
	rt.Roles("POST /v1/seller/orders/{id}/preparing", h.sellerSimple(h.svc.StartPreparing), identity.RoleSeller)
	rt.Roles("POST /v1/seller/orders/{id}/ready", h.sellerSimple(h.svc.MarkReady), identity.RoleSeller)
	rt.Roles("POST /v1/seller/orders/{id}/handover", h.handover, identity.RoleSeller)
	rt.Roles("POST /v1/seller/orders/{id}/confirm-return", h.sellerSimple(h.svc.ConfirmReturn), identity.RoleSeller)

	rt.Roles("GET /v1/admin/orders", h.adminList, identity.RoleAdmin)
	rt.Roles("GET /v1/admin/orders/{id}", h.adminGet, identity.RoleAdmin)
	rt.Roles("POST /v1/admin/orders/{id}/cancel", h.adminCancel, identity.RoleAdmin)
	rt.Roles("POST /v1/admin/orders/{id}/unlock-handover", h.adminUnlock, identity.RoleAdmin)
	rt.Roles("POST /v1/admin/orders/{id}/confirm-return", h.adminConfirmReturn, identity.RoleAdmin)
	rt.Roles("GET /v1/admin/refund-queue", h.refundQueue, identity.RoleAdmin)
}

func uid(r *http.Request) identity.Principal { return identity.MustFromContext(r.Context()) }

func (h *Handler) quote(w http.ResponseWriter, r *http.Request) error {
	var in CheckoutInput
	if err := httpapi.Decode(r, &in); err != nil {
		return err
	}
	q, err := h.svc.Quote(r.Context(), uid(r).UserID, in)
	if err != nil {
		return err
	}
	return httpapi.OK(w, q)
}

func (h *Handler) checkout(w http.ResponseWriter, r *http.Request) error {
	var in CheckoutInput
	if err := httpapi.Decode(r, &in); err != nil {
		return err
	}
	o, err := h.svc.Checkout(r.Context(), uid(r).UserID, in)
	if err != nil {
		return err
	}
	return httpapi.Created(w, o)
}

func (h *Handler) listMine(w http.ResponseWriter, r *http.Request) error {
	q := httpapi.NewQuery(r)
	page := q.Page()
	group := q.Enum("group", "", "active", "done")
	if err := q.Err(); err != nil {
		return err
	}
	items, err := h.svc.ListForBuyer(r.Context(), uid(r).UserID, group, page.FetchLimit(), int32(page.Offset))
	if err != nil {
		return err
	}
	return httpapi.OK(w, httpapi.NewList(items, page))
}

func (h *Handler) getMine(w http.ResponseWriter, r *http.Request) error {
	id, err := httpapi.PathUUID(r, "id")
	if err != nil {
		return err
	}
	o, err := h.svc.GetForBuyer(r.Context(), uid(r).UserID, id)
	if err != nil {
		return err
	}
	return httpapi.OK(w, o)
}

func (h *Handler) cancel(w http.ResponseWriter, r *http.Request) error {
	id, err := httpapi.PathUUID(r, "id")
	if err != nil {
		return err
	}
	o, err := h.svc.CancelByBuyer(r.Context(), uid(r).UserID, id)
	if err != nil {
		return err
	}
	return httpapi.OK(w, o)
}

func (h *Handler) sellerList(w http.ResponseWriter, r *http.Request) error {
	q := httpapi.NewQuery(r)
	page := q.Page()
	shopID := q.UUID("shop_id")
	status := Status(q.Enum("status", "", orderStatuses...))
	group := q.Enum("group", "", "new", "active", "done")
	if err := q.Err(); err != nil {
		return err
	}
	items, err := h.svc.ListForSeller(r.Context(), uid(r).UserID, shopID, status, group, page.FetchLimit(), int32(page.Offset))
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
	o, err := h.svc.GetForSeller(r.Context(), uid(r).UserID, id)
	if err != nil {
		return err
	}
	return httpapi.OK(w, o)
}

type sellerFn = func(ctx context.Context, sellerID, orderID uuid.UUID) (SellerOrder, error)

func (h *Handler) sellerSimple(fn sellerFn) httpapi.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) error {
		id, err := httpapi.PathUUID(r, "id")
		if err != nil {
			return err
		}
		o, err := fn(r.Context(), uid(r).UserID, id)
		if err != nil {
			return err
		}
		return httpapi.OK(w, o)
	}
}

func (h *Handler) reject(w http.ResponseWriter, r *http.Request) error {
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
	o, err := h.svc.Reject(r.Context(), uid(r).UserID, id, validate.Clean(in.Reason))
	if err != nil {
		return err
	}
	return httpapi.OK(w, o)
}

func (h *Handler) handover(w http.ResponseWriter, r *http.Request) error {
	id, err := httpapi.PathUUID(r, "id")
	if err != nil {
		return err
	}
	var in struct {
		Code string `json:"code"`
	}
	if err := httpapi.Decode(r, &in); err != nil {
		return err
	}
	o, err := h.svc.CompletePickup(r.Context(), uid(r).UserID, id, in.Code)
	if err != nil {
		return err
	}
	return httpapi.OK(w, o)
}

func (h *Handler) adminList(w http.ResponseWriter, r *http.Request) error {
	q := httpapi.NewQuery(r)
	page := q.Page()
	f := AdminFilter{
		Status:  Status(q.Enum("status", "", orderStatuses...)),
		ShopID:  q.UUID("shop_id"),
		BuyerID: q.UUID("buyer_id"),
		Number:  q.Int64("number", 1, 1<<53),
	}
	if err := q.Err(); err != nil {
		return err
	}
	items, err := h.svc.AdminList(r.Context(), f, page.FetchLimit(), int32(page.Offset))
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
	o, err := h.svc.AdminGet(r.Context(), id)
	if err != nil {
		return err
	}
	return httpapi.OK(w, o)
}

func (h *Handler) adminCancel(w http.ResponseWriter, r *http.Request) error {
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
	o, err := h.svc.CancelByAdmin(r.Context(), uid(r).UserID, id, validate.Clean(in.Reason))
	if err != nil {
		return err
	}
	return httpapi.OK(w, o)
}

func (h *Handler) adminUnlock(w http.ResponseWriter, r *http.Request) error {
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
	o, err := h.svc.UnlockHandover(r.Context(), uid(r).UserID, id, validate.Clean(in.Reason))
	if err != nil {
		return err
	}
	return httpapi.OK(w, o)
}

func (h *Handler) adminConfirmReturn(w http.ResponseWriter, r *http.Request) error {
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
	o, err := h.svc.ConfirmReturnByAdmin(r.Context(), uid(r).UserID, id, validate.Clean(in.Reason))
	if err != nil {
		return err
	}
	return httpapi.OK(w, o)
}

func (h *Handler) refundQueue(w http.ResponseWriter, r *http.Request) error {
	q := httpapi.NewQuery(r)
	page := q.Page()
	if err := q.Err(); err != nil {
		return err
	}
	items, err := h.svc.RefundQueue(r.Context(), page.FetchLimit(), int32(page.Offset))
	if err != nil {
		return err
	}
	return httpapi.OK(w, httpapi.NewList(items, page))
}
