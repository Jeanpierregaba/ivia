package catalog

import (
	"context"
	"fmt"
	"slices"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/google/uuid"

	"ivia/backend/internal/admin"
	"ivia/backend/internal/catalog/store"
	"ivia/backend/internal/platform/apperr"
	"ivia/backend/internal/platform/validate"
)

// Promotion et mise en avant des produits (produits IVI et AWU-IVI d'abord), et gestion d'un
// produit par l'admin (boutiques gérées par la plateforme). Les prix facturés suivent
// EffectivePriceXOF (panier, commande) : une promotion n'a jamais besoin de code ailleurs.

// Badges proposés : promotion, offre spéciale, produit vedette, meilleure vente.
var Badges = []string{"promotion", "special_offer", "featured", "best_seller"}

const (
	maxFeatures      = 12
	maxFeatureLength = 80
)

// MarketingInput : promotion et mise en avant d'un produit. PromoPriceXOF nil retire la
// promotion ; FeaturedRank nil retire la mise en avant (1 = premier).
type MarketingInput struct {
	PromoPriceXOF *int64     `json:"promo_price_xof"`
	PromoStartsAt *time.Time `json:"promo_starts_at"`
	PromoEndsAt   *time.Time `json:"promo_ends_at"`
	Badges        []string   `json:"badges"`
	FeaturedRank  *int32     `json:"featured_rank"`
	Features      []string   `json:"features"`
}

func promoActive(price *int64, starts, ends *time.Time, now time.Time) bool {
	return price != nil && (starts == nil || !now.Before(*starts)) && (ends == nil || now.Before(*ends))
}

func nonNil(v []string) []string {
	if v == nil {
		return []string{}
	}
	return v
}

// SetMarketing enregistre promotion, badges, mise en avant et caractéristiques (admin, journalisé).
func (s *Service) SetMarketing(ctx context.Context, adminID, productID uuid.UUID, in MarketingInput) (Product, error) {
	cur, err := s.get(ctx, productID)
	if err != nil {
		return Product{}, err
	}
	v := validate.New()
	if in.PromoPriceXOF != nil {
		v.Check(cur.PriceXOF > 0, "promo_price_xof", "Indiquez d'abord le prix normal.")
		v.Check(*in.PromoPriceXOF > 0 && *in.PromoPriceXOF < cur.PriceXOF, "promo_price_xof", "Le prix promotionnel doit être inférieur au prix normal.")
	} else {
		in.PromoStartsAt, in.PromoEndsAt = nil, nil
	}
	if in.PromoStartsAt != nil && in.PromoEndsAt != nil {
		v.Check(in.PromoEndsAt.After(*in.PromoStartsAt), "promo_ends_at", "La fin doit suivre le début.")
	}
	in.Badges = nonNil(in.Badges)
	for _, b := range in.Badges {
		v.Check(slices.Contains(Badges, b), "badges", "Badge inconnu : "+strings.Join(Badges, ", ")+".")
	}
	slices.Sort(in.Badges)
	in.Badges = slices.Compact(in.Badges)
	if in.FeaturedRank != nil {
		v.Check(*in.FeaturedRank >= 1 && *in.FeaturedRank <= 1000, "featured_rank", "Rang entre 1 et 1000.")
	}
	features := make([]string, 0, len(in.Features))
	for _, f := range in.Features {
		if f = validate.Clean(f); f != "" {
			v.Check(utf8.RuneCountInString(f) <= maxFeatureLength, "features", fmt.Sprintf("%d caractères au plus par caractéristique.", maxFeatureLength))
			features = append(features, f)
		}
	}
	v.Check(len(features) <= maxFeatures, "features", fmt.Sprintf("%d caractéristiques au plus.", maxFeatures))
	if err := v.Err(); err != nil {
		return Product{}, err
	}
	err = s.db.InTx(ctx, func(ctx context.Context) error {
		if err := store.New(s.db.Conn(ctx)).SetProductMarketing(ctx, store.SetProductMarketingParams{
			ID: productID, PromoPriceXof: in.PromoPriceXOF, PromoStartsAt: in.PromoStartsAt, PromoEndsAt: in.PromoEndsAt,
			Badges: in.Badges, FeaturedRank: in.FeaturedRank, Features: features,
		}); err != nil {
			return fmt.Errorf("promotion du produit : %w", err)
		}
		return s.audit.Record(ctx, admin.AuditEntry{
			AdminID: &adminID, Action: "product.marketing", TargetType: "product", TargetID: productID.String(),
			Before: map[string]any{"promo_price_xof": cur.PromoPriceXOF, "badges": cur.Badges, "featured_rank": cur.FeaturedRank},
			After:  map[string]any{"promo_price_xof": in.PromoPriceXOF, "badges": in.Badges, "featured_rank": in.FeaturedRank},
		})
	})
	if err != nil {
		return Product{}, err
	}
	return s.get(ctx, productID)
}

