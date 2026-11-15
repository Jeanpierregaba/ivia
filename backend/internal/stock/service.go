// Package stock gère la quantité disponible des produits à stock suivi et le journal de ses
// mouvements. La survente est impossible : une réservation est une mise à jour conditionnelle
// (quantité suffisante) et la base refuse toute quantité négative.
package stock

import (
	"bytes"
	"context"
	"fmt"
	"slices"
	"time"

	"github.com/google/uuid"

	"ivia/backend/internal/platform/apperr"
	"ivia/backend/internal/platform/database"
	"ivia/backend/internal/stock/store"
)

// Raisons des mouvements.
const (
	ReasonInitial    = "initial"
	ReasonAdjustment = "adjustment"
	ReasonReserved   = "order_reserved"
	ReasonReleased   = "order_released"
)

// MaxQuantity borne la quantité saisie par un marchand.
const MaxQuantity = 1_000_000

// Line est une quantité d'un produit dans une commande.
type Line struct {
	ProductID uuid.UUID
	Quantity  int32
}

// Movement est une ligne du journal de stock.
type Movement struct {
	ID            int64      `json:"id"`
	Delta         int32      `json:"delta"`
	QuantityAfter int32      `json:"quantity_after"`
	Reason        string     `json:"reason"`
	OrderID       *uuid.UUID `json:"order_id"`
	Note          string     `json:"note"`
	CreatedAt     time.Time  `json:"created_at"`
}

// InsufficientStockError signale le produit dont la quantité ne suffit pas.
type InsufficientStockError struct {
	ProductID uuid.UUID
}

func (e *InsufficientStockError) Error() string {
	return "stock insuffisant pour le produit " + e.ProductID.String()
}

// Service gère le stock.
type Service struct {
	db *database.DB
}

// NewService crée le service.
func NewService(db *database.DB) *Service { return &Service{db: db} }

// Init crée le stock d'un nouveau produit suivi.
func (s *Service) Init(ctx context.Context, productID uuid.UUID, qty int32, actorID uuid.UUID) error {
	if qty < 0 || qty > MaxQuantity {
		return apperr.Validation(map[string]string{"stock_quantity": "Quantité entre 0 et 1 000 000."})
	}
	return s.db.InTx(ctx, func(ctx context.Context) error {
		q := store.New(s.db.Conn(ctx))
		if err := q.InitLevel(ctx, store.InitLevelParams{ProductID: productID, Quantity: qty}); err != nil {
			return fmt.Errorf("création du stock : %w", err)
		}
		if qty == 0 {
			return nil
		}
		return q.InsertMovement(ctx, store.InsertMovementParams{
			ProductID: productID, Delta: qty, QuantityAfter: qty, Reason: ReasonInitial, ActorID: &actorID,
		})
	})
}

// SetQuantity fixe la quantité disponible (inventaire du marchand) et journalise l'écart.
func (s *Service) SetQuantity(ctx context.Context, productID uuid.UUID, qty int32, actorID uuid.UUID, note string) (int32, error) {
	if qty < 0 || qty > MaxQuantity {
		return 0, apperr.Validation(map[string]string{"quantity": "Quantité entre 0 et 1 000 000."})
	}
	err := s.db.InTx(ctx, func(ctx context.Context) error {
		q := store.New(s.db.Conn(ctx))
		cur, err := q.GetLevelForUpdate(ctx, productID)
		if database.IsNoRows(err) {
			return apperr.Conflict("stock_not_tracked", "Ce produit n'a pas de stock suivi.")
		}
		if err != nil {
			return fmt.Errorf("lecture du stock : %w", err)
		}
		if cur == qty {
			return nil
		}
		if err := q.SetLevel(ctx, store.SetLevelParams{ProductID: productID, Quantity: qty}); err != nil {
			return fmt.Errorf("mise à jour du stock : %w", err)
		}
		return q.InsertMovement(ctx, store.InsertMovementParams{
			ProductID: productID, Delta: qty - cur, QuantityAfter: qty, Reason: ReasonAdjustment, ActorID: &actorID, Note: note,
		})
	})
	return qty, err
}

