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
}

// RegisterDevice associe un jeton push au compte (le dernier compte connecté sur l'appareil l'emporte).
func (s *Service) RegisterDevice(ctx context.Context, userID uuid.UUID, in DeviceInput) error {
	v := validate.New()
	v.Text("token", in.Token, 1, 4096)
	v.Check(in.Platform == "android" || in.Platform == "ios", "platform", "Valeur attendue : android ou ios.")
	v.Check(in.App == "buyer" || in.App == "seller" || in.App == "driver" || in.App == "pharmacy", "app", "Valeur attendue : buyer, seller, driver ou pharmacy.")
	if err := v.Err(); err != nil {
		return err
	}
	if err := store.New(s.db.Conn(ctx)).UpsertDeviceToken(ctx, store.UpsertDeviceTokenParams{
		UserID: userID, Token: in.Token, Platform: in.Platform, App: in.App,
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

// DeviceTokens retourne les jetons push d'un utilisateur pour une app.
func (s *Service) DeviceTokens(ctx context.Context, userID uuid.UUID, app string) ([]string, error) {
	tokens, err := store.New(s.db.Conn(ctx)).ListDeviceTokens(ctx, store.ListDeviceTokensParams{UserID: userID, App: app})
	if err != nil {
		return nil, fmt.Errorf("lecture des jetons push : %w", err)
	}
	return tokens, nil
}

// ForgetDeviceToken supprime un jeton que le service push déclare invalide.
func (s *Service) ForgetDeviceToken(ctx context.Context, token string) error {
	if err := store.New(s.db.Conn(ctx)).DeleteDeviceTokenByValue(ctx, token); err != nil {
		return fmt.Errorf("suppression du jeton push : %w", err)
	}
	return nil
}
