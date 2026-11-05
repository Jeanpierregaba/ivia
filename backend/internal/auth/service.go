// Package auth gère les comptes et les sessions opaques (ADR 0011, qui remplace l'ADR 0006) :
// création de compte avec un code reçu par e-mail puis un mot de passe, connexion par mot de passe
// ou par Google, mot de passe oublié, double vérification par code pour les admins.
//
// Le code n'est jamais stocké en clair : seul son HMAC (clé AUTH_SECRET, liée au canal, à l'usage
// et au destinataire) l'est. Le mot de passe est haché en Argon2id (password.go). Le jeton de
// session est 32 octets aléatoires ; seul son SHA-256 est stocké.
package auth

import (
	"context"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"fmt"
	"log/slog"
	"math/big"
	"time"

	"github.com/google/uuid"

	"ivia/backend/internal/auth/store"
	"ivia/backend/internal/platform/apperr"
	"ivia/backend/internal/platform/database"
	"ivia/backend/internal/platform/identity"
	"ivia/backend/internal/platform/ratelimit"
	"ivia/backend/internal/platform/validate"
	"ivia/backend/internal/users"
)

// Règles des codes (ADR 0006).
const (
	OTPTTL          = 10 * time.Minute
	OTPMaxAttempts  = 5
	OTPPerMinute    = 1
	OTPPerDay       = 10
	sessionTouchGap = time.Hour
)

// Channel est le canal d'envoi du code.
type Channel string

const (
	ChannelEmail Channel = "email"
	// ChannelPhone : identifiant « numéro de téléphone » ; le code part par WhatsApp ou par SMS.
	ChannelPhone    Channel = "phone"
	ChannelWhatsApp Channel = "whatsapp"
	ChannelSMS      Channel = "sms"
)

// Purpose est l'usage d'un code : il fixe le texte de l'e-mail et n'est valable que pour cet usage.
type Purpose string

const (
	// PurposeLogin : ancienne connexion par code (ADR 0006), gardée le temps que les apps migrent.
	PurposeLogin  Purpose = "login"
	PurposeSignup Purpose = "signup"
	PurposeReset  Purpose = "reset"
	PurposeMFA    Purpose = "mfa"
	// PurposePhoneLogin : connexion ou inscription par numéro (ADR 0012).
	PurposePhoneLogin Purpose = "phone_login"
	// PurposePhoneChange : confirmation d'un nouveau numéro sur un compte connecté.
	PurposePhoneChange Purpose = "phone_change"
)

// OTPMessage est un code à envoyer.
type OTPMessage struct {
	Channel   Channel
	Recipient string
	Code      string
	Purpose   Purpose
}

// OTPSender envoie un code par un canal (e-mail au lancement, WhatsApp et SMS ensuite).
type OTPSender interface {
	Send(ctx context.Context, m OTPMessage) error
}

// UserDirectory est ce dont auth a besoin du module users.
type UserDirectory interface {
	FindOrCreateByEmail(ctx context.Context, email string) (users.User, bool, error)
	FindByEmail(ctx context.Context, email string) (users.User, error)
	FindByPhone(ctx context.Context, phone string) (users.User, error)
	MarkPhoneVerified(ctx context.Context, id uuid.UUID) error
	CreateWithPhone(ctx context.Context, phone string, in users.PhoneSignup) (users.User, bool, error)
	SetVerifiedPhone(ctx context.Context, id uuid.UUID, phone string) (users.User, error)
	Get(ctx context.Context, id uuid.UUID) (users.User, error)
	Roles(ctx context.Context, id uuid.UUID) ([]identity.Role, error)
}

