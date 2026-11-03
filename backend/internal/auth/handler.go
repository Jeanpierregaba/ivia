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
	// Ancienne connexion par code (ADR 0006), gardée le temps que les apps passent au mot de passe.
	rt.Public("POST /v1/auth/otp", h.requestOTP)
	rt.Public("POST /v1/auth/verify", h.verify)

	rt.Public("GET /v1/auth/providers", h.providers)
	rt.Public("POST /v1/auth/signup/code", h.emailCode(h.svc.RequestSignupCode))
	rt.Public("POST /v1/auth/signup", h.signup)
	rt.Public("POST /v1/auth/login", h.login)
	rt.Public("POST /v1/auth/password/forgot", h.emailCode(h.svc.RequestPasswordReset))
	rt.Public("POST /v1/auth/password/reset", h.resetPassword)
	rt.Public("POST /v1/auth/google", h.google)

	rt.Auth("GET /v1/auth/session", h.session)
	rt.Auth("POST /v1/auth/mfa/code", h.mfaCode)
	rt.Auth("POST /v1/auth/mfa/verify", h.mfaVerify)
	rt.Auth("POST /v1/me/password", h.changePassword)
	rt.Auth("POST /v1/auth/logout", h.logout)
	rt.Auth("POST /v1/auth/logout-all", h.logoutAll)
}

func (h *Handler) providers(w http.ResponseWriter, _ *http.Request) error {
	return httpapi.OK(w, map[string]bool{"password": true, "google": h.svc.GoogleEnabled()})
}

func (h *Handler) emailCode(send func(ctx context.Context, email, ip string) (OTPRequested, error)) httpapi.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) error {
		var in struct {
			Email string `json:"email"`
		}
		if err := httpapi.Decode(r, &in); err != nil {
			return err
		}
		out, err := send(r.Context(), in.Email, httpapi.ClientIP(r.Context()))
		if err != nil {
			return err
		}
		httpapi.WriteJSON(w, http.StatusAccepted, out)
		return nil
	}
}

type credentialsInput struct {
	Email    string `json:"email"`
	Code     string `json:"code"`
	Password string `json:"password"`
}

func (h *Handler) signup(w http.ResponseWriter, r *http.Request) error {
	var in credentialsInput
	if err := httpapi.Decode(r, &in); err != nil {
		return err
	}
	sess, err := h.svc.Signup(r.Context(), in.Email, in.Code, in.Password, r.UserAgent(), httpapi.ClientIP(r.Context()))
	if err != nil {
		return err
	}
	return httpapi.Created(w, sess)
}

func (h *Handler) login(w http.ResponseWriter, r *http.Request) error {
	var in credentialsInput
	if err := httpapi.Decode(r, &in); err != nil {
		return err
	}
	sess, err := h.svc.Login(r.Context(), in.Email, in.Password, r.UserAgent(), httpapi.ClientIP(r.Context()))
	if err != nil {
		return err
	}
	return httpapi.OK(w, sess)
}

func (h *Handler) resetPassword(w http.ResponseWriter, r *http.Request) error {
	var in credentialsInput
	if err := httpapi.Decode(r, &in); err != nil {
		return err
	}
	sess, err := h.svc.ResetPassword(r.Context(), in.Email, in.Code, in.Password, r.UserAgent(), httpapi.ClientIP(r.Context()))
	if err != nil {
		return err
	}
	return httpapi.OK(w, sess)
}

func (h *Handler) google(w http.ResponseWriter, r *http.Request) error {
	var in struct {
		IDToken string `json:"id_token"`
	}
	if err := httpapi.Decode(r, &in); err != nil {
		return err
	}
	sess, err := h.svc.GoogleSignIn(r.Context(), in.IDToken, r.UserAgent(), httpapi.ClientIP(r.Context()))
	if err != nil {
		return err
	}
	return httpapi.OK(w, sess)
}

func (h *Handler) session(w http.ResponseWriter, r *http.Request) error {
	info, err := h.svc.SessionInfo(r.Context(), identity.MustFromContext(r.Context()))
	if err != nil {
		return err
	}
	return httpapi.OK(w, info)
}

func (h *Handler) mfaCode(w http.ResponseWriter, r *http.Request) error {
	out, err := h.svc.RequestMFACode(r.Context(), identity.MustFromContext(r.Context()), httpapi.ClientIP(r.Context()))
	if err != nil {
		return err
	}
	httpapi.WriteJSON(w, http.StatusAccepted, out)
	return nil
}

func (h *Handler) mfaVerify(w http.ResponseWriter, r *http.Request) error {
	var in struct {
		Code string `json:"code"`
	}
	if err := httpapi.Decode(r, &in); err != nil {
		return err
	}
	info, err := h.svc.VerifyMFA(r.Context(), identity.MustFromContext(r.Context()), in.Code, httpapi.ClientIP(r.Context()))
	if err != nil {
		return err
	}
	return httpapi.OK(w, info)
}

func (h *Handler) changePassword(w http.ResponseWriter, r *http.Request) error {
	var in struct {
		CurrentPassword string `json:"current_password"`
		NewPassword     string `json:"new_password"`
	}
	if err := httpapi.Decode(r, &in); err != nil {
		return err
	}
	if err := h.svc.ChangePassword(r.Context(), identity.MustFromContext(r.Context()), in.CurrentPassword, in.NewPassword); err != nil {
		return err
	}
	return httpapi.NoContent(w)
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
