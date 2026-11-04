package orders

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"

	"ivia/backend/internal/admin"
	"ivia/backend/internal/catalog"
	"ivia/backend/internal/orders/store"
	"ivia/backend/internal/platform/apperr"
	"ivia/backend/internal/platform/database"
	"ivia/backend/internal/shops"
	"ivia/backend/internal/stock"
	"ivia/backend/internal/users"
)

// CheckoutInput décrit la commande à créer à partir du panier.
type CheckoutInput struct {
	Fulfillment Fulfillment `json:"fulfillment"`
	AddressID   *uuid.UUID  `json:"address_id"`
	// VehicleType : facultatif, le moins cher des véhicules compatibles par défaut.
	VehicleType *Vehicle `json:"vehicle_type"`
	// ClientRequestID rend la création idempotente : une requête rejouée renvoie la même commande.
	ClientRequestID *uuid.UUID `json:"client_request_id"`
}

// VehicleQuote est le prix de livraison d'un véhicule.
type VehicleQuote struct {
	VehicleType    Vehicle `json:"vehicle_type"`
	DeliveryFeeXOF int64   `json:"delivery_fee_xof"`
}

// Quote est le récapitulatif affiché avant paiement.
type Quote struct {
	ShopID             uuid.UUID          `json:"shop_id"`
	Fulfillment        Fulfillment        `json:"fulfillment"`
	Items              []Item             `json:"items"`
	SubtotalXOF        int64              `json:"subtotal_xof"`
	ParcelSize         catalog.ParcelSize `json:"parcel_size"`
	VehicleOptions     []VehicleQuote     `json:"vehicle_options"`
	VehicleType        *Vehicle           `json:"vehicle_type"`
	DeliveryDistanceM  *int64             `json:"delivery_distance_m"`
	DeliveryFeeXOF     int64              `json:"delivery_fee_xof"`
	TotalXOF           int64              `json:"total_xof"`
	PaymentTimeoutMins int32              `json:"payment_timeout_minutes"`

	commissionBP  int32
	commissionXOF int64
	address       *users.Address
	shop          shops.Shop
	settings      admin.Settings
}

