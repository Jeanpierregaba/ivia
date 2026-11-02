// Package cart gère le panier de l'acheteur, limité à une seule boutique : ajouter un produit d'une
// autre boutique demande de vider le panier (replace_cart).
package cart

import (
	"context"
	"fmt"

	"github.com/google/uuid"

	"ivia/backend/internal/cart/store"
	"ivia/backend/internal/catalog"
	"ivia/backend/internal/platform/apperr"
	"ivia/backend/internal/platform/database"
	"ivia/backend/internal/shops"
)

// Limites du panier.
const (
	MaxLines    = 30
	MaxQuantity = 99
)

// Item est une ligne du panier, avec l'état actuel du produit.
type Item struct {
	ProductID    uuid.UUID          `json:"product_id"`
	Name         string             `json:"name"`
	ImageURL     *string            `json:"image_url"`
	UnitPriceXOF int64              `json:"unit_price_xof"`
	Quantity     int32              `json:"quantity"`
	LineTotalXOF int64              `json:"line_total_xof"`
	ParcelSize   catalog.ParcelSize `json:"parcel_size"`
	// Issue explique pourquoi la ligne empêche de commander (vide si tout va bien), à afficher tel quel.
	Issue string `json:"issue"`
	// IssueCode est la même raison pour les apps : "" , "unavailable" ou "insufficient_stock".
	IssueCode string `json:"issue_code"`
	// StockLeft : stock restant, renseigné quand IssueCode vaut "insufficient_stock".
	StockLeft *int32 `json:"stock_left"`
}

// Codes des raisons d'une ligne bloquée.
const (
	IssueUnavailable       = "unavailable"
	IssueInsufficientStock = "insufficient_stock"
)

// Cart est le panier de l'acheteur.
type Cart struct {
	Shop        *shops.PublicShop `json:"shop"`
	Items       []Item            `json:"items"`
	SubtotalXOF int64             `json:"subtotal_xof"`
	// Orderable : toutes les lignes sont disponibles et la boutique accepte les commandes.
	Orderable bool `json:"orderable"`
}

// Line est une ligne brute (pour la création de commande).
type Line struct {
	ProductID uuid.UUID
	Quantity  int32
}

// Service gère les paniers.
type Service struct {
	db      *database.DB
	catalog *catalog.Service
	shops   *shops.Service
}

// NewService crée le service.
func NewService(db *database.DB, cat *catalog.Service, shopSvc *shops.Service) *Service {
	return &Service{db: db, catalog: cat, shops: shopSvc}
}

// Get retourne le panier avec les prix et disponibilités actuels.
func (s *Service) Get(ctx context.Context, buyerID uuid.UUID) (Cart, error) {
	q := store.New(s.db.Conn(ctx))
	c, err := q.GetCart(ctx, buyerID)
	if database.IsNoRows(err) {
		return Cart{Items: []Item{}}, nil
	}
	if err != nil {
		return Cart{}, fmt.Errorf("lecture du panier : %w", err)
	}
	rows, err := q.ListItems(ctx, buyerID)
	if err != nil {
		return Cart{}, fmt.Errorf("lecture du panier : %w", err)
	}
	ids := make([]uuid.UUID, len(rows))
	for i, r := range rows {
		ids[i] = r.ProductID
	}
	products, err := s.catalog.ProductsByIDs(ctx, ids)
	if err != nil {
		return Cart{}, err
	}
	out := Cart{Items: make([]Item, 0, len(rows)), Orderable: len(rows) > 0}
	shop, err := s.shops.RequirePublished(ctx, c.ShopID)
	switch {
	case err == nil:
		pub := shop.Public()
		out.Shop = &pub
		if !shop.AcceptingOrders {
			out.Orderable = false
		}
	case apperr.IsCode(err, "shop_not_found"):
		out.Orderable = false
	default:
		return Cart{}, err
	}
	for _, r := range rows {
		p := products[r.ProductID]
		it := Item{
			ProductID: r.ProductID, Name: p.Name, UnitPriceXOF: p.PriceXOF, Quantity: r.Quantity,
			LineTotalXOF: p.PriceXOF * int64(r.Quantity), ParcelSize: p.ParcelSize,
		}
		if len(p.Images) > 0 {
			it.ImageURL = &p.Images[0].URL
		}
		switch {
		case !p.IsActive || out.Shop == nil:
			it.Issue, it.IssueCode = "Ce produit n'est plus disponible.", IssueUnavailable
		case p.StockQuantity != nil && *p.StockQuantity < r.Quantity:
			it.Issue, it.IssueCode = fmt.Sprintf("Plus que %d en stock.", *p.StockQuantity), IssueInsufficientStock
			left := *p.StockQuantity
			it.StockLeft = &left
		}
		if it.Issue != "" {
			out.Orderable = false
		} else {
			out.SubtotalXOF += it.LineTotalXOF
		}
		out.Items = append(out.Items, it)
	}
	return out, nil
}

