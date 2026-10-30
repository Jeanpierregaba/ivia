package users

import (
	"net/http"

	"ivia/backend/internal/platform/httpapi"
	"ivia/backend/internal/platform/identity"
	"ivia/backend/internal/platform/validate"
)

// Handler expose les routes du compte, du carnet d'adresses et de l'administration des comptes.
type Handler struct {
	svc *Service
}

// NewHandler crée le handler.
func NewHandler(svc *Service) *Handler { return &Handler{svc: svc} }

// Register enregistre les routes.
func (h *Handler) Register(rt *httpapi.Router) {
	rt.Auth("GET /v1/me", h.me)
	rt.Auth("PATCH /v1/me", h.updateMe)
	rt.Auth("DELETE /v1/me", h.deleteMe)

	rt.Auth("GET /v1/me/addresses", h.listAddresses)
	rt.Auth("POST /v1/me/addresses", h.createAddress)
	rt.Auth("PUT /v1/me/addresses/{id}", h.updateAddress)
	rt.Auth("DELETE /v1/me/addresses/{id}", h.deleteAddress)

	rt.Auth("PUT /v1/me/devices", h.registerDevice)
	rt.Auth("DELETE /v1/me/devices", h.unregisterDevice)

	rt.Roles("GET /v1/admin/users", h.adminList, identity.RoleAdmin)
	rt.Roles("GET /v1/admin/users/{id}", h.adminGet, identity.RoleAdmin)
	rt.Roles("POST /v1/admin/users/{id}/grant-admin", h.adminGrant, identity.RoleAdmin)
	rt.Roles("POST /v1/admin/users/{id}/revoke-admin", h.adminRevoke, identity.RoleAdmin)
}

func userID(r *http.Request) identity.Principal { return identity.MustFromContext(r.Context()) }

func (h *Handler) me(w http.ResponseWriter, r *http.Request) error {
	u, err := h.svc.Get(r.Context(), userID(r).UserID)
	if err != nil {
		return err
	}
	return httpapi.OK(w, u)
}

func (h *Handler) updateMe(w http.ResponseWriter, r *http.Request) error {
	var in ProfileInput
	if err := httpapi.Decode(r, &in); err != nil {
		return err
	}
	u, err := h.svc.UpdateProfile(r.Context(), userID(r).UserID, in)
	if err != nil {
		return err
	}
	return httpapi.OK(w, u)
}

func (h *Handler) deleteMe(w http.ResponseWriter, r *http.Request) error {
	if err := h.svc.DeleteAccount(r.Context(), userID(r).UserID); err != nil {
		return err
	}
	return httpapi.NoContent(w)
}

func (h *Handler) listAddresses(w http.ResponseWriter, r *http.Request) error {
	items, err := h.svc.ListAddresses(r.Context(), userID(r).UserID)
	if err != nil {
		return err
	}
	return httpapi.OK(w, map[string]any{"items": items})
}

func (h *Handler) createAddress(w http.ResponseWriter, r *http.Request) error {
	var in AddressInput
	if err := httpapi.Decode(r, &in); err != nil {
		return err
	}
	a, err := h.svc.CreateAddress(r.Context(), userID(r).UserID, in)
	if err != nil {
		return err
	}
	return httpapi.Created(w, a)
}

func (h *Handler) updateAddress(w http.ResponseWriter, r *http.Request) error {
	id, err := httpapi.PathUUID(r, "id")
	if err != nil {
		return err
	}
	var in AddressInput
	if err := httpapi.Decode(r, &in); err != nil {
		return err
	}
	a, err := h.svc.UpdateAddress(r.Context(), userID(r).UserID, id, in)
	if err != nil {
		return err
	}
	return httpapi.OK(w, a)
}

func (h *Handler) deleteAddress(w http.ResponseWriter, r *http.Request) error {
	id, err := httpapi.PathUUID(r, "id")
	if err != nil {
		return err
	}
	if err := h.svc.DeleteAddress(r.Context(), userID(r).UserID, id); err != nil {
		return err
	}
	return httpapi.NoContent(w)
}

func (h *Handler) registerDevice(w http.ResponseWriter, r *http.Request) error {
	var in DeviceInput
	if err := httpapi.Decode(r, &in); err != nil {
		return err
	}
	if err := h.svc.RegisterDevice(r.Context(), userID(r).UserID, in); err != nil {
		return err
	}
	return httpapi.NoContent(w)
}

func (h *Handler) unregisterDevice(w http.ResponseWriter, r *http.Request) error {
	var in struct {
		Token string `json:"token"`
	}
	if err := httpapi.Decode(r, &in); err != nil {
		return err
	}
	if err := h.svc.UnregisterDevice(r.Context(), userID(r).UserID, in.Token); err != nil {
		return err
	}
	return httpapi.NoContent(w)
}

func (h *Handler) adminList(w http.ResponseWriter, r *http.Request) error {
	q := httpapi.NewQuery(r)
	page := q.Page()
	search := q.String("q", 100)
	role := q.Enum("role", "", "buyer", "seller", "driver", "admin")
	if err := q.Err(); err != nil {
		return err
	}
	items, err := h.svc.AdminSearch(r.Context(), search, role, page.FetchLimit(), int32(page.Offset))
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
	u, err := h.svc.Get(r.Context(), id)
	if err != nil {
		return err
	}
	return httpapi.OK(w, u)
}

type reasonInput struct {
	Reason string `json:"reason"`
}

func (h *Handler) adminGrant(w http.ResponseWriter, r *http.Request) error {
	id, err := httpapi.PathUUID(r, "id")
	if err != nil {
		return err
	}
	var in reasonInput
	if err := httpapi.Decode(r, &in); err != nil {
		return err
	}
	by := userID(r).UserID
	u, err := h.svc.AdminGrantAdmin(r.Context(), &by, id, validate.Clean(in.Reason))
	if err != nil {
		return err
	}
	return httpapi.OK(w, u)
}

func (h *Handler) adminRevoke(w http.ResponseWriter, r *http.Request) error {
	id, err := httpapi.PathUUID(r, "id")
	if err != nil {
		return err
	}
	var in reasonInput
	if err := httpapi.Decode(r, &in); err != nil {
		return err
	}
	u, err := h.svc.AdminRevokeAdmin(r.Context(), userID(r).UserID, id, validate.Clean(in.Reason))
	if err != nil {
		return err
	}
	return httpapi.OK(w, u)
}
