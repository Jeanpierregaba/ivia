// Package properties publie les biens immobiliers (vente, location) affichés dans l'app acheteur :
// liste par proximité, fiche, contact de l'annonceur par téléphone.
package properties

import (
	"context"
	"fmt"
	"net/http"
	"time"

	"github.com/google/uuid"

	"ivia/backend/internal/platform/apperr"
	"ivia/backend/internal/platform/database"
	"ivia/backend/internal/platform/httpapi"
	"ivia/backend/internal/properties/store"
)

// Property est une annonce publiée.
type Property struct {
	ID           uuid.UUID `json:"id"`
	Title        string    `json:"title"`
	Kind         string    `json:"kind"`
	PropertyType string    `json:"property_type"`
	PriceXOF     int64     `json:"price_xof"`
	Bedrooms     int32     `json:"bedrooms"`
	SurfaceM2    int32     `json:"surface_m2"`
	Neighborhood string    `json:"neighborhood"`
	AddressText  string    `json:"address_text"`
	Lat          float64   `json:"lat"`
	Lng          float64   `json:"lng"`
	Description  string    `json:"description"`
	PhotoURLs    []string  `json:"photo_urls"`
	ContactName  string    `json:"contact_name"`
	ContactPhone string    `json:"contact_phone"`
	DistanceM    int32     `json:"distance_m"`
	CreatedAt    time.Time `json:"created_at"`
}

// Seed est une annonce de démonstration.
type Seed = store.UpsertPropertyParams

// PublicURLs donne l'adresse publique d'un fichier (module uploads).
type PublicURLs interface{ PublicURL(key string) string }

// Service gère les annonces.
type Service struct {
	db   *database.DB
	urls PublicURLs
}

// NewService crée le service.
func NewService(db *database.DB, urls PublicURLs) *Service { return &Service{db: db, urls: urls} }

func (s *Service) photos(keys []string) []string {
	out := make([]string, len(keys))
	for i, k := range keys {
		out[i] = s.urls.PublicURL(k)
	}
	return out
}

// List retourne les annonces actives, les plus proches d'abord.
func (s *Service) List(ctx context.Context, lat, lng *float64, kind *string, limit int32) ([]Property, error) {
	rows, err := store.New(s.db.Pool).ListProperties(ctx, store.ListPropertiesParams{Lat: lat, Lng: lng, Kind: kind, Lim: limit})
	if err != nil {
		return nil, fmt.Errorf("annonces : %w", err)
	}
	out := make([]Property, len(rows))
	for i, r := range rows {
		out[i] = Property{
			ID: r.ID, Title: r.Title, Kind: r.Kind, PropertyType: r.PropertyType, PriceXOF: r.PriceXof,
			Bedrooms: r.Bedrooms, SurfaceM2: r.SurfaceM2, Neighborhood: r.Neighborhood, AddressText: r.AddressText,
			Lat: r.Lat, Lng: r.Lng, Description: r.Description, PhotoURLs: s.photos(r.PhotoKeys),
			ContactName: r.ContactName, ContactPhone: r.ContactPhone, DistanceM: int32(r.DistanceM), CreatedAt: r.CreatedAt,
		}
	}
	return out, nil
}

// Get retourne une annonce active.
func (s *Service) Get(ctx context.Context, id uuid.UUID) (Property, error) {
	r, err := store.New(s.db.Pool).GetProperty(ctx, id)
	if database.IsNoRows(err) {
		return Property{}, apperr.NotFound("property_not_found", "Annonce introuvable.")
	}
	if err != nil {
		return Property{}, fmt.Errorf("annonce : %w", err)
	}
	return Property{
		ID: r.ID, Title: r.Title, Kind: r.Kind, PropertyType: r.PropertyType, PriceXOF: r.PriceXof,
		Bedrooms: r.Bedrooms, SurfaceM2: r.SurfaceM2, Neighborhood: r.Neighborhood, AddressText: r.AddressText,
		Lat: r.Lat, Lng: r.Lng, Description: r.Description, PhotoURLs: s.photos(r.PhotoKeys),
		ContactName: r.ContactName, ContactPhone: r.ContactPhone, CreatedAt: r.CreatedAt,
	}, nil
}

// Seed crée ou réactive une annonce de démonstration ; vrai si elle a déjà des photos.
func (s *Service) Seed(ctx context.Context, in Seed) (bool, error) {
	q := store.New(s.db.Pool)
	n, err := q.CountPropertyPhotos(ctx, store.CountPropertyPhotosParams{Title: in.Title, Neighborhood: in.Neighborhood})
	if err == nil && n > 0 {
		return true, nil // déjà publiée avec ses photos
	}
	if _, err := q.UpsertProperty(ctx, in); err != nil {
		return false, fmt.Errorf("annonce de démonstration : %w", err)
	}
	return false, nil
}

// Register enregistre les routes publiques.
func (s *Service) Register(rt *httpapi.Router) {
	rt.Public("GET /v1/properties", func(w http.ResponseWriter, r *http.Request) error {
		q := httpapi.NewQuery(r)
		lat, lng := q.Float("lat", -90, 90), q.Float("lng", -180, 180)
		kind := q.Enum("kind", "", "", "sale", "rent")
		limit := q.Int64("limit", 1, 50)
		if err := q.Err(); err != nil {
			return err
		}
		lim := int32(20)
		if limit != nil {
			lim = int32(*limit)
		}
		var k *string
		if kind != "" {
			k = &kind
		}
		items, err := s.List(r.Context(), lat, lng, k, lim)
		if err != nil {
			return err
		}
		return httpapi.OK(w, map[string]any{"items": items})
	})
	rt.Public("GET /v1/properties/{id}", func(w http.ResponseWriter, r *http.Request) error {
		id, err := httpapi.PathUUID(r, "id")
		if err != nil {
			return err
		}
		p, err := s.Get(r.Context(), id)
		if err != nil {
			return err
		}
		return httpapi.OK(w, p)
	})
}