// Reserve retire les quantités d'une commande. Tout ou rien : si un produit manque, rien n'est
// réservé et l'erreur indique lequel (InsufficientStockError). À appeler dans la transaction de
// création de la commande.
func (s *Service) Reserve(ctx context.Context, orderID uuid.UUID, lines []Line) error {
	return s.db.InTx(ctx, func(ctx context.Context) error {
		q := store.New(s.db.Conn(ctx))
		for _, l := range sorted(lines) {
			after, err := q.Decrement(ctx, store.DecrementParams{ProductID: l.ProductID, Qty: l.Quantity})
			if database.IsNoRows(err) {
				return &InsufficientStockError{ProductID: l.ProductID}
			}
			if err != nil {
				return fmt.Errorf("réservation du stock : %w", err)
			}
			if err := q.InsertMovement(ctx, store.InsertMovementParams{
				ProductID: l.ProductID, Delta: -l.Quantity, QuantityAfter: after, Reason: ReasonReserved, OrderID: &orderID,
			}); err != nil {
				return fmt.Errorf("journal du stock : %w", err)
			}
		}
		return nil
	})
}

// Release rend les quantités d'une commande (expirée, annulée, colis revenu en boutique).
// L'appelant garantit qu'il ne l'appelle qu'une fois par commande.
func (s *Service) Release(ctx context.Context, orderID uuid.UUID, lines []Line) error {
	return s.db.InTx(ctx, func(ctx context.Context) error {
		q := store.New(s.db.Conn(ctx))
		for _, l := range sorted(lines) {
			after, err := q.Increment(ctx, store.IncrementParams{ProductID: l.ProductID, Qty: l.Quantity})
			if database.IsNoRows(err) {
				continue // produit devenu non suivi : rien à rendre
			}
			if err != nil {
				return fmt.Errorf("libération du stock : %w", err)
			}
			if err := q.InsertMovement(ctx, store.InsertMovementParams{
				ProductID: l.ProductID, Delta: l.Quantity, QuantityAfter: after, Reason: ReasonReleased, OrderID: &orderID,
			}); err != nil {
				return fmt.Errorf("journal du stock : %w", err)
			}
		}
		return nil
	})
}

// Levels retourne la quantité disponible des produits suivis parmi ids.
func (s *Service) Levels(ctx context.Context, ids []uuid.UUID) (map[uuid.UUID]int32, error) {
	rows, err := store.New(s.db.Conn(ctx)).ListLevels(ctx, ids)
	if err != nil {
		return nil, fmt.Errorf("lecture du stock : %w", err)
	}
	out := make(map[uuid.UUID]int32, len(rows))
	for _, r := range rows {
		out[r.ProductID] = r.Quantity
	}
	return out, nil
}

// Movements retourne le journal d'un produit, du plus récent au plus ancien.
func (s *Service) Movements(ctx context.Context, productID uuid.UUID, limit, offset int32) ([]Movement, error) {
	rows, err := store.New(s.db.Conn(ctx)).ListMovements(ctx, store.ListMovementsParams{ProductID: productID, Lim: limit, Off: offset})
	if err != nil {
		return nil, fmt.Errorf("journal du stock : %w", err)
	}
	out := make([]Movement, len(rows))
	for i, r := range rows {
		out[i] = Movement{ID: r.ID, Delta: r.Delta, QuantityAfter: r.QuantityAfter, Reason: r.Reason, OrderID: r.OrderID, Note: r.Note, CreatedAt: r.CreatedAt}
	}
	return out, nil
}

// sorted trie par produit : les verrous sont toujours pris dans le même ordre (pas d'interblocage).
func sorted(lines []Line) []Line {
	out := slices.Clone(lines)
	slices.SortFunc(out, func(a, b Line) int { return bytes.Compare(a.ProductID[:], b.ProductID[:]) })
	return out
}
