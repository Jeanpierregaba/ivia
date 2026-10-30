// Package settlements gère les relevés des sommes dues aux marchands et leur marquage « réglé »
// par l'admin (le virement se fait hors application).
//
// Un relevé couvre les commandes remises (retrait ou livraison) d'une boutique sur une période en
// dates de Lomé : net = montant des produits − commission. Une commande n'entre que dans un seul
// relevé (contrainte d'unicité) ; un relevé réglé est figé (trigger). Les frais de livraison
// restent à la plateforme. Les commandes annulées ou revenues en boutique ne sont jamais remises,
// donc jamais versées au marchand : leur remboursement ne se déduit d'aucun relevé.
package settlements

import (
	"context"
	"fmt"
	"time"

	"github.com/google/uuid"

	"ivia/backend/internal/admin"
	"ivia/backend/internal/notifications"
	"ivia/backend/internal/orders"
	"ivia/backend/internal/platform/apperr"
	"ivia/backend/internal/platform/database"
	"ivia/backend/internal/platform/validate"
	"ivia/backend/internal/settlements/store"
	"ivia/backend/internal/shops"
)

// Lome est le fuseau des périodes de règlement (UTC toute l'année).
var Lome = func() *time.Location {
	loc, err := time.LoadLocation("Africa/Lome")
	if err != nil {
		return time.FixedZone("Africa/Lome", 0)
	}
	return loc
}()

// Settlement est un relevé.
type Settlement struct {
	ID                  uuid.UUID  `json:"id"`
	ShopID              uuid.UUID  `json:"shop_id"`
	ShopName            string     `json:"shop_name"`
	PeriodStart         string     `json:"period_start"`
	PeriodEnd           string     `json:"period_end"`
	OrdersCount         int32      `json:"orders_count"`
	GrossXOF            int64      `json:"gross_xof"`
	CommissionXOF       int64      `json:"commission_xof"`
	NetXOF              int64      `json:"net_xof"`
	Status              string     `json:"status"`
	SettledAt           *time.Time `json:"settled_at"`
	SettlementReference string     `json:"settlement_reference"`
	Note                string     `json:"note"`
	CreatedAt           time.Time  `json:"created_at"`
	Lines               []Line     `json:"lines,omitempty"`
}

// Line est une commande comprise dans un relevé.
type Line struct {
	OrderID       uuid.UUID `json:"order_id"`
	Reference     string    `json:"order_reference"`
	CompletedAt   time.Time `json:"completed_at"`
	SubtotalXOF   int64     `json:"subtotal_xof"`
	CommissionXOF int64     `json:"commission_xof"`
	NetXOF        int64     `json:"net_xof"`

	number int64
}

// Service gère les relevés.
type Service struct {
	db     *database.DB
	orders *orders.Service
	shops  *shops.Service
	audit  *admin.Service
	notify *notifications.Service
}

// NewService crée le service.
func NewService(db *database.DB, ord *orders.Service, shopSvc *shops.Service, audit *admin.Service, notify *notifications.Service) *Service {
	return &Service{db: db, orders: ord, shops: shopSvc, audit: audit, notify: notify}
}

var errNotFound = apperr.NotFound("settlement_not_found", "Relevé introuvable.")

// period convertit des dates de Lomé (bornes incluses) en instants [début, fin).
func period(from, to time.Time) (time.Time, time.Time, error) {
	if to.Before(from) || to.Sub(from) > 366*24*time.Hour {
		return time.Time{}, time.Time{}, apperr.Validation(map[string]string{"period_end": "Période invalide (un an au plus)."})
	}
	start := time.Date(from.Year(), from.Month(), from.Day(), 0, 0, 0, 0, Lome)
	end := time.Date(to.Year(), to.Month(), to.Day(), 0, 0, 0, 0, Lome).AddDate(0, 0, 1)
	return start, end, nil
}

// Preview calcule le relevé d'une boutique sur une période, sans l'enregistrer.
func (s *Service) Preview(ctx context.Context, shopID uuid.UUID, from, to time.Time) (Settlement, error) {
	shop, err := s.shops.Get(ctx, shopID)
	if err != nil {
		return Settlement{}, err
	}
	start, end, err := period(from, to)
	if err != nil {
		return Settlement{}, err
	}
	completed, err := s.orders.CompletedForShop(ctx, shopID, start, end)
	if err != nil {
		return Settlement{}, err
	}
	ids := make([]uuid.UUID, len(completed))
	for i, o := range completed {
		ids[i] = o.ID
	}
	settled, err := store.New(s.db.Conn(ctx)).AlreadySettledOrders(ctx, ids)
	if err != nil {
		return Settlement{}, fmt.Errorf("commandes déjà réglées : %w", err)
	}
	skip := map[uuid.UUID]bool{}
	for _, id := range settled {
		skip[id] = true
	}
	out := Settlement{
		ShopID: shopID, ShopName: shop.Name, Status: "preview",
		PeriodStart: from.Format(time.DateOnly), PeriodEnd: to.Format(time.DateOnly), Lines: []Line{},
	}
	for _, o := range completed {
		if skip[o.ID] {
			continue
		}
		out.Lines = append(out.Lines, Line{
			OrderID: o.ID, Reference: orders.Reference(o.Number), CompletedAt: o.CompletedAt,
			SubtotalXOF: o.SubtotalXOF, CommissionXOF: o.CommissionXOF, NetXOF: o.SubtotalXOF - o.CommissionXOF,
			number: o.Number,
		})
		out.GrossXOF += o.SubtotalXOF
		out.CommissionXOF += o.CommissionXOF
	}
	out.OrdersCount = int32(len(out.Lines))
	out.NetXOF = out.GrossXOF - out.CommissionXOF
	return out, nil
}

