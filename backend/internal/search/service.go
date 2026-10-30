// Package search gère la recherche de produits et de boutiques : texte (plein texte français sans
// accents + tolérance aux fautes), catégorie, prix, quartier, « autour de moi » (PostGIS).
//
// Il lit des vues en lecture seule sur le catalogue publié (ADR 0009) plutôt que les tables des
// modules catalog, shops et stock.
package search

import (
	"context"
	"fmt"
	"net/http"
	"time"

	"github.com/google/uuid"

	"ivia/backend/internal/platform/apperr"
	"ivia/backend/internal/platform/database"
	"ivia/backend/internal/platform/httpapi"
	"ivia/backend/internal/platform/ratelimit"
	"ivia/backend/internal/search/store"
)

// MaxRadiusMeters borne la recherche « autour de moi » (Grand Lomé).
const MaxRadiusMeters = 50_000

// URLResolver retourne l'URL publique d'un fichier (photos, logos).
type URLResolver interface {
	PublicURL(key string) string
}

// ProductHit est un produit trouvé.
type ProductHit struct {
	ID             uuid.UUID  `json:"id"`
	ShopID         uuid.UUID  `json:"shop_id"`
	Name           string     `json:"name"`
	PriceXOF       int64      `json:"price_xof"`
	ParcelSize     string     `json:"parcel_size"`
	ShopName       string     `json:"shop_name"`
	NeighborhoodID *uuid.UUID `json:"neighborhood_id"`
	ImageURL       *string    `json:"image_url"`
	InStock        bool       `json:"in_stock"`
	DistanceM      *int64     `json:"distance_m"`
}

// ShopHit est une boutique trouvée.
type ShopHit struct {
	ID              uuid.UUID  `json:"id"`
	Name            string     `json:"name"`
	Description     string     `json:"description"`
	NeighborhoodID  *uuid.UUID `json:"neighborhood_id"`
	LogoURL         *string    `json:"logo_url"`
	AcceptingOrders bool       `json:"accepting_orders"`
	DistanceM       *int64     `json:"distance_m"`
}

// Service exécute les recherches.
type Service struct {
	db      *database.DB
	urls    URLResolver
	limiter *ratelimit.Limiter
}

// NewService crée le service.
func NewService(db *database.DB, urls URLResolver) *Service {
	return &Service{db: db, urls: urls, limiter: ratelimit.New(120, time.Minute)}
}

type filters struct {
	q                            *string
	lat, lng, radius             *float64
	neighborhood, category, shop *uuid.UUID
	minPrice, maxPrice           *int64
	inStockOnly                  bool
	sort                         string
	page                         httpapi.Page
}

func parseFilters(r *http.Request, sorts ...string) (filters, error) {
	q := httpapi.NewQuery(r)
	f := filters{page: q.Page()}
	if s := q.String("q", 100); s != "" {
		f.q = &s
	}
	f.lat = q.Float("lat", -90, 90)
	f.lng = q.Float("lng", -180, 180)
	if rad := q.Int64("radius_m", 100, MaxRadiusMeters); rad != nil {
		v := float64(*rad)
		f.radius = &v
	}
	f.neighborhood = q.UUID("neighborhood_id")
	f.category = q.UUID("category_id")
	f.shop = q.UUID("shop_id")
	f.minPrice = q.Int64("min_price", 0, 100_000_000)
	f.maxPrice = q.Int64("max_price", 0, 100_000_000)
	f.inStockOnly = q.Enum("in_stock", "false", "true", "false") == "true"
	f.sort = q.Enum("sort", "relevance", sorts...)
	if err := q.Err(); err != nil {
		return f, err
	}
	fields := map[string]string{}
	if (f.lat == nil) != (f.lng == nil) {
		fields["lat"] = "Indiquez lat et lng ensemble."
	}
	if (f.radius != nil || f.sort == "distance") && f.lat == nil {
		fields["lat"] = "La position est nécessaire pour chercher autour de vous."
	}
	if f.minPrice != nil && f.maxPrice != nil && *f.minPrice > *f.maxPrice {
		fields["min_price"] = "Le prix minimal dépasse le prix maximal."
	}
	if len(fields) > 0 {
		return f, apperr.Validation(fields)
	}
	return f, nil
}

