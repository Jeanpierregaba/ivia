package auth

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"

	"ivia/backend/internal/auth/store"
	"ivia/backend/internal/platform/apperr"
	"ivia/backend/internal/platform/database"
	"ivia/backend/internal/platform/identity"
	"ivia/backend/internal/users"
)

// Parcours de l'ADR 0011 : création de compte (code puis mot de passe), connexion par mot de
// passe ou par Google, mot de passe oublié, changement de mot de passe, double vérification admin.

const (
	// MaxLoginFailures échecs de mot de passe d'affilée verrouillent le compte LockDuration.
	MaxLoginFailures = 10
	LockDuration     = 15 * time.Minute
	// AdminSessionCap : durée maximale d'une session vérifiée par code (back-office), sans
	// prolongation glissante au-delà.
	AdminSessionCap = 8 * time.Hour
)

var (
	errInvalidCredentials = apperr.Unauthorized("invalid_credentials", "E-mail ou mot de passe incorrect.")
	errAccountExists      = apperr.Conflict("account_exists", "Un compte existe déjà avec cet e-mail : connectez-vous, ou utilisez « Mot de passe oublié ».")
	errGoogleDisabled     = apperr.BadRequest("google_disabled", "La connexion avec Google n'est pas encore disponible.")
	errGoogleInvalid      = apperr.Unauthorized("google_token_invalid", "Connexion avec Google impossible. Réessayez.")
)

func (s *Service) email(raw string) (string, error) {
	return s.normalize(ChannelEmail, raw)
}

// --- Création de compte -------------------------------------------------------------------

// RequestSignupCode envoie le code de création de compte. La réponse ne dit jamais si un compte
// existe : on le découvre seulement après avoir prouvé qu'on reçoit les e-mails de l'adresse.
func (s *Service) RequestSignupCode(ctx context.Context, rawEmail, ip string) (OTPRequested, error) {
	email, err := s.email(rawEmail)
	if err != nil {
		return OTPRequested{}, err
	}
	return s.sendCode(ctx, ChannelEmail, email, PurposeSignup, ip)
}

// Signup vérifie le code et crée le compte avec son mot de passe. Un compte déjà créé par
// l'ancienne connexion par code (sans mot de passe) reçoit ici son mot de passe ; un compte qui en
// a déjà un est refusé (account_exists), le code restant valable.
func (s *Service) Signup(ctx context.Context, rawEmail, code, password, userAgent, ip string) (Session, error) {
	email, err := s.email(rawEmail)
	if err != nil {
		return Session{}, err
	}
	if err := checkPassword(password, email); err != nil {
		return Session{}, err
	}
	otpID, err := s.checkCode(ctx, ChannelEmail, email, PurposeSignup, code, ip)
	if err != nil {
		return Session{}, err
	}
	hash, err := s.hasher.hash(password)
	if err != nil {
		return Session{}, err
	}
	var out Session
	err = s.db.InTx(ctx, func(ctx context.Context) error {
		user, created, err := s.users.FindOrCreateByEmail(ctx, email)
		if err != nil {
			return err
		}
		q := store.New(s.db.Conn(ctx))
		if !created {
			if _, err := q.GetPassword(ctx, user.ID); err == nil {
				return errAccountExists
			} else if !database.IsNoRows(err) {
				return fmt.Errorf("lecture du mot de passe : %w", err)
			}
		}
		if err := s.consumeCode(ctx, otpID); err != nil {
			return err
		}
		if err := q.SetPassword(ctx, store.SetPasswordParams{UserID: user.ID, PasswordHash: hash}); err != nil {
			return fmt.Errorf("enregistrement du mot de passe : %w", err)
		}
		token, expiresAt, err := s.createSession(ctx, user.ID, userAgent)
		if err != nil {
			return err
		}
		out = Session{Token: token, ExpiresAt: expiresAt, IsNewUser: created, User: user}
		return nil
	})
	return out, err
}

// --- Connexion par mot de passe -----------------------------------------------------------

