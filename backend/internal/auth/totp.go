package auth

import (
	"context"
	"crypto/aes"
	"crypto/cipher"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha1" //nolint:gosec // HMAC-SHA1 : algorithme imposé par TOTP (RFC 6238) et les applis d'authentification.
	"crypto/sha256"
	"encoding/base32"
	"encoding/binary"
	"errors"
	"fmt"
	"net/url"
	"strings"
	"time"

	"github.com/google/uuid"

	"ivia/backend/internal/admin"
	"ivia/backend/internal/auth/store"
	"ivia/backend/internal/platform/apperr"
	"ivia/backend/internal/platform/database"
	"ivia/backend/internal/platform/identity"
)

// Double vérification par application d'authentification (TOTP, RFC 6238 : 6 chiffres, pas de
// 30 s, SHA-1), avec 10 codes de secours à usage unique. Une fois activée, elle remplace le code
// par e-mail : on ne peut plus revenir à l'e-mail, seulement à un code de secours (ADR 0012).

const (
	totpPeriod = 30
	totpDigits = 6
	// recoveryCodeCount : codes de secours remis à l'activation. Les essais de code sont limités à
	// PhoneCodesPerDevicePerHour par compte et par heure (pas de compteur par code en TOTP).
	recoveryCodeCount = 10
)

var (
	errTOTPInvalid    = apperr.Unauthorized("otp_invalid", "Code incorrect.")
	errTOTPRequired   = apperr.Conflict("mfa_use_totp", "Saisissez le code de votre application d'authentification, ou un code de secours.")
	errTOTPNotStarted = apperr.Conflict("totp_not_started", "Commencez par afficher le QR code à scanner.")
	errTOTPEnabled    = apperr.Conflict("totp_already_enabled", "L'application d'authentification est déjà activée.")
	errTOTPDisabled   = apperr.Conflict("totp_not_enabled", "L'application d'authentification n'est pas activée.")
	errMFAFirst       = apperr.Forbidden("mfa_required", "Validez d'abord la double vérification.")
)

// Auditor journalise les actions des admins (module admin).
type Auditor interface {
	Record(ctx context.Context, e admin.AuditEntry) error
}

// SetAuditor branche le journal des actions admin.
func (s *Service) SetAuditor(a Auditor) { s.auditor = a }

// TOTPSetup : secret à saisir à la main et lien otpauth à afficher en QR code.
type TOTPSetup struct {
	Secret     string `json:"secret"`
	OtpauthURI string `json:"otpauth_uri"`
}

// RecoveryCodes : codes de secours, affichés une seule fois.
type RecoveryCodes struct {
	Codes []string `json:"recovery_codes"`
}

func (s *Service) totpKey() []byte {
	h := hmac.New(sha256.New, s.opts.Secret)
	h.Write([]byte("totp-secret-key"))
	return h.Sum(nil)
}

func (s *Service) sealTOTP(secret []byte) ([]byte, error) {
	block, err := aes.NewCipher(s.totpKey())
	if err != nil {
		return nil, err
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return nil, err
	}
	nonce := make([]byte, gcm.NonceSize())
	if _, err := rand.Read(nonce); err != nil {
		return nil, err
	}
	return gcm.Seal(nonce, nonce, secret, nil), nil
}

func (s *Service) openTOTP(sealed []byte) ([]byte, error) {
	block, err := aes.NewCipher(s.totpKey())
	if err != nil {
		return nil, err
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return nil, err
	}
	if len(sealed) < gcm.NonceSize() {
		return nil, errors.New("secret TOTP illisible")
	}
	return gcm.Open(nil, sealed[:gcm.NonceSize()], sealed[gcm.NonceSize():], nil)
}

// hotp calcule le code d'un pas (RFC 4226).
func hotp(secret []byte, step uint64) string {
	var msg [8]byte
	binary.BigEndian.PutUint64(msg[:], step)
	m := hmac.New(sha1.New, secret)
	m.Write(msg[:])
	sum := m.Sum(nil)
	off := sum[len(sum)-1] & 0x0f
	v := binary.BigEndian.Uint32(sum[off:off+4]) & 0x7fffffff
	return fmt.Sprintf("%0*d", totpDigits, v%1_000_000)
}

// matchTOTP retourne le pas qui correspond au code (pas courant, précédent ou suivant : décalage
// d'horloge du téléphone), ou 0.
func matchTOTP(secret []byte, code string, now time.Time) int64 {
	cur := now.Unix() / totpPeriod
	for _, d := range []int64{0, -1, 1} {
		step := cur + d
		if hmac.Equal([]byte(hotp(secret, uint64(step))), []byte(code)) {
			return step
		}
	}
	return 0
}

func (s *Service) totpState(ctx context.Context, userID uuid.UUID) (store.AuthTotp, bool, error) {
	row, err := store.New(s.db.Conn(ctx)).GetTOTP(ctx, userID)
	if database.IsNoRows(err) {
		return store.AuthTotp{}, false, nil
	}
	if err != nil {
		return store.AuthTotp{}, false, fmt.Errorf("lecture de la double vérification : %w", err)
	}
	return row, true, nil
}

