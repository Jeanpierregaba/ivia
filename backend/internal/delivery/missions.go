package delivery

import (
	"context"
	"fmt"
	"slices"
	"time"

	"github.com/google/uuid"

	"ivia/backend/internal/delivery/store"
	"ivia/backend/internal/geo"
	"ivia/backend/internal/orders"
	"ivia/backend/internal/platform/apperr"
	"ivia/backend/internal/platform/database"
	"ivia/backend/internal/platform/validate"
)

// contactStatuses : statuts où le livreur voit le prénom, le numéro et l'adresse de l'acheteur.
var contactStatuses = []string{"assigned", "at_shop", "picked_up", "at_customer"}

// Mission est la vue du livreur sur sa mission.
type Mission struct {
	ID             uuid.UUID `json:"id"`
	OrderID        uuid.UUID `json:"order_id"`
	OrderReference string    `json:"order_reference"`
	Status         string    `json:"status"`
	FeeXOF         int64     `json:"fee_xof"`
	ItemsCount     int32     `json:"items_count"`
	// Items : articles à récupérer à la boutique (nom et quantité).
	Items      []orders.DeliveryItem `json:"items"`
	ParcelSize string                `json:"parcel_size"`
	Shop       MissionPOI            `json:"shop"`
	// Customer n'est renseigné que pendant la mission (jusqu'à la remise ou l'échec).
	Customer          *MissionPOI `json:"customer"`
	AssignedAt        time.Time   `json:"assigned_at"`
	ArrivedShopAt     *time.Time  `json:"arrived_shop_at"`
	PickedUpAt        *time.Time  `json:"picked_up_at"`
	ArrivedCustomerAt *time.Time  `json:"arrived_customer_at"`
	DeliveredAt       *time.Time  `json:"delivered_at"`
	FailedAt          *time.Time  `json:"failed_at"`
	FailureReason     string      `json:"failure_reason"`
}

// MissionPOI est un lieu de la mission (boutique ou client).
type MissionPOI struct {
	Name         string    `json:"name"`
	Phone        string    `json:"phone"`
	AddressText  string    `json:"address_text"`
	Neighborhood string    `json:"neighborhood"`
	Instructions string    `json:"instructions,omitempty"`
	Location     geo.Point `json:"location"`
}

// DeliveryInfo est ce que l'acheteur et le marchand voient du livreur.
type DeliveryInfo struct {
	Status          string     `json:"status"`
	DriverFirstName string     `json:"driver_first_name"`
	VehicleType     string     `json:"vehicle_type"`
	VehiclePlate    string     `json:"vehicle_plate"`
	AssignedAt      time.Time  `json:"assigned_at"`
	PickedUpAt      *time.Time `json:"picked_up_at"`
}

func (s *Service) missionView(ctx context.Context, deliveryID uuid.UUID) (Mission, error) {
	m, err := store.New(s.db.Conn(ctx)).GetDelivery(ctx, deliveryID)
	if err != nil {
		return Mission{}, fmt.Errorf("lecture de la mission : %w", err)
	}
	order, err := s.orders.ForDelivery(ctx, m.OrderID)
	if err != nil {
		return Mission{}, err
	}
	shop, err := s.shops.Get(ctx, order.ShopID)
	if err != nil {
		return Mission{}, err
	}
	out := Mission{
		ID: m.ID, OrderID: m.OrderID, OrderReference: order.Reference, Status: m.Status, FeeXOF: m.FeeXof,
		ItemsCount: order.ItemsCount, Items: order.Items, ParcelSize: order.ParcelSize,
		Shop: MissionPOI{
			Name: shop.Name, Phone: shop.Phone, AddressText: shop.AddressText,
			Neighborhood: shop.NeighborhoodName, Location: shop.Location,
		},
		AssignedAt: m.AssignedAt, ArrivedShopAt: m.ArrivedShopAt, PickedUpAt: m.PickedUpAt,
		ArrivedCustomerAt: m.ArrivedCustomerAt, DeliveredAt: m.DeliveredAt, FailedAt: m.FailedAt,
		FailureReason: m.FailureReason,
	}
	if slices.Contains(contactStatuses, m.Status) {
		c, err := s.users.Contact(ctx, order.BuyerID)
		if err != nil {
			return Mission{}, err
		}
		out.Customer = &MissionPOI{
			Name: c.FirstName, Phone: c.Phone, AddressText: order.Address.AddressText,
			Neighborhood: order.Address.Neighborhood, Instructions: order.Address.Instructions, Location: order.Address.Location,
		}
	}
	return out, nil
}