// Options de configuration du service.
type Options struct {
	Secret     []byte
	SessionTTL time.Duration
	// Plafonds par adresse IP, volontairement hauts (IP partagées par les opérateurs mobiles).
	RequestsPerIPPerHour int
	VerifiesPerIPPerHour int
	// GoogleClientIDs : identifiants OAuth acceptés comme audience des jetons Google (Android, iOS,
	// web). Vide : connexion Google désactivée.
	GoogleClientIDs []string
	// PhoneChannels : canaux d'envoi des codes par numéro, dans l'ordre d'essai (whatsapp, sms).
	// Vide : connexion par numéro fermée.
	PhoneChannels []Channel
	// PhoneCodesPerHour : plafond global des codes WhatsApp et SMS par heure (fraude aux SMS) ;
	// au-delà, les demandes sont refusées et les admins prévenus. 0 : 1 000.
	PhoneCodesPerHour int
	// AccessTTL : durée du jeton d'accès des sessions à rafraîchissement. 0 : 15 minutes.
	AccessTTL time.Duration
}

// Notifier prévient les admins (back-office) et les utilisateurs (alertes de sécurité).
type Notifier interface {
	NotifyAdmins(ctx context.Context, kind, title, body string, data map[string]string) error
	NotifyUser(ctx context.Context, userID uuid.UUID, app, kind, title, body string, data map[string]string) error
}

// Service gère codes et sessions.
type Service struct {
	db       *database.DB
	users    UserDirectory
	sender   OTPSender
	logger   *slog.Logger
	opts     Options
	reqByIP  *ratelimit.Limiter
	verByIP  *ratelimit.Limiter
	loginIP  *ratelimit.Limiter
	channels map[Channel]bool
	hasher   *passwordHasher
	google   *googleVerifier
	notifier Notifier
	auditor  Auditor
	byDevice *ratelimit.Limiter
	capAlert alertGate
}

// SetNotifier branche les alertes (le module notifications est créé après auth).
func (s *Service) SetNotifier(n Notifier) { s.notifier = n }

// NewService crée le service. Seul le canal e-mail est ouvert au lancement.
func NewService(db *database.DB, userDir UserDirectory, sender OTPSender, logger *slog.Logger, opts Options) *Service {
	// Plafonds par IP élevés : une même IP d'opérateur mobile est partagée par de nombreux abonnés.
	// La vraie protection est la limite par destinataire (1 code par minute, 10 par jour, 5 essais).
	if opts.RequestsPerIPPerHour == 0 {
		opts.RequestsPerIPPerHour = 2000
	}
	if opts.VerifiesPerIPPerHour == 0 {
		opts.VerifiesPerIPPerHour = 4000
	}
	if opts.PhoneCodesPerHour == 0 {
		opts.PhoneCodesPerHour = 1000
	}
	if opts.AccessTTL == 0 {
		opts.AccessTTL = 15 * time.Minute
	}
	return &Service{
		db: db, users: userDir, sender: sender, logger: logger, opts: opts,
		reqByIP:  ratelimit.New(opts.RequestsPerIPPerHour, time.Hour),
		verByIP:  ratelimit.New(opts.VerifiesPerIPPerHour, time.Hour),
		loginIP:  ratelimit.New(opts.VerifiesPerIPPerHour, time.Hour),
		channels: map[Channel]bool{ChannelEmail: true},
		hasher:   newPasswordHasher(),
		google:   newGoogleVerifier(opts.GoogleClientIDs),
		byDevice: ratelimit.New(PhoneCodesPerDevicePerHour, time.Hour),
	}
}

// OTPRequested est la réponse à une demande de code, identique que le compte existe ou non.
type OTPRequested struct {
	Channel            Channel `json:"channel"`
	ExpiresInSeconds   int     `json:"expires_in_seconds"`
	ResendAfterSeconds int     `json:"resend_after_seconds"`
}

// Session est le résultat d'une connexion réussie. Les sessions des apps mobiles (connexion par
// numéro) ont un jeton d'accès court (token, jusqu'à access_expires_at) et un jeton de
// rafraîchissement (refresh_token) changé à chaque usage ; expires_at est alors la fin de la
// session si elle n'est plus rafraîchie.
type Session struct {
	Token           string     `json:"token"`
	RefreshToken    string     `json:"refresh_token,omitempty"`
	AccessExpiresAt *time.Time `json:"access_expires_at,omitempty"`
	ExpiresAt       time.Time  `json:"expires_at"`
	IsNewUser       bool       `json:"is_new_user"`
	User            users.User `json:"user"`
}