// Featured retourne les produits mis en avant en vente, dans une boutique publiée, par rang.
func (s *Service) Featured(ctx context.Context, limit int32) ([]Product, error) {
	rows, err := store.New(s.db.Conn(ctx)).FeaturedProducts(ctx, limit)
	if err != nil {
		return nil, fmt.Errorf("produits mis en avant : %w", err)
	}
	list, err := s.enrich(ctx, rows)
	if err != nil {
		return nil, err
	}
	out := list[:0]
	for _, p := range list {
		if _, err := s.shops.RequirePublished(ctx, p.ShopID); err == nil {
			out = append(out, p)
		}
	}
	return out, nil
}

// --- Gestion par l'admin -------------------------------------------------------------------
// Pour les boutiques gérées par la plateforme (IVI) : mêmes règles que le marchand, sans
// contrôle de propriété ; les photos sont celles envoyées par l'admin (clés products/<admin>/).

// AdminList liste les produits d'une boutique (ou de toutes), mis en avant d'abord.
func (s *Service) AdminList(ctx context.Context, shopID *uuid.UUID, q string, limit, offset int32) ([]Product, error) {
	var search *string
	if q = strings.TrimSpace(q); q != "" {
		e := strings.NewReplacer(`\`, `\\`, `%`, `\%`, `_`, `\_`).Replace(q)
		search = &e
	}
	rows, err := store.New(s.db.Conn(ctx)).AdminListProducts(ctx, store.AdminListProductsParams{ShopID: shopID, Q: search, Lim: limit, Off: offset})
	if err != nil {
		return nil, fmt.Errorf("liste des produits : %w", err)
	}
	return s.enrich(ctx, rows)
}

// AdminGet retourne un produit quel que soit son état.
func (s *Service) AdminGet(ctx context.Context, productID uuid.UUID) (Product, error) {
	return s.get(ctx, productID)
}

// AdminCreate crée un produit dans une boutique (journalisé).
func (s *Service) AdminCreate(ctx context.Context, adminID, shopID uuid.UUID, in ProductInput) (Product, error) {
	if _, err := s.shops.Get(ctx, shopID); err != nil {
		return Product{}, err
	}
	p, err := s.create(ctx, adminID, shopID, in)
	if err != nil {
		return Product{}, err
	}
	return p, s.audit.Record(ctx, admin.AuditEntry{
		AdminID: &adminID, Action: "product.create", TargetType: "product", TargetID: p.ID.String(),
		After: map[string]any{"name": p.Name, "shop_id": shopID, "price_xof": p.PriceXOF},
	})
}

// AdminUpdate modifie un produit (journalisé).
func (s *Service) AdminUpdate(ctx context.Context, adminID, productID uuid.UUID, in ProductInput) (Product, error) {
	cur, err := s.get(ctx, productID)
	if err != nil {
		return Product{}, err
	}
	p, err := s.update(ctx, adminID, cur, in)
	if err != nil {
		return Product{}, err
	}
	return p, s.audit.Record(ctx, admin.AuditEntry{
		AdminID: &adminID, Action: "product.update", TargetType: "product", TargetID: productID.String(),
		Before: map[string]any{"price_xof": cur.PriceXOF, "is_active": cur.IsActive},
		After:  map[string]any{"price_xof": p.PriceXOF, "is_active": p.IsActive},
	})
}

// AdminSetStock fixe la quantité d'un produit suivi.
func (s *Service) AdminSetStock(ctx context.Context, adminID, productID uuid.UUID, qty int32, note string) (Product, error) {
	p, err := s.get(ctx, productID)
	if err != nil {
		return Product{}, err
	}
	if p.StockMode != StockTracked {
		return Product{}, apperr.Conflict("stock_not_tracked", "Ce produit n'a pas de stock suivi.")
	}
	if _, err := s.stock.SetQuantity(ctx, productID, qty, adminID, validate.Clean(note)); err != nil {
		return Product{}, err
	}
	return s.get(ctx, productID)
}