// Login ouvre une session avec l'e-mail et le mot de passe. Le message d'erreur et le temps de
// réponse sont les mêmes que le compte existe ou non. Après MaxLoginFailures échecs, le compte
// est verrouillé LockDuration.
func (s *Service) Login(ctx context.Context, rawEmail, password, userAgent, ip string) (Session, error) {
	email, err := s.email(rawEmail)
	if err != nil {
		return Session{}, errInvalidCredentials
	}
	if ok, retry := s.loginIP.Allow(ip); !ok {
		return Session{}, apperr.TooManyRequests("rate_limited", "Trop de tentatives depuis votre réseau. Réessayez plus tard.", retry)
	}
	if len(password) > 4*MaxPasswordLength {
		return Session{}, errInvalidCredentials
	}
	q := store.New(s.db.Pool)
	user, err := s.users.FindByEmail(ctx, email)
	var pw store.AuthPassword
	if err == nil {
		pw, err = q.GetPassword(ctx, user.ID)
	}
	if err != nil {
		if !apperr.IsCode(err, "user_not_found") && !database.IsNoRows(err) {
			return Session{}, fmt.Errorf("lecture du compte : %w", err)
		}
		_, _ = s.hasher.verify(password, s.hasher.dummy) // même durée qu'un vrai essai
		return Session{}, errInvalidCredentials
	}
	if pw.LockedUntil != nil && time.Now().Before(*pw.LockedUntil) {
		return Session{}, errLocked(*pw.LockedUntil)
	}
	ok, err := s.hasher.verify(password, pw.PasswordHash)
	if err != nil {
		return Session{}, fmt.Errorf("vérification du mot de passe : %w", err)
	}
	if !ok {
		lockedUntil, err := q.RecordLoginFailure(ctx, store.RecordLoginFailureParams{
			UserID: user.ID, MaxAttempts: MaxLoginFailures, LockSeconds: int32(LockDuration.Seconds()),
		})
		if err != nil {
			return Session{}, fmt.Errorf("comptage des échecs : %w", err)
		}
		if lockedUntil != nil && time.Now().Before(*lockedUntil) {
			return Session{}, errLocked(*lockedUntil)
		}
		return Session{}, errInvalidCredentials
	}
	if err := q.ResetLoginFailures(ctx, user.ID); err != nil {
		return Session{}, fmt.Errorf("remise à zéro des échecs : %w", err)
	}
	token, expiresAt, err := s.createSession(ctx, user.ID, userAgent)
	if err != nil {
		return Session{}, err
	}
	return Session{Token: token, ExpiresAt: expiresAt, User: user}, nil
}

func errLocked(until time.Time) error {
	secs := max(1, int(time.Until(until).Seconds()))
	return apperr.TooManyRequests("account_locked",
		fmt.Sprintf("Trop d'essais : compte bloqué %d min. Réessayez plus tard, ou utilisez « Mot de passe oublié ».", (secs+59)/60), secs)
}

// --- Mot de passe oublié ------------------------------------------------------------------

// RequestPasswordReset envoie un code de réinitialisation si le compte existe ; la réponse est la
// même sinon (aucun envoi).
func (s *Service) RequestPasswordReset(ctx context.Context, rawEmail, ip string) (OTPRequested, error) {
	email, err := s.email(rawEmail)
	if err != nil {
		return OTPRequested{}, err
	}
	if _, err := s.users.FindByEmail(ctx, email); err != nil {
		if apperr.IsCode(err, "user_not_found") {
			if ok, retry := s.reqByIP.Allow(ip); !ok {
				return OTPRequested{}, apperr.TooManyRequests("rate_limited", "Trop de demandes depuis votre réseau. Réessayez plus tard.", retry)
			}
			// Mêmes limites par adresse qu'un compte existant : la réponse ne révèle rien.
			if ok, _ := s.unknownMinute.Allow(email); !ok {
				return OTPRequested{}, errOTPPerMinute()
			}
			if ok, _ := s.unknownDay.Allow(email); !ok {
				return OTPRequested{}, errOTPPerDay()
			}
			return OTPRequested{Channel: ChannelEmail, ExpiresInSeconds: int(OTPTTL.Seconds()), ResendAfterSeconds: 60}, nil
		}
		return OTPRequested{}, err
	}
	return s.sendCode(ctx, ChannelEmail, email, PurposeReset, ip)
}

