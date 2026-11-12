package delivery

import (
	"net/http"
	"strings"

	"ivia/backend/internal/platform/httpapi"
	"ivia/backend/internal/platform/identity"
)

// registerPartner enregistre les routes du workflow partenaire (livreur, chauffeur VTC).
func (h *Handler) registerPartner(rt *httpapi.Router) {
	h.registerIncidents(rt)
	// Inscription : ouverte à tout utilisateur connecté (le rôle driver vient de la validation).
	rt.Auth("GET /v1/driver/options", h.options)
	rt.Auth("PUT /v1/driver/activities/{activity}", h.saveActivity)
	rt.Auth("POST /v1/driver/activities/{activity}/submit", h.submit)
	rt.Auth("PUT /v1/driver/payout", h.payout)
	rt.Auth("GET /v1/driver/guide", h.guide)

	rt.Roles("POST /v1/admin/drivers/{id}/request-changes", h.review("request_changes"), identity.RoleAdmin)
	rt.Roles("POST /v1/admin/drivers/{id}/activities/{activity}/vehicle-check", h.vehicleCheck, identity.RoleAdmin)
	for _, d := range []string{"approve", "request-changes", "reject"} {
		rt.Roles("POST /v1/admin/drivers/{id}/activities/{activity}/"+d, h.reviewActivity(strings.ReplaceAll(d, "-", "_")), identity.RoleAdmin)
	}
	rt.Roles("GET /v1/admin/driver-settings", h.settings, identity.RoleAdmin)
	rt.Roles("PUT /v1/admin/driver-settings", h.updateSettings, identity.RoleAdmin)
}

func (h *Handler) options(w http.ResponseWriter, r *http.Request) error {
	items, err := h.svc.Options(r.Context())
	if err != nil {
		return err
	}
	zones, err := h.svc.WorkZones(r.Context())
	if err != nil {
		return err
	}
	return httpapi.OK(w, map[string]any{"activities": items, "zones": zones})
}

func (h *Handler) saveActivity(w http.ResponseWriter, r *http.Request) error {
	var in ActivityInput
	if err := httpapi.Decode(r, &in); err != nil {
		return err
	}
	d, err := h.svc.SaveActivity(r.Context(), me(r).UserID, r.PathValue("activity"), in)
	if err != nil {
		return err
	}
	return httpapi.OK(w, d)
}

func (h *Handler) submit(w http.ResponseWriter, r *http.Request) error {
	d, err := h.svc.Submit(r.Context(), me(r).UserID, r.PathValue("activity"))
	if err != nil {
		return err
	}
	return httpapi.OK(w, d)
}

func (h *Handler) payout(w http.ResponseWriter, r *http.Request) error {
	var in PayoutInput
	if err := httpapi.Decode(r, &in); err != nil {
		return err
	}
	d, err := h.svc.SetPayout(r.Context(), me(r).UserID, in)
	if err != nil {
		return err
	}
	return httpapi.OK(w, d)
}

func (h *Handler) guide(w http.ResponseWriter, r *http.Request) error {
	g, err := h.svc.Guide(r.Context())
	if err != nil {
		return err
	}
	return httpapi.OK(w, map[string]string{"guide": g})
}

func (h *Handler) vehicleCheck(w http.ResponseWriter, r *http.Request) error {
	id, err := httpapi.PathUUID(r, "id")
	if err != nil {
		return err
	}
	var in struct {
		Passed bool   `json:"passed"`
		Note   string `json:"note"`
	}
	if err := httpapi.Decode(r, &in); err != nil {
		return err
	}
	d, err := h.svc.VehicleCheck(r.Context(), me(r).UserID, id, r.PathValue("activity"), in.Passed, in.Note)
	if err != nil {
		return err
	}
	return httpapi.OK(w, d)
}

func (h *Handler) reviewActivity(decision string) httpapi.HandlerFunc {
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
		d, err := h.svc.ReviewActivity(r.Context(), me(r).UserID, id, r.PathValue("activity"), decision, in.Reason)
		if err != nil {
			return err
		}
		return httpapi.OK(w, d)
	}
}

func (h *Handler) settings(w http.ResponseWriter, r *http.Request) error {
	st, err := h.svc.Settings(r.Context())
	if err != nil {
		return err
	}
	return httpapi.OK(w, st)
}

func (h *Handler) updateSettings(w http.ResponseWriter, r *http.Request) error {
	var in DriverSettings
	if err := httpapi.Decode(r, &in); err != nil {
		return err
	}
	st, err := h.svc.UpdateSettings(r.Context(), me(r).UserID, in)
	if err != nil {
		return err
	}
	return httpapi.OK(w, st)
}
