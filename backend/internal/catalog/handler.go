package catalog

import (
	"net/http"

	"ivia/backend/internal/platform/httpapi"
	"ivia/backend/internal/platform/identity"
)

// Handler expose les routes du catalogue.
type Handler struct {
	svc *Service
}

// NewHandler crée le handler.
func NewHandler(svc *Service) *Handler { return &Handler{svc: svc} }

// Register enregistre les routes.
func (h *Handler) Register(rt *httpapi.Router) {
	rt.Public("GET /v1/categories", h.listCategories)
	rt.Public("GET /v1/products/{id}", h.getProduct)
	rt.Public("GET /v1/shops/{id}/products", h.listShopProducts)

	rt.Roles("GET /v1/seller/shops/{id}/products", h.sellerList, identity.RoleSeller)
	rt.Roles("POST /v1/seller/shops/{id}/products", h.create, identity.RoleSeller)
	rt.Roles("GET /v1/seller/products/{id}", h.sellerGet, identity.RoleSeller)
	rt.Roles("PATCH /v1/seller/products/{id}", h.update, identity.RoleSeller)
	rt.Roles("PUT /v1/seller/products/{id}/stock", h.setStock, identity.RoleSeller)
	rt.Roles("GET /v1/seller/products/{id}/stock-movements", h.stockMovements, identity.RoleSeller)

	rt.Roles("GET /v1/admin/categories", h.adminListCategories, identity.RoleAdmin)
	rt.Roles("POST /v1/admin/categories", h.createCategory, identity.RoleAdmin)
	rt.Roles("PATCH /v1/admin/categories/{id}", h.updateCategory, identity.RoleAdmin)
}

func principal(r *http.Request) identity.Principal { return identity.MustFromContext(r.Context()) }

func (h *Handler) listCategories(w http.ResponseWriter, r *http.Request) error {
	items, err := h.svc.ListCategories(r.Context(), false)
	if err != nil {
		return err
	}
	return httpapi.OK(w, map[string]any{"items": items})
}

func (h *Handler) adminListCategories(w http.ResponseWriter, r *http.Request) error {
	items, err := h.svc.ListCategories(r.Context(), true)
	if err != nil {
		return err
	}
	return httpapi.OK(w, map[string]any{"items": items})
}

func (h *Handler) getProduct(w http.ResponseWriter, r *http.Request) error {
	id, err := httpapi.PathUUID(r, "id")
	if err != nil {
		return err
	}
	p, shop, err := h.svc.GetPublic(r.Context(), id)
	if err != nil {
		return err
	}
	return httpapi.OK(w, map[string]any{"product": p, "shop": shop})
}

func (h *Handler) listShopProducts(w http.ResponseWriter, r *http.Request) error {
	id, err := httpapi.PathUUID(r, "id")
	if err != nil {
		return err
	}
	q := httpapi.NewQuery(r)
	page := q.Page()
	if err := q.Err(); err != nil {
		return err
	}
	items, err := h.svc.ListPublicForShop(r.Context(), id, page.FetchLimit(), int32(page.Offset))
	if err != nil {
		return err
	}
	return httpapi.OK(w, httpapi.NewList(items, page))
}

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
	items, err := h.svc.ListForSeller(r.Context(), principal(r).UserID, id, page.FetchLimit(), int32(page.Offset))
	if err != nil {
		return err
	}
	return httpapi.OK(w, httpapi.NewList(items, page))
}

func (h *Handler) create(w http.ResponseWriter, r *http.Request) error {
	shopID, err := httpapi.PathUUID(r, "id")
	if err != nil {
		return err
	}
	var in ProductInput
	if err := httpapi.Decode(r, &in); err != nil {
		return err
	}
	p, err := h.svc.Create(r.Context(), principal(r).UserID, shopID, in)
	if err != nil {
		return err
	}
	return httpapi.Created(w, p)
}

func (h *Handler) sellerGet(w http.ResponseWriter, r *http.Request) error {
	id, err := httpapi.PathUUID(r, "id")
	if err != nil {
		return err
	}
	p, err := h.svc.RequireOwned(r.Context(), principal(r).UserID, id)
	if err != nil {
		return err
	}
	return httpapi.OK(w, p)
}

func (h *Handler) update(w http.ResponseWriter, r *http.Request) error {
	id, err := httpapi.PathUUID(r, "id")
	if err != nil {
		return err
	}
	var in ProductInput
	if err := httpapi.Decode(r, &in); err != nil {
		return err
	}
	p, err := h.svc.Update(r.Context(), principal(r).UserID, id, in)
	if err != nil {
		return err
	}
	return httpapi.OK(w, p)
}

func (h *Handler) setStock(w http.ResponseWriter, r *http.Request) error {
	id, err := httpapi.PathUUID(r, "id")
	if err != nil {
		return err
	}
	var in struct {
		Quantity int32  `json:"quantity"`
		Note     string `json:"note"`
	}
	if err := httpapi.Decode(r, &in); err != nil {
		return err
	}
	p, err := h.svc.SetStock(r.Context(), principal(r).UserID, id, in.Quantity, in.Note)
	if err != nil {
		return err
	}
	return httpapi.OK(w, p)
}

func (h *Handler) stockMovements(w http.ResponseWriter, r *http.Request) error {
	id, err := httpapi.PathUUID(r, "id")
	if err != nil {
		return err
	}
	q := httpapi.NewQuery(r)
	page := q.Page()
	if err := q.Err(); err != nil {
		return err
	}
	items, err := h.svc.StockMovements(r.Context(), principal(r).UserID, id, page.FetchLimit(), int32(page.Offset))
	if err != nil {
		return err
	}
	return httpapi.OK(w, httpapi.NewList(items, page))
}

func (h *Handler) createCategory(w http.ResponseWriter, r *http.Request) error {
	var in CategoryInput
	if err := httpapi.Decode(r, &in); err != nil {
		return err
	}
	c, err := h.svc.CreateCategory(r.Context(), principal(r).UserID, in)
	if err != nil {
		return err
	}
	return httpapi.Created(w, c)
}

func (h *Handler) updateCategory(w http.ResponseWriter, r *http.Request) error {
	id, err := httpapi.PathUUID(r, "id")
	if err != nil {
		return err
	}
	var in CategoryInput
	if err := httpapi.Decode(r, &in); err != nil {
		return err
	}
	c, err := h.svc.UpdateCategory(r.Context(), principal(r).UserID, id, in)
	if err != nil {
		return err
	}
	return httpapi.OK(w, c)
}
