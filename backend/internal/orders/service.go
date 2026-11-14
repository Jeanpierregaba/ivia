// Package orders gère les commandes et leur machine à états.
//
// Toute transition de statut passe par Service.apply : elle vérifie la machine à états, écrit
// l'historique (order_status_events) et crée les notifications et tâches qui en découlent, dans
// une seule transaction (règle 5 d'AGENTS.md).
package orders

import (
	"context"
	"crypto/rand"
	"fmt"
	"log/slog"
	"math/big"
	"time"

	"github.com/google/uuid"

	"ivia/backend/internal/admin"
	"ivia/backend/internal/cart"
	"ivia/backend/internal/catalog"
	"ivia/backend/internal/coupons"
	"ivia/backend/internal/geo"
	"ivia/backend/internal/notifications"
	"ivia/backend/internal/orders/store"
	"ivia/backend/internal/platform/apperr"
	"ivia/backend/internal/platform/database"
	"ivia/backend/internal/platform/jobs"
	"ivia/backend/internal/platform/ratelimit"
	"ivia/backend/internal/shops"
	"ivia/backend/internal/stock"
	"ivia/backend/internal/users"
)

// Fulfillment est le mode de remise.
type Fulfillment string

const (
	FulfillmentPickup   Fulfillment = "pickup"
	FulfillmentDelivery Fulfillment = "delivery"
)

// MaxHandoverAttempts : au-delà, le code de remise est bloqué jusqu'à l'intervention d'un admin.
const MaxHandoverAttempts = 5

// Item est une ligne de commande (copie du produit au moment de l'achat).
type Item struct {
	ProductID    uuid.UUID `json:"product_id"`
	ProductName  string    `json:"product_name"`
	UnitPriceXOF int64     `json:"unit_price_xof"`
	Quantity     int32     `json:"quantity"`
	LineTotalXOF int64     `json:"line_total_xof"`
	ParcelSize   string    `json:"parcel_size"`
	StockMode    string    `json:"stock_mode"`
}

// Event est une ligne de l'historique des statuts.
type Event struct {
	FromStatus *Status    `json:"from_status"`
	ToStatus   Status     `json:"to_status"`
	ActorType  ActorType  `json:"actor_type"`
	ActorID    *uuid.UUID `json:"-"`
	Reason     string     `json:"reason"`
	CreatedAt  time.Time  `json:"created_at"`
}

// DeliveryAddress est la copie de l'adresse de livraison faite à la commande.
type DeliveryAddress struct {
	AddressText  string    `json:"address_text"`
	Neighborhood string    `json:"neighborhood"`
	Instructions string    `json:"instructions"`
	Location     geo.Point `json:"location"`
}

// Order est une commande. Les champs `json:"-"` ne sont exposés que par les vues qui y ont droit.
type Order struct {
	ID                uuid.UUID        `json:"id"`
	Number            int64            `json:"number"`
	Reference         string           `json:"reference"`
	Status            Status           `json:"status"`
	Fulfillment       Fulfillment      `json:"fulfillment"`
	VehicleType       *Vehicle         `json:"vehicle_type"`
	ParcelSize        string           `json:"parcel_size"`
	SubtotalXOF       int64            `json:"subtotal_xof"`
	DeliveryFeeXOF    int64            `json:"delivery_fee_xof"`
	TotalXOF          int64            `json:"total_xof"`
	PromoCode         *string          `json:"promo_code"`
	DiscountXOF       int64            `json:"discount_xof"`
	DeliveryAddress   *DeliveryAddress `json:"delivery_address"`
	CancelReason      string           `json:"cancel_reason"`
	PaymentDeadlineAt time.Time        `json:"payment_deadline_at"`
	SellerDeadlineAt  *time.Time       `json:"seller_deadline_at"`
	PaidAt            *time.Time       `json:"paid_at"`
	AcceptedAt        *time.Time       `json:"accepted_at"`
	ReadyAt           *time.Time       `json:"ready_at"`
	PickedUpAt        *time.Time       `json:"picked_up_at"`
	CompletedAt       *time.Time       `json:"completed_at"`
	CancelledAt       *time.Time       `json:"cancelled_at"`
	RefundedAt        *time.Time       `json:"refunded_at"`
	CreatedAt         time.Time        `json:"created_at"`
	UpdatedAt         time.Time        `json:"updated_at"`
	Items             []Item           `json:"items"`
	Events            []Event          `json:"events"`

	BuyerID           uuid.UUID `json:"-"`
	ShopID            uuid.UUID `json:"-"`
	CommissionRateBP  int32     `json:"-"`
	CommissionXOF     int64     `json:"-"`
	RefundDueXOF      int64     `json:"-"`
	HandoverCode      string    `json:"-"`
	HandoverAttempts  int32     `json:"-"`
	StockReleased     bool      `json:"-"`
	DeliveryDistanceM *int32    `json:"-"`
	DiscountFundedBy  *string   `json:"-"`
}

