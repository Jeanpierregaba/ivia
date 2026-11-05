package auth

import (
	"context"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"fmt"
	"sync"
	"time"

	"github.com/google/uuid"

	"ivia/backend/internal/auth/store"
	"ivia/backend/internal/platform/apperr"
	"ivia/backend/internal/platform/database"
	"ivia/backend/internal/platform/validate"
	"ivia/backend/internal/users"
)

// Connexion par numéro de téléphone (ADR 0012, spec 001 v2) : un code à 6 chiffres part par
// WhatsApp (SMS en secours) ; un numéro connu ouvre une session, un numéro inconnu ouvre une
// inscription en attente (le compte n'est créé qu'avec le nom, au plus 15 minutes plus tard).

const (
	// PhoneOTPTTL : durée de validité d'un code envoyé par WhatsApp ou SMS.
	PhoneOTPTTL = 5 * time.Minute
	// PhoneLockDuration : verrou du numéro après OTPMaxAttempts codes faux.
	PhoneLockDuration = 15 * time.Minute
	// PendingSignupTTL : délai pour saisir son nom après la vérification du code.
	PendingSignupTTL = 15 * time.Minute
	// PhoneCodesPerDevicePerHour : codes demandés au plus par appareil et par heure.
	PhoneCodesPerDevicePerHour = 10
	// refreshReuseGrace : un ancien jeton de rafraîchissement présenté juste après son
	// remplacement (deux requêtes simultanées de l'app) ne révoque pas la session.
	refreshReuseGrace = 30 * time.Second
)

var (
	errPhoneDisabled = apperr.BadRequest("otp_channel_unavailable", "La connexion par numéro n'est pas encore disponible.")
	errSignupExpired = apperr.Unauthorized("signup_expired", "Votre inscription a expiré. Recommencez avec un nouveau code.")
	errServiceBusy   = apperr.Unavailable("otp_service_busy", "Le service d'envoi des codes est très demandé. Réessayez dans quelques minutes.")
)

// DeviceInfo décrit l'appareil qui se connecte. ID est l'identifiant d'installation tiré au hasard
// par l'app (jamais un identifiant matériel) ; il n'est gardé que haché.
type DeviceInfo struct {
	ID   string `json:"device_id"`
	Name string `json:"device_name"`
	// App : buyer, seller, driver ou pharmacy (destinataire des alertes de sécurité).
	App string `json:"app"`
}

func (d *DeviceInfo) validate(v validate.Errors) {
	d.Name = validate.Clean(d.Name)
	if len(d.Name) > 80 {
		d.Name = d.Name[:80]
	}
	if len(d.ID) < 8 || len(d.ID) > 100 {
		v.Add("device_id", "Identifiant d'appareil manquant.")
	}
	switch d.App {
	case "":
		d.App = "buyer"
	case "buyer", "seller", "driver", "pharmacy":
	default:
		v.Add("app", "Application inconnue.")
	}
}

// PhoneCodeInput demande un code par numéro.
type PhoneCodeInput struct {
	Phone string `json:"phone"`
	// Channel : whatsapp (par défaut) ou sms (« Recevoir par SMS »).
	Channel Channel `json:"channel"`
	DeviceInfo
}

// PhoneVerifyInput vérifie le code reçu.
type PhoneVerifyInput struct {
	Phone string `json:"phone"`
	Code  string `json:"code"`
	DeviceInfo
}

// PhoneSignupInput termine une inscription en attente.
type PhoneSignupInput struct {
	SignupToken string `json:"signup_token"`
	users.PhoneSignup
	DeviceInfo
}

// PhoneVerifyResult : signed_in (session ouverte) ou signup_required (numéro prouvé, nom à saisir
// avec signup_token avant signup_expires_at).
type PhoneVerifyResult struct {
	Status          string     `json:"status"`
	Session         *Session   `json:"session,omitempty"`
	SignupToken     string     `json:"signup_token,omitempty"`
	SignupExpiresAt *time.Time `json:"signup_expires_at,omitempty"`
}

