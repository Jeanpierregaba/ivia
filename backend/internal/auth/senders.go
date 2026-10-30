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
func (s *LogSender) Send(_ context.Context, channel Channel, recipient, code string) error {
	s.mu.Lock()
	if s.last == nil {
		s.last = map[string]string{}
	}
	s.last[recipient] = code
	s.mu.Unlock()
	s.Logger.Info("[DEV] code de connexion", "channel", channel, "recipient", recipient, "code", code)
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
func (s *BrevoSender) Send(ctx context.Context, channel Channel, recipient, code string) error {
	if channel != ChannelEmail {
		return fmt.Errorf("brevo : canal non pris en charge : %s", channel)
	}
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
		"to":          []map[string]string{{"email": recipient}},
		"subject":     "Votre code de connexion ivia : " + code,
		"textContent": otpText(code),
		"htmlContent": otpHTML(code),
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

func otpText(code string) string {
	return "Bonjour,\n\nVotre code de connexion ivia est : " + code + "\n\n" +
		"Il est valable 10 minutes. Ne le communiquez à personne : l'équipe ivia ne vous le demandera jamais.\n\n" +
		"Si vous n'avez pas demandé ce code, ignorez cet e-mail."
}

func otpHTML(code string) string {
	c := html.EscapeString(code)
	return `<p>Bonjour,</p><p>Votre code de connexion ivia est :</p>` +
		`<p style="font-size:28px;font-weight:bold;letter-spacing:6px">` + c + `</p>` +
		`<p>Il est valable 10 minutes. Ne le communiquez à personne : l'équipe ivia ne vous le demandera jamais.</p>` +
		`<p>Si vous n'avez pas demandé ce code, ignorez cet e-mail.</p>`
}
