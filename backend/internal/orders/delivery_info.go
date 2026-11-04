package orders

import (
	"context"
	"fmt"
	"time"

	"github.com/google/uuid"

	"ivia/backend/internal/orders/store"
	"ivia/backend/internal/platform/apperr"
)

// DeliveryOrder est ce que le module delivery connaît d'une commande à livrer.
type DeliveryOrder struct {
	ID             uuid.UUID
	Reference      string
	Status         Status
	ShopID         uuid.UUID
	BuyerID        uuid.UUID
	VehicleType    Vehicle
	ParcelSize     string
	DeliveryFeeXOF int64
	Address        DeliveryAddress
	ItemsCount     int32
	ReadyAt        *time.Time
}

// ForDelivery retourne une commande en livraison (erreur si elle n'est pas en mode livraison).
func (s *Service) ForDelivery(ctx context.Context, orderID uuid.UUID) (DeliveryOrder, error) {
	o, err := s.get(ctx, orderID)
	if err != nil {
		return DeliveryOrder{}, err
	}
	if o.Fulfillment != FulfillmentDelivery || o.VehicleType == nil || o.DeliveryAddress == nil {
		return DeliveryOrder{}, apperr.Conflict("not_a_delivery", "Cette commande n'est pas à livrer.")
	}
	var n int32
	for _, it := range o.Items {
		n += it.Quantity
	}
	return DeliveryOrder{
		ID: o.ID, Reference: o.Reference, Status: o.Status, ShopID: o.ShopID, BuyerID: o.BuyerID,
		VehicleType: *o.VehicleType, ParcelSize: o.ParcelSize, DeliveryFeeXOF: o.DeliveryFeeXOF,
		Address: *o.DeliveryAddress, ItemsCount: n, ReadyAt: o.ReadyAt,
	}, nil
}

// IsBuyerOf indique si l'utilisateur est l'acheteur de la commande.
func (s *Service) IsBuyerOf(ctx context.Context, userID, orderID uuid.UUID) (bool, error) {
	o, err := s.get(ctx, orderID)
	if err != nil {
		return false, err
	}
	return o.BuyerID == userID, nil
}

// ShopOf retourne la boutique d'une commande.
func (s *Service) ShopOf(ctx context.Context, orderID uuid.UUID) (uuid.UUID, error) {
	o, err := s.get(ctx, orderID)
	if err != nil {
		return uuid.Nil, err
	}
	return o.ShopID, nil
}

// SettleableOrder est une commande remise, prise en compte dans un relevé marchand.
type SettleableOrder struct {
	ID            uuid.UUID
	Number        int64
	CompletedAt   time.Time
	SubtotalXOF   int64
	CommissionXOF int64
}

// CompletedForShop liste les commandes remises d'une boutique sur [from, to).
func (s *Service) CompletedForShop(ctx context.Context, shopID uuid.UUID, from, to time.Time) ([]SettleableOrder, error) {
	rows, err := store.New(s.db.Conn(ctx)).CompletedForShop(ctx, store.CompletedForShopParams{ShopID: shopID, FromTime: from, ToTime: to})
	if err != nil {
		return nil, fmt.Errorf("commandes remises : %w", err)
	}
	out := make([]SettleableOrder, len(rows))
	for i, r := range rows {
		out[i] = SettleableOrder{ID: r.ID, Number: r.Number, CompletedAt: *r.CompletedAt, SubtotalXOF: r.SubtotalXof, CommissionXOF: r.CommissionXof}
	}
	return out, nil
}

// CheckAccountDeletable refuse la suppression d'un compte qui a une commande en cours, comme
// acheteur ou comme marchand (users.DeletionGuard).
func (s *Service) CheckAccountDeletable(ctx context.Context, userID uuid.UUID) error {
	q := store.New(s.db.Conn(ctx))
	n, err := q.CountActiveBuyerOrders(ctx, userID)
	if err != nil {
		return fmt.Errorf("commandes en cours : %w", err)
	}
	if n > 0 {
		return apperr.Conflict("active_orders", "Vous avez une commande en cours ou un remboursement en attente : la suppression sera possible une fois terminés.")
	}
	shopIDs, err := s.shops.OwnedShopIDs(ctx, userID)
	if err != nil {
		return err
	}
	if len(shopIDs) > 0 {
		n, err := q.CountActiveShopOrders(ctx, shopIDs)
		if err != nil {
			return fmt.Errorf("commandes en cours : %w", err)
		}
		if n > 0 {
			return apperr.Conflict("active_shop_orders", "Vos boutiques ont des commandes en cours : terminez-les avant de supprimer votre compte.")
		}
	}
	return nil
}