// BuyerOrder est la vue de l'acheteur : son code de remise et la boutique (pour un retrait).
type BuyerOrder struct {
	Order
	HandoverCode *string          `json:"handover_code"`
	Shop         shops.PublicShop `json:"shop"`
}

// SellerOrder est la vue du marchand : jamais le numéro ni l'adresse de l'acheteur.
type SellerOrder struct {
	Order
	ShopID           uuid.UUID `json:"shop_id"`
	BuyerFirstName   string    `json:"buyer_first_name"`
	CommissionXOF    int64     `json:"commission_xof"`
	NetXOF           int64     `json:"net_xof"`
	HandoverAttempts int32     `json:"handover_attempts"`
}

// AdminOrder est la vue complète du back-office.
type AdminOrder struct {
	Order
	BuyerID           uuid.UUID `json:"buyer_id"`
	ShopID            uuid.UUID `json:"shop_id"`
	CommissionRateBP  int32     `json:"commission_rate_bp"`
	CommissionXOF     int64     `json:"commission_xof"`
	RefundDueXOF      int64     `json:"refund_due_xof"`
	HandoverAttempts  int32     `json:"handover_attempts"`
	DeliveryDistanceM *int32    `json:"delivery_distance_m"`
}

// Service gère les commandes.
type Service struct {
	db      *database.DB
	jobs    jobs.Enqueuer
	admin   *admin.Service
	users   *users.Service
	geo     *geo.Service
	shops   *shops.Service
	catalog *catalog.Service
	stock   *stock.Service
	cart    *cart.Service
	notify  *notifications.Service
	logger  *slog.Logger
	limiter *ratelimit.Limiter
	coupons *coupons.Service
}

// Deps regroupe les dépendances du service.
type Deps struct {
	DB      *database.DB
	Jobs    jobs.Enqueuer
	Admin   *admin.Service
	Users   *users.Service
	Geo     *geo.Service
	Shops   *shops.Service
	Catalog *catalog.Service
	Stock   *stock.Service
	Cart    *cart.Service
	Notify  *notifications.Service
	Logger  *slog.Logger
	Coupons *coupons.Service
}

// NewService crée le service.
func NewService(d Deps) *Service {
	return &Service{
		db: d.DB, jobs: d.Jobs, admin: d.Admin, users: d.Users, geo: d.Geo, shops: d.Shops,
		catalog: d.Catalog, stock: d.Stock, cart: d.Cart, notify: d.Notify, logger: d.Logger, coupons: d.Coupons,
		// Création de commande : 20 par heure et par acheteur.
		limiter: ratelimit.New(20, time.Hour),
	}
}

var errNotFound = apperr.NotFound("order_not_found", "Commande introuvable.")

// Reference formate le numéro lisible d'une commande.
func Reference(number int64) string { return fmt.Sprintf("IV-%06d", number) }

// get charge une commande avec ses lignes et son historique.
func (s *Service) get(ctx context.Context, id uuid.UUID) (Order, error) {
	q := store.New(s.db.Conn(ctx))
	r, err := q.GetOrder(ctx, id)
	if database.IsNoRows(err) {
		return Order{}, errNotFound
	}
	if err != nil {
		return Order{}, fmt.Errorf("lecture de la commande : %w", err)
	}
	items, err := q.ListItems(ctx, id)
	if err != nil {
		return Order{}, fmt.Errorf("lecture des lignes : %w", err)
	}
	events, err := q.ListEvents(ctx, id)
	if err != nil {
		return Order{}, fmt.Errorf("lecture de l'historique : %w", err)
	}
	return buildOrder(r, items, events), nil
}