// ResetPassword vérifie le code, change le mot de passe (déverrouille le compte), déconnecte tous
// les appareils et ouvre une nouvelle session.
func (s *Service) ResetPassword(ctx context.Context, rawEmail, code, password, userAgent, ip string) (Session, error) {
	email, err := s.email(rawEmail)
	if err != nil {
		return Session{}, err
	}
	if err := checkPassword(password, email); err != nil {
		return Session{}, err
	}
	otpID, err := s.checkCode(ctx, ChannelEmail, email, PurposeReset, code, ip)
	if err != nil {
		return Session{}, err
	}
	hash, err := s.hasher.hash(password)
	if err != nil {
		return Session{}, err
	}
	var out Session
	err = s.db.InTx(ctx, func(ctx context.Context) error {
		user, err := s.users.FindByEmail(ctx, email)
		if apperr.IsCode(err, "user_not_found") {
			return errOTPInvalid
		}
		if err != nil {
			return err
		}
		if err := s.consumeCode(ctx, otpID); err != nil {
			return err
		}
		q := store.New(s.db.Conn(ctx))
		if err := q.SetPassword(ctx, store.SetPasswordParams{UserID: user.ID, PasswordHash: hash}); err != nil {
			return fmt.Errorf("enregistrement du mot de passe : %w", err)
		}
		if err := q.RevokeUserSessions(ctx, user.ID); err != nil {
			return fmt.Errorf("déconnexion des appareils : %w", err)
		}
		token, expiresAt, err := s.createSession(ctx, user.ID, userAgent)
		if err != nil {
			return err
		}
		out = Session{Token: token, ExpiresAt: expiresAt, User: user}
		return nil
	})
	return out, err
}

// ChangePassword change le mot de passe d'un utilisateur connecté. L'actuel est exigé s'il en
// existe un (un compte créé avec Google peut en définir un) ; les autres appareils sont déconnectés.
func (s *Service) ChangePassword(ctx context.Context, p identity.Principal, current, next string) error {
	user, err := s.users.Get(ctx, p.UserID)
	if err != nil {
		return err
	}
	email := ""
	if user.Email != nil {
		email = *user.Email
	}
	if err := checkPasswordField("new_password", next, email); err != nil {
		return err
	}
	q := store.New(s.db.Pool)
	pw, err := q.GetPassword(ctx, p.UserID)
	switch {
	case err == nil:
		if pw.LockedUntil != nil && time.Now().Before(*pw.LockedUntil) {
			return errLocked(*pw.LockedUntil)
		}
		ok, err := s.hasher.verify(current, pw.PasswordHash)
		if err != nil {
			return fmt.Errorf("vérification du mot de passe : %w", err)
		}
		if !ok {
			if _, err := q.RecordLoginFailure(ctx, store.RecordLoginFailureParams{
				UserID: p.UserID, MaxAttempts: MaxLoginFailures, LockSeconds: int32(LockDuration.Seconds()),
			}); err != nil {
				return fmt.Errorf("comptage des échecs : %w", err)
			}
			return apperr.Validation(map[string]string{"current_password": "Mot de passe actuel incorrect."})
		}
	case !database.IsNoRows(err):
		return fmt.Errorf("lecture du mot de passe : %w", err)
	}
	hash, err := s.hasher.hash(next)
	if err != nil {
		return err
	}
	return s.db.InTx(ctx, func(ctx context.Context) error {
		q := store.New(s.db.Conn(ctx))
		if err := q.SetPassword(ctx, store.SetPasswordParams{UserID: p.UserID, PasswordHash: hash}); err != nil {
			return fmt.Errorf("enregistrement du mot de passe : %w", err)
		}
		return q.RevokeOtherSessions(ctx, store.RevokeOtherSessionsParams{UserID: p.UserID, Keep: p.SessionID})
	})
}