func (s *Service) phoneEnabled() bool { return len(s.opts.PhoneChannels) > 0 }

// PhoneEnabled indique si la connexion par numéro est ouverte (GET /v1/auth/providers).
func (s *Service) PhoneEnabled() bool { return s.phoneEnabled() }

func normalizePhone(raw string) (string, error) {
	phone, ok := validate.NormalizeTogoPhone(raw)
	if !ok {
		return "", apperr.Validation(map[string]string{"phone": "Numéro mobile togolais attendu (8 chiffres commençant par 7 ou 9)."})
	}
	return phone, nil
}

// phoneVia : canaux à essayer, celui demandé d'abord, puis les autres en secours.
func (s *Service) phoneVia(preferred Channel) []Channel {
	out := make([]Channel, 0, len(s.opts.PhoneChannels))
	for _, c := range s.opts.PhoneChannels {
		if c == preferred {
			out = append(out, c)
		}
	}
	for _, c := range s.opts.PhoneChannels {
		if c != preferred {
			out = append(out, c)
		}
	}
	return out
}

// checkPhoneLock refuse un numéro verrouillé (trop de codes faux).
func (s *Service) checkPhoneLock(ctx context.Context, phone string) error {
	until, err := store.New(s.db.Pool).GetRecipientLock(ctx, store.GetRecipientLockParams{Channel: string(ChannelPhone), Recipient: phone})
	if database.IsNoRows(err) {
		return nil
	}
	if err != nil {
		return fmt.Errorf("lecture du verrou : %w", err)
	}
	return errPhoneLocked(until)
}

func errPhoneLocked(until time.Time) error {
	retry := int(time.Until(until).Seconds()) + 1
	if retry < 1 {
		retry = 1
	}
	return apperr.TooManyRequests("phone_locked", "Trop de codes incorrects. Ce numéro est bloqué pendant 15 minutes.", retry)
}

// lockPhone verrouille le numéro et annule ses codes en cours (5 codes faux).
func (s *Service) lockPhone(ctx context.Context, phone string) error {
	until := time.Now().Add(PhoneLockDuration)
	err := s.db.InTx(ctx, func(ctx context.Context) error {
		q := store.New(s.db.Conn(ctx))
		if err := q.LockRecipientUntil(ctx, store.LockRecipientUntilParams{Channel: string(ChannelPhone), Recipient: phone, LockedUntil: until}); err != nil {
			return err
		}
		return q.InvalidateAllOTPs(ctx, store.InvalidateAllOTPsParams{Channel: string(ChannelPhone), Recipient: phone})
	})
	if err != nil {
		return fmt.Errorf("verrou du numéro : %w", err)
	}
	s.logger.Warn("numéro verrouillé après trop de codes faux", "minutes", int(PhoneLockDuration.Minutes()))
	return errPhoneLocked(until)
}

// RequestPhoneCode envoie un code de connexion au numéro. La réponse est la même que le numéro ait
// un compte ou non. Limites : celles du destinataire (1 par minute, 10 par jour), 10 par appareil
// et par heure, le plafond par IP et un plafond global horaire.
func (s *Service) RequestPhoneCode(ctx context.Context, in PhoneCodeInput, ip string) (OTPRequested, error) {
	if !s.phoneEnabled() {
		return OTPRequested{}, errPhoneDisabled
	}
	phone, err := normalizePhone(in.Phone)
	if err != nil {
		return OTPRequested{}, err
	}
	v := validate.New()
	in.validate(v)
	if in.Channel != "" && in.Channel != ChannelWhatsApp && in.Channel != ChannelSMS {
		v.Add("channel", "Canal attendu : whatsapp ou sms.")
	}
	if err := v.Err(); err != nil {
		return OTPRequested{}, err
	}
	return s.sendPhoneCode(ctx, phone, in.Channel, PurposePhoneLogin, "device:"+string(s.deviceHash(in.ID)), ip)
}