// TOTPEnabled indique si l'utilisateur a activé l'application d'authentification.
func (s *Service) TOTPEnabled(ctx context.Context, userID uuid.UUID) (bool, error) {
	row, ok, err := s.totpState(ctx, userID)
	return ok && row.ConfirmedAt != nil, err
}

// StartTOTP tire un nouveau secret à scanner. Réservé à une session déjà vérifiée.
func (s *Service) StartTOTP(ctx context.Context, p identity.Principal) (TOTPSetup, error) {
	if !p.MFA {
		return TOTPSetup{}, errMFAFirst
	}
	row, ok, err := s.totpState(ctx, p.UserID)
	if err != nil {
		return TOTPSetup{}, err
	}
	if ok && row.ConfirmedAt != nil {
		return TOTPSetup{}, errTOTPEnabled
	}
	email, err := s.accountEmail(ctx, p.UserID)
	if err != nil {
		return TOTPSetup{}, err
	}
	secret := make([]byte, 20)
	if _, err := rand.Read(secret); err != nil {
		return TOTPSetup{}, fmt.Errorf("tirage du secret : %w", err)
	}
	sealed, err := s.sealTOTP(secret)
	if err != nil {
		return TOTPSetup{}, fmt.Errorf("chiffrement du secret : %w", err)
	}
	if err := store.New(s.db.Pool).UpsertTOTP(ctx, store.UpsertTOTPParams{UserID: p.UserID, SecretEnc: sealed}); err != nil {
		return TOTPSetup{}, fmt.Errorf("enregistrement du secret : %w", err)
	}
	b32 := base32.StdEncoding.WithPadding(base32.NoPadding).EncodeToString(secret)
	label := url.PathEscape("ivia:" + email)
	uri := "otpauth://totp/" + label + "?secret=" + b32 + "&issuer=ivia&algorithm=SHA1&digits=6&period=30"
	return TOTPSetup{Secret: b32, OtpauthURI: uri}, nil
}

// ConfirmTOTP active l'application d'authentification avec un premier code et retourne les codes
// de secours.
func (s *Service) ConfirmTOTP(ctx context.Context, p identity.Principal, code string) (RecoveryCodes, error) {
	if !p.MFA {
		return RecoveryCodes{}, errMFAFirst
	}
	var out RecoveryCodes
	err := s.db.InTx(ctx, func(ctx context.Context) error {
		row, ok, err := s.totpState(ctx, p.UserID)
		if err != nil {
			return err
		}
		if !ok {
			return errTOTPNotStarted
		}
		if row.ConfirmedAt != nil {
			return errTOTPEnabled
		}
		if err := s.checkTOTP(ctx, p.UserID, row, code); err != nil {
			return err
		}
		if err := store.New(s.db.Conn(ctx)).ConfirmTOTP(ctx, p.UserID); err != nil {
			return fmt.Errorf("activation : %w", err)
		}
		out, err = s.newRecoveryCodes(ctx, p.UserID)
		return err
	})
	return out, err
}

// RegenerateRecoveryCodes remplace les codes de secours (code de l'application exigé).
func (s *Service) RegenerateRecoveryCodes(ctx context.Context, p identity.Principal, code string) (RecoveryCodes, error) {
	if !p.MFA {
		return RecoveryCodes{}, errMFAFirst
	}
	var out RecoveryCodes
	err := s.db.InTx(ctx, func(ctx context.Context) error {
		row, ok, err := s.totpState(ctx, p.UserID)
		if err != nil {
			return err
		}
		if !ok || row.ConfirmedAt == nil {
			return errTOTPDisabled
		}
		if err := s.checkTOTP(ctx, p.UserID, row, code); err != nil {
			return err
		}
		out, err = s.newRecoveryCodes(ctx, p.UserID)
		return err
	})
	return out, err
}

// DisableTOTP désactive l'application d'authentification (code de l'application exigé) : le code
// par e-mail redevient la double vérification.
func (s *Service) DisableTOTP(ctx context.Context, p identity.Principal, code string) error {
	if !p.MFA {
		return errMFAFirst
	}
	return s.db.InTx(ctx, func(ctx context.Context) error {
		row, ok, err := s.totpState(ctx, p.UserID)
		if err != nil {
			return err
		}
		if !ok || row.ConfirmedAt == nil {
			return errTOTPDisabled
		}
		if err := s.checkTOTP(ctx, p.UserID, row, code); err != nil {
			return err
		}
		return s.dropTOTP(ctx, p.UserID)
	})
}