func (s *Service) normalize(channel Channel, recipient string) (string, error) {
	if !s.channels[channel] {
		return "", apperr.BadRequest("otp_channel_unavailable", "Ce mode de connexion n'est pas encore disponible.")
	}
	switch channel {
	case ChannelEmail:
		email, ok := validate.NormalizeEmail(recipient)
		if !ok {
			return "", apperr.Validation(map[string]string{"recipient": "Adresse e-mail invalide."})
		}
		return email, nil
	default:
		phone, ok := validate.NormalizeTogoPhone(recipient)
		if !ok {
			return "", apperr.Validation(map[string]string{"recipient": "Numéro mobile togolais invalide."})
		}
		return phone, nil
	}
}

// RequestOTP génère et envoie un code de connexion (ancienne connexion par code, en retrait).
// La réponse ne dit jamais si un compte existe.
func (s *Service) RequestOTP(ctx context.Context, channel Channel, recipient, ip string) (OTPRequested, error) {
	recipient, err := s.normalize(channel, recipient)
	if err != nil {
		return OTPRequested{}, err
	}
	return s.sendCode(ctx, channel, recipient, PurposeLogin, ip)
}

// sendCode génère, enregistre et envoie un code par e-mail pour un usage. recipient est déjà
// normalisé.
func (s *Service) sendCode(ctx context.Context, channel Channel, recipient string, purpose Purpose, ip string) (OTPRequested, error) {
	return s.sendCodeVia(ctx, channel, recipient, purpose, ip, OTPTTL, []Channel{channel})
}

// sendCodeVia génère, enregistre et envoie un code. channel est le type d'identifiant (email ou
// phone) ; via liste les canaux d'envoi à essayer dans l'ordre (WhatsApp puis SMS en secours). Les
// limites (1 code par minute et par usage, 10 par jour) valent par identifiant, tous canaux
// confondus.
func (s *Service) sendCodeVia(ctx context.Context, channel Channel, recipient string, purpose Purpose, ip string, ttl time.Duration, via []Channel) (OTPRequested, error) {
	if ok, retry := s.reqByIP.Allow(ip); !ok {
		return OTPRequested{}, apperr.TooManyRequests("rate_limited", "Trop de demandes depuis votre réseau. Réessayez plus tard.", retry)
	}

	code, err := randomDigits(6)
	if err != nil {
		return OTPRequested{}, err
	}
	var otpID uuid.UUID
	err = s.db.InTx(ctx, func(ctx context.Context) error {
		q := store.New(s.db.Conn(ctx))
		if err := q.LockRecipient(ctx, store.LockRecipientParams{Channel: string(channel), Recipient: recipient}); err != nil {
			return fmt.Errorf("verrou du destinataire : %w", err)
		}
		now := time.Now()
		purposeStr := string(purpose)
		lastMinute, err := q.CountRecentOTP(ctx, store.CountRecentOTPParams{Channel: string(channel), Recipient: recipient, Since: now.Add(-time.Minute), Purpose: &purposeStr})
		if err != nil {
			return fmt.Errorf("limite par minute : %w", err)
		}
		if lastMinute >= OTPPerMinute {
			return apperr.TooManyRequests("otp_rate_limited", "Un code vient d'être envoyé. Patientez une minute avant d'en demander un autre.", 60)
		}
		lastDay, err := q.CountRecentOTP(ctx, store.CountRecentOTPParams{Channel: string(channel), Recipient: recipient, Since: now.Add(-24 * time.Hour)})
		if err != nil {
			return fmt.Errorf("limite par jour : %w", err)
		}
		if lastDay >= OTPPerDay {
			return apperr.TooManyRequests("otp_daily_limit", "Nombre maximal de codes atteint pour aujourd'hui. Réessayez demain.", 3600)
		}
		if err := q.InvalidateOTPs(ctx, store.InvalidateOTPsParams{Channel: string(channel), Recipient: recipient, Purpose: string(purpose)}); err != nil {
			return fmt.Errorf("annulation des anciens codes : %w", err)
		}
		otpID, err = q.CreateOTP(ctx, store.CreateOTPParams{
			Channel: string(channel), Recipient: recipient, Purpose: string(purpose),
			CodeHash: s.hashCode(channel, purpose, recipient, code), ExpiresAt: now.Add(ttl),
		})
		if err != nil {
			return fmt.Errorf("enregistrement du code : %w", err)
		}
		return nil
	})
	if err != nil {
		return OTPRequested{}, err
	}

	for _, ch := range via {
		sendCtx, cancel := context.WithTimeout(ctx, 15*time.Second)
		err := s.sender.Send(sendCtx, OTPMessage{Channel: ch, Recipient: recipient, Code: code, Purpose: purpose})
		cancel()
		if err != nil {
			// Ni le destinataire ni le code dans le journal (SECURITY).
			s.logger.Warn("envoi du code impossible", "channel", ch, "purpose", purpose, "err", err)
			continue
		}
		sentVia := string(ch)
		if err := store.New(s.db.Pool).SetOTPSentVia(ctx, store.SetOTPSentViaParams{ID: otpID, SentVia: &sentVia}); err != nil {
			s.logger.Warn("canal d'envoi non noté", "err", err)
		}
		return OTPRequested{Channel: ch, ExpiresInSeconds: int(ttl.Seconds()), ResendAfterSeconds: 60}, nil
	}
	s.logger.Error("aucun canal n'a pu envoyer le code", "purpose", purpose, "tried", len(via))
	return OTPRequested{}, apperr.Unavailable("otp_send_failed", "Le code n'a pas pu être envoyé. Réessayez dans un instant.")
}