// buildOrder assemble une commande à partir de ses lignes et de son historique.
func buildOrder(r store.GetOrderRow, items []store.OrderItem, events []store.OrderStatusEvent) Order {
	o := Order{
		ID: r.ID, Number: r.Number, Reference: Reference(r.Number), Status: Status(r.Status),
		Fulfillment: Fulfillment(r.Fulfillment), ParcelSize: r.ParcelSize,
		SubtotalXOF: r.SubtotalXof, DeliveryFeeXOF: r.DeliveryFeeXof, TotalXOF: r.TotalXof,
		CancelReason: r.CancelReason, PaymentDeadlineAt: r.PaymentDeadlineAt, SellerDeadlineAt: r.SellerDeadlineAt,
		PaidAt: r.PaidAt, AcceptedAt: r.AcceptedAt, ReadyAt: r.ReadyAt, PickedUpAt: r.PickedUpAt,
		CompletedAt: r.CompletedAt, CancelledAt: r.CancelledAt, RefundedAt: r.RefundedAt,
		CreatedAt: r.CreatedAt, UpdatedAt: r.UpdatedAt,
		BuyerID: r.BuyerID, ShopID: r.ShopID, CommissionRateBP: r.CommissionRateBp, CommissionXOF: r.CommissionXof,
		RefundDueXOF: r.RefundDueXof, HandoverCode: r.HandoverCode, HandoverAttempts: r.HandoverAttempts,
		StockReleased: r.StockReleased, DeliveryDistanceM: r.DeliveryDistanceM,
		PromoCode: r.PromoCode, DiscountXOF: r.DiscountXof, DiscountFundedBy: r.DiscountFundedBy,
	}
	if r.VehicleType != nil {
		v := Vehicle(*r.VehicleType)
		o.VehicleType = &v
	}
	if r.HasDeliveryLocation {
		o.DeliveryAddress = &DeliveryAddress{
			AddressText: deref(r.DeliveryAddressText), Neighborhood: deref(r.DeliveryNeighborhood),
			Instructions: deref(r.DeliveryInstructions), Location: geo.Point{Lat: r.DeliveryLat, Lng: r.DeliveryLng},
		}
	}
	o.Items = make([]Item, len(items))
	for i, it := range items {
		o.Items[i] = Item{
			ProductID: it.ProductID, ProductName: it.ProductName, UnitPriceXOF: it.UnitPriceXof,
			Quantity: it.Quantity, LineTotalXOF: it.LineTotalXof, ParcelSize: it.ParcelSize, StockMode: it.StockMode,
		}
	}
	o.Events = make([]Event, len(events))
	for i, e := range events {
		var from *Status
		if e.FromStatus != nil {
			f := Status(*e.FromStatus)
			from = &f
		}
		o.Events[i] = Event{FromStatus: from, ToStatus: Status(e.ToStatus), ActorType: ActorType(e.ActorType), ActorID: e.ActorID, Reason: e.Reason, CreatedAt: e.CreatedAt}
	}
	return o
}

// loadOrders charge plusieurs commandes en trois requêtes, dans l'ordre de ids.
func (s *Service) loadOrders(ctx context.Context, ids []uuid.UUID) ([]Order, error) {
	q := store.New(s.db.Conn(ctx))
	rows, err := q.GetOrdersByIDs(ctx, ids)
	if err != nil {
		return nil, fmt.Errorf("lecture des commandes : %w", err)
	}
	allItems, err := q.ListItemsForOrders(ctx, ids)
	if err != nil {
		return nil, fmt.Errorf("lecture des lignes : %w", err)
	}
	allEvents, err := q.ListEventsForOrders(ctx, ids)
	if err != nil {
		return nil, fmt.Errorf("lecture de l'historique : %w", err)
	}
	items := make(map[uuid.UUID][]store.OrderItem, len(ids))
	for _, it := range allItems {
		items[it.OrderID] = append(items[it.OrderID], it)
	}
	events := make(map[uuid.UUID][]store.OrderStatusEvent, len(ids))
	for _, e := range allEvents {
		events[e.OrderID] = append(events[e.OrderID], e)
	}
	byID := make(map[uuid.UUID]Order, len(rows))
	for _, r := range rows {
		byID[r.ID] = buildOrder(store.GetOrderRow(r), items[r.ID], events[r.ID])
	}
	out := make([]Order, 0, len(ids))
	for _, id := range ids {
		if o, ok := byID[id]; ok {
			out = append(out, o)
		}
	}
	return out, nil
}