// Create enregistre le relevé d'une période (admin, journalisé).
func (s *Service) Create(ctx context.Context, adminID, shopID uuid.UUID, from, to time.Time, note string) (Settlement, error) {
	var id uuid.UUID
	err := s.db.InTx(ctx, func(ctx context.Context) error {
		p, err := s.Preview(ctx, shopID, from, to)
		if err != nil {
			return err
		}
		if p.OrdersCount == 0 {
			return apperr.Conflict("nothing_to_settle", "Aucune commande remise à régler sur cette période.")
		}
		q := store.New(s.db.Conn(ctx))
		row, err := q.InsertSettlement(ctx, store.InsertSettlementParams{
			ShopID: shopID, PeriodStart: from, PeriodEnd: to, OrdersCount: p.OrdersCount, GrossXof: p.GrossXOF,
			CommissionXof: p.CommissionXOF, NetXof: p.NetXOF, CreatedBy: adminID, Note: validate.Clean(note),
		})
		if err != nil {
			return fmt.Errorf("création du relevé : %w", err)
		}
		id = row.ID
		for _, l := range p.Lines {
			err := q.InsertLine(ctx, store.InsertLineParams{
				SettlementID: row.ID, OrderID: l.OrderID, OrderNumber: l.number, CompletedAt: l.CompletedAt,
				SubtotalXof: l.SubtotalXOF, CommissionXof: l.CommissionXOF,
			})
			if database.IsUniqueViolation(err, "") {
				return apperr.Conflict("settlement_conflict", "Un autre relevé vient d'inclure ces commandes. Réessayez.")
			}
			if err != nil {
				return fmt.Errorf("ligne de relevé : %w", err)
			}
		}
		return s.audit.Record(ctx, admin.AuditEntry{
			AdminID: &adminID, Action: "settlement.create", TargetType: "settlement", TargetID: row.ID.String(),
			After: map[string]any{"shop_id": shopID, "period_start": p.PeriodStart, "period_end": p.PeriodEnd, "net_xof": p.NetXOF, "orders_count": p.OrdersCount},
		})
	})
	if err != nil {
		return Settlement{}, err
	}
	return s.Get(ctx, id)
}

// MarkSettled marque un relevé comme réglé : il devient non modifiable (admin, journalisé).
func (s *Service) MarkSettled(ctx context.Context, adminID, id uuid.UUID, reference, note string) (Settlement, error) {
	reference = validate.Clean(reference)
	if reference == "" {
		return Settlement{}, apperr.Validation(map[string]string{"settlement_reference": "Indiquez la référence du virement ou du transfert."})
	}
	err := s.db.InTx(ctx, func(ctx context.Context) error {
		cur, err := s.Get(ctx, id)
		if err != nil {
			return err
		}
		n, err := store.New(s.db.Conn(ctx)).MarkSettled(ctx, store.MarkSettledParams{ID: id, SettledBy: &adminID, Reference: reference, Note: validate.Clean(note)})
		if err != nil {
			return fmt.Errorf("règlement du relevé : %w", err)
		}
		if n == 0 {
			return apperr.Conflict("already_settled", "Ce relevé est déjà réglé.")
		}
		if err := s.audit.Record(ctx, admin.AuditEntry{
			AdminID: &adminID, Action: "settlement.mark_settled", TargetType: "settlement", TargetID: id.String(),
			Before: map[string]any{"status": "open"}, After: map[string]any{"status": "settled", "reference": reference, "net_xof": cur.NetXOF},
		}); err != nil {
			return err
		}
		shop, err := s.shops.Get(ctx, cur.ShopID)
		if err != nil {
			return err
		}
		return s.notify.Notify(ctx, notifications.Message{
			UserID: shop.OwnerID, App: notifications.AppSeller, Kind: "settlement_paid", Title: "Règlement effectué",
			Body: fmt.Sprintf("Votre relevé du %s au %s a été réglé.", cur.PeriodStart, cur.PeriodEnd),
			Data: map[string]string{"settlement_id": id.String()},
		})
	})
	if err != nil {
		return Settlement{}, err
	}
	return s.Get(ctx, id)
}

