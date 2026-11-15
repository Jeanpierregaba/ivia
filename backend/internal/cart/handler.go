package cart

import (
	"net/http"

	"github.com/google/uuid"

	"ivia/backend/internal/platform/httpapi"
	"ivia/backend/internal/platform/identity"
)

// Handler expose les routes du panier.
type Handler struct {
	svc *Service
}

// NewHandler crée le handler.
func NewHandler(svc *Service) *Handler { return &Handler{svc: svc} }

// Register enregistre les routes.
func (h *Handler) Register(rt *httpapi.Router) {
	rt.Roles("GET /v1/cart", h.get, identity.RoleBuyer)
	rt.Roles("PUT /v1/cart/items", h.setItem, identity.RoleBuyer)
	rt.Roles("DELETE /v1/cart", h.clear, identity.RoleBuyer)
}

func (h *Handler) get(w http.ResponseWriter, r *http.Request) error {
	c, err := h.svc.Get(r.Context(), identity.MustFromContext(r.Context()).UserID)
	if err != nil {
		return err
	}
	return httpapi.OK(w, c)
}

func (h *Handler) setItem(w http.ResponseWriter, r *http.Request) error {
	var in struct {
		ProductID   uuid.UUID `json:"product_id"`
		Quantity    int32     `json:"quantity"`
		ReplaceCart bool      `json:"replace_cart"`
	}
	if err := httpapi.Decode(r, &in); err != nil {
		return err
	}
	c, err := h.svc.SetItem(r.Context(), identity.MustFromContext(r.Context()).UserID, in.ProductID, in.Quantity, in.ReplaceCart)
	if err != nil {
		return err
	}
	return httpapi.OK(w, c)
}

func (h *Handler) clear(w http.ResponseWriter, r *http.Request) error {
	if err := h.svc.Clear(r.Context(), identity.MustFromContext(r.Context()).UserID); err != nil {
		return err
	}
	return httpapi.NoContent(w)
}
