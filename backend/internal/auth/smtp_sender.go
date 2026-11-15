package auth

import (
	"bytes"
	"context"
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"mime"
	"mime/quotedprintable"
	"net/smtp"
	"strings"
	"time"
)

// SMTPSender envoie le code par e-mail à un serveur SMTP. Prévu pour le développement : la boîte
// de réception locale Mailpit (docker compose, http://localhost:8025) reçoit les e-mails sans
// qu'aucun ne sorte vers Internet (RULES.md). En production, l'envoi passe par Brevo.
type SMTPSender struct {
	// Addr : hôte:port du serveur SMTP (Mailpit : localhost:1025).
	Addr string
	// From : expéditeur, ex. « ivia <no-reply@ivia.local> ».
	From string
}

// Send implémente OTPSender (canal e-mail uniquement).
func (s *SMTPSender) Send(ctx context.Context, m OTPMessage) error {
	if m.Channel != ChannelEmail {
		return fmt.Errorf("smtp : canal non pris en charge : %s", m.Channel)
	}
	recipient := m.Recipient
	msg, err := buildOTPMessage(s.From, recipient, copyFor(m.Purpose), m.Code)
	if err != nil {
		return err
	}
	done := make(chan error, 1)
	go func() { done <- smtp.SendMail(s.Addr, nil, addressOf(s.From), []string{recipient}, msg) }()
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

// buildOTPMessage construit un e-mail MIME en deux versions (texte et HTML), sujet encodé en UTF-8.
func buildOTPMessage(from, to string, c mailCopy, code string) ([]byte, error) {
	b := make([]byte, 12)
	_, _ = rand.Read(b)
	boundary := "ivia-" + hex.EncodeToString(b)

	var buf bytes.Buffer
	header := func(k, v string) { fmt.Fprintf(&buf, "%s: %s\r\n", k, v) }
	header("From", from)
	header("To", to)
	header("Subject", mime.QEncoding.Encode("utf-8", c.subject+code))
	header("Date", time.Now().UTC().Format(time.RFC1123Z))
	header("MIME-Version", "1.0")
	header("Content-Type", `multipart/alternative; boundary="`+boundary+`"`)
	buf.WriteString("\r\n")

	for _, part := range []struct{ contentType, body string }{
		{"text/plain; charset=utf-8", otpText(c, code)},
		{"text/html; charset=utf-8", otpHTML(c, code)},
	} {
		fmt.Fprintf(&buf, "--%s\r\nContent-Type: %s\r\nContent-Transfer-Encoding: quoted-printable\r\n\r\n", boundary, part.contentType)
		w := quotedprintable.NewWriter(&buf)
		if _, err := w.Write([]byte(part.body)); err != nil {
			return nil, err
		}
		if err := w.Close(); err != nil {
			return nil, err
		}
		buf.WriteString("\r\n")
	}
	fmt.Fprintf(&buf, "--%s--\r\n", boundary)
	return buf.Bytes(), nil
}

// addressOf extrait l'adresse d'un expéditeur de la forme « Nom <adresse> ».
func addressOf(from string) string {
	if i := strings.LastIndex(from, "<"); i >= 0 {
		return strings.TrimSuffix(from[i+1:], ">")
	}
	return from
}

// TeeSender envoie le code par plusieurs canaux de développement (SMTP local et journal), pour
// garder POST /v1/dev/otp disponible aux tests automatisés des apps.
type TeeSender []OTPSender

// Send implémente OTPSender : tous les envois doivent réussir.
func (t TeeSender) Send(ctx context.Context, m OTPMessage) error {
	for _, s := range t {
		if err := s.Send(ctx, m); err != nil {
			return err
		}
	}
	return nil
}