// CurrentMission retourne la mission en cours du livreur (nil s'il n'en a pas).
func (s *Service) CurrentMission(ctx context.Context, driverID uuid.UUID) (*Mission, error) {
	if _, err := s.requireActiveDriver(ctx, driverID); err != nil {
		return nil, err
	}
	m, err := store.New(s.db.Conn(ctx)).ActiveDeliveryForDriver(ctx, driverID)
	if database.IsNoRows(err) {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("mission en cours : %w", err)
	}
	v, err := s.missionView(ctx, m.ID)
	return &v, err
}

// History retourne les missions passées du livreur (sans données de l'acheteur).
func (s *Service) History(ctx context.Context, driverID uuid.UUID, limit, offset int32) ([]Mission, error) {
	rows, err := store.New(s.db.Conn(ctx)).ListDriverDeliveries(ctx, store.ListDriverDeliveriesParams{DriverID: driverID, Lim: limit, Off: offset})
	if err != nil {
		return nil, fmt.Errorf("historique des missions : %w", err)
	}
	out := make([]Mission, 0, len(rows))
	for _, r := range rows {
		v, err := s.missionView(ctx, r.ID)
		if err != nil {
			return nil, err
		}
		out = append(out, v)
	}
	return out, nil
}

// requireOwnMission verrouille une mission du livreur (celle d'un autre est introuvable).
func (s *Service) requireOwnMission(ctx context.Context, driverID, deliveryID uuid.UUID) (store.Delivery, error) {
	if _, err := s.requireActiveDriver(ctx, driverID); err != nil {
		return store.Delivery{}, err
	}
	m, err := store.New(s.db.Conn(ctx)).LockDelivery(ctx, deliveryID)
	if database.IsNoRows(err) || (err == nil && m.DriverID != driverID) {
		return store.Delivery{}, apperr.NotFound("mission_not_found", "Mission introuvable.")
	}
	if err != nil {
		return store.Delivery{}, fmt.Errorf("verrou de la mission : %w", err)
	}
	return m, nil
}

func (s *Service) setStatus(ctx context.Context, m store.Delivery, to string, from []string, reason string, calls int32) error {
	n, err := store.New(s.db.Conn(ctx)).SetDeliveryStatus(ctx, store.SetDeliveryStatusParams{
		ID: m.ID, NewStatus: to, FromStatuses: from, FailureReason: reason, CallAttempts: calls,
	})
	if err != nil {
		return fmt.Errorf("statut de la mission : %w", err)
	}
	if n == 0 {
		return apperr.Conflict("invalid_mission_step", "Étape impossible : la mission est « "+m.Status+" ».")
	}
	return nil
}

func (s *Service) missionStep(ctx context.Context, driverID, deliveryID uuid.UUID, fn func(ctx context.Context, m store.Delivery) error) (Mission, error) {
	err := s.db.InTx(ctx, func(ctx context.Context) error {
		m, err := s.requireOwnMission(ctx, driverID, deliveryID)
		if err != nil {
			return err
		}
		return fn(ctx, m)
	})
	if err != nil {
		return Mission{}, err
	}
	return s.missionView(ctx, deliveryID)
}

// ArrivedAtShop : le livreur est à la boutique.
func (s *Service) ArrivedAtShop(ctx context.Context, driverID, deliveryID uuid.UUID) (Mission, error) {
	return s.missionStep(ctx, driverID, deliveryID, func(ctx context.Context, m store.Delivery) error {
		return s.setStatus(ctx, m, "at_shop", []string{"assigned"}, "", 0)
	})
}

