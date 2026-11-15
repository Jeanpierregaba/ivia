// Package geo gère les quartiers de la ville et les calculs de distance (PostGIS).
package geo

import (
	"context"
	"fmt"

	"github.com/google/uuid"

	"ivia/backend/internal/admin"
	"ivia/backend/internal/geo/store"
	"ivia/backend/internal/platform/apperr"
	"ivia/backend/internal/platform/database"
	"ivia/backend/internal/platform/validate"
)

// Point est une position en degrés (WGS 84).
type Point struct {
	Lat float64 `json:"lat"`
	Lng float64 `json:"lng"`
}

// Neighborhood est un quartier.
type Neighborhood struct {
	ID       uuid.UUID `json:"id"`
	City     string    `json:"city"`
	Name     string    `json:"name"`
	IsActive bool      `json:"is_active"`
	Center   *Point    `json:"center"`
}

// NeighborhoodInput crée ou modifie un quartier.
type NeighborhoodInput struct {
	Name     string `json:"name"`
	City     string `json:"city"`
	IsActive *bool  `json:"is_active"`
	Center   *Point `json:"center"`
}

// Service gère les quartiers.
type Service struct {
	db    *database.DB
	audit *admin.Service
}

// NewService crée le service.
func NewService(db *database.DB, audit *admin.Service) *Service {
	return &Service{db: db, audit: audit}
}

var errNotFound = apperr.NotFound("neighborhood_not_found", "Quartier introuvable.")

// nearestMaxM : au-delà, le point n'est rattaché à aucun quartier connu.
const nearestMaxM = 4000

// NearestName retourne le nom du quartier le plus proche de p ; « » si aucun quartier connu n'est
// assez près. Ne renvoie jamais le point lui-même.
func (s *Service) NearestName(ctx context.Context, p Point) (string, error) {
	name, err := store.New(s.db.Conn(ctx)).NearestNeighborhood(ctx, store.NearestNeighborhoodParams{
		Lat: p.Lat, Lng: p.Lng, MaxM: nearestMaxM,
	})
	if database.IsNoRows(err) {
		return "", nil
	}
	if err != nil {
		return "", fmt.Errorf("quartier le plus proche : %w", err)
	}
	return name, nil
}

// List retourne les quartiers (actifs seulement, sauf includeInactive).
func (s *Service) List(ctx context.Context, includeInactive bool) ([]Neighborhood, error) {
	rows, err := store.New(s.db.Conn(ctx)).ListNeighborhoods(ctx, includeInactive)
	if err != nil {
		return nil, fmt.Errorf("liste des quartiers : %w", err)
	}
	out := make([]Neighborhood, len(rows))
	for i, r := range rows {
		out[i] = toNeighborhood(r.ID, r.City, r.Name, r.IsActive, r.HasCenter, r.Lat, r.Lng)
	}
	return out, nil
}

// Get retourne un quartier.
func (s *Service) Get(ctx context.Context, id uuid.UUID) (Neighborhood, error) {
	r, err := store.New(s.db.Conn(ctx)).GetNeighborhood(ctx, id)
	if database.IsNoRows(err) {
		return Neighborhood{}, errNotFound
	}
	if err != nil {
		return Neighborhood{}, fmt.Errorf("lecture du quartier : %w", err)
	}
	return toNeighborhood(r.ID, r.City, r.Name, r.IsActive, r.HasCenter, r.Lat, r.Lng), nil
}

// RequireActive vérifie qu'un quartier choisi par un utilisateur existe et est actif.
func (s *Service) RequireActive(ctx context.Context, id uuid.UUID) (Neighborhood, error) {
	n, err := s.Get(ctx, id)
	if err != nil {
		if apperr.IsCode(err, "neighborhood_not_found") {
			return Neighborhood{}, apperr.Validation(map[string]string{"neighborhood_id": "Quartier inconnu."})
		}
		return Neighborhood{}, err
	}
	if !n.IsActive {
		return Neighborhood{}, apperr.Validation(map[string]string{"neighborhood_id": "Quartier indisponible."})
	}
	return n, nil
}