var (
	errOTPInvalid  = apperr.Unauthorized("otp_invalid", "Code incorrect ou expiré.")
	errOTPExpired  = apperr.Unauthorized("otp_expired", "Ce code a expiré. Demandez-en un nouveau.")
	errOTPAttempts = apperr.Unauthorized("otp_too_many_attempts", "Trop d'essais. Demandez un nouveau code.")
)

// Verify vérifie un code de connexion (ancienne connexion par code, en retrait) et ouvre une
// session. Le compte acheteur est créé à la première connexion.
func (s *Service) Verify(ctx context.Context, channel Channel, recipient, code, userAgent, ip string) (Session, error) {
	recipient, err := s.normalize(channel, recipient)
	if err != nil {
		return Session{}, err
	}
	otpID, err := s.checkCode(ctx, channel, recipient, PurposeLogin, code, ip)
	if err != nil {
		return Session{}, err
	}

	var out Session
	err = s.db.InTx(ctx, func(ctx context.Context) error {
		if err := s.consumeCode(ctx, otpID); err != nil {
			return err
		}
		// Seul l'e-mail est ouvert (normalize refuse les autres canaux) ; l'identifiant est l'e-mail.
		user, created, err := s.users.FindOrCreateByEmail(ctx, recipient)
		if err != nil {
			return err
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

// checkCode vérifie le dernier code actif d'un destinataire pour un usage et retourne son
// identifiant, à consommer (consumeCode) dans la transaction qui l'utilise. L'essai est compté
// avant la comparaison : impossible de dépasser 5 essais, même en parallèle.
func (s *Service) checkCode(ctx context.Context, channel Channel, recipient string, purpose Purpose, code, ip string) (uuid.UUID, error) {
	if ok, retry := s.verByIP.Allow(ip); !ok {
		return uuid.Nil, apperr.TooManyRequests("rate_limited", "Trop de tentatives depuis votre réseau. Réessayez plus tard.", retry)
	}
	if len(code) != 6 {
		return uuid.Nil, errOTPInvalid
	}
	q := store.New(s.db.Pool)
	otp, err := q.LatestActiveOTP(ctx, store.LatestActiveOTPParams{Channel: string(channel), Recipient: recipient, Purpose: string(purpose)})
	if database.IsNoRows(err) {
		return uuid.Nil, errOTPInvalid
	}
	if err != nil {
		return uuid.Nil, fmt.Errorf("lecture du code : %w", err)
	}
	if time.Now().After(otp.ExpiresAt) {
		return uuid.Nil, errOTPExpired
	}
	attempts, err := q.IncrementOTPAttempts(ctx, store.IncrementOTPAttemptsParams{ID: otp.ID, MaxAttempts: OTPMaxAttempts})
	if database.IsNoRows(err) {
		return uuid.Nil, errOTPAttempts
	}
	if err != nil {
		return uuid.Nil, fmt.Errorf("comptage des essais : %w", err)
	}
	if !hmac.Equal(otp.CodeHash, s.hashCode(channel, purpose, recipient, code)) {
		if attempts >= OTPMaxAttempts {
			return uuid.Nil, errOTPAttempts
		}
		return uuid.Nil, errOTPInvalid
	}
	return otp.ID, nil
}

// consumeCode marque un code comme utilisé : seule la première requête qui le consomme réussit.
func (s *Service) consumeCode(ctx context.Context, otpID uuid.UUID) error {
	n, err := store.New(s.db.Conn(ctx)).ConsumeOTP(ctx, otpID)
	if err != nil {
		return fmt.Errorf("consommation du code : %w", err)
	}
	if n == 0 {
		return errOTPInvalid // déjà utilisé par une requête simultanée
	}
	return nil
}

func (s *Service) createSession(ctx context.Context, userID uuid.UUID, userAgent string) (string, time.Time, error) {
	raw := make([]byte, 32)
	if _, err := rand.Read(raw); err != nil {
		return "", time.Time{}, fmt.Errorf("génération du jeton : %w", err)
	}
	token := base64.RawURLEncoding.EncodeToString(raw)
	if len(userAgent) > 300 {
		userAgent = userAgent[:300]
	}
	row, err := store.New(s.db.Conn(ctx)).CreateSession(ctx, store.CreateSessionParams{
		UserID: userID, TokenHash: hashToken(token), UserAgent: userAgent, ExpiresAt: time.Now().Add(s.opts.SessionTTL),
	})
	if err != nil {
		return "", time.Time{}, fmt.Errorf("création de la session : %w", err)
	}
	return token, row.ExpiresAt, nil
}

var (
	errInvalidSession = apperr.Unauthorized("invalid_session", "Votre session a expiré. Reconnectez-vous.")
	// errAccessExpired : le jeton d'accès court a expiré ; l'app le renouvelle avec son jeton de
	// rafraîchissement (POST /v1/auth/refresh) sans rien demander à l'utilisateur.
	errAccessExpired = apperr.Unauthorized("access_token_expired", "Session à renouveler.")
)

// Authenticate retrouve l'utilisateur d'un jeton de session (appelé à chaque requête). Les rôles
// sont relus à chaque fois : un rôle retiré ou un compte supprimé prend effet immédiatement.
func (s *Service) Authenticate(ctx context.Context, token string) (identity.Principal, error) {
	if len(token) < 40 || len(token) > 64 {
		return identity.Principal{}, errInvalidSession
	}
	q := store.New(s.db.Pool)
	sess, err := q.GetSessionByHash(ctx, hashToken(token))
	if database.IsNoRows(err) {
		return identity.Principal{}, errInvalidSession
	}
	if err != nil {
		return identity.Principal{}, fmt.Errorf("lecture de la session : %w", err)
	}
	if sess.AccessExpiresAt != nil && time.Now().After(*sess.AccessExpiresAt) {
		return identity.Principal{}, errAccessExpired
	}
	roles, err := s.users.Roles(ctx, sess.UserID)
	if apperr.IsCode(err, "user_not_found") {
		return identity.Principal{}, errInvalidSession
	}
	if err != nil {
		return identity.Principal{}, err
	}
	// Expiration glissante, écrite au plus une fois par heure pour éviter une écriture par requête.
	if time.Since(sess.LastUsedAt) > sessionTouchGap {
		if err := q.TouchSession(ctx, store.TouchSessionParams{ID: sess.ID, ExpiresAt: time.Now().Add(s.opts.SessionTTL)}); err != nil {
			s.logger.Warn("prolongation de session impossible", "err", err)
		}
	}
	return identity.Principal{UserID: sess.UserID, SessionID: sess.ID, Roles: roles, MFA: sess.MfaVerifiedAt != nil}, nil
}

// Logout révoque la session courante.
func (s *Service) Logout(ctx context.Context, sessionID uuid.UUID) error {
	if err := store.New(s.db.Conn(ctx)).RevokeSession(ctx, sessionID); err != nil {
		return fmt.Errorf("révocation de la session : %w", err)
	}
	return nil
}

// LogoutAll révoque toutes les sessions d'un utilisateur (tous ses appareils).
func (s *Service) LogoutAll(ctx context.Context, userID uuid.UUID) error {
	if err := store.New(s.db.Conn(ctx)).RevokeUserSessions(ctx, userID); err != nil {
		return fmt.Errorf("révocation des sessions : %w", err)
	}
	return nil
}

// OnAccountDeleted révoque toutes les sessions du compte supprimé et efface son mot de passe et
// ses comptes Google rattachés (users.DeletionHook).
func (s *Service) OnAccountDeleted(ctx context.Context, userID uuid.UUID) error {
	q := store.New(s.db.Conn(ctx))
	if err := q.DeletePassword(ctx, userID); err != nil {
		return fmt.Errorf("suppression du mot de passe : %w", err)
	}
	if err := q.DeleteIdentitiesOf(ctx, userID); err != nil {
		return fmt.Errorf("suppression des comptes rattachés : %w", err)
	}
	if err := q.DeleteDevicesOf(ctx, userID); err != nil {
		return fmt.Errorf("suppression des appareils : %w", err)
	}
	if err := q.DeleteTOTP(ctx, userID); err != nil {
		return fmt.Errorf("suppression de la double vérification : %w", err)
	}
	if err := q.DeleteRecoveryCodes(ctx, userID); err != nil {
		return fmt.Errorf("suppression des codes de secours : %w", err)
	}
	return s.LogoutAll(ctx, userID)
}

// Purge supprime les codes et sessions périmés (tâche de fond quotidienne).
func (s *Service) Purge(ctx context.Context) error {
	q := store.New(s.db.Conn(ctx))
	if _, err := q.PurgeOTPs(ctx); err != nil {
		return fmt.Errorf("purge des codes : %w", err)
	}
	if _, err := q.PurgePendingSignups(ctx); err != nil {
		return fmt.Errorf("purge des inscriptions en attente : %w", err)
	}
	if _, err := q.PurgeRecipientLocks(ctx); err != nil {
		return fmt.Errorf("purge des verrous : %w", err)
	}
	if _, err := q.PurgeSessions(ctx); err != nil {
		return fmt.Errorf("purge des sessions : %w", err)
	}
	return nil
}

func (s *Service) hashCode(channel Channel, purpose Purpose, recipient, code string) []byte {
	h := hmac.New(sha256.New, s.opts.Secret)
	h.Write([]byte(string(channel) + "\x00" + string(purpose) + "\x00" + recipient + "\x00" + code))
	return h.Sum(nil)
}

func hashToken(token string) []byte {
	sum := sha256.Sum256([]byte(token))
	return sum[:]
}

// randomDigits tire n chiffres uniformément avec crypto/rand.
func randomDigits(n int) (string, error) {
	max := new(big.Int).Exp(big.NewInt(10), big.NewInt(int64(n)), nil)
	v, err := rand.Int(rand.Reader, max)
	if err != nil {
		return "", fmt.Errorf("tirage du code : %w", err)
	}
	return fmt.Sprintf("%0*d", n, v), nil
}