// SetPassword définit le mot de passe d'un compte sans code ni mot de passe actuel : réservé aux
// données de démonstration locales (cmd/manage seed-dev), jamais exposé par l'API.
func (s *Service) SetPassword(ctx context.Context, userID uuid.UUID, password string) error {
	hash, err := s.hasher.hash(password)
	if err != nil {
		return err
	}
	return store.New(s.db.Conn(ctx)).SetPassword(ctx, store.SetPasswordParams{UserID: userID, PasswordHash: hash})
}

// --- Google -------------------------------------------------------------------------------

// GoogleEnabled indique si la connexion avec Google est configurée.
func (s *Service) GoogleEnabled() bool { return s.google.enabled() }

// GoogleSignIn vérifie le jeton d'identité Google de l'app et ouvre une session : compte déjà
// rattaché à ce compte Google, sinon compte existant de même e-mail (vérifié par Google), sinon
// nouveau compte acheteur.
func (s *Service) GoogleSignIn(ctx context.Context, idToken, userAgent, ip string) (Session, error) {
	if !s.google.enabled() {
		return Session{}, errGoogleDisabled
	}
	if ok, retry := s.loginIP.Allow(ip); !ok {
		return Session{}, apperr.TooManyRequests("rate_limited", "Trop de tentatives depuis votre réseau. Réessayez plus tard.", retry)
	}
	gid, err := s.google.verify(ctx, idToken)
	if err != nil {
		if errors.Is(err, errGoogleToken) {
			s.logger.Warn("jeton Google refusé", "err", err)
			return Session{}, errGoogleInvalid
		}
		return Session{}, err
	}
	var out Session
	err = s.db.InTx(ctx, func(ctx context.Context) error {
		q := store.New(s.db.Conn(ctx))
		var user users.User
		created := false
		linked, err := q.GetIdentity(ctx, store.GetIdentityParams{Provider: "google", Subject: gid.Subject})
		switch {
		case err == nil:
			if user, err = s.users.Get(ctx, linked.UserID); err != nil {
				return err
			}
		case database.IsNoRows(err):
			email, err := s.email(gid.Email)
			if err != nil {
				return errGoogleInvalid
			}
			if user, created, err = s.users.FindOrCreateByEmail(ctx, email); err != nil {
				return err
			}
			if err := q.CreateIdentity(ctx, store.CreateIdentityParams{Provider: "google", Subject: gid.Subject, UserID: user.ID}); err != nil {
				return fmt.Errorf("rattachement du compte Google : %w", err)
			}
		default:
			return fmt.Errorf("lecture du compte Google : %w", err)
		}
		token, expiresAt, err := s.createSession(ctx, user.ID, userAgent)
		if err != nil {
			return err
		}
		out = Session{Token: token, ExpiresAt: expiresAt, IsNewUser: created, User: user}
		return nil
	})
	return out, err
}

// --- Double vérification (back-office) ----------------------------------------------------

// SessionInfo décrit la session courante.
type SessionInfo struct {
	MFAVerified bool `json:"mfa_verified"`
	HasPassword bool `json:"has_password"`
	// MFAMethod : second facteur attendu, « totp » (application d'authentification) ou « email ».
	MFAMethod string `json:"mfa_method"`
	// RecoveryCodesLeft : codes de secours restants (application d'authentification activée).
	RecoveryCodesLeft int       `json:"recovery_codes_left"`
	ExpiresAt         time.Time `json:"expires_at"`
}

// RequestMFACode envoie le code de vérification à l'e-mail du compte connecté.
func (s *Service) RequestMFACode(ctx context.Context, p identity.Principal, ip string) (OTPRequested, error) {
	if on, err := s.TOTPEnabled(ctx, p.UserID); err != nil {
		return OTPRequested{}, err
	} else if on {
		return OTPRequested{}, errTOTPRequired // pas de retour à l'e-mail une fois l'application activée
	}
	email, err := s.accountEmail(ctx, p.UserID)
	if err != nil {
		return OTPRequested{}, err
	}
	return s.sendCode(ctx, ChannelEmail, email, PurposeMFA, ip)
}