// Quote calcule le récapitulatif de la commande sans rien enregistrer.
func (s *Service) Quote(ctx context.Context, buyerID uuid.UUID, in CheckoutInput) (Quote, error) {
	shopID, lines, err := s.cart.Lines(ctx, buyerID)
	if err != nil {
		return Quote{}, err
	}
	if len(lines) == 0 {
		return Quote{}, apperr.Conflict("cart_empty", "Votre panier est vide.")
	}
	if in.Fulfillment != FulfillmentPickup && in.Fulfillment != FulfillmentDelivery {
		return Quote{}, apperr.Validation(map[string]string{"fulfillment": "Mode attendu : pickup ou delivery."})
	}
	shop, err := s.shops.RequirePublished(ctx, shopID)
	if err != nil {
		if apperr.IsCode(err, "shop_not_found") {
			return Quote{}, apperr.Conflict("shop_unavailable", "Cette boutique n'est plus disponible.")
		}
		return Quote{}, err
	}
	if !shop.AcceptingOrders {
		return Quote{}, apperr.Conflict("shop_closed", "Cette boutique ne prend pas de commande pour le moment.")
	}
	ids := make([]uuid.UUID, len(lines))
	for i, l := range lines {
		ids[i] = l.ProductID
	}
	products, err := s.catalog.ProductsByIDs(ctx, ids)
	if err != nil {
		return Quote{}, err
	}
	settings, err := s.admin.Settings(ctx)
	if err != nil {
		return Quote{}, err
	}

	q := Quote{ShopID: shopID, Fulfillment: in.Fulfillment, shop: shop, settings: settings, PaymentTimeoutMins: settings.PaymentTimeoutMinutes}
	q.ParcelSize = catalog.ParcelSmall
	for _, l := range lines {
		p, ok := products[l.ProductID]
		if !ok || !p.IsActive || p.ShopID != shopID {
			return Quote{}, apperr.Conflict("product_unavailable", "Un produit de votre panier n'est plus disponible.")
		}
		if p.StockQuantity != nil && *p.StockQuantity < l.Quantity {
			return Quote{}, apperr.Conflict("insufficient_stock", fmt.Sprintf("Stock insuffisant pour « %s ».", p.Name))
		}
		line := p.EffectivePriceXOF * int64(l.Quantity) // prix promotionnel pendant la promotion
		q.Items = append(q.Items, Item{
			ProductID: p.ID, ProductName: p.Name, UnitPriceXOF: p.EffectivePriceXOF, Quantity: l.Quantity,
			LineTotalXOF: line, ParcelSize: string(p.ParcelSize), StockMode: string(p.StockMode),
		})
		q.SubtotalXOF += line
		if p.ParcelSize.Rank() > q.ParcelSize.Rank() {
			q.ParcelSize = p.ParcelSize
		}
	}
	q.commissionBP = settings.CommissionRateBP
	q.commissionXOF = Commission(q.SubtotalXOF, settings.CommissionRateBP)
	q.TotalXOF = q.SubtotalXOF
	q.VehicleOptions = []VehicleQuote{}

	if in.Fulfillment == FulfillmentDelivery {
		if in.AddressID == nil {
			return Quote{}, apperr.Validation(map[string]string{"address_id": "Choisissez une adresse de livraison."})
		}
		addr, err := s.users.GetAddress(ctx, buyerID, *in.AddressID)
		if err != nil {
			if apperr.IsCode(err, "address_not_found") {
				return Quote{}, apperr.Validation(map[string]string{"address_id": "Adresse inconnue."})
			}
			return Quote{}, err
		}
		dist, err := s.geo.DistanceMeters(ctx, shop.Location, addr.Location)
		if err != nil {
			return Quote{}, err
		}
		if dist > MaxDeliveryDistanceM {
			return Quote{}, apperr.Conflict("delivery_too_far", "Cette adresse est trop éloignée de la boutique pour être livrée.")
		}
		compatible := CompatibleVehicles(q.ParcelSize)
		for _, v := range compatible {
			q.VehicleOptions = append(q.VehicleOptions, VehicleQuote{VehicleType: v, DeliveryFeeXOF: DeliveryFee(settings, v, dist)})
		}
		chosen := compatible[0]
		if in.VehicleType != nil {
			ok := false
			for _, v := range compatible {
				ok = ok || v == *in.VehicleType
			}
			if !ok {
				return Quote{}, apperr.Validation(map[string]string{"vehicle_type": "Ce véhicule ne peut pas transporter ce colis."})
			}
			chosen = *in.VehicleType
		}
		q.VehicleType = &chosen
		q.DeliveryDistanceM = &dist
		q.DeliveryFeeXOF = DeliveryFee(settings, chosen, dist)
		q.TotalXOF += q.DeliveryFeeXOF
		q.address = &addr
	}
	return q, nil
}

