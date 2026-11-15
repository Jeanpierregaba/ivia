package users

import (
	"context"
	"fmt"

	"github.com/google/uuid"

	"ivia/backend/internal/platform/validate"
	"ivia/backend/internal/users/store"
)

// DeviceInput enregistre le jeton push d'une app sur un appareil.
type DeviceInput struct {
	Token    string `json:"token"`
	Platform string `json:"platform"`
	App      string `json:"app"`
	// AlertSound : sonnerie des alertes sur ce téléphone ; absent = active (spec 032).
	AlertSound *bool `json:"alert_sound"`
}

// PushDevice : jeton push d'un appareil et son choix de sonnerie.
type PushDevice struct {
	Token      string
	AlertSound bool
}

// RegisterDevice associe un jeton push au compte (le dernier compte connecté sur l'appareil l'emporte).
func (s *Service) RegisterDevice(ctx context.Context, userID uuid.UUID, in DeviceInput) error {
	v := validate.New()
	v.Text("token", in.Token, 1, 4096)
	v.Check(in.Platform == "android" || in.Platform == "ios" || in.Platform == "web", "platform", "Valeur attendue : android, ios ou web.")
	v.Check(in.App == "buyer" || in.App == "seller" || in.App == "driver" || in.App == "pharmacy", "app", "Valeur attendue : buyer, seller, driver ou pharmacy.")
	if err := v.Err(); err != nil {
		return err
	}
	sound := in.AlertSound == nil || *in.AlertSound
	if err := store.New(s.db.Conn(ctx)).UpsertDeviceToken(ctx, store.UpsertDeviceTokenParams{
		UserID: userID, Token: in.Token, Platform: in.Platform, App: in.App, AlertSound: sound,
	}); err != nil {
		return fmt.Errorf("enregistrement du jeton push : %w", err)
	}
	return nil
}

// UnregisterDevice retire un jeton push du compte (déconnexion de l'app).
func (s *Service) UnregisterDevice(ctx context.Context, userID uuid.UUID, token string) error {
	if err := store.New(s.db.Conn(ctx)).DeleteDeviceToken(ctx, store.DeleteDeviceTokenParams{UserID: userID, Token: token}); err != nil {
		return fmt.Errorf("suppression du jeton push : %w", err)
	}
	return nil
}

// PushDevices retourne les appareils d'un utilisateur pour une app, avec leur choix de sonnerie.
func (s *Service) PushDevices(ctx context.Context, userID uuid.UUID, app string) ([]PushDevice, error) {
	rows, err := store.New(s.db.Conn(ctx)).ListDeviceTokens(ctx, store.ListDeviceTokensParams{UserID: userID, App: app})
	if err != nil {
		return nil, fmt.Errorf("lecture des jetons push : %w", err)
	}
	out := make([]PushDevice, len(rows))
	for i, r := range rows {
		out[i] = PushDevice{Token: r.Token, AlertSound: r.AlertSound}
	}
	return out, nil
}

// ForgetDeviceToken supprime un jeton que le service push déclare invalide.
func (s *Service) ForgetDeviceToken(ctx context.Context, token string) error {
	if err := store.New(s.db.Conn(ctx)).DeleteDeviceTokenByValue(ctx, token); err != nil {
		return fmt.Errorf("suppression du jeton push : %w", err)
	}
	return nil
}