func (s *Service) products(ctx context.Context, f filters) ([]ProductHit, error) {
	rows, err := store.New(s.db.Conn(ctx)).SearchProducts(ctx, store.SearchProductsParams{
		Q: f.q, Lat: f.lat, Lng: f.lng, RadiusM: f.radius, CategoryID: f.category, ShopID: f.shop,
		MinPrice: f.minPrice, MaxPrice: f.maxPrice, NeighborhoodID: f.neighborhood,
		InStockOnly: f.inStockOnly, Sort: f.sort, Lim: f.page.FetchLimit(), Off: int32(f.page.Offset),
	})
	if err != nil {
		return nil, fmt.Errorf("recherche de produits : %w", err)
	}
	out := make([]ProductHit, len(rows))
	for i, r := range rows {
		out[i] = ProductHit{
			ID: r.ID, ShopID: r.ShopID, Name: r.Name, PriceXOF: r.PriceXof, ParcelSize: r.ParcelSize,
			ShopName: r.ShopName, NeighborhoodID: r.NeighborhoodID, InStock: r.InStock, DistanceM: meters(r.DistanceM),
		}
		if r.MainImageKey != "" {
			u := s.urls.PublicURL(r.MainImageKey)
			out[i].ImageURL = &u
		}
	}
	return out, nil
}

func (s *Service) shops(ctx context.Context, f filters) ([]ShopHit, error) {
	rows, err := store.New(s.db.Conn(ctx)).SearchShops(ctx, store.SearchShopsParams{
		Q: f.q, Lat: f.lat, Lng: f.lng, RadiusM: f.radius, NeighborhoodID: f.neighborhood,
		Sort: f.sort, Lim: f.page.FetchLimit(), Off: int32(f.page.Offset),
	})
	if err != nil {
		return nil, fmt.Errorf("recherche de boutiques : %w", err)
	}
	out := make([]ShopHit, len(rows))
	for i, r := range rows {
		out[i] = ShopHit{
			ID: r.ID, Name: r.Name, Description: r.Description, NeighborhoodID: r.NeighborhoodID,
			AcceptingOrders: r.AcceptingOrders, DistanceM: meters(r.DistanceM),
		}
		if r.LogoKey != nil {
			u := s.urls.PublicURL(*r.LogoKey)
			out[i].LogoURL = &u
		}
	}
	return out, nil
}

// Register enregistre les routes de recherche (publiques, limitées par adresse IP).
func (s *Service) Register(rt *httpapi.Router) {
	rt.Public("GET /v1/search/products", func(w http.ResponseWriter, r *http.Request) error {
		if err := s.allow(r); err != nil {
			return err
		}
		f, err := parseFilters(r, "relevance", "distance", "price_asc", "price_desc")
		if err != nil {
			return err
		}
		hits, err := s.products(r.Context(), f)
		if err != nil {
			return err
		}
		return httpapi.OK(w, httpapi.NewList(hits, f.page))
	})
	rt.Public("GET /v1/search/shops", func(w http.ResponseWriter, r *http.Request) error {
		if err := s.allow(r); err != nil {
			return err
		}
		f, err := parseFilters(r, "relevance", "distance")
		if err != nil {
			return err
		}
		hits, err := s.shops(r.Context(), f)
		if err != nil {
			return err
		}
		return httpapi.OK(w, httpapi.NewList(hits, f.page))
	})
}

func (s *Service) allow(r *http.Request) error {
	if ok, retry := s.limiter.Allow(httpapi.ClientIP(r.Context())); !ok {
		return apperr.TooManyRequests("rate_limited", "Trop de recherches. Patientez un instant.", retry)
	}
	return nil
}

// meters convertit une distance (-1 : pas de position fournie).
func meters(f float64) *int64 {
	if f < 0 {
		return nil
	}
	m := int64(f + 0.5)
	return &m
}
