package auth

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

// WhatsAppSender envoie le code par WhatsApp avec l'API Cloud de Meta, au moyen d'un modèle de
// message de catégorie « authentification » approuvé par Meta (le texte est fixé par Meta : « <code>
// est votre code de vérification… », avec un bouton « Copier le code »).
//
// Configuration (ADR 0012) : WHATSAPP_PHONE_NUMBER_ID (identifiant du numéro expéditeur dans
// WhatsApp Business), WHATSAPP_ACCESS_TOKEN_FILE (jeton système, secret), WHATSAPP_TEMPLATE et
// WHATSAPP_TEMPLATE_LANG. Le numéro expéditeur lui-même n'est jamais écrit dans le code.
type WhatsAppSender struct {
	PhoneNumberID string
	AccessToken   string
	Template      string
	Language      string
	// Endpoint vaut https://graph.facebook.com/v21.0 par défaut (remplacé dans les tests).
	Endpoint string
	Client   *http.Client
}

// Send implémente OTPSender (canal WhatsApp uniquement). Une erreur (numéro sans WhatsApp, modèle
// refusé, panne) fait passer le service au SMS.
func (s *WhatsAppSender) Send(ctx context.Context, m OTPMessage) error {
	if m.Channel != ChannelWhatsApp {
		return fmt.Errorf("whatsapp : canal non pris en charge : %s", m.Channel)
	}
	endpoint := s.Endpoint
	if endpoint == "" {
		endpoint = "https://graph.facebook.com/v21.0"
	}
	client := s.Client
	if client == nil {
		client = &http.Client{Timeout: 10 * time.Second}
	}
	lang := s.Language
	if lang == "" {
		lang = "fr"
	}
	body, err := json.Marshal(map[string]any{
		"messaging_product": "whatsapp",
		"recipient_type":    "individual",
		"to":                strings.TrimPrefix(m.Recipient, "+"),
		"type":              "template",
		"template": map[string]any{
			"name":     s.Template,
			"language": map[string]string{"code": lang},
			"components": []map[string]any{
				{"type": "body", "parameters": []map[string]string{{"type": "text", "text": m.Code}}},
				{"type": "button", "sub_type": "url", "index": "0", "parameters": []map[string]string{{"type": "text", "text": m.Code}}},
			},
		},
	})
	if err != nil {
		return err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint+"/"+s.PhoneNumberID+"/messages", bytes.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+s.AccessToken)
	req.Header.Set("Content-Type", "application/json")
	resp, err := client.Do(req)
	if err != nil {
		return fmt.Errorf("whatsapp : %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 300 {
		// On ne garde que le code d'erreur de Meta : le corps peut citer le numéro.
		var e struct {
			Error struct {
				Code int    `json:"code"`
				Type string `json:"type"`
			} `json:"error"`
		}
		raw, _ := io.ReadAll(io.LimitReader(resp.Body, 4096))
		_ = json.Unmarshal(raw, &e)
		return fmt.Errorf("whatsapp : statut %d, erreur %d (%s)", resp.StatusCode, e.Error.Code, e.Error.Type)
	}
	return nil
}

// ChannelRouter confie chaque code à l'expéditeur de son canal. Un canal sans expéditeur échoue
// (le service essaie alors le canal suivant).
type ChannelRouter struct {
	Email    OTPSender
	WhatsApp OTPSender
	SMS      OTPSender
}

var errNoSender = errors.New("aucun expéditeur pour ce canal")

// Send implémente OTPSender.
func (r ChannelRouter) Send(ctx context.Context, m OTPMessage) error {
	var s OTPSender
	switch m.Channel {
	case ChannelEmail:
		s = r.Email
	case ChannelWhatsApp:
		s = r.WhatsApp
	case ChannelSMS:
		s = r.SMS
	}
	if s == nil {
		return fmt.Errorf("%w : %s", errNoSender, m.Channel)
	}
	return s.Send(ctx, m)
}