// merchantGross : montant des produits pour le marchand, moins la réduction d'un code de boutique.
func (o Order) merchantGross() int64 {
	if o.DiscountFundedBy != nil && *o.DiscountFundedBy == coupons.FundedByShop {
		return o.SubtotalXOF - o.DiscountXOF
	}
	return o.SubtotalXOF
}

// trackedLines retourne les lignes à stock suivi (réservation et libération).
func (o Order) trackedLines() []stock.Line {
	var out []stock.Line
	for _, it := range o.Items {
		if it.StockMode == string(catalog.StockTracked) {
			out = append(out, stock.Line{ProductID: it.ProductID, Quantity: it.Quantity})
		}
	}
	return out
}

// --- Vues -----------------------------------------------------------------------------------

func (s *Service) buyerView(ctx context.Context, o Order) (BuyerOrder, error) {
	shop, err := s.shops.Get(ctx, o.ShopID)
	if err != nil {
		return BuyerOrder{}, err
	}
	v := BuyerOrder{Order: o, Shop: shop.Public()}
	if o.Status.ShowsHandoverCode() {
		code := o.HandoverCode
		v.HandoverCode = &code
	}
	return v, nil
}

func (s *Service) sellerView(ctx context.Context, o Order) (SellerOrder, error) {
	contact, err := s.users.Contact(ctx, o.BuyerID)
	if err != nil {
		return SellerOrder{}, err
	}
	return sellerOrder(o, contact.FirstName), nil
}

// sellerOrder construit la vue du marchand : jamais l'adresse de l'acheteur.
func sellerOrder(o Order, buyerFirstName string) SellerOrder {
	o.DeliveryAddress = nil
	return SellerOrder{
		Order: o, ShopID: o.ShopID, BuyerFirstName: buyerFirstName,
		CommissionXOF: o.CommissionXOF, NetXOF: o.merchantGross() - o.CommissionXOF, HandoverAttempts: o.HandoverAttempts,
	}
}

func adminView(o Order) AdminOrder {
	return AdminOrder{
		Order: o, BuyerID: o.BuyerID, ShopID: o.ShopID, CommissionRateBP: o.CommissionRateBP,
		CommissionXOF: o.CommissionXOF, RefundDueXOF: o.RefundDueXOF, HandoverAttempts: o.HandoverAttempts,
		DeliveryDistanceM: o.DeliveryDistanceM,
	}
}

// GetForBuyer retourne une commande de l'acheteur (celle d'un autre est introuvable).
func (s *Service) GetForBuyer(ctx context.Context, buyerID, id uuid.UUID) (BuyerOrder, error) {
	o, err := s.get(ctx, id)
	if err != nil {
		return BuyerOrder{}, err
	}
	if o.BuyerID != buyerID {
		return BuyerOrder{}, errNotFound
	}
	return s.buyerView(ctx, o)
}

// ListForBuyer retourne les commandes de l'acheteur, les plus récentes d'abord.
func (s *Service) ListForBuyer(ctx context.Context, buyerID uuid.UUID, group string, limit, offset int32) ([]BuyerOrder, error) {
	ids, err := store.New(s.db.Conn(ctx)).ListBuyerOrders(ctx, store.ListBuyerOrdersParams{
		BuyerID: buyerID, Statuses: groupStatuses(BuyerGroups, group), Lim: limit, Off: offset,
	})
	if err != nil {
		return nil, fmt.Errorf("liste des commandes : %w", err)
	}
	out := make([]BuyerOrder, 0, len(ids))
	for _, id := range ids {
		o, err := s.get(ctx, id)
		if err != nil {
			return nil, err
		}
		v, err := s.buyerView(ctx, o)
		if err != nil {
			return nil, err
		}
		out = append(out, v)
	}
	return out, nil
}

// requireSellerOrder retourne une commande d'une boutique du marchand (boutique non suspendue).
func (s *Service) requireSellerOrder(ctx context.Context, sellerID, id uuid.UUID) (Order, error) {
	o, err := s.get(ctx, id)
	if err != nil {
		return Order{}, err
	}
	if _, err := s.shops.RequireOwned(ctx, sellerID, o.ShopID); err != nil {
		if apperr.IsCode(err, "shop_not_found") {
			return Order{}, errNotFound
		}
		return Order{}, err
	}
	// Une commande jamais payée (en attente, expirée ou abandonnée) n'existe pas pour le marchand.
	if o.PaidAt == nil {
		return Order{}, errNotFound
	}
	return o, nil
}

