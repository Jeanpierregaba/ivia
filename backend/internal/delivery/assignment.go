package delivery

import (
	"context"
	"fmt"
	"math"
	"time"

	"github.com/google/uuid"
	"github.com/riverqueue/river"

	"ivia/backend/internal/delivery/store"
	"ivia/backend/internal/geo"
	"ivia/backend/internal/notifications"
	"ivia/backend/internal/orders"
	"ivia/backend/internal/platform/apperr"
	"ivia/backend/internal/platform/database"
	"ivia/backend/internal/platform/jobs"
)

// Offer est une proposition de mission vue par le livreur.
type Offer struct {
	ID              uuid.UUID `json:"id"`
	OrderID         uuid.UUID `json:"order_id"`
	OrderReference  string    `json:"order_reference"`
	ShopName        string    `json:"shop_name"`
	ShopAddress     string    `json:"shop_address"`
	ShopNeighborood string    `json:"shop_neighborhood"`
	DeliveryArea    string    `json:"delivery_neighborhood"`
	DistanceToShopM int32     `json:"distance_to_shop_m"`
	ShopToClientM   int64     `json:"shop_to_client_m"`
	ParcelSize      string    `json:"parcel_size"`
	// EarningXOF est le gain indicatif (frais de livraison de la commande).
	EarningXOF int64     `json:"earning_xof"`
	ExpiresAt  time.Time `json:"expires_at"`
	// ShopLocation : position exacte de la boutique (lieu public).
	ShopLocation geo.Point `json:"shop_location"`
	// ClientArea : position du client arrondie à 2 décimales (environ 1 km), pour le tracé de la
	// proposition. L'adresse exacte n'est donnée qu'après acceptation, dans la mission.
	ClientArea geo.Point `json:"client_area"`
}

// roughArea arrondit une position à 2 décimales (environ 1 km).
func roughArea(p geo.Point) geo.Point {
	return geo.Point{Lat: math.Round(p.Lat*100) / 100, Lng: math.Round(p.Lng*100) / 100}
}

// assignOutcome est le résultat d'une tentative d'attribution.
type assignOutcome int

const (
	assignDone     assignOutcome = iota // proposition envoyée, mission en cours ou commande sortie de l'attente
	assignNoDriver                      // personne de disponible : réessayer plus tard
)

// StartAssignment ouvre la recherche d'un livreur pour une commande prête (StatusChangedArgs).
func (s *Service) StartAssignment(ctx context.Context, orderID uuid.UUID) error {
	return s.db.InTx(ctx, func(ctx context.Context) error {
		if _, err := store.New(s.db.Conn(ctx)).StartAssignment(ctx, orderID); err != nil {
			return fmt.Errorf("ouverture de l'attribution : %w", err)
		}
		return s.jobs.Enqueue(ctx, AssignArgs{OrderID: orderID}, nil)
	})
}