// OnAccountDeleted efface l'adresse de livraison copiée dans les commandes de l'acheteur ; montants
// et historique sont conservés (users.DeletionHook). Les commandes en cours ont été refusées avant.
func (s *Service) OnAccountDeleted(ctx context.Context, userID uuid.UUID) error {
	if err := store.New(s.db.Conn(ctx)).EraseBuyerPersonalData(ctx, userID); err != nil {
		return fmt.Errorf("effacement des adresses de livraison : %w", err)
	}
	return nil
}

// Metrics regroupe les indicateurs des commandes sur une période.
type Metrics struct {
	PaidOrders                int64      `json:"paid_orders"`
	CompletedOrders           int64      `json:"completed_orders"`
	CancelledAfterPayment     int64      `json:"cancelled_after_payment"`
	ExpiredOrders             int64      `json:"expired_orders"`
	CancellationRatePct       float64    `json:"cancellation_rate_pct"`
	GMVXOF                    int64      `json:"gmv_xof"`
	CommissionXOF             int64      `json:"commission_xof"`
	MedianReadyToDeliveredMin float64    `json:"median_ready_to_delivered_minutes"`
	PaidPerDay                []DayCount `json:"paid_per_day"`
}

// DayCount est un nombre par jour (fuseau de Lomé).
type DayCount struct {
	Day   string `json:"day"`
	Count int64  `json:"count"`
}

// MetricsBetween calcule les indicateurs des commandes créées sur [from, to).
func (s *Service) MetricsBetween(ctx context.Context, from, to time.Time) (Metrics, error) {
	q := store.New(s.db.Conn(ctx))
	m, err := q.Metrics(ctx, store.MetricsParams{FromTime: from, ToTime: to})
	if err != nil {
		return Metrics{}, fmt.Errorf("indicateurs des commandes : %w", err)
	}
	days, err := q.PaidOrdersPerDay(ctx, store.PaidOrdersPerDayParams{FromTime: from, ToTime: to})
	if err != nil {
		return Metrics{}, fmt.Errorf("commandes par jour : %w", err)
	}
	out := Metrics{
		PaidOrders: m.PaidOrders, CompletedOrders: m.CompletedOrders, CancelledAfterPayment: m.CancelledAfterPayment,
		ExpiredOrders: m.ExpiredOrders, GMVXOF: m.GmvXof, CommissionXOF: m.CommissionXof,
		MedianReadyToDeliveredMin: m.MedianReadyToDeliveredS / 60, PaidPerDay: make([]DayCount, len(days)),
	}
	if m.PaidOrders > 0 {
		out.CancellationRatePct = float64(m.CancelledAfterPayment) * 100 / float64(m.PaidOrders)
	}
	for i, d := range days {
		out.PaidPerDay[i] = DayCount{Day: d.Day.Format(time.DateOnly), Count: d.Orders}
	}
	return out, nil
}

// ProductSale : ventes payées d'un produit sur une période.
type ProductSale struct {
	Orders     int64 `json:"orders"`
	Units      int64 `json:"units"`
	RevenueXOF int64 `json:"revenue_xof"`
}

// ProductSales retourne les ventes payées des produits sur [from, to), par produit.
func (s *Service) ProductSales(ctx context.Context, productIDs []uuid.UUID, from, to time.Time) (map[uuid.UUID]ProductSale, error) {
	out := map[uuid.UUID]ProductSale{}
	if len(productIDs) == 0 {
		return out, nil
	}
	rows, err := store.New(s.db.Conn(ctx)).ProductSales(ctx, store.ProductSalesParams{ProductIds: productIDs, FromTime: from, ToTime: to})
	if err != nil {
		return nil, fmt.Errorf("ventes des produits : %w", err)
	}
	for _, r := range rows {
		out[r.ProductID] = ProductSale{Orders: r.Orders, Units: r.Units, RevenueXOF: r.RevenueXof}
	}
	return out, nil
}
