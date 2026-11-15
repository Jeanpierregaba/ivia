package orders

import (
	"context"
	"net/http"

	"github.com/google/uuid"

	"ivia/backend/internal/admin"
	"ivia/backend/internal/platform/apperr"
	"ivia/backend/internal/platform/httpapi"
	"ivia/backend/internal/platform/identity"
)

// Commandes des boutiques gérées par ivia (boutique officielle IVI) : le back-office joue le rôle
// du marchand. Les actions passent par les mêmes transitions que dans Ivia Business (au nom du
// compte de la boutique) et sont journalisées avec l'admin qui les fait.

// PlatformOrders liste les commandes des boutiques gérées par ivia (groupe : new, active, done).
func (s *Service) PlatformOrders(ctx context.Context, group string, limit, offset int32) ([]SellerOrder, error) {
	shops, err := s.shops.ManagedShops(ctx)
	if err != nil {
		return nil, err
	}
	out := []SellerOrder{}
	for _, sh := range shops {
		id := sh.ID
		items, err := s.ListForSeller(ctx, sh.OwnerID, &id, "", group, limit, offset)
		if err != nil {
			return nil, err
		}
		out = append(out, items...)
	}
	return out, nil
}

// PlatformAction traite une commande d'une boutique gérée par ivia : accept, reject, preparing,
// ready, handover (code du client), confirm-return. Autre boutique : 404.
func (s *Service) PlatformAction(ctx context.Context, adminID, orderID uuid.UUID, action, reason, code string) (SellerOrder, error) {
	o, err := s.get(ctx, orderID)
	if err != nil {
		return SellerOrder{}, err
	}
	shop, err := s.shops.Get(ctx, o.ShopID)
	if err != nil {
		return SellerOrder{}, err
	}
	if !shop.ManagedByPlatform {
		return SellerOrder{}, errNotFound
	}
	owner := shop.OwnerID
	var out SellerOrder
	switch action {
	case "accept":
		out, err = s.Accept(ctx, owner, orderID)
	case "reject":
		out, err = s.Reject(ctx, owner, orderID, reason)
	case "preparing":
		out, err = s.StartPreparing(ctx, owner, orderID)
	case "ready":
		out, err = s.MarkReady(ctx, owner, orderID)
	case "handover":
		out, err = s.CompletePickup(ctx, owner, orderID, code)
	case "confirm-return":
		out, err = s.ConfirmReturn(ctx, owner, orderID)
	default:
		return SellerOrder{}, apperr.Validation(map[string]string{"action": "Action inconnue."})
	}
	if err != nil {
		return SellerOrder{}, err
	}
	_ = s.admin.Record(ctx, admin.AuditEntry{
		AdminID: &adminID, Action: "platform_order." + action, TargetType: "order", TargetID: orderID.String(),
		After: map[string]any{"status": out.Status}, Reason: reason,
	})
	return out, nil
}

func (h *Handler) platformList(w http.ResponseWriter, r *http.Request) error {
	q := httpapi.NewQuery(r)
	page := q.Page()
	group := q.Enum("group", "new", "new", "active", "done")
	if err := q.Err(); err != nil {
		return err
	}
	items, err := h.svc.PlatformOrders(r.Context(), group, page.FetchLimit(), int32(page.Offset))
	if err != nil {
		return err
	}
	return httpapi.OK(w, httpapi.NewList(items, page))
}

func (h *Handler) platformAction(w http.ResponseWriter, r *http.Request) error {
	id, err := httpapi.PathUUID(r, "id")
	if err != nil {
		return err
	}
	var in struct {
		Reason string `json:"reason"`
		Code   string `json:"code"`
	}
	if r.ContentLength > 0 {
		if err := httpapi.Decode(r, &in); err != nil {
			return err
		}
	}
	o, err := h.svc.PlatformAction(r.Context(), identity.MustFromContext(r.Context()).UserID, id, r.PathValue("action"), in.Reason, in.Code)
	if err != nil {
		return err
	}
	return httpapi.OK(w, o)
}