// VerifyMFA vérifie le code et marque la session comme vérifiée, pour AdminSessionCap au plus.
// Seule une session vérifiée ouvre les routes admin.
func (s *Service) VerifyMFA(ctx context.Context, p identity.Principal, code, ip string) (SessionInfo, error) {
	totp, hasTOTP, err := s.totpState(ctx, p.UserID)
	if err != nil {
		return SessionInfo{}, err
	}
	if hasTOTP && totp.ConfirmedAt != nil {
		err = s.db.InTx(ctx, func(ctx context.Context) error {
			if err := s.verifySecondFactor(ctx, p.UserID, totp, code); err != nil {
				return err
			}
			_, err := store.New(s.db.Conn(ctx)).MarkSessionMFA(ctx, store.MarkSessionMFAParams{ID: p.SessionID, Cap: time.Now().Add(AdminSessionCap)})
			if database.IsNoRows(err) {
				return errInvalidSession
			}
			return err
		})
		if err != nil {
			return SessionInfo{}, err
		}
		return s.SessionInfo(ctx, p)
	}
	email, err := s.accountEmail(ctx, p.UserID)
	if err != nil {
		return SessionInfo{}, err
	}
	otpID, err := s.checkCode(ctx, ChannelEmail, email, PurposeMFA, code, ip)
	if err != nil {
		return SessionInfo{}, err
	}
	err = s.db.InTx(ctx, func(ctx context.Context) error {
		if err := s.consumeCode(ctx, otpID); err != nil {
			return err
		}
		_, err := store.New(s.db.Conn(ctx)).MarkSessionMFA(ctx, store.MarkSessionMFAParams{ID: p.SessionID, Cap: time.Now().Add(AdminSessionCap)})
		if database.IsNoRows(err) {
			return errInvalidSession
		}
		return err
	})
	if err != nil {
		return SessionInfo{}, err
	}
	return s.SessionInfo(ctx, p)
}

// SessionInfo retourne l'état de la session courante (vérification, mot de passe, expiration).
func (s *Service) SessionInfo(ctx context.Context, p identity.Principal) (SessionInfo, error) {
	q := store.New(s.db.Pool)
	sess, err := q.GetSession(ctx, p.SessionID)
	if database.IsNoRows(err) {
		return SessionInfo{}, errInvalidSession
	}
	if err != nil {
		return SessionInfo{}, fmt.Errorf("lecture de la session : %w", err)
	}
	_, pwErr := q.GetPassword(ctx, p.UserID)
	if pwErr != nil && !database.IsNoRows(pwErr) {
		return SessionInfo{}, fmt.Errorf("lecture du mot de passe : %w", pwErr)
	}
	info := SessionInfo{MFAVerified: sess.MfaVerifiedAt != nil, HasPassword: pwErr == nil, MFAMethod: "email", ExpiresAt: sess.ExpiresAt}
	if on, err := s.TOTPEnabled(ctx, p.UserID); err != nil {
		return SessionInfo{}, err
	} else if on {
		info.MFAMethod = "totp"
		left, err := q.CountRecoveryCodesLeft(ctx, p.UserID)
		if err != nil {
			return SessionInfo{}, fmt.Errorf("codes de secours : %w", err)
		}
		info.RecoveryCodesLeft = int(left)
	}
	return info, nil
}

func (s *Service) accountEmail(ctx context.Context, userID uuid.UUID) (string, error) {
	user, err := s.users.Get(ctx, userID)
	if err != nil {
		return "", err
	}
	if user.Email == nil {
		return "", apperr.Conflict("no_email", "Ce compte n'a pas d'adresse e-mail.")
	}
	return *user.Email, nil
}
