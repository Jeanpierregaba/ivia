package auth

import (
	"context"
	"net/http"
	"time"

	"github.com/riverqueue/river"

	"ivia/backend/internal/platform/httpapi"
	"ivia/backend/internal/platform/identity"
	"ivia/backend/internal/platform/jobs"
)

// Handler expose les routes de connexion.
type Handler struct {
	svc *Service
}

// NewHandler crée le handler.
func NewHandler(svc *Service) *Handler { return &Handler{svc: svc} }

// Register enregistre les routes.
func (h *Handler) Register(rt *httpapi.Router) {
	rt.Public("POST /v1/auth/otp", h.requestOTP)
	rt.Public("POST /v1/auth/verify", h.verify)
	rt.Auth("POST /v1/auth/logout", h.logout)
	rt.Auth("POST /v1/auth/logout-all", h.logoutAll)
}

func (h *Handler) requestOTP(w http.ResponseWriter, r *http.Request) error {
	var in struct {
		Channel   Channel `json:"channel"`
		Recipient string  `json:"recipient"`
	}
	if err := httpapi.Decode(r, &in); err != nil {
		return err
	}
	if in.Channel == "" {
		in.Channel = ChannelEmail
	}
	out, err := h.svc.RequestOTP(r.Context(), in.Channel, in.Recipient, httpapi.ClientIP(r.Context()))
	if err != nil {
		return err
	}
	httpapi.WriteJSON(w, http.StatusAccepted, out)
	return nil
}

func (h *Handler) verify(w http.ResponseWriter, r *http.Request) error {
	var in struct {
		Channel   Channel `json:"channel"`
		Recipient string  `json:"recipient"`
		Code      string  `json:"code"`
	}
	if err := httpapi.Decode(r, &in); err != nil {
		return err
	}
	if in.Channel == "" {
		in.Channel = ChannelEmail
	}
	sess, err := h.svc.Verify(r.Context(), in.Channel, in.Recipient, in.Code, r.UserAgent(), httpapi.ClientIP(r.Context()))
	if err != nil {
		return err
	}
	return httpapi.OK(w, sess)
}

func (h *Handler) logout(w http.ResponseWriter, r *http.Request) error {
	if err := h.svc.Logout(r.Context(), identity.MustFromContext(r.Context()).SessionID); err != nil {
		return err
	}
	return httpapi.NoContent(w)
}

func (h *Handler) logoutAll(w http.ResponseWriter, r *http.Request) error {
	if err := h.svc.LogoutAll(r.Context(), identity.MustFromContext(r.Context()).UserID); err != nil {
		return err
	}
	return httpapi.NoContent(w)
}

// PurgeArgs : purge quotidienne des codes et sessions périmés.
type PurgeArgs struct{}

// Kind implémente river.JobArgs.
func (PurgeArgs) Kind() string { return "auth.purge" }

type purgeWorker struct {
	river.WorkerDefaults[PurgeArgs]
	svc *Service
}

func (w *purgeWorker) Work(ctx context.Context, _ *river.Job[PurgeArgs]) error {
	return w.svc.Purge(ctx)
}

// RegisterJobs déclare les tâches de fond du module.
func (s *Service) RegisterJobs(reg *jobs.Registry) {
	river.AddWorker(reg.Workers, &purgeWorker{svc: s})
	reg.AddPeriodic(24*time.Hour, func() river.JobArgs { return PurgeArgs{} })
}
