package users

import (
	"context"
	"fmt"
	"time"

	"github.com/google/uuid"

	"ivia/backend/internal/geo"
	"ivia/backend/internal/platform/apperr"
	"ivia/backend/internal/platform/database"
	"ivia/backend/internal/platform/validate"
	"ivia/backend/internal/users/store"
)

// maxAddresses limite la taille du carnet d'adresses.
const maxAddresses = 20

// Address est une adresse de livraison du carnet de l'acheteur.
type Address struct {
	ID               uuid.UUID  `json:"id"`
	Label            string     `json:"label"`
	AddressText      string     `json:"address_text"`
	NeighborhoodID   *uuid.UUID `json:"neighborhood_id"`
	NeighborhoodName string     `json:"neighborhood_name"`
	Location         geo.Point  `json:"location"`
	Instructions     string     `json:"instructions"`
	CreatedAt        time.Time  `json:"created_at"`
	UpdatedAt        time.Time  `json:"updated_at"`
}

// AddressInput crée ou remplace une adresse.
type AddressInput struct {
	Label          string     `json:"label"`
	AddressText    string     `json:"address_text"`
	NeighborhoodID *uuid.UUID `json:"neighborhood_id"`
	Location       geo.Point  `json:"location"`
	Instructions   string     `json:"instructions"`
}

var errAddressNotFound = apperr.NotFound("address_not_found", "Adresse introuvable.")

func (s *Service) validateAddress(ctx context.Context, in *AddressInput) error {
	in.Label = validate.Clean(in.Label)
	in.AddressText = validate.Clean(in.AddressText)
	in.Instructions = validate.Clean(in.Instructions)
	v := validate.New()
	v.Text("label", in.Label, 1, 50)
	v.Text("address_text", in.AddressText, 1, 300)
	v.Text("instructions", in.Instructions, 0, 300)
	v.Coordinates("location.", in.Location.Lat, in.Location.Lng)
	if err := v.Err(); err != nil {
		return err
	}
	if in.NeighborhoodID != nil {
		if _, err := s.geo.RequireActive(ctx, *in.NeighborhoodID); err != nil {
			return err
		}
	}
	return nil
}

// ListAddresses retourne le carnet d'adresses.
func (s *Service) ListAddresses(ctx context.Context, userID uuid.UUID) ([]Address, error) {
	rows, err := store.New(s.db.Conn(ctx)).ListAddresses(ctx, userID)
	if err != nil {
		return nil, fmt.Errorf("liste des adresses : %w", err)
	}
	out := make([]Address, len(rows))
	for i, r := range rows {
		out[i] = Address{
			ID: r.ID, Label: r.Label, AddressText: r.AddressText, NeighborhoodID: r.NeighborhoodID,
			Location: geo.Point{Lat: r.Lat, Lng: r.Lng}, Instructions: r.Instructions,
			CreatedAt: r.CreatedAt, UpdatedAt: r.UpdatedAt,
		}
		if err := s.fillNeighborhood(ctx, &out[i]); err != nil {
			return nil, err
		}
	}
	return out, nil
}

// GetAddress retourne une adresse de l'utilisateur ; celle d'un autre utilisateur est introuvable.
func (s *Service) GetAddress(ctx context.Context, userID, id uuid.UUID) (Address, error) {
	r, err := store.New(s.db.Conn(ctx)).GetAddress(ctx, store.GetAddressParams{ID: id, UserID: userID})
	if err != nil {
		if database.IsNoRows(err) {
			return Address{}, errAddressNotFound
		}
		return Address{}, fmt.Errorf("lecture de l'adresse : %w", err)
	}
	a := Address{
		ID: r.ID, Label: r.Label, AddressText: r.AddressText, NeighborhoodID: r.NeighborhoodID,
		Location: geo.Point{Lat: r.Lat, Lng: r.Lng}, Instructions: r.Instructions,
		CreatedAt: r.CreatedAt, UpdatedAt: r.UpdatedAt,
	}
	return a, s.fillNeighborhood(ctx, &a)
}

// CreateAddress ajoute une adresse au carnet.
func (s *Service) CreateAddress(ctx context.Context, userID uuid.UUID, in AddressInput) (Address, error) {
	if err := s.validateAddress(ctx, &in); err != nil {
		return Address{}, err
	}
	q := store.New(s.db.Conn(ctx))
	n, err := q.CountAddresses(ctx, userID)
	if err != nil {
		return Address{}, fmt.Errorf("décompte des adresses : %w", err)
	}
	if n >= maxAddresses {
		return Address{}, apperr.Conflict("too_many_addresses", "Votre carnet contient déjà 20 adresses.")
	}
	id, err := q.CreateAddress(ctx, store.CreateAddressParams{
		UserID: userID, Label: in.Label, AddressText: in.AddressText, NeighborhoodID: in.NeighborhoodID,
		Lat: in.Location.Lat, Lng: in.Location.Lng, Instructions: in.Instructions,
	})
	if err != nil {
		return Address{}, fmt.Errorf("création de l'adresse : %w", err)
	}
	return s.GetAddress(ctx, userID, id)
}

// UpdateAddress remplace une adresse. Les commandes passées gardent leur copie de l'adresse.
func (s *Service) UpdateAddress(ctx context.Context, userID, id uuid.UUID, in AddressInput) (Address, error) {
	if err := s.validateAddress(ctx, &in); err != nil {
		return Address{}, err
	}
	n, err := store.New(s.db.Conn(ctx)).UpdateAddress(ctx, store.UpdateAddressParams{
		ID: id, UserID: userID, Label: in.Label, AddressText: in.AddressText, NeighborhoodID: in.NeighborhoodID,
		Lat: in.Location.Lat, Lng: in.Location.Lng, Instructions: in.Instructions,
	})
	if err != nil {
		return Address{}, fmt.Errorf("mise à jour de l'adresse : %w", err)
	}
	if n == 0 {
		return Address{}, errAddressNotFound
	}
	return s.GetAddress(ctx, userID, id)
}

// DeleteAddress supprime une adresse du carnet.
func (s *Service) DeleteAddress(ctx context.Context, userID, id uuid.UUID) error {
	n, err := store.New(s.db.Conn(ctx)).DeleteAddress(ctx, store.DeleteAddressParams{ID: id, UserID: userID})
	if err != nil {
		return fmt.Errorf("suppression de l'adresse : %w", err)
	}
	if n == 0 {
		return errAddressNotFound
	}
	return nil
}

func (s *Service) fillNeighborhood(ctx context.Context, a *Address) error {
	if a.NeighborhoodID == nil {
		return nil
	}
	n, err := s.geo.Get(ctx, *a.NeighborhoodID)
	if err != nil {
		return err
	}
	a.NeighborhoodName = n.Name
	return nil
}