// DeleteOpen supprime un relevé non réglé (erreur de période), journalisé.
func (s *Service) DeleteOpen(ctx context.Context, adminID, id uuid.UUID, reason string) error {
	return s.db.InTx(ctx, func(ctx context.Context) error {
		cur, err := s.Get(ctx, id)
		if err != nil {
			return err
		}
		n, err := store.New(s.db.Conn(ctx)).DeleteOpenSettlement(ctx, id)
		if err != nil {
			return fmt.Errorf("suppression du relevé : %w", err)
		}
		if n == 0 {
			return apperr.Conflict("already_settled", "Un relevé réglé ne peut pas être supprimé.")
		}
		cur.Lines = nil
		return s.audit.Record(ctx, admin.AuditEntry{
			AdminID: &adminID, Action: "settlement.delete", TargetType: "settlement", TargetID: id.String(),
			Before: cur, Reason: validate.Clean(reason),
		})
	})
}

// Get retourne un relevé et ses lignes.
func (s *Service) Get(ctx context.Context, id uuid.UUID) (Settlement, error) {
	q := store.New(s.db.Conn(ctx))
	row, err := q.GetSettlement(ctx, id)
	if database.IsNoRows(err) {
		return Settlement{}, errNotFound
	}
	if err != nil {
		return Settlement{}, fmt.Errorf("lecture du relevé : %w", err)
	}
	out, err := s.toSettlement(ctx, row)
	if err != nil {
		return Settlement{}, err
	}
	lines, err := q.ListLines(ctx, id)
	if err != nil {
		return Settlement{}, fmt.Errorf("lignes du relevé : %w", err)
	}
	out.Lines = make([]Line, len(lines))
	for i, l := range lines {
		out.Lines[i] = Line{
			OrderID: l.OrderID, Reference: orders.Reference(l.OrderNumber), CompletedAt: l.CompletedAt,
			SubtotalXOF: l.SubtotalXof, CommissionXOF: l.CommissionXof, NetXOF: l.SubtotalXof - l.CommissionXof,
		}
	}
	return out, nil
}

// List liste les relevés (filtrés par boutique et statut).
func (s *Service) List(ctx context.Context, shopID *uuid.UUID, status string, limit, offset int32) ([]Settlement, error) {
	var st *string
	if status != "" {
		st = &status
	}
	rows, err := store.New(s.db.Conn(ctx)).ListSettlements(ctx, store.ListSettlementsParams{ShopID: shopID, Status: st, Lim: limit, Off: offset})
	if err != nil {
		return nil, fmt.Errorf("liste des relevés : %w", err)
	}
	out := make([]Settlement, len(rows))
	for i, r := range rows {
		if out[i], err = s.toSettlement(ctx, r); err != nil {
			return nil, err
		}
	}
	return out, nil
}

// requireOwner vérifie que le marchand possède la boutique (même suspendue : il garde l'accès à ses relevés).
func (s *Service) requireOwner(ctx context.Context, sellerID, shopID uuid.UUID) error {
	shop, err := s.shops.Get(ctx, shopID)
	if err != nil {
		return err
	}
	if shop.OwnerID != sellerID {
		return apperr.NotFound("shop_not_found", "Boutique introuvable.")
	}
	return nil
}

// ListForSeller retourne les relevés d'une boutique du marchand.
func (s *Service) ListForSeller(ctx context.Context, sellerID, shopID uuid.UUID, limit, offset int32) ([]Settlement, error) {
	if err := s.requireOwner(ctx, sellerID, shopID); err != nil {
		return nil, err
	}
	return s.List(ctx, &shopID, "", limit, offset)
}

// GetForSeller retourne un relevé d'une boutique du marchand.
func (s *Service) GetForSeller(ctx context.Context, sellerID, id uuid.UUID) (Settlement, error) {
	out, err := s.Get(ctx, id)
	if err != nil {
		return Settlement{}, err
	}
	if err := s.requireOwner(ctx, sellerID, out.ShopID); err != nil {
		return Settlement{}, errNotFound
	}
	return out, nil
}

func (s *Service) toSettlement(ctx context.Context, r store.Settlement) (Settlement, error) {
	shop, err := s.shops.Get(ctx, r.ShopID)
	if err != nil {
		return Settlement{}, err
	}
	return Settlement{
		ID: r.ID, ShopID: r.ShopID, ShopName: shop.Name,
		PeriodStart: r.PeriodStart.Format(time.DateOnly), PeriodEnd: r.PeriodEnd.Format(time.DateOnly),
		OrdersCount: r.OrdersCount, GrossXOF: r.GrossXof, CommissionXOF: r.CommissionXof, NetXOF: r.NetXof,
		Status: r.Status, SettledAt: r.SettledAt, SettlementReference: r.SettlementReference, Note: r.Note, CreatedAt: r.CreatedAt,
	}, nil
}