func (s *Service) sendPhoneCode(ctx context.Context, phone string, preferred Channel, purpose Purpose, limiterKey, ip string) (OTPRequested, error) {
	if err := s.checkPhoneLock(ctx, phone); err != nil {
		return OTPRequested{}, err
	}
	if ok, retry := s.byDevice.Allow(limiterKey); !ok {
		return OTPRequested{}, apperr.TooManyRequests("rate_limited", "Trop de codes demandés depuis cet appareil. Réessayez plus tard.", retry)
	}
	n, err := store.New(s.db.Pool).CountRecentPhoneOTPs(ctx, time.Now().Add(-time.Hour))
	if err != nil {
		return OTPRequested{}, fmt.Errorf("plafond global : %w", err)
	}
	if n >= int64(s.opts.PhoneCodesPerHour) {
		s.alertCapReached(ctx)
		return OTPRequested{}, errServiceBusy
	}
	if preferred == "" {
		preferred = ChannelWhatsApp
	}
	return s.sendCodeVia(ctx, ChannelPhone, phone, purpose, ip, PhoneOTPTTL, s.phoneVia(preferred))
}

// alertGate n'envoie une même alerte qu'une fois par heure.
type alertGate struct {
	mu   sync.Mutex
	last time.Time
}

func (g *alertGate) open() bool {
	g.mu.Lock()
	defer g.mu.Unlock()
	if time.Since(g.last) < time.Hour {
		return false
	}
	g.last = time.Now()
	return true
}

func (s *Service) alertCapReached(ctx context.Context) {
	if !s.capAlert.open() {
		return
	}
	s.logger.Error("plafond horaire des codes WhatsApp/SMS atteint", "cap", s.opts.PhoneCodesPerHour)
	if s.notifier == nil {
		return
	}
	body := fmt.Sprintf("Plus de %d codes de connexion envoyés en une heure : les nouvelles demandes sont refusées. Vérifiez qu'il ne s'agit pas d'une fraude aux SMS, ou relevez le plafond (PHONE_CODES_PER_HOUR).", s.opts.PhoneCodesPerHour)
	if err := s.notifier.NotifyAdmins(context.WithoutCancel(ctx), "auth_otp_cap", "Envoi des codes suspendu", body, nil); err != nil {
		s.logger.Warn("alerte du plafond non envoyée", "err", err)
	}
}

// VerifyPhone vérifie le code. Numéro connu : session ouverte (alerte si l'appareil est nouveau).
// Numéro inconnu : inscription en attente, sans compte créé. 5 codes faux verrouillent le numéro
// 15 minutes.
func (s *Service) VerifyPhone(ctx context.Context, in PhoneVerifyInput, userAgent, ip string) (PhoneVerifyResult, error) {
	if !s.phoneEnabled() {
		return PhoneVerifyResult{}, errPhoneDisabled
	}
	phone, err := normalizePhone(in.Phone)
	if err != nil {
		return PhoneVerifyResult{}, err
	}
	v := validate.New()
	in.validate(v)
	if err := v.Err(); err != nil {
		return PhoneVerifyResult{}, err
	}
	if err := s.checkPhoneLock(ctx, phone); err != nil {
		return PhoneVerifyResult{}, err
	}
	otpID, err := s.checkCode(ctx, ChannelPhone, phone, PurposePhoneLogin, in.Code, ip)
	if apperr.IsCode(err, "otp_too_many_attempts") {
		return PhoneVerifyResult{}, s.lockPhone(ctx, phone)
	}
	if err != nil {
		return PhoneVerifyResult{}, err
	}

	var out PhoneVerifyResult
	err = s.db.InTx(ctx, func(ctx context.Context) error {
		if err := s.consumeCode(ctx, otpID); err != nil {
			return err
		}
		user, err := s.users.FindByPhone(ctx, phone)
		if apperr.IsCode(err, "user_not_found") {
			token, err := randomToken()
			if err != nil {
				return err
			}
			expires := time.Now().Add(PendingSignupTTL)
			if err := store.New(s.db.Conn(ctx)).CreatePendingSignup(ctx, store.CreatePendingSignupParams{TokenHash: hashToken(token), Phone: phone, ExpiresAt: expires}); err != nil {
				return fmt.Errorf("inscription en attente : %w", err)
			}
			out = PhoneVerifyResult{Status: "signup_required", SignupToken: token, SignupExpiresAt: &expires}
			return nil
		}
		if err != nil {
			return err
		}
		if !user.PhoneVerified {
			if err := s.users.MarkPhoneVerified(ctx, user.ID); err != nil {
				return err
			}
			user.PhoneVerified = true
		}
		sess, err := s.openMobileSession(ctx, user, in.DeviceInfo, userAgent)
		if err != nil {
			return err
		}
		out = PhoneVerifyResult{Status: "signed_in", Session: &sess}
		return nil
	})
	return out, err
}

