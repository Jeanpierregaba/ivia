package admin

import (
	"net/http"

	"ivia/backend/internal/platform/httpapi"
	"ivia/backend/internal/platform/identity"
	"ivia/backend/internal/platform/validate"
)

// Handler expose les routes admin des paramètres et du journal.
type Handler struct {
	svc *Service
}

// NewHandler crée le handler.
func NewHandler(svc *Service) *Handler { return &Handler{svc: svc} }

// Register enregistre les routes.
func (h *Handler) Register(rt *httpapi.Router) {
	rt.Roles("GET /v1/admin/settings", h.getSettings, identity.RoleAdmin)
	rt.Roles("PATCH /v1/admin/settings", h.updateSettings, identity.RoleAdmin)
	rt.Roles("GET /v1/admin/audit-log", h.listAudit, identity.RoleAdmin)
}

func (h *Handler) getSettings(w http.ResponseWriter, r *http.Request) error {
	s, err := h.svc.Settings(r.Context())
	if err != nil {
		return err
	}
	return httpapi.OK(w, s)
}

func (h *Handler) updateSettings(w http.ResponseWriter, r *http.Request) error {
	var in struct {
		SettingsPatch
		Reason string `json:"reason"`
	}
	if err := httpapi.Decode(r, &in); err != nil {
		return err
	}
	p := identity.MustFromContext(r.Context())
	s, err := h.svc.UpdateSettings(r.Context(), p.UserID, in.SettingsPatch, validate.Clean(in.Reason))
	if err != nil {
		return err
	}
	return httpapi.OK(w, s)
}

func (h *Handler) listAudit(w http.ResponseWriter, r *http.Request) error {
	q := httpapi.NewQuery(r)
	page := q.Page()
	f := AuditFilter{
		AdminID:    q.UUID("admin_id"),
		TargetType: q.String("target_type", 50),
		TargetID:   q.String("target_id", 100),
		Limit:      page.FetchLimit(),
		Offset:     int32(page.Offset),
	}
	if err := q.Err(); err != nil {
		return err
	}
	rows, err := h.svc.ListAudit(r.Context(), f)
	if err != nil {
		return err
	}
	return httpapi.OK(w, httpapi.NewList(rows, page))
}
