package shops

import (
	"context"
	"fmt"
	"net/http"

	"github.com/google/uuid"

	"ivia/backend/internal/admin"
	"ivia/backend/internal/platform/apperr"
	"ivia/backend/internal/platform/httpapi"
	"ivia/backend/internal/platform/identity"
	"ivia/backend/internal/shops/store"
)

// SetManagedByPlatform confie (ou retire) une boutique au back-office : ses commandes y sont
// reçues et traitées (boutique officielle IVI). Journalisé.
func (s *Service) SetManagedByPlatform(ctx context.Context, adminID, shopID uuid.UUID, managed bool) (Shop, error) {
	var out Shop
	err := s.db.InTx(ctx, func(ctx context.Context) error {
		n, err := store.New(s.db.Conn(ctx)).SetManagedByPlatform(ctx, store.SetManagedByPlatformParams{ID: shopID, Managed: managed})
		if err != nil {
			return fmt.Errorf("boutique gérée par ivia : %w", err)
		}
		if n == 0 {
			return apperr.NotFound("shop_not_found", "Boutique introuvable.")
		}
		if out, err = s.get(ctx, shopID); err != nil {
			return err
		}
		return s.audit.Record(ctx, admin.AuditEntry{
			AdminID: &adminID, Action: "shop.platform_managed", TargetType: "shop", TargetID: shopID.String(),
			After: map[string]any{"managed_by_platform": managed},
		})
	})
	return out, err
}

// ManagedShops liste les boutiques gérées par ivia.
func (s *Service) ManagedShops(ctx context.Context) ([]Shop, error) {
	ids, err := store.New(s.db.Conn(ctx)).ListManagedShopIDs(ctx)
	if err != nil {
		return nil, fmt.Errorf("boutiques gérées par ivia : %w", err)
	}
	out := make([]Shop, 0, len(ids))
	for _, id := range ids {
		sh, err := s.get(ctx, id)
		if err != nil {
			return nil, err
		}
		out = append(out, sh)
	}
	return out, nil
}

func (h *Handler) setPlatformManaged(w http.ResponseWriter, r *http.Request) error {
	id, err := httpapi.PathUUID(r, "id")
	if err != nil {
		return err
	}
	var in struct {
		Managed bool `json:"managed"`
	}
	if err := httpapi.Decode(r, &in); err != nil {
		return err
	}
	sh, err := h.svc.SetManagedByPlatform(r.Context(), identity.MustFromContext(r.Context()).UserID, id, in.Managed)
	if err != nil {
		return err
	}
	return httpapi.OK(w, sh)
}