// PhoneSignup crée le compte d'une inscription en attente (nom, consentement) et ouvre la
// session. Le back-office est prévenu du nouvel acheteur.
func (s *Service) PhoneSignup(ctx context.Context, in PhoneSignupInput, userAgent string) (Session, error) {
	if !s.phoneEnabled() {
		return Session{}, errPhoneDisabled
	}
	v := validate.New()
	in.validate(v)
	if err := v.Err(); err != nil {
		return Session{}, err
	}
	// Profil contrôlé avant de consommer l'inscription : une faute de saisie se corrige.
	if err := users.ValidatePhoneSignup(&in.PhoneSignup); err != nil {
		return Session{}, err
	}
	if len(in.SignupToken) < 40 || len(in.SignupToken) > 64 {
		return Session{}, errSignupExpired
	}
	var out Session
	err := s.db.InTx(ctx, func(ctx context.Context) error {
		phone, err := store.New(s.db.Conn(ctx)).ConsumePendingSignup(ctx, hashToken(in.SignupToken))
		if database.IsNoRows(err) {
			return errSignupExpired
		}
		if err != nil {
			return fmt.Errorf("lecture de l'inscription : %w", err)
		}
		user, created, err := s.users.CreateWithPhone(ctx, phone, in.PhoneSignup)
		if err != nil {
			return err
		}
		if out, err = s.openMobileSession(ctx, user, in.DeviceInfo, userAgent); err != nil {
			return err
		}
		out.IsNewUser = created
		if created && s.notifier != nil {
			return s.notifier.NotifyAdmins(ctx, "new_buyer", "Nouvel acheteur",
				"Un nouvel acheteur vient de créer son compte.", map[string]string{"user_id": user.ID.String()})
		}
		return nil
	})
	return out, err
}

func (s *Service) deviceHash(deviceID string) []byte {
	h := hmac.New(sha256.New, s.opts.Secret)
	h.Write([]byte("device\x00" + deviceID))
	return h.Sum(nil)
}