// PickedUp : le livreur a récupéré le colis.
func (s *Service) PickedUp(ctx context.Context, driverID, deliveryID uuid.UUID) (Mission, error) {
	return s.missionStep(ctx, driverID, deliveryID, func(ctx context.Context, m store.Delivery) error {
		if err := s.setStatus(ctx, m, "picked_up", []string{"assigned", "at_shop"}, "", 0); err != nil {
			return err
		}
		return s.orders.MarkPickedUp(ctx, m.OrderID, driverID)
	})
}

// ArrivedAtCustomer : le livreur est à l'adresse de livraison (démarre l'attente avant échec).
func (s *Service) ArrivedAtCustomer(ctx context.Context, driverID, deliveryID uuid.UUID) (Mission, error) {
	return s.missionStep(ctx, driverID, deliveryID, func(ctx context.Context, m store.Delivery) error {
		return s.setStatus(ctx, m, "at_customer", []string{"picked_up"}, "", 0)
	})
}

// Deliver : le livreur saisit le code de remise de l'acheteur.
func (s *Service) Deliver(ctx context.Context, driverID, deliveryID uuid.UUID, code string) (Mission, error) {
	return s.missionStep(ctx, driverID, deliveryID, func(ctx context.Context, m store.Delivery) error {
		if m.Status != "picked_up" && m.Status != "at_customer" {
			return apperr.Conflict("invalid_mission_step", "Étape impossible : la mission est « "+m.Status+" ».")
		}
		if err := s.orders.CompleteDelivery(ctx, m.OrderID, driverID, code); err != nil {
			return err
		}
		if err := s.setStatus(ctx, m, "delivered", []string{"picked_up", "at_customer"}, "", 0); err != nil {
			return err
		}
		return store.New(s.db.Conn(ctx)).SetAvailability(ctx, store.SetAvailabilityParams{UserID: driverID, Availability: Available})
	})
}

// Fail déclare l'échec de la livraison : après 10 minutes d'attente sur place et deux appels
// sans réponse. Le livreur rapporte ensuite le colis en boutique.
func (s *Service) Fail(ctx context.Context, driverID, deliveryID uuid.UUID, reason string, callAttempts int32) (Mission, error) {
	reason = validate.Clean(reason)
	return s.missionStep(ctx, driverID, deliveryID, func(ctx context.Context, m store.Delivery) error {
		if m.Status != "at_customer" || m.ArrivedCustomerAt == nil {
			return apperr.Conflict("not_at_customer", "Signalez d'abord votre arrivée chez le client.")
		}
		if wait := time.Since(*m.ArrivedCustomerAt); wait < MinWaitBeforeFailure {
			return apperr.Conflict("wait_required", fmt.Sprintf("Attendez encore %d minute(s) avant de déclarer l'échec.", int((MinWaitBeforeFailure-wait).Minutes())+1))
		}
		if callAttempts < MinCallsBeforeFailure {
			return apperr.Validation(map[string]string{"call_attempts": "Appelez le client au moins deux fois avant de déclarer l'échec."})
		}
		if reason == "" {
			reason = "Client absent ou injoignable."
		}
		if err := s.setStatus(ctx, m, "returning", []string{"at_customer"}, reason, callAttempts); err != nil {
			return err
		}
		return s.orders.MarkDeliveryFailed(ctx, m.OrderID, driverID, reason)
	})
}

// Withdraw : le livreur se désiste avant la récupération ; la commande repart à l'attribution.
func (s *Service) Withdraw(ctx context.Context, driverID, deliveryID uuid.UUID, reason string) error {
	return s.db.InTx(ctx, func(ctx context.Context) error {
		m, err := s.requireOwnMission(ctx, driverID, deliveryID)
		if err != nil {
			return err
		}
		return s.withdraw(ctx, m, orders.As(orders.ActorDriver, driverID), validate.Clean(reason))
	})
}