// Create ajoute un quartier (admin).
func (s *Service) Create(ctx context.Context, adminID uuid.UUID, in NeighborhoodInput) (Neighborhood, error) {
	in.Name, in.City = validate.Clean(in.Name), validate.Clean(in.City)
	if in.City == "" {
		in.City = "Lomé"
	}
	if err := validateInput(in); err != nil {
		return Neighborhood{}, err
	}
	var out Neighborhood
	err := s.db.InTx(ctx, func(ctx context.Context) error {
		lat, lng := pointArgs(in.Center)
		id, err := store.New(s.db.Conn(ctx)).CreateNeighborhood(ctx, store.CreateNeighborhoodParams{
			City: in.City, Name: in.Name, Lat: lat, Lng: lng,
		})
		if database.IsUniqueViolation(err, "") {
			return apperr.Conflict("neighborhood_exists", "Ce quartier existe déjà.")
		}
		if err != nil {
			return fmt.Errorf("création du quartier : %w", err)
		}
		if out, err = s.Get(ctx, id); err != nil {
			return err
		}
		return s.audit.Record(ctx, admin.AuditEntry{
			AdminID: &adminID, Action: "neighborhood.create", TargetType: "neighborhood", TargetID: id.String(), After: out,
		})
	})
	return out, err
}

// Update modifie un quartier (admin). Désactiver un quartier le retire des listes de choix sans
// toucher aux adresses et boutiques qui y font référence.
func (s *Service) Update(ctx context.Context, adminID, id uuid.UUID, in NeighborhoodInput) (Neighborhood, error) {
	var out Neighborhood
	err := s.db.InTx(ctx, func(ctx context.Context) error {
		before, err := s.Get(ctx, id)
		if err != nil {
			return err
		}
		in.Name = validate.Clean(in.Name)
		if in.Name == "" {
			in.Name = before.Name
		}
		in.City = before.City
		if err := validateInput(in); err != nil {
			return err
		}
		active := before.IsActive
		if in.IsActive != nil {
			active = *in.IsActive
		}
		lat, lng := pointArgs(in.Center)
		_, err = store.New(s.db.Conn(ctx)).UpdateNeighborhood(ctx, store.UpdateNeighborhoodParams{
			ID: id, Name: in.Name, IsActive: active, Lat: lat, Lng: lng,
		})
		if database.IsUniqueViolation(err, "") {
			return apperr.Conflict("neighborhood_exists", "Ce quartier existe déjà.")
		}
		if err != nil {
			return fmt.Errorf("mise à jour du quartier : %w", err)
		}
		if out, err = s.Get(ctx, id); err != nil {
			return err
		}
		return s.audit.Record(ctx, admin.AuditEntry{
			AdminID: &adminID, Action: "neighborhood.update", TargetType: "neighborhood", TargetID: id.String(),
			Before: before, After: out,
		})
	})
	return out, err
}

// DistanceMeters retourne la distance à vol d'oiseau entre deux points, en mètres.
func (s *Service) DistanceMeters(ctx context.Context, from, to Point) (int64, error) {
	m, err := store.New(s.db.Conn(ctx)).DistanceMeters(ctx, store.DistanceMetersParams{
		FromLat: from.Lat, FromLng: from.Lng, ToLat: to.Lat, ToLng: to.Lng,
	})
	if err != nil {
		return 0, fmt.Errorf("calcul de distance : %w", err)
	}
	return int64(m + 0.5), nil
}

func validateInput(in NeighborhoodInput) error {
	v := validate.New()
	v.Text("name", in.Name, 1, 100)
	v.Text("city", in.City, 1, 100)
	if in.Center != nil {
		v.Coordinates("center.", in.Center.Lat, in.Center.Lng)
	}
	return v.Err()
}

func pointArgs(p *Point) (*float64, *float64) {
	if p == nil {
		return nil, nil
	}
	return &p.Lat, &p.Lng
}

func toNeighborhood(id uuid.UUID, city, name string, active, hasCenter bool, lat, lng float64) Neighborhood {
	n := Neighborhood{ID: id, City: city, Name: name, IsActive: active}
	if hasCenter {
		n.Center = &Point{Lat: lat, Lng: lng}
	}
	return n
}