// openMobileSession enregistre l'appareil et ouvre une session à jeton d'accès court et jeton de
// rafraîchissement. Un appareil inconnu d'un compte qui en a déjà déclenche une alerte.
func (s *Service) openMobileSession(ctx context.Context, user users.User, dev DeviceInfo, userAgent string) (Session, error) {
	q := store.New(s.db.Conn(ctx))
	known, err := q.CountDevices(ctx, user.ID)
	if err != nil {
		return Session{}, fmt.Errorf("lecture des appareils : %w", err)
	}
	d, err := q.UpsertDevice(ctx, store.UpsertDeviceParams{UserID: user.ID, DeviceHash: s.deviceHash(dev.ID), Name: dev.Name})
	if err != nil {
		return Session{}, fmt.Errorf("enregistrement de l'appareil : %w", err)
	}
	if d.Inserted && known > 0 && s.notifier != nil {
		name := dev.Name
		if name == "" {
			name = "appareil inconnu"
		}
		body := "Votre compte ivia vient d'être ouvert sur un nouvel appareil (" + name + "). Si ce n'est pas vous, " +
			"déconnectez-le dans Profil › Appareils connectés."
		if err := s.notifier.NotifyUser(ctx, user.ID, dev.App, "new_device_login", "Nouvelle connexion à votre compte", body, nil); err != nil {
			return Session{}, err
		}
	}
	access, refresh, err := randomToken2()
	if err != nil {
		return Session{}, err
	}
	if len(userAgent) > 300 {
		userAgent = userAgent[:300]
	}
	accessExp := time.Now().Add(s.opts.AccessTTL)
	app := dev.App
	row, err := q.CreateRefreshableSession(ctx, store.CreateRefreshableSessionParams{
		UserID: user.ID, TokenHash: hashToken(access), RefreshHash: hashToken(refresh), UserAgent: userAgent,
		ExpiresAt: time.Now().Add(s.opts.SessionTTL), AccessExpiresAt: &accessExp, DeviceID: &d.ID, App: &app,
	})
	if err != nil {
		return Session{}, fmt.Errorf("création de la session : %w", err)
	}
	return Session{Token: access, RefreshToken: refresh, AccessExpiresAt: &accessExp, ExpiresAt: row.ExpiresAt, User: user}, nil
}

// Refresh échange un jeton de rafraîchissement contre un nouveau couple de jetons. Un ancien jeton
// présenté à nouveau (hors du délai de grâce) révoque la session : il a pu être volé.
func (s *Service) Refresh(ctx context.Context, refreshToken string) (Session, error) {
	if len(refreshToken) < 40 || len(refreshToken) > 64 {
		return Session{}, errInvalidSession
	}
	q := store.New(s.db.Pool)
	old := hashToken(refreshToken)
	sess, err := q.GetSessionByRefresh(ctx, old)
	if database.IsNoRows(err) {
		prev, perr := q.GetSessionByPreviousRefresh(ctx, old)
		if perr == nil && (prev.RefreshedAt == nil || time.Since(*prev.RefreshedAt) > refreshReuseGrace) {
			if err := q.RevokeSession(ctx, prev.ID); err != nil {
				return Session{}, fmt.Errorf("révocation : %w", err)
			}
			s.logger.Warn("jeton de rafraîchissement réutilisé : session révoquée", "session_id", prev.ID)
		}
		return Session{}, errInvalidSession
	}
	if err != nil {
		return Session{}, fmt.Errorf("lecture de la session : %w", err)
	}
	user, err := s.users.Get(ctx, sess.UserID)
	if apperr.IsCode(err, "user_not_found") {
		return Session{}, errInvalidSession
	}
	if err != nil {
		return Session{}, err
	}
	access, refresh, err := randomToken2()
	if err != nil {
		return Session{}, err
	}
	accessExp := time.Now().Add(s.opts.AccessTTL)
	expires := time.Now().Add(s.opts.SessionTTL)
	n, err := q.RotateSession(ctx, store.RotateSessionParams{
		ID: sess.ID, TokenHash: hashToken(access), RefreshHash: hashToken(refresh), OldRefreshHash: old,
		AccessExpiresAt: &accessExp, ExpiresAt: expires,
	})
	if err != nil {
		return Session{}, fmt.Errorf("renouvellement de la session : %w", err)
	}
	if n == 0 {
		return Session{}, errInvalidSession // un autre renouvellement est passé avant
	}
	if sess.ExpiresCap != nil && sess.ExpiresCap.Before(expires) {
		expires = *sess.ExpiresCap
	}
	return Session{Token: access, RefreshToken: refresh, AccessExpiresAt: &accessExp, ExpiresAt: expires, User: user}, nil
}