// SetItem fixe la quantité d'un produit (0 = retirer). Un produit d'une autre boutique est refusé
// (cart_shop_conflict) sauf si replace vaut true : le panier est alors vidé d'abord.
func (s *Service) SetItem(ctx context.Context, buyerID, productID uuid.UUID, qty int32, replace bool) (Cart, error) {
	if qty < 0 || qty > MaxQuantity {
		return Cart{}, apperr.Validation(map[string]string{"quantity": "Quantité entre 0 et 99."})
	}
	err := s.db.InTx(ctx, func(ctx context.Context) error {
		q := store.New(s.db.Conn(ctx))
		if qty == 0 {
			if err := q.DeleteItem(ctx, store.DeleteItemParams{BuyerID: buyerID, ProductID: productID}); err != nil {
				return fmt.Errorf("retrait du produit : %w", err)
			}
			return s.dropIfEmpty(ctx, buyerID)
		}
		p, _, err := s.catalog.GetPublic(ctx, productID)
		if err != nil {
			return err
		}
		if !p.Available {
			return apperr.Conflict("product_unavailable", "Ce produit n'est plus disponible.")
		}
		if p.StockQuantity != nil && *p.StockQuantity < qty {
			return apperr.Conflict("insufficient_stock", fmt.Sprintf("Seulement %d en stock.", *p.StockQuantity))
		}
		cur, err := q.GetCart(ctx, buyerID)
		switch {
		case database.IsNoRows(err):
		case err != nil:
			return fmt.Errorf("lecture du panier : %w", err)
		case cur.ShopID != p.ShopID:
			if !replace {
				return apperr.Conflict("cart_shop_conflict", "Votre panier contient des produits d'une autre boutique. Videz-le pour ajouter celui-ci.")
			}
			if err := q.DeleteCart(ctx, buyerID); err != nil {
				return fmt.Errorf("vidage du panier : %w", err)
			}
		}
		if err := q.UpsertCart(ctx, store.UpsertCartParams{BuyerID: buyerID, ShopID: p.ShopID}); err != nil {
			return fmt.Errorf("création du panier : %w", err)
		}
		if err := q.SetItem(ctx, store.SetItemParams{BuyerID: buyerID, ProductID: productID, Quantity: qty}); err != nil {
			return fmt.Errorf("ajout au panier : %w", err)
		}
		n, err := q.CountItems(ctx, buyerID)
		if err != nil {
			return fmt.Errorf("lecture du panier : %w", err)
		}
		if n > MaxLines {
			return apperr.Conflict("cart_full", "Votre panier contient trop de produits différents.")
		}
		return nil
	})
	if err != nil {
		return Cart{}, err
	}
	return s.Get(ctx, buyerID)
}

// Clear vide le panier.
func (s *Service) Clear(ctx context.Context, buyerID uuid.UUID) error {
	if err := store.New(s.db.Conn(ctx)).DeleteCart(ctx, buyerID); err != nil {
		return fmt.Errorf("vidage du panier : %w", err)
	}
	return nil
}

// Lines retourne la boutique et les lignes brutes du panier (création de commande).
func (s *Service) Lines(ctx context.Context, buyerID uuid.UUID) (uuid.UUID, []Line, error) {
	q := store.New(s.db.Conn(ctx))
	c, err := q.GetCart(ctx, buyerID)
	if database.IsNoRows(err) {
		return uuid.Nil, nil, nil
	}
	if err != nil {
		return uuid.Nil, nil, fmt.Errorf("lecture du panier : %w", err)
	}
	rows, err := q.ListItems(ctx, buyerID)
	if err != nil {
		return uuid.Nil, nil, fmt.Errorf("lecture du panier : %w", err)
	}
	lines := make([]Line, len(rows))
	for i, r := range rows {
		lines[i] = Line{ProductID: r.ProductID, Quantity: r.Quantity}
	}
	return c.ShopID, lines, nil
}

// OnAccountDeleted vide le panier du compte supprimé (users.DeletionHook).
func (s *Service) OnAccountDeleted(ctx context.Context, userID uuid.UUID) error {
	return s.Clear(ctx, userID)
}

func (s *Service) dropIfEmpty(ctx context.Context, buyerID uuid.UUID) error {
	q := store.New(s.db.Conn(ctx))
	n, err := q.CountItems(ctx, buyerID)
	if err != nil {
		return fmt.Errorf("lecture du panier : %w", err)
	}
	if n == 0 {
		return q.DeleteCart(ctx, buyerID)
	}
	return nil
}