// assign propose la commande au livreur compatible le plus proche. Idempotente : la ligne
// assignment_requests est verrouillée et rien n'est fait s'il y a déjà une proposition ou une mission.
func (s *Service) assign(ctx context.Context, orderID uuid.UUID) (assignOutcome, error) {
	order, err := s.orders.ForDelivery(ctx, orderID)
	if err != nil {
		return assignDone, err
	}
	outcome := assignDone
	err = s.db.InTx(ctx, func(ctx context.Context) error {
		q := store.New(s.db.Conn(ctx))
		req, err := q.LockAssignment(ctx, orderID)
		if database.IsNoRows(err) {
			return nil
		}
		if err != nil {
			return fmt.Errorf("verrou de l'attribution : %w", err)
		}
		if req.ClosedAt != nil {
			return nil
		}
		if order.Status != orders.StatusAwaitingDriver {
			return q.CloseAssignment(ctx, orderID)
		}
		if _, err := q.PendingOfferForOrder(ctx, orderID); err == nil {
			return nil // une proposition attend sa réponse
		} else if !database.IsNoRows(err) {
			return fmt.Errorf("proposition en cours : %w", err)
		}
		if _, err := q.ActiveDeliveryForOrder(ctx, orderID); err == nil {
			return q.CloseAssignment(ctx, orderID)
		} else if !database.IsNoRows(err) {
			return fmt.Errorf("mission en cours : %w", err)
		}

		settings, err := s.admin.Settings(ctx)
		if err != nil {
			return err
		}
		if req.AlertedAt == nil && (req.OffersCount >= settings.AssignmentMaxOffers || time.Since(req.StartedAt) >= settings.AssignmentAlertAfter()) {
			if err := q.MarkAlerted(ctx, orderID); err != nil {
				return fmt.Errorf("alerte d'attribution : %w", err)
			}
			if err := s.notify.NotifyAdmins(ctx, "assignment_alert", "Aucun livreur pour "+order.Reference,
				fmt.Sprintf("%d livreur(s) sollicité(s) sans succès. Intervention nécessaire.", req.OffersCount),
				map[string]string{"order_id": orderID.String()}); err != nil {
				return err
			}
		}

		shop, err := s.shops.Get(ctx, order.ShopID)
		if err != nil {
			return err
		}
		driver, err := q.FindNearestDriver(ctx, store.FindNearestDriverParams{
			OrderID: orderID, VehicleType: string(order.VehicleType),
			Lat: shop.Location.Lat, Lng: shop.Location.Lng, MaxDistanceM: MaxDriverDistanceM,
		})
		if database.IsNoRows(err) {
			outcome = assignNoDriver
			return nil
		}
		if err != nil {
			return fmt.Errorf("recherche d'un livreur : %w", err)
		}
		expires := time.Now().Add(settings.DriverOfferTimeout())
		offer, err := q.CreateOffer(ctx, store.CreateOfferParams{
			OrderID: orderID, DriverID: driver.UserID, DistanceToShopM: int32(driver.DistanceM + 0.5), ExpiresAt: expires,
		})
		if database.IsUniqueViolation(err, "") {
			return nil // proposition créée en parallèle : rien à faire
		}
		if err != nil {
			return fmt.Errorf("création de la proposition : %w", err)
		}
		if err := q.IncrementOffers(ctx, orderID); err != nil {
			return fmt.Errorf("décompte des propositions : %w", err)
		}
		if err := s.jobs.Enqueue(ctx, OfferTimeoutArgs{OfferID: offer.ID}, jobs.At(expires)); err != nil {
			return err
		}
		return s.notify.Notify(ctx, notifications.Message{
			UserID: driver.UserID, App: notifications.AppDriver, Kind: "delivery_offer",
			Title: "Nouvelle mission", Body: fmt.Sprintf("%s · %d m de vous. Répondez vite !", shop.Name, int64(driver.DistanceM+0.5)),
			Data: map[string]string{"offer_id": offer.ID.String(), "expires_at": expires.UTC().Format(time.RFC3339)},
		})
	})
	return outcome, err
}

// CurrentOffer retourne la proposition en attente du livreur (interrogée toutes les 10 s par l'app).
func (s *Service) CurrentOffer(ctx context.Context, driverID uuid.UUID) (*Offer, error) {
	if _, err := s.requireActiveDriver(ctx, driverID); err != nil {
		return nil, err
	}
	o, err := store.New(s.db.Conn(ctx)).PendingOfferForDriver(ctx, driverID)
	if database.IsNoRows(err) {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("proposition en cours : %w", err)
	}
	if time.Now().After(o.ExpiresAt) {
		return nil, nil
	}
	order, err := s.orders.ForDelivery(ctx, o.OrderID)
	if err != nil {
		return nil, err
	}
	shop, err := s.shops.Get(ctx, order.ShopID)
	if err != nil {
		return nil, err
	}
	dist, err := s.geo.DistanceMeters(ctx, shop.Location, order.Address.Location)
	if err != nil {
		return nil, err
	}
	return &Offer{
		ID: o.ID, OrderID: o.OrderID, OrderReference: order.Reference, ShopName: shop.Name, ShopAddress: shop.AddressText,
		ShopNeighborood: shop.NeighborhoodName, DeliveryArea: order.Address.Neighborhood,
		DistanceToShopM: o.DistanceToShopM, ShopToClientM: dist, ParcelSize: order.ParcelSize,
		EarningXOF: order.DeliveryFeeXOF, ExpiresAt: o.ExpiresAt,
		ShopLocation: shop.Location, ClientArea: roughArea(order.Address.Location),
	}, nil
}