// RequestPhoneChange envoie un code au nouveau numéro d'un compte connecté.
func (s *Service) RequestPhoneChange(ctx context.Context, userID uuid.UUID, rawPhone string, channel Channel, ip string) (OTPRequested, error) {
	if !s.phoneEnabled() {
		return OTPRequested{}, errPhoneDisabled
	}
	phone, err := normalizePhone(rawPhone)
	if err != nil {
		return OTPRequested{}, err
	}
	if channel != "" && channel != ChannelWhatsApp && channel != ChannelSMS {
		return OTPRequested{}, apperr.Validation(map[string]string{"channel": "Canal attendu : whatsapp ou sms."})
	}
	return s.sendPhoneCode(ctx, phone, channel, PurposePhoneChange, "user:"+userID.String(), ip)
}

// ConfirmPhoneChange vérifie le code et remplace le numéro du compte.
func (s *Service) ConfirmPhoneChange(ctx context.Context, userID uuid.UUID, rawPhone, code, ip string) (users.User, error) {
	phone, err := normalizePhone(rawPhone)
	if err != nil {
		return users.User{}, err
	}
	if err := s.checkPhoneLock(ctx, phone); err != nil {
		return users.User{}, err
	}
	otpID, err := s.checkCode(ctx, ChannelPhone, phone, PurposePhoneChange, code, ip)
	if apperr.IsCode(err, "otp_too_many_attempts") {
		return users.User{}, s.lockPhone(ctx, phone)
	}
	if err != nil {
		return users.User{}, err
	}
	var out users.User
	err = s.db.InTx(ctx, func(ctx context.Context) error {
		if err := s.consumeCode(ctx, otpID); err != nil {
			return err
		}
		out, err = s.users.SetVerifiedPhone(ctx, userID, phone)
		return err
	})
	return out, err
}

// SessionView est une session active, vue par son titulaire (« Appareils connectés »).
type SessionView struct {
	ID         uuid.UUID `json:"id"`
	DeviceName string    `json:"device_name"`
	UserAgent  string    `json:"user_agent"`
	App        *string   `json:"app"`
	CreatedAt  time.Time `json:"created_at"`
	LastUsedAt time.Time `json:"last_used_at"`
	Current    bool      `json:"current"`
}

// ListSessions retourne les sessions actives d'un utilisateur, la plus récente d'abord.
func (s *Service) ListSessions(ctx context.Context, userID, current uuid.UUID) ([]SessionView, error) {
	rows, err := store.New(s.db.Pool).ListUserSessions(ctx, userID)
	if err != nil {
		return nil, fmt.Errorf("lecture des sessions : %w", err)
	}
	out := make([]SessionView, len(rows))
	for i, r := range rows {
		out[i] = SessionView{ID: r.ID, DeviceName: r.DeviceName, UserAgent: r.UserAgent, App: r.App,
			CreatedAt: r.CreatedAt, LastUsedAt: r.LastUsedAt, Current: r.ID == current}
	}
	return out, nil
}

// RevokeSession déconnecte une session de l'utilisateur (un autre appareil).
func (s *Service) RevokeSession(ctx context.Context, userID, sessionID uuid.UUID) error {
	n, err := store.New(s.db.Pool).RevokeUserSession(ctx, store.RevokeUserSessionParams{ID: sessionID, UserID: userID})
	if err != nil {
		return fmt.Errorf("révocation : %w", err)
	}
	if n == 0 {
		return apperr.NotFound("session_not_found", "Session introuvable.")
	}
	return nil
}

func randomToken() (string, error) {
	raw := make([]byte, 32)
	if _, err := rand.Read(raw); err != nil {
		return "", fmt.Errorf("génération du jeton : %w", err)
	}
	return base64.RawURLEncoding.EncodeToString(raw), nil
}

func randomToken2() (string, string, error) {
	a, err := randomToken()
	if err != nil {
		return "", "", err
	}
	b, err := randomToken()
	return a, b, err
}