// AdminResetTOTP désactive l'application d'authentification d'un autre compte (téléphone perdu
// sans code de secours) et le déconnecte partout. L'action est journalisée.
func (s *Service) AdminResetTOTP(ctx context.Context, by identity.Principal, userID uuid.UUID, reason string) error {
	reason = strings.TrimSpace(reason)
	if len(reason) < 3 || len(reason) > 500 {
		return apperr.Validation(map[string]string{"reason": "Motif obligatoire (3 à 500 caractères)."})
	}
	if by.UserID == userID {
		return apperr.Forbidden("self_reset_forbidden", "Un autre admin doit réinitialiser votre double vérification.")
	}
	return s.db.InTx(ctx, func(ctx context.Context) error {
		_, ok, err := s.totpState(ctx, userID)
		if err != nil {
			return err
		}
		if !ok {
			return errTOTPDisabled
		}
		if err := s.dropTOTP(ctx, userID); err != nil {
			return err
		}
		if err := store.New(s.db.Conn(ctx)).RevokeUserSessions(ctx, userID); err != nil {
			return fmt.Errorf("déconnexion : %w", err)
		}
		if s.auditor == nil {
			return nil
		}
		return s.auditor.Record(ctx, admin.AuditEntry{
			AdminID: &by.UserID, Action: "user.reset_totp", TargetType: "user", TargetID: userID.String(), Reason: reason,
		})
	})
}

func (s *Service) dropTOTP(ctx context.Context, userID uuid.UUID) error {
	q := store.New(s.db.Conn(ctx))
	if err := q.DeleteTOTP(ctx, userID); err != nil {
		return fmt.Errorf("désactivation : %w", err)
	}
	if err := q.DeleteRecoveryCodes(ctx, userID); err != nil {
		return fmt.Errorf("suppression des codes de secours : %w", err)
	}
	return nil
}

// checkTOTP vérifie un code de l'application, au plus une fois par pas (anti-rejeu).
func (s *Service) checkTOTP(ctx context.Context, userID uuid.UUID, row store.AuthTotp, code string) error {
	if ok, retry := s.byDevice.Allow("totp:" + userID.String()); !ok {
		return apperr.TooManyRequests("rate_limited", "Trop d'essais. Réessayez dans quelques minutes.", retry)
	}
	code = strings.TrimSpace(code)
	if len(code) != totpDigits {
		return errTOTPInvalid
	}
	secret, err := s.openTOTP(row.SecretEnc)
	if err != nil {
		return fmt.Errorf("lecture du secret : %w", err)
	}
	step := matchTOTP(secret, code, time.Now())
	if step == 0 {
		return errTOTPInvalid
	}
	n, err := store.New(s.db.Conn(ctx)).AdvanceTOTPStep(ctx, store.AdvanceTOTPStepParams{UserID: userID, Step: step})
	if err != nil {
		return fmt.Errorf("anti-rejeu : %w", err)
	}
	if n == 0 {
		return errTOTPInvalid // code déjà utilisé
	}
	return nil
}

const recoveryAlphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789" // sans 0/O ni 1/I

func (s *Service) hashRecovery(userID uuid.UUID, code string) []byte {
	h := hmac.New(sha256.New, s.opts.Secret)
	h.Write([]byte("recovery\x00" + userID.String() + "\x00" + normalizeRecovery(code)))
	return h.Sum(nil)
}

func normalizeRecovery(code string) string {
	return strings.ToUpper(strings.NewReplacer("-", "", " ", "").Replace(code))
}

func (s *Service) newRecoveryCodes(ctx context.Context, userID uuid.UUID) (RecoveryCodes, error) {
	q := store.New(s.db.Conn(ctx))
	if err := q.DeleteRecoveryCodes(ctx, userID); err != nil {
		return RecoveryCodes{}, fmt.Errorf("suppression des anciens codes : %w", err)
	}
	codes := make([]string, recoveryCodeCount)
	for i := range codes {
		raw := make([]byte, 8)
		if _, err := rand.Read(raw); err != nil {
			return RecoveryCodes{}, err
		}
		var b strings.Builder
		for j, c := range raw {
			if j == 4 {
				b.WriteByte('-')
			}
			b.WriteByte(recoveryAlphabet[int(c)%len(recoveryAlphabet)])
		}
		codes[i] = b.String()
		if err := q.CreateRecoveryCode(ctx, store.CreateRecoveryCodeParams{UserID: userID, CodeHash: s.hashRecovery(userID, codes[i])}); err != nil {
			return RecoveryCodes{}, fmt.Errorf("enregistrement des codes de secours : %w", err)
		}
	}
	return RecoveryCodes{Codes: codes}, nil
}

// verifySecondFactor vérifie le code de l'application ou un code de secours (XXXX-XXXX).
func (s *Service) verifySecondFactor(ctx context.Context, userID uuid.UUID, row store.AuthTotp, code string) error {
	if len(normalizeRecovery(code)) == 8 && len(strings.TrimSpace(code)) != totpDigits {
		if ok, retry := s.byDevice.Allow("totp:" + userID.String()); !ok {
			return apperr.TooManyRequests("rate_limited", "Trop d'essais. Réessayez dans quelques minutes.", retry)
		}
		n, err := store.New(s.db.Conn(ctx)).UseRecoveryCode(ctx, store.UseRecoveryCodeParams{UserID: userID, CodeHash: s.hashRecovery(userID, code)})
		if err != nil {
			return fmt.Errorf("code de secours : %w", err)
		}
		if n == 0 {
			return errTOTPInvalid
		}
		s.logger.Warn("double vérification par code de secours", "user_id", userID)
		return nil
	}
	return s.checkTOTP(ctx, userID, row, code)
}
