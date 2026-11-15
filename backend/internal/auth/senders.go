package auth

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"html"
	"io"
	"log/slog"
	"net/http"
	"strings"
	"sync"
	"time"
)

// LogSender affiche le code dans les journaux. Réservé au développement local : la configuration
// refuse ce mode hors local (voir config.Load), conformément à ARCHITECTURE (« e-mails affichés
// dans les logs » en local).
type LogSender struct {
	Logger *slog.Logger

	mu   sync.Mutex
	last map[string]string
}

// Send implémente OTPSender.
func (s *LogSender) Send(_ context.Context, m OTPMessage) error {
	s.mu.Lock()
	if s.last == nil {
		s.last = map[string]string{}
	}
	s.last[m.Recipient] = m.Code
	s.mu.Unlock()
	s.Logger.Info("[DEV] code", "purpose", m.Purpose, "channel", m.Channel, "recipient", m.Recipient, "code", m.Code)
	return nil
}

// LastCode retourne le dernier code envoyé à un destinataire (tests automatisés en local).
func (s *LogSender) LastCode(recipient string) (string, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	c, ok := s.last[recipient]
	return c, ok
}

// BrevoSender envoie le code par e-mail via l'API transactionnelle de Brevo.
type BrevoSender struct {
	APIKey      string
	SenderEmail string
	SenderName  string
	// Endpoint vaut https://api.brevo.com/v3/smtp/email par défaut (remplacé dans les tests).
	Endpoint string
	Client   *http.Client
}

// Send implémente OTPSender (canal e-mail uniquement).
func (s *BrevoSender) Send(ctx context.Context, m OTPMessage) error {
	if m.Channel != ChannelEmail {
		return fmt.Errorf("brevo : canal non pris en charge : %s", m.Channel)
	}
	c := copyFor(m.Purpose)
	endpoint := s.Endpoint
	if endpoint == "" {
		endpoint = "https://api.brevo.com/v3/smtp/email"
	}
	client := s.Client
	if client == nil {
		client = &http.Client{Timeout: 10 * time.Second}
	}
	body, err := json.Marshal(map[string]any{
		"sender":      map[string]string{"email": s.SenderEmail, "name": s.SenderName},
		"to":          []map[string]string{{"email": m.Recipient}},
		"subject":     c.subject + m.Code,
		"textContent": otpText(c, m.Code),
		"htmlContent": otpHTML(c, m.Code),
		"tags":        []string{"otp"},
	})
	if err != nil {
		return err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("api-key", s.APIKey)
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Accept", "application/json")
	resp, err := client.Do(req)
	if err != nil {
		return fmt.Errorf("brevo : %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 300 {
		// Le corps de réponse ne contient pas le code ; on n'en garde que le début.
		msg, _ := io.ReadAll(io.LimitReader(resp.Body, 300))
		return errors.New("brevo : statut " + resp.Status + " : " + string(msg))
	}
	return nil
}

// mailCopy : textes de l'e-mail selon l'usage du code.
type mailCopy struct {
	subject  string // suivi du code
	overline string
	sentence string // suivi du code
}

func copyFor(p Purpose) mailCopy {
	switch p {
	case PurposeSignup:
		return mailCopy{"Votre code pour créer votre compte ivia : ", "Création de compte", "Votre code pour créer votre compte ivia est : "}
	case PurposeReset:
		return mailCopy{"Votre code pour changer de mot de passe ivia : ", "Mot de passe oublié", "Votre code pour choisir un nouveau mot de passe ivia est : "}
	case PurposeMFA:
		return mailCopy{"Votre code de vérification du back-office ivia : ", "Back-office", "Votre code de vérification du back-office ivia est : "}
	default:
		return mailCopy{"Votre code de connexion ivia : ", "Code de connexion", "Votre code de connexion ivia est : "}
	}
}

func otpText(c mailCopy, code string) string {
	return "Bonjour,\n\n" + c.sentence + code + "\n\n" +
		"Il est valable 10 minutes. Ne le communiquez à personne : l'équipe ivia ne vous le demandera jamais.\n\n" +
		"Si vous n'avez pas demandé ce code, ignorez cet e-mail."
}

// otpHTML : e-mail aux couleurs d'ivia (docs/DESIGN.md). Mise en page en tableaux et styles en
// ligne, seule forme lue correctement par les messageries (Gmail, Outlook, applis mobiles).
func otpHTML(c mailCopy, code string) string {
	var digits strings.Builder
	for _, d := range code {
		digits.WriteString(`<td style="width:44px;height:56px;background:#F3F4F6;border-radius:14px;` +
			`font-size:28px;font-weight:700;color:#0E2E54;text-align:center;font-family:Arial,sans-serif">` +
			html.EscapeString(string(d)) + `</td><td style="width:8px"></td>`)
	}
	return `<!doctype html><html lang="fr"><body style="margin:0;background:#F3F4F6;font-family:Arial,Helvetica,sans-serif;color:#0A1A30">` +
		`<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#F3F4F6;padding:24px 12px"><tr><td align="center">` +
		`<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:480px;background:#FFFFFF;border-radius:18px;overflow:hidden">` +
		`<tr><td style="background:#0E2E54;padding:24px 28px;font-size:30px;font-weight:700;letter-spacing:-0.5px;color:#FFFFFF">ivia</td></tr>` +
		`<tr><td style="padding:28px">` +
		`<p style="margin:0 0 4px;font-size:12px;font-weight:700;letter-spacing:1px;color:#004DA8;text-transform:uppercase">` + html.EscapeString(c.overline) + `</p>` +
		`<p style="margin:0 0 20px;font-size:22px;line-height:28px;font-weight:700">Voici votre code <span style="color:#ED1C2F">ivia</span></p>` +
		`<table role="presentation" cellpadding="0" cellspacing="0"><tr>` + digits.String() + `</tr></table>` +
		`<p style="margin:20px 0 0;font-size:15px;line-height:22px;color:#3A4A60">Saisissez-le dans l'application. Il est valable <strong>10 minutes</strong>.</p>` +
		`<p style="margin:16px 0 0;padding:12px 14px;background:#E5EEF8;border-radius:14px;font-size:13px;line-height:18px;color:#0E2E54">` +
		`Ne communiquez ce code à personne : l'équipe ivia ne vous le demandera jamais.</p>` +
		`<p style="margin:16px 0 0;font-size:13px;line-height:18px;color:#5A6A80">Vous n'avez pas demandé ce code ? Ignorez cet e-mail, votre compte reste protégé.</p>` +
		`</td></tr></table>` +
		`<p style="margin:16px 0 0;font-size:12px;color:#5A6A80">ivia · Lomé, Togo</p>` +
		`</td></tr></table></body></html>`
}