// AcceptOffer : le livreur accepte. Une seule mission par commande et par livreur : si un autre
// livreur a été retenu entre-temps, l'acceptation est refusée.
func (s *Service) AcceptOffer(ctx context.Context, driverID, offerID uuid.UUID) (Mission, error) {
	var deliveryID uuid.UUID
	err := s.db.InTx(ctx, func(ctx context.Context) error {
		d, err := s.requireActiveDriver(ctx, driverID)
		if err != nil {
			return err
		}
		q := store.New(s.db.Conn(ctx))
		o, err := q.LockOffer(ctx, offerID)
		if database.IsNoRows(err) || (err == nil && o.DriverID != driverID) {
			return apperr.NotFound("offer_not_found", "Proposition introuvable.")
		}
		if err != nil {
			return fmt.Errorf("verrou de la proposition : %w", err)
		}
		if o.Status != "pending" || time.Now().After(o.ExpiresAt) {
			return apperr.Conflict("offer_expired", "Cette proposition n'est plus disponible.")
		}
		if d.Availability != Available {
			return apperr.Conflict("driver_not_available", "Passez en ligne pour accepter une mission.")
		}
		if _, err := q.RespondOffer(ctx, store.RespondOfferParams{ID: offerID, NewStatus: "accepted"}); err != nil {
			return fmt.Errorf("acceptation : %w", err)
		}
		order, err := s.orders.ForDelivery(ctx, o.OrderID)
		if err != nil {
			return err
		}
		m, err := q.CreateDelivery(ctx, store.CreateDeliveryParams{OrderID: o.OrderID, DriverID: driverID, OfferID: &o.ID, FeeXof: order.DeliveryFeeXOF})
		if database.IsUniqueViolation(err, "deliveries_one_active_per_order") || database.IsUniqueViolation(err, "deliveries_one_active_per_driver") {
			return apperr.Conflict("offer_expired", "Cette mission a déjà été attribuée.")
		}
		if err != nil {
			return fmt.Errorf("création de la mission : %w", err)
		}
		deliveryID = m.ID
		if err := q.SetAvailability(ctx, store.SetAvailabilityParams{UserID: driverID, Availability: Busy}); err != nil {
			return fmt.Errorf("disponibilité : %w", err)
		}
		if err := s.orders.AssignDriver(ctx, o.OrderID, driverID); err != nil {
			if apperr.IsCode(err, "invalid_transition") {
				return apperr.Conflict("offer_expired", "Cette commande n'attend plus de livreur.")
			}
			return err
		}
		return q.CloseAssignment(ctx, o.OrderID)
	})
	if err != nil {
		return Mission{}, err
	}
	return s.missionView(ctx, deliveryID)
}

// DeclineOffer : le livreur refuse ; la commande est proposée au suivant.
func (s *Service) DeclineOffer(ctx context.Context, driverID, offerID uuid.UUID) error {
	return s.db.InTx(ctx, func(ctx context.Context) error {
		q := store.New(s.db.Conn(ctx))
		o, err := q.GetOffer(ctx, offerID)
		if database.IsNoRows(err) || (err == nil && o.DriverID != driverID) {
			return apperr.NotFound("offer_not_found", "Proposition introuvable.")
		}
		if err != nil {
			return fmt.Errorf("lecture de la proposition : %w", err)
		}
		n, err := q.RespondOffer(ctx, store.RespondOfferParams{ID: offerID, NewStatus: "declined"})
		if err != nil {
			return fmt.Errorf("refus : %w", err)
		}
		if n == 0 {
			return nil // déjà expirée
		}
		return s.jobs.Enqueue(ctx, AssignArgs{OrderID: o.OrderID}, nil)
	})
}

// ExpireOffer clôt une proposition dont le délai est dépassé et passe au livreur suivant
// (tâche de fond ; sans effet si la proposition a reçu une réponse).
func (s *Service) ExpireOffer(ctx context.Context, offerID uuid.UUID) error {
	return s.db.InTx(ctx, func(ctx context.Context) error {
		q := store.New(s.db.Conn(ctx))
		o, err := q.GetOffer(ctx, offerID)
		if err != nil {
			return fmt.Errorf("lecture de la proposition : %w", err)
		}
		if o.Status != "pending" {
			return nil
		}
		if time.Now().Before(o.ExpiresAt) {
			return river.JobSnooze(time.Until(o.ExpiresAt) + 100*time.Millisecond)
		}
		n, err := q.ExpireOffer(ctx, offerID)
		if err != nil {
			return fmt.Errorf("expiration de la proposition : %w", err)
		}
		if n == 0 {
			return nil
		}
		return s.jobs.Enqueue(ctx, AssignArgs{OrderID: o.OrderID}, nil)
	})
}

// onOrderStatusChanged réagit aux changements de statut des commandes à livrer.
func (s *Service) onOrderStatusChanged(ctx context.Context, orderID uuid.UUID, status orders.Status) error {
	switch status {
	case orders.StatusAwaitingDriver:
		return s.StartAssignment(ctx, orderID)
	case orders.StatusCancelled:
		return s.db.InTx(ctx, func(ctx context.Context) error {
			q := store.New(s.db.Conn(ctx))
			if err := q.CancelPendingOffersForOrder(ctx, orderID); err != nil {
				return fmt.Errorf("annulation des propositions : %w", err)
			}
			return q.CloseAssignment(ctx, orderID)
		})
	case orders.StatusReturnedToShop:
		return s.closeReturnedMission(ctx, orderID)
	}
	return nil
}
