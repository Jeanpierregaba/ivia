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

	// Connexion par numéro (ADR 0012) : apps mobiles.
	rt.Public("POST /v1/auth/phone/code", h.phoneCode)
	rt.Public("POST /v1/auth/phone/verify", h.phoneVerify)
	rt.Public("POST /v1/auth/phone/signup", h.phoneSignup)
	rt.Public("POST /v1/auth/refresh", h.refresh)
	rt.Auth("POST /v1/me/phone/code", h.phoneChangeCode)
	rt.Auth("POST /v1/me/phone", h.phoneChange)
	rt.Auth("GET /v1/me/sessions", h.listSessions)
	rt.Auth("DELETE /v1/me/sessions/{id}", h.revokeSession)

	// Application d'authentification (back-office).
	rt.Auth("POST /v1/auth/mfa/totp/setup", h.totpSetup)
	rt.Auth("POST /v1/auth/mfa/totp/confirm", h.totpConfirm)
	rt.Auth("POST /v1/auth/mfa/totp/recovery-codes", h.totpRecovery)
	rt.Auth("POST /v1/auth/mfa/totp/disable", h.totpDisable)
	rt.Roles("POST /v1/admin/users/{id}/mfa/reset", h.adminResetTOTP, identity.RoleAdmin)

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
	return httpapi.OK(w, map[string]bool{"password": true, "google": h.svc.GoogleEnabled(), "phone": h.svc.PhoneEnabled()})
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

func (h *Handler) phoneCode(w http.ResponseWriter, r *http.Request) error {
	var in PhoneCodeInput
	if err := httpapi.Decode(r, &in); err != nil {
		return err
	}
	out, err := h.svc.RequestPhoneCode(r.Context(), in, httpapi.ClientIP(r.Context()))
	if err != nil {
		return err
	}
	httpapi.WriteJSON(w, http.StatusAccepted, out)
	return nil
}

func (h *Handler) phoneVerify(w http.ResponseWriter, r *http.Request) error {
	var in PhoneVerifyInput
	if err := httpapi.Decode(r, &in); err != nil {
		return err
	}
	out, err := h.svc.VerifyPhone(r.Context(), in, r.UserAgent(), httpapi.ClientIP(r.Context()))
	if err != nil {
		return err
	}
	return httpapi.OK(w, out)
}

func (h *Handler) phoneSignup(w http.ResponseWriter, r *http.Request) error {
	var in PhoneSignupInput
	if err := httpapi.Decode(r, &in); err != nil {
		return err
	}
	sess, err := h.svc.PhoneSignup(r.Context(), in, r.UserAgent())
	if err != nil {
		return err
	}
	return httpapi.Created(w, sess)
}

func (h *Handler) refresh(w http.ResponseWriter, r *http.Request) error {
	var in struct {
		RefreshToken string `json:"refresh_token"`
	}
	if err := httpapi.Decode(r, &in); err != nil {
		return err
	}
	sess, err := h.svc.Refresh(r.Context(), in.RefreshToken)
	if err != nil {
		return err
	}
	return httpapi.OK(w, sess)
}

func (h *Handler) phoneChangeCode(w http.ResponseWriter, r *http.Request) error {
	var in struct {
		Phone   string  `json:"phone"`
		Channel Channel `json:"channel"`
	}
	if err := httpapi.Decode(r, &in); err != nil {
		return err
	}
	p := identity.MustFromContext(r.Context())
	out, err := h.svc.RequestPhoneChange(r.Context(), p.UserID, in.Phone, in.Channel, httpapi.ClientIP(r.Context()))
	if err != nil {
		return err
	}
	httpapi.WriteJSON(w, http.StatusAccepted, out)
	return nil
}

func (h *Handler) phoneChange(w http.ResponseWriter, r *http.Request) error {
	var in struct {
		Phone string `json:"phone"`
		Code  string `json:"code"`
	}
	if err := httpapi.Decode(r, &in); err != nil {
		return err
	}
	p := identity.MustFromContext(r.Context())
	user, err := h.svc.ConfirmPhoneChange(r.Context(), p.UserID, in.Phone, in.Code, httpapi.ClientIP(r.Context()))
	if err != nil {
		return err
	}
	return httpapi.OK(w, user)
}

func (h *Handler) listSessions(w http.ResponseWriter, r *http.Request) error {
	p := identity.MustFromContext(r.Context())
	items, err := h.svc.ListSessions(r.Context(), p.UserID, p.SessionID)
	if err != nil {
		return err
	}
	return httpapi.OK(w, map[string]any{"items": items})
}

func (h *Handler) revokeSession(w http.ResponseWriter, r *http.Request) error {
	id, err := httpapi.PathUUID(r, "id")
	if err != nil {
		return err
	}
	if err := h.svc.RevokeSession(r.Context(), identity.MustFromContext(r.Context()).UserID, id); err != nil {
		return err
	}
	return httpapi.NoContent(w)
}

type codeInput struct {
	Code string `json:"code"`
}

func (h *Handler) totpSetup(w http.ResponseWriter, r *http.Request) error {
	out, err := h.svc.StartTOTP(r.Context(), identity.MustFromContext(r.Context()))
	if err != nil {
		return err
	}
	return httpapi.OK(w, out)
}

func (h *Handler) totpConfirm(w http.ResponseWriter, r *http.Request) error {
	var in codeInput
	if err := httpapi.Decode(r, &in); err != nil {
		return err
	}
	out, err := h.svc.ConfirmTOTP(r.Context(), identity.MustFromContext(r.Context()), in.Code)
	if err != nil {
		return err
	}
	return httpapi.OK(w, out)
}

func (h *Handler) totpRecovery(w http.ResponseWriter, r *http.Request) error {
	var in codeInput
	if err := httpapi.Decode(r, &in); err != nil {
		return err
	}
	out, err := h.svc.RegenerateRecoveryCodes(r.Context(), identity.MustFromContext(r.Context()), in.Code)
	if err != nil {
		return err
	}
	return httpapi.OK(w, out)
}

func (h *Handler) totpDisable(w http.ResponseWriter, r *http.Request) error {
	var in codeInput
	if err := httpapi.Decode(r, &in); err != nil {
		return err
	}
	if err := h.svc.DisableTOTP(r.Context(), identity.MustFromContext(r.Context()), in.Code); err != nil {
		return err
	}
	return httpapi.NoContent(w)
}

func (h *Handler) adminResetTOTP(w http.ResponseWriter, r *http.Request) error {
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
	if err := h.svc.AdminResetTOTP(r.Context(), identity.MustFromContext(r.Context()), id, in.Reason); err != nil {
		return err
	}
	return httpapi.NoContent(w)
}