// Checkout crée la commande à partir du panier : copie des prix, réservation du stock suivi,
// vidage du panier et planification de l'expiration du paiement, dans une seule transaction.
func (s *Service) Checkout(ctx context.Context, buyerID uuid.UUID, in CheckoutInput) (BuyerOrder, error) {
	if in.ClientRequestID != nil {
		id, err := store.New(s.db.Conn(ctx)).GetOrderByClientRequest(ctx, store.GetOrderByClientRequestParams{BuyerID: buyerID, ClientRequestID: in.ClientRequestID})
		if err == nil {
			return s.GetForBuyer(ctx, buyerID, id)
		}
		if !database.IsNoRows(err) {
			return BuyerOrder{}, fmt.Errorf("lecture de la commande : %w", err)
		}
	}
	if ok, retry := s.limiter.Allow(buyerID.String()); !ok {
		return BuyerOrder{}, apperr.TooManyRequests("rate_limited", "Trop de commandes en peu de temps. Réessayez plus tard.", retry)
	}
	buyer, err := s.users.Get(ctx, buyerID)
	if err != nil {
		return BuyerOrder{}, err
	}
	if !buyer.ProfileComplete {
		return BuyerOrder{}, apperr.Conflict("profile_incomplete", "Complétez votre profil (prénom, téléphone, consentement) avant de commander.")
	}
	q, err := s.Quote(ctx, buyerID, in)
	if err != nil {
		return BuyerOrder{}, err
	}
	code, err := randomHandoverCode()
	if err != nil {
		return BuyerOrder{}, err
	}

	var orderID uuid.UUID
	err = s.db.InTx(ctx, func(ctx context.Context) error {
		deadline := time.Now().Add(q.settings.PaymentTimeout())
		p := store.CreateOrderParams{
			BuyerID: buyerID, ShopID: q.ShopID, Fulfillment: string(q.Fulfillment), ParcelSize: string(q.ParcelSize),
			SubtotalXof: q.SubtotalXOF, DeliveryFeeXof: q.DeliveryFeeXOF, TotalXof: q.TotalXOF,
			CommissionRateBp: q.commissionBP, CommissionXof: q.commissionXOF,
			HandoverCode: code, ClientRequestID: in.ClientRequestID, PaymentDeadlineAt: deadline,
		}
		if q.address != nil {
			v := string(*q.VehicleType)
			dist := int32(*q.DeliveryDistanceM)
			p.VehicleType = &v
			p.DeliveryDistanceM = &dist
			p.DeliveryAddressText = &q.address.AddressText
			p.DeliveryNeighborhood = &q.address.NeighborhoodName
			p.DeliveryInstructions = &q.address.Instructions
			p.DeliveryLat = &q.address.Location.Lat
			p.DeliveryLng = &q.address.Location.Lng
		}
		st := store.New(s.db.Conn(ctx))
		var err error
		orderID, err = st.CreateOrder(ctx, p)
		if database.IsUniqueViolation(err, "orders_buyer_id_client_request_id_key") {
			return apperr.Conflict("duplicate_request", "Cette commande est déjà en cours de création.")
		}
		if err != nil {
			return fmt.Errorf("création de la commande : %w", err)
		}
		var tracked []stock.Line
		for _, it := range q.Items {
			if err := st.InsertItem(ctx, store.InsertItemParams{
				OrderID: orderID, ProductID: it.ProductID, ProductName: it.ProductName, UnitPriceXof: it.UnitPriceXOF,
				Quantity: it.Quantity, LineTotalXof: it.LineTotalXOF, ParcelSize: it.ParcelSize, StockMode: it.StockMode,
			}); err != nil {
				return fmt.Errorf("ajout d'une ligne : %w", err)
			}
			if it.StockMode == string(catalog.StockTracked) {
				tracked = append(tracked, stock.Line{ProductID: it.ProductID, Quantity: it.Quantity})
			}
		}
		if err := s.stock.Reserve(ctx, orderID, tracked); err != nil {
			var insufficient *stock.InsufficientStockError
			if errors.As(err, &insufficient) {
				return apperr.Conflict("insufficient_stock", "Un produit de votre panier vient d'être épuisé.")
			}
			return err
		}
		buyerActor := buyerID
		if err := st.InsertEvent(ctx, store.InsertEventParams{
			OrderID: orderID, ToStatus: string(StatusPendingPayment), ActorType: string(ActorBuyer), ActorID: &buyerActor,
		}); err != nil {
			return fmt.Errorf("historique de la commande : %w", err)
		}
		if err := s.cart.Clear(ctx, buyerID); err != nil {
			return err
		}
		return s.jobs.Enqueue(ctx, ExpirePaymentArgs{OrderID: orderID}, atTime(deadline))
	})
	if err != nil {
		return BuyerOrder{}, err
	}
	return s.GetForBuyer(ctx, buyerID, orderID)
}
