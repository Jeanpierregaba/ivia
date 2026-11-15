package notifications

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"mime"
	"net/http"
	"net/smtp"
	"regexp"
	"time"
)

// EmailSender envoie un e-mail d'information en texte simple. Le sujet et le texte sont écrits par
// l'application ; le destinataire a été validé à la saisie.
type EmailSender interface {
	SendEmail(ctx context.Context, to, subject, text string) error
}

// SMTPEmail écrit dans un serveur SMTP. Prévu pour le développement : la boîte locale Mailpit reçoit
// les e-mails sans qu'aucun ne sorte vers Internet.
type SMTPEmail struct {
	Addr string
	From string
}

var angle = regexp.MustCompile(`<([^>]+)>`)

// SendEmail implémente EmailSender.
func (s *SMTPEmail) SendEmail(ctx context.Context, to, subject, text string) error {
	var msg bytes.Buffer
	fmt.Fprintf(&msg, "From: %s\r\nTo: %s\r\nSubject: %s\r\nDate: %s\r\nMIME-Version: 1.0\r\nContent-Type: text/plain; charset=utf-8\r\n\r\n%s\r\n",
		s.From, to, mime.QEncoding.Encode("utf-8", subject), time.Now().UTC().Format(time.RFC1123Z), text)
	from := s.From
	if m := angle.FindStringSubmatch(from); m != nil {
		from = m[1]
	}
	done := make(chan error, 1)
	go func() { done <- smtp.SendMail(s.Addr, nil, from, []string{to}, msg.Bytes()) }()
	select {
	case err := <-done:
		if err != nil {
			return fmt.Errorf("smtp : %w", err)
		}
		return nil
	case <-ctx.Done():
		return fmt.Errorf("smtp : %w", ctx.Err())
	}
}

// BrevoEmail passe par l'API transactionnelle de Brevo (production).
type BrevoEmail struct {
	APIKey      string
	SenderEmail string
	SenderName  string
	Client      *http.Client
}

// SendEmail implémente EmailSender.
func (s *BrevoEmail) SendEmail(ctx context.Context, to, subject, text string) error {
	body, err := json.Marshal(map[string]any{
		"sender":      map[string]string{"email": s.SenderEmail, "name": s.SenderName},
		"to":          []map[string]string{{"email": to}},
		"subject":     subject,
		"textContent": text,
		"tags":        []string{"information"},
	})
	if err != nil {
		return err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, "https://api.brevo.com/v3/smtp/email", bytes.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("api-key", s.APIKey)
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Accept", "application/json")
	client := s.Client
	if client == nil {
		client = &http.Client{Timeout: 10 * time.Second}
	}
	resp, err := client.Do(req)
	if err != nil {
		return fmt.Errorf("brevo : %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 300 {
		msg, _ := io.ReadAll(io.LimitReader(resp.Body, 300))
		return errors.New("brevo : statut " + resp.Status + " : " + string(msg))
	}
	return nil
}

// LogEmail n'envoie rien : le journal note l'objet, jamais le destinataire ni le texte.
type LogEmail struct {
	Logger *slog.Logger
}

// SendEmail implémente EmailSender.
func (s *LogEmail) SendEmail(_ context.Context, _, subject, _ string) error {
	s.Logger.Info("[DEV] e-mail non envoyé", "subject", subject)
	return nil
}