func (s *Service) withdraw(ctx context.Context, m store.Delivery, actor orders.Actor, reason string) error {
	if reason == "" {
		reason = "Désistement du livreur."
	}
	if err := s.setStatus(ctx, m, "withdrawn", []string{"assigned", "at_shop"}, "", 0); err != nil {
		return err
	}
	if err := store.New(s.db.Conn(ctx)).SetAvailability(ctx, store.SetAvailabilityParams{UserID: m.DriverID, Availability: Available}); err != nil {
		return fmt.Errorf("disponibilité : %w", err)
	}
	// La commande repasse « en attente d'un livreur » : orders crée la tâche qui relance l'attribution.
	return s.orders.UnassignDriver(ctx, m.OrderID, actor, reason)
}

// AdminUnassign retire le livreur d'une commande avant la récupération (journalisé).
func (s *Service) AdminUnassign(ctx context.Context, adminID, orderID uuid.UUID, reason string) error {
	return s.db.InTx(ctx, func(ctx context.Context) error {
		m, err := store.New(s.db.Conn(ctx)).ActiveDeliveryForOrder(ctx, orderID)
		if database.IsNoRows(err) {
			return apperr.Conflict("no_active_mission", "Aucun livreur n'est assigné à cette commande.")
		}
		if err != nil {
			return fmt.Errorf("mission en cours : %w", err)
		}
		if err := s.withdraw(ctx, m, orders.As(orders.ActorAdmin, adminID), validate.Clean(reason)); err != nil {
			return err
		}
		return s.admin.Record(ctx, adminAudit(adminID, "order.unassign_driver", orderID, m.DriverID, reason))
	})
}

// closeReturnedMission termine la mission quand le marchand confirme le retour du colis.
func (s *Service) closeReturnedMission(ctx context.Context, orderID uuid.UUID) error {
	return s.db.InTx(ctx, func(ctx context.Context) error {
		q := store.New(s.db.Conn(ctx))
		m, err := q.ActiveDeliveryForOrder(ctx, orderID)
		if database.IsNoRows(err) {
			return nil
		}
		if err != nil {
			return fmt.Errorf("mission en cours : %w", err)
		}
		if m.Status != "returning" {
			return nil
		}
		if err := s.setStatus(ctx, m, "returned", []string{"returning"}, "", 0); err != nil {
			return err
		}
		return q.SetAvailability(ctx, store.SetAvailabilityParams{UserID: m.DriverID, Availability: Available})
	})
}

// InfoForBuyer retourne le livreur de la commande de l'acheteur.
func (s *Service) InfoForBuyer(ctx context.Context, buyerID, orderID uuid.UUID) (*DeliveryInfo, error) {
	ok, err := s.orders.IsBuyerOf(ctx, buyerID, orderID)
	if err != nil {
		return nil, err
	}
	if !ok {
		return nil, apperr.NotFound("order_not_found", "Commande introuvable.")
	}
	return s.info(ctx, orderID)
}

// InfoForSeller retourne le livreur d'une commande d'une boutique du marchand.
func (s *Service) InfoForSeller(ctx context.Context, sellerID, orderID uuid.UUID) (*DeliveryInfo, error) {
	if _, err := s.orders.GetForSeller(ctx, sellerID, orderID); err != nil {
		return nil, err
	}
	return s.info(ctx, orderID)
}

func (s *Service) info(ctx context.Context, orderID uuid.UUID) (*DeliveryInfo, error) {
	m, err := store.New(s.db.Conn(ctx)).LatestDeliveryForOrder(ctx, orderID)
	if database.IsNoRows(err) {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("mission : %w", err)
	}
	d, err := store.New(s.db.Conn(ctx)).GetDriver(ctx, m.DriverID)
	if err != nil {
		return nil, fmt.Errorf("lecture du livreur : %w", err)
	}
	c, err := s.users.Contact(ctx, m.DriverID)
	if err != nil {
		return nil, err
	}
	return &DeliveryInfo{
		Status: m.Status, DriverFirstName: c.FirstName, VehicleType: d.VehicleType, VehiclePlate: d.VehiclePlate,
		AssignedAt: m.AssignedAt, PickedUpAt: m.PickedUpAt,
	}, nil
}