// GetForSeller retourne une commande d'une boutique du marchand.
func (s *Service) GetForSeller(ctx context.Context, sellerID, id uuid.UUID) (SellerOrder, error) {
	o, err := s.requireSellerOrder(ctx, sellerID, id)
	if err != nil {
		return SellerOrder{}, err
	}
	return s.sellerView(ctx, o)
}

// ListForSeller retourne les commandes payées des boutiques du marchand (ou d'une seule).
func (s *Service) ListForSeller(ctx context.Context, sellerID uuid.UUID, shopID *uuid.UUID, status Status, group string, limit, offset int32) ([]SellerOrder, error) {
	var shopIDs []uuid.UUID
	if shopID != nil {
		if _, err := s.shops.RequireOwned(ctx, sellerID, *shopID); err != nil {
			return nil, err
		}
		shopIDs = []uuid.UUID{*shopID}
	} else {
		var err error
		if shopIDs, err = s.shops.OwnedShopIDs(ctx, sellerID); err != nil {
			return nil, err
		}
	}
	var st *string
	if status != "" {
		v := string(status)
		st = &v
	}
	ids, err := store.New(s.db.Conn(ctx)).ListShopOrders(ctx, store.ListShopOrdersParams{ShopIds: shopIDs, Status: st, Statuses: groupStatuses(SellerGroups, group), Lim: limit, Off: offset})
	if err != nil {
		return nil, fmt.Errorf("liste des commandes : %w", err)
	}
	orders, err := s.loadOrders(ctx, ids)
	if err != nil {
		return nil, err
	}
	buyerIDs := make([]uuid.UUID, len(orders))
	for i, o := range orders {
		buyerIDs[i] = o.BuyerID
	}
	names, err := s.users.FirstNames(ctx, buyerIDs)
	if err != nil {
		return nil, err
	}
	out := make([]SellerOrder, len(orders))
	for i, o := range orders {
		out[i] = sellerOrder(o, names[o.BuyerID])
	}
	return out, nil
}

// AdminFilter filtre la supervision des commandes.
type AdminFilter struct {
	Status  Status
	ShopID  *uuid.UUID
	BuyerID *uuid.UUID
	Number  *int64
}

// AdminList liste les commandes pour le back-office.
func (s *Service) AdminList(ctx context.Context, f AdminFilter, limit, offset int32) ([]AdminOrder, error) {
	var st *string
	if f.Status != "" {
		v := string(f.Status)
		st = &v
	}
	ids, err := store.New(s.db.Conn(ctx)).AdminListOrders(ctx, store.AdminListOrdersParams{
		Status: st, ShopID: f.ShopID, BuyerID: f.BuyerID, Number: f.Number, Lim: limit, Off: offset,
	})
	if err != nil {
		return nil, fmt.Errorf("liste des commandes : %w", err)
	}
	return s.adminViews(ctx, ids)
}

// AdminGet retourne une commande pour le back-office.
func (s *Service) AdminGet(ctx context.Context, id uuid.UUID) (AdminOrder, error) {
	o, err := s.get(ctx, id)
	if err != nil {
		return AdminOrder{}, err
	}
	return adminView(o), nil
}

// RefundQueue liste les commandes annulées après paiement ou revenues en boutique, pas encore remboursées.
func (s *Service) RefundQueue(ctx context.Context, limit, offset int32) ([]AdminOrder, error) {
	ids, err := store.New(s.db.Conn(ctx)).RefundQueue(ctx, store.RefundQueueParams{Lim: limit, Off: offset})
	if err != nil {
		return nil, fmt.Errorf("file de remboursement : %w", err)
	}
	return s.adminViews(ctx, ids)
}

func (s *Service) adminViews(ctx context.Context, ids []uuid.UUID) ([]AdminOrder, error) {
	out := make([]AdminOrder, 0, len(ids))
	for _, id := range ids {
		o, err := s.get(ctx, id)
		if err != nil {
			return nil, err
		}
		out = append(out, adminView(o))
	}
	return out, nil
}

func randomHandoverCode() (string, error) {
	v, err := rand.Int(rand.Reader, big.NewInt(10000))
	if err != nil {
		return "", fmt.Errorf("tirage du code de remise : %w", err)
	}
	return fmt.Sprintf("%04d", v), nil
}

func deref(s *string) string {
	if s == nil {
		return ""
	}
	return *s
}
