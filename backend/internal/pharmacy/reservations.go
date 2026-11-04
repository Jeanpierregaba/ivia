package pharmacy

import (
	"context"
	"crypto/subtle"
	"fmt"
	"slices"
	"time"

	"github.com/google/uuid"

	"ivia/backend/internal/admin"
	"ivia/backend/internal/geo"
	"ivia/backend/internal/notifications"
	"ivia/backend/internal/orders"
	"ivia/backend/internal/pharmacy/store"
	"ivia/backend/internal/platform/apperr"
	"ivia/backend/internal/platform/database"
	"ivia/backend/internal/platform/jobs"
	"ivia/backend/internal/platform/validate"
)

// ReserveInput : le client choisit une réponse et le mode de remise.
type ReserveInput struct {
	ResponseID  uuid.UUID `json:"response_id"`
	Fulfillment string    `json:"fulfillment"`
	// Quantity : par défaut celle de l'alerte, plafonnée au stock annoncé.
	Quantity int32 `json:"quantity"`
	// AddressID : adresse de livraison enregistrée (livraison seulement).
	AddressID *uuid.UUID `json:"address_id"`
}

// Reservation est une réservation vue par le client.
type Reservation struct {
	ID             uuid.UUID `json:"id"`
	AlertID        uuid.UUID `json:"alert_id"`
	Fulfillment    string    `json:"fulfillment"`
	Status         string    `json:"status"`
	ProductName    string    `json:"product_name"`
	Quantity       int32     `json:"quantity"`
	UnitPriceXOF   int64     `json:"unit_price_xof"`
	ItemsXOF       int64     `json:"items_xof"`
	DeliveryFeeXOF int64     `json:"delivery_fee_xof"`
	TotalXOF       int64     `json:"total_xof"`
	// PayInApp : livraison à payer dans l'app (le retrait se paie à la pharmacie).
	PayInApp bool `json:"pay_in_app"`
	// HandoverCode : à donner au pharmacien (retrait) ou au livreur (livraison). Client seulement.
	HandoverCode    string          `json:"handover_code,omitempty"`
	DeliveryAddress string          `json:"delivery_address"`
	ExpiresAt       *time.Time      `json:"expires_at"`
	CancelReason    string          `json:"cancel_reason"`
	Pharmacy        PharmacyContact `json:"pharmacy"`
	Courier         *CourierContact `json:"courier"`
	CreatedAt       time.Time       `json:"created_at"`
	CompletedAt     *time.Time      `json:"completed_at"`
}

// PharmacyReservation est une réservation vue par la pharmacie (prénom du client seulement).
type PharmacyReservation struct {
	ID             uuid.UUID       `json:"id"`
	AlertID        uuid.UUID       `json:"alert_id"`
	Fulfillment    string          `json:"fulfillment"`
	Status         string          `json:"status"`
	ProductName    string          `json:"product_name"`
	Quantity       int32           `json:"quantity"`
	UnitPriceXOF   int64           `json:"unit_price_xof"`
	ItemsXOF       int64           `json:"items_xof"`
	CommissionXOF  int64           `json:"commission_xof"`
	PharmacyDueXOF int64           `json:"pharmacy_due_xof"`
	BuyerFirstName string          `json:"buyer_first_name"`
	ExpiresAt      *time.Time      `json:"expires_at"`
	CancelReason   string          `json:"cancel_reason"`
	Courier        *CourierContact `json:"courier"`
	CreatedAt      time.Time       `json:"created_at"`
	CompletedAt    *time.Time      `json:"completed_at"`
}

// CourierContact : le livreur ivia d'une livraison en cours.
type CourierContact struct {
	FirstName string `json:"first_name"`
	Phone     string `json:"phone"`
	Status    string `json:"status"`
}

// Earnings : sommes dues à une pharmacie (livraisons payées dans l'app) et reversements.
type Earnings struct {
	DueXOF         int64    `json:"due_xof"`
	PaidOutXOF     int64    `json:"paid_out_xof"`
	BalanceXOF     int64    `json:"balance_xof"`
	DeliveredCount int64    `json:"delivered_count"`
	PickupCount    int64    `json:"pickup_count"`
	Payouts        []Payout `json:"payouts"`
}

// Payout est un reversement fait par ivia à une pharmacie.
type Payout struct {
	ID        uuid.UUID `json:"id"`
	AmountXOF int64     `json:"amount_xof"`
	Reference string    `json:"reference"`
	Note      string    `json:"note"`
	CreatedAt time.Time `json:"created_at"`
}

var errReservationNotFound = apperr.NotFound("reservation_not_found", "Réservation introuvable.")

// Reserve réserve le médicament chez une pharmacie qui a répondu (alerte débloquée).
func (s *Service) Reserve(ctx context.Context, buyerID, alertID uuid.UUID, in ReserveInput) (Reservation, error) {
	v := validate.New()
	v.Check(in.Fulfillment == Pickup || in.Fulfillment == Delivery, "fulfillment", "Valeur attendue : pickup ou delivery.")
	v.Check(in.Quantity >= 0 && in.Quantity <= 20, "quantity", "Entre 1 et 20.")
	v.Check(in.Fulfillment != Delivery || in.AddressID != nil, "address_id", "Adresse de livraison obligatoire.")
	if err := v.Err(); err != nil {
		return Reservation{}, err
	}
	q := s.q(ctx)
	a, err := q.GetAlert(ctx, alertID)
	if database.IsNoRows(err) || (err == nil && a.BuyerID != buyerID) {
		return Reservation{}, errAlertNotFound
	}
	if err != nil {
		return Reservation{}, fmt.Errorf("lecture de l'alerte : %w", err)
	}
	if a.UnlockedAt == nil {
		return Reservation{}, apperr.Conflict("unlock_required", "Débloquez d'abord les pharmacies qui ont répondu.")
	}
	resp, err := q.GetResponse(ctx, in.ResponseID)
	if database.IsNoRows(err) || (err == nil && resp.AlertID != alertID) {
		return Reservation{}, apperr.Validation(map[string]string{"response_id": "Réponse introuvable pour cette alerte."})
	}
	if err != nil {
		return Reservation{}, fmt.Errorf("lecture de la réponse : %w", err)
	}
	if resp.Status != "active" {
		return Reservation{}, apperr.Conflict("response_withdrawn", "Cette pharmacie n'a plus le produit. Choisissez-en une autre.")
	}
	if in.Fulfillment == Delivery && (a.Kind == KindPrescription || resp.PrescriptionRequired) {
		return Reservation{}, apperr.Unprocessable("prescription_pickup_only",
			"Médicament sur ordonnance : retrait en pharmacie uniquement, ordonnance à présenter.")
	}
	qty := in.Quantity
	if qty == 0 {
		qty = min(a.Quantity, resp.QuantityAvailable)
	}
	if qty > resp.QuantityAvailable {
		return Reservation{}, apperr.Validation(map[string]string{"quantity": fmt.Sprintf("La pharmacie n'en a que %d.", resp.QuantityAvailable)})
	}
	ph, err := q.GetPharmacy(ctx, resp.PharmacyID)
	if err != nil {
		return Reservation{}, fmt.Errorf("lecture de la pharmacie : %w", err)
	}
	if ph.SuspendedAt != nil {
		return Reservation{}, apperr.Conflict("response_withdrawn", "Cette pharmacie n'est plus disponible. Choisissez-en une autre.")
	}
	settings, err := s.Settings(ctx)
	if err != nil {
		return Reservation{}, err
	}
	platform, err := s.admin.Settings(ctx)
	if err != nil {
		return Reservation{}, err
	}
	code, err := newCode()
	if err != nil {
		return Reservation{}, err
	}
	items := resp.UnitPriceXof * int64(qty)
	p := store.CreateReservationParams{
		AlertID: alertID, ResponseID: resp.ID, PharmacyID: ph.ID, BuyerID: buyerID, Fulfillment: in.Fulfillment,
		Quantity: qty, UnitPriceXof: resp.UnitPriceXof, ItemsXof: items, TotalXof: items, HandoverCode: code,
	}
	var expires time.Time
	if in.Fulfillment == Pickup {
		p.Status = ResReserved
		expires = time.Now().Add(time.Duration(settings.PickupHoldMinutes) * time.Minute)
	} else {
		addr, err := s.users.GetAddress(ctx, buyerID, *in.AddressID)
		if err != nil {
			return Reservation{}, err
		}
		dist, err := s.geo.DistanceMeters(ctx, geo.Point{Lat: ph.Lat, Lng: ph.Lng}, addr.Location)
		if err != nil {
			return Reservation{}, err
		}
		if dist > int64(maxDeliveryM) {
			return Reservation{}, apperr.Unprocessable("too_far", "Cette pharmacie est trop loin pour une livraison : choisissez le retrait ou une pharmacie plus proche.")
		}
		fee := orders.DeliveryFee(platform, orders.VehicleMotorbike, dist)
		commission := orders.Commission(items, platform.CommissionRateBP)
		p.Status = ResAwaitingPayment
		p.DeliveryFeeXof, p.CommissionXof, p.PharmacyDueXof, p.TotalXof = fee, commission, items-commission, items+fee
		p.DeliveryAddress = addr.AddressText
		p.DeliveryInstructions = addr.Instructions
		p.HasLocation, p.Lat, p.Lng = true, addr.Location.Lat, addr.Location.Lng
		expires = time.Now().Add(platform.PaymentTimeout())
	}
	p.ExpiresAt = &expires

	var id uuid.UUID
	err = s.db.InTx(ctx, func(ctx context.Context) error {
		q := s.q(ctx)
		cur, err := q.LockAlert(ctx, alertID)
		if err != nil {
			return fmt.Errorf("verrou de l'alerte : %w", err)
		}
		if !slices.Contains(openAlert, cur.Status) {
			return apperr.Conflict("alert_closed", "Cette alerte est terminée.")
		}
		id, err = q.CreateReservation(ctx, p)
		if database.IsUniqueViolation(err, "pharmacy_reservations_one_active_per_alert") {
			return apperr.Conflict("reservation_exists", "Une réservation est déjà en cours pour cette alerte.")
		}
		if err != nil {
			return fmt.Errorf("création de la réservation : %w", err)
		}
		if err := s.jobs.Enqueue(ctx, ExpireReservationArgs{ReservationID: id}, jobs.At(expires)); err != nil {
			return err
		}
		if in.Fulfillment == Pickup {
			return s.notify.Notify(ctx, notifications.Message{
				UserID: ph.OwnerID, App: notifications.AppPharmacy, Kind: "pharmacy_reservation",
				Title: "Retrait réservé", Body: fmt.Sprintf("%d × %s mis de côté : le client passe le récupérer.", qty, resp.ProductName),
				Data: map[string]string{"reservation_id": id.String()},
			})
		}
		return nil
	})
	if err != nil {
		return Reservation{}, err
	}
	return s.GetReservation(ctx, buyerID, id)
}

// maxDeliveryM : distance maximale pharmacie → client pour une livraison ivia.
const maxDeliveryM = 20_000

func (s *Service) reservationRow(ctx context.Context, id uuid.UUID) (store.GetReservationRow, error) {
	r, err := s.q(ctx).GetReservation(ctx, id)
	if database.IsNoRows(err) {
		return r, errReservationNotFound
	}
	if err != nil {
		return r, fmt.Errorf("lecture de la réservation : %w", err)
	}
	return r, nil
}

func (s *Service) courierOf(ctx context.Context, reservationID uuid.UUID) (*CourierContact, error) {
	d, err := s.q(ctx).LatestDeliveryForReservation(ctx, reservationID)
	if database.IsNoRows(err) {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("livraison de la réservation : %w", err)
	}
	if d.Status == "cancelled" {
		return nil, nil
	}
	c, err := s.users.Contact(ctx, d.DriverID)
	if err != nil {
		return nil, err
	}
	out := &CourierContact{FirstName: c.FirstName, Status: d.Status}
	if d.Status == "assigned" || d.Status == "picked_up" {
		out.Phone = c.Phone // numéro donné seulement pendant la course
	}
	return out, nil
}

// GetReservation retourne une réservation du client.
func (s *Service) GetReservation(ctx context.Context, buyerID, id uuid.UUID) (Reservation, error) {
	r, err := s.reservationRow(ctx, id)
	if err != nil {
		return Reservation{}, err
	}
	if r.BuyerID != buyerID {
		return Reservation{}, errReservationNotFound
	}
	q := s.q(ctx)
	resp, err := q.GetResponse(ctx, r.ResponseID)
	if err != nil {
		return Reservation{}, fmt.Errorf("lecture de la réponse : %w", err)
	}
	ph, err := q.GetPharmacy(ctx, r.PharmacyID)
	if err != nil {
		return Reservation{}, fmt.Errorf("lecture de la pharmacie : %w", err)
	}
	courier, err := s.courierOf(ctx, r.ID)
	if err != nil {
		return Reservation{}, err
	}
	out := Reservation{
		ID: r.ID, AlertID: r.AlertID, Fulfillment: r.Fulfillment, Status: r.Status, ProductName: resp.ProductName,
		Quantity: r.Quantity, UnitPriceXOF: r.UnitPriceXof, ItemsXOF: r.ItemsXof, DeliveryFeeXOF: r.DeliveryFeeXof,
		TotalXOF: r.TotalXof, PayInApp: r.Fulfillment == Delivery, DeliveryAddress: r.DeliveryAddress, ExpiresAt: r.ExpiresAt,
		CancelReason: r.CancelReason, Courier: courier, CreatedAt: r.CreatedAt, CompletedAt: r.CompletedAt,
		Pharmacy: PharmacyContact{
			ID: ph.ID, Name: ph.Name, Phone: ph.Phone, AddressText: ph.AddressText,
			Location: geo.Point{Lat: ph.Lat, Lng: ph.Lng}, OnDuty: ph.OnDuty,
		},
	}
	if slices.Contains(activeReservation, r.Status) && r.Status != ResAwaitingPayment {
		out.HandoverCode = r.HandoverCode
	}
	return out, nil
}

// ListReservations retourne les réservations du client.
func (s *Service) ListReservations(ctx context.Context, buyerID uuid.UUID, limit, offset int32) ([]Reservation, error) {
	ids, err := s.q(ctx).ListBuyerReservationIDs(ctx, store.ListBuyerReservationIDsParams{BuyerID: buyerID, Lim: limit, Off: offset})
	if err != nil {
		return nil, fmt.Errorf("liste des réservations : %w", err)
	}
	out := make([]Reservation, 0, len(ids))
	for _, id := range ids {
		r, err := s.GetReservation(ctx, buyerID, id)
		if err != nil {
			return nil, err
		}
		out = append(out, r)
	}
	return out, nil
}

func (s *Service) pharmacyReservationView(ctx context.Context, r store.GetReservationRow) (PharmacyReservation, error) {
	resp, err := s.q(ctx).GetResponse(ctx, r.ResponseID)
	if err != nil {
		return PharmacyReservation{}, fmt.Errorf("lecture de la réponse : %w", err)
	}
	buyer, err := s.users.Contact(ctx, r.BuyerID)
	if err != nil {
		return PharmacyReservation{}, err
	}
	courier, err := s.courierOf(ctx, r.ID)
	if err != nil {
		return PharmacyReservation{}, err
	}
	return PharmacyReservation{
		ID: r.ID, AlertID: r.AlertID, Fulfillment: r.Fulfillment, Status: r.Status, ProductName: resp.ProductName,
		Quantity: r.Quantity, UnitPriceXOF: r.UnitPriceXof, ItemsXOF: r.ItemsXof, CommissionXOF: r.CommissionXof,
		PharmacyDueXOF: r.PharmacyDueXof, BuyerFirstName: buyer.FirstName, ExpiresAt: r.ExpiresAt,
		CancelReason: r.CancelReason, Courier: courier, CreatedAt: r.CreatedAt, CompletedAt: r.CompletedAt,
	}, nil
}

func (s *Service) ownReservation(ctx context.Context, ownerID, id uuid.UUID) (store.GetReservationRow, store.GetPharmacyRow, error) {
	ph, err := s.requireActivePharmacy(ctx, ownerID)
	if err != nil {
		return store.GetReservationRow{}, ph, err
	}
	r, err := s.reservationRow(ctx, id)
	if err != nil {
		return r, ph, err
	}
	if r.PharmacyID != ph.ID {
		return r, ph, errReservationNotFound
	}
	return r, ph, nil
}

// PharmacyReservations liste les réservations de la pharmacie (activeOnly : en cours).
func (s *Service) PharmacyReservations(ctx context.Context, ownerID uuid.UUID, activeOnly bool, limit, offset int32) ([]PharmacyReservation, error) {
	ph, err := s.requireActivePharmacy(ctx, ownerID)
	if err != nil {
		return nil, err
	}
	ids, err := s.q(ctx).ListPharmacyReservationIDs(ctx, store.ListPharmacyReservationIDsParams{
		PharmacyID: ph.ID, ActiveOnly: activeOnly, Lim: limit, Off: offset,
	})
	if err != nil {
		return nil, fmt.Errorf("réservations de la pharmacie : %w", err)
	}
	out := make([]PharmacyReservation, 0, len(ids))
	for _, id := range ids {
		r, err := s.reservationRow(ctx, id)
		if err != nil {
			return nil, err
		}
		v, err := s.pharmacyReservationView(ctx, r)
		if err != nil {
			return nil, err
		}
		out = append(out, v)
	}
	return out, nil
}

// PharmacyGetReservation retourne une réservation de la pharmacie.
func (s *Service) PharmacyGetReservation(ctx context.Context, ownerID, id uuid.UUID) (PharmacyReservation, error) {
	r, _, err := s.ownReservation(ctx, ownerID, id)
	if err != nil {
		return PharmacyReservation{}, err
	}
	return s.pharmacyReservationView(ctx, r)
}

// CompletePickup : le client est à la pharmacie et donne son code ; il paie sur place.
func (s *Service) CompletePickup(ctx context.Context, ownerID, id uuid.UUID, code string) (PharmacyReservation, error) {
	r, _, err := s.ownReservation(ctx, ownerID, id)
	if err != nil {
		return PharmacyReservation{}, err
	}
	if r.Fulfillment != Pickup {
		return PharmacyReservation{}, apperr.Conflict("not_pickup", "Cette réservation est livrée par un livreur ivia.")
	}
	if subtle.ConstantTimeCompare([]byte(code), []byte(r.HandoverCode)) != 1 {
		return PharmacyReservation{}, apperr.Validation(map[string]string{"code": "Code incorrect."})
	}
	err = s.db.InTx(ctx, func(ctx context.Context) error {
		if err := s.complete(ctx, r, []string{ResReserved}); err != nil {
			return err
		}
		return s.notify.Notify(ctx, notifications.Message{
			UserID: r.BuyerID, App: notifications.AppBuyer, Kind: "pharmacy_completed",
			Title: "Médicament retiré", Body: "Merci d'avoir utilisé l'alerte médicament ivia. Prompt rétablissement !",
			Data: map[string]string{"reservation_id": r.ID.String()},
		})
	})
	if err != nil {
		return PharmacyReservation{}, err
	}
	return s.PharmacyGetReservation(ctx, ownerID, id)
}

// complete clôt la réservation et l'alerte.
func (s *Service) complete(ctx context.Context, r store.GetReservationRow, from []string) error {
	q := s.q(ctx)
	if _, err := q.LockReservation(ctx, r.ID); err != nil {
		return fmt.Errorf("verrou de la réservation : %w", err)
	}
	n, err := q.SetReservationStatus(ctx, store.SetReservationStatusParams{ID: r.ID, NewStatus: ResCompleted, FromStatuses: from})
	if err != nil {
		return fmt.Errorf("clôture de la réservation : %w", err)
	}
	if n == 0 {
		return apperr.Conflict("invalid_transition", "Cette réservation n'est plus en cours.")
	}
	if _, err := q.SetAlertStatus(ctx, store.SetAlertStatusParams{
		ID: r.AlertID, NewStatus: AlertFulfilled, FromStatuses: []string{AlertSearching, AlertAnswered, AlertUnlocked},
	}); err != nil {
		return fmt.Errorf("clôture de l'alerte : %w", err)
	}
	return q.ExpirePendingTargets(ctx, r.AlertID)
}

// CancelReservation : le client annule (avant que le livreur ait le médicament). Une livraison
// déjà payée est remboursée.
func (s *Service) CancelReservation(ctx context.Context, buyerID, id uuid.UUID, reason string) (Reservation, error) {
	r, err := s.reservationRow(ctx, id)
	if err != nil {
		return Reservation{}, err
	}
	if r.BuyerID != buyerID {
		return Reservation{}, errReservationNotFound
	}
	if !slices.Contains([]string{ResReserved, ResAwaitingPayment, ResPaid}, r.Status) {
		return Reservation{}, apperr.Conflict("not_cancellable", "Un livreur est déjà en route : la réservation ne peut plus être annulée.")
	}
	reason = validate.Clean(reason)
	if reason == "" {
		reason = "Annulée par le client."
	}
	if err := s.db.InTx(ctx, func(ctx context.Context) error {
		return s.endReservation(ctx, r, ResCancelled, reason, true)
	}); err != nil {
		return Reservation{}, err
	}
	return s.GetReservation(ctx, buyerID, id)
}

// PharmacyCancelReservation : la pharmacie n'a finalement plus le produit (avant la remise au
// livreur). Sa réponse est retirée ; le client peut réserver ailleurs, remboursé s'il avait payé.
func (s *Service) PharmacyCancelReservation(ctx context.Context, ownerID, id uuid.UUID, reason string) (PharmacyReservation, error) {
	r, _, err := s.ownReservation(ctx, ownerID, id)
	if err != nil {
		return PharmacyReservation{}, err
	}
	reason = validate.Clean(reason)
	v := validate.New()
	v.Text("reason", reason, 3, 300)
	if err := v.Err(); err != nil {
		return PharmacyReservation{}, err
	}
	if !slices.Contains([]string{ResReserved, ResAwaitingPayment, ResPaid, ResCourierAssigned}, r.Status) {
		return PharmacyReservation{}, apperr.Conflict("not_cancellable", "Le médicament a déjà été remis : la réservation ne peut plus être annulée.")
	}
	err = s.db.InTx(ctx, func(ctx context.Context) error {
		if err := s.endReservation(ctx, r, ResCancelled, "Annulée par la pharmacie : "+reason, false); err != nil {
			return err
		}
		return s.q(ctx).WithdrawResponse(ctx, r.ResponseID)
	})
	if err != nil {
		return PharmacyReservation{}, err
	}
	return s.PharmacyGetReservation(ctx, ownerID, id)
}

// expireReservation : retrait non effectué ou livraison non payée dans le délai (tâche).
func (s *Service) expireReservation(ctx context.Context, id uuid.UUID) error {
	r, err := s.reservationRow(ctx, id)
	if err != nil {
		return err
	}
	if r.Status != ResReserved && r.Status != ResAwaitingPayment {
		return nil
	}
	if r.ExpiresAt != nil && time.Now().Before(*r.ExpiresAt) {
		return nil
	}
	return s.db.InTx(ctx, func(ctx context.Context) error {
		err := s.endReservation(ctx, r, ResExpired, "Délai dépassé.", false)
		if apperr.IsCode(err, "invalid_transition") {
			return nil // payée ou retirée entre-temps
		}
		return err
	})
}

// endReservation annule ou expire une réservation en cours : propositions de course annulées,
// livreur libéré, remboursement si la livraison était payée, parties prévenues. Dans une transaction.
func (s *Service) endReservation(ctx context.Context, r store.GetReservationRow, to, reason string, byBuyer bool) error {
	q := s.q(ctx)
	cur, err := q.LockReservation(ctx, r.ID)
	if err != nil {
		return fmt.Errorf("verrou de la réservation : %w", err)
	}
	from := []string{ResReserved, ResAwaitingPayment, ResPaid, ResCourierAssigned}
	if to == ResExpired {
		from = []string{ResReserved, ResAwaitingPayment}
	}
	n, err := q.SetReservationStatus(ctx, store.SetReservationStatusParams{ID: r.ID, NewStatus: to, Reason: reason, FromStatuses: from})
	if err != nil {
		return fmt.Errorf("fin de la réservation : %w", err)
	}
	if n == 0 {
		return apperr.Conflict("invalid_transition", "Cette réservation n'est plus annulable.")
	}
	if err := q.CancelCourierOffers(ctx, r.ID); err != nil {
		return fmt.Errorf("propositions de course : %w", err)
	}
	if d, err := q.ActiveDeliveryForReservation(ctx, r.ID); err == nil {
		if _, err := q.SetDeliveryStatus(ctx, store.SetDeliveryStatusParams{ID: d.ID, NewStatus: "cancelled", FromStatuses: []string{"assigned", "picked_up"}}); err != nil {
			return fmt.Errorf("annulation de la course : %w", err)
		}
		if err := s.drivers.ReleaseFromErrand(ctx, d.DriverID); err != nil {
			return err
		}
		if err := s.notify.Notify(ctx, notifications.Message{
			UserID: d.DriverID, App: notifications.AppDriver, Kind: "pharmacy_mission_cancelled",
			Title: "Course annulée", Body: "La course pharmacie a été annulée. Vous êtes de nouveau disponible.",
			Data: map[string]string{"delivery_id": d.ID.String()},
		}); err != nil {
			return err
		}
	} else if !database.IsNoRows(err) {
		return fmt.Errorf("course en cours : %w", err)
	}
	// Payée : remboursement automatique.
	if slices.Contains([]string{ResPaid, ResCourierAssigned}, cur) {
		pay, err := q.SucceededOrderPayment(ctx, &r.ID)
		if err == nil {
			if err := s.startRefund(ctx, nil, pay, reason); err != nil {
				return err
			}
		} else if !database.IsNoRows(err) {
			return fmt.Errorf("paiement de la réservation : %w", err)
		}
	}
	ph, err := q.GetPharmacy(ctx, r.PharmacyID)
	if err != nil {
		return fmt.Errorf("lecture de la pharmacie : %w", err)
	}
	if byBuyer {
		if cur == ResAwaitingPayment {
			return nil // la pharmacie n'avait encore rien préparé
		}
		return s.notify.Notify(ctx, notifications.Message{
			UserID: ph.OwnerID, App: notifications.AppPharmacy, Kind: "pharmacy_reservation_cancelled",
			Title: "Réservation annulée", Body: "Le client a annulé sa réservation.",
			Data: map[string]string{"reservation_id": r.ID.String()},
		})
	}
	title, body := "Réservation annulée", "La pharmacie n'a plus le produit. Choisissez une autre pharmacie dans votre alerte."
	if to == ResExpired {
		title, body = "Réservation expirée", "Le délai est dépassé. Vous pouvez réserver à nouveau depuis votre alerte."
	}
	if slices.Contains([]string{ResPaid, ResCourierAssigned}, cur) {
		body += " Votre paiement vous est remboursé."
	}
	return s.notify.Notify(ctx, notifications.Message{
		UserID: r.BuyerID, App: notifications.AppBuyer, Kind: "pharmacy_reservation_" + to, Title: title, Body: body,
		Data: map[string]string{"reservation_id": r.ID.String(), "alert_id": r.AlertID.String()},
	})
}

// --- Reversements -----------------------------------------------------------------------------

func (s *Service) earnings(ctx context.Context, pharmacyID uuid.UUID) (Earnings, error) {
	q := s.q(ctx)
	e, err := q.PharmacyEarnings(ctx, pharmacyID)
	if err != nil {
		return Earnings{}, fmt.Errorf("sommes dues : %w", err)
	}
	rows, err := q.ListPayouts(ctx, pharmacyID)
	if err != nil {
		return Earnings{}, fmt.Errorf("reversements : %w", err)
	}
	out := Earnings{
		DueXOF: e.DueXof, PaidOutXOF: e.PaidOutXof, BalanceXOF: e.DueXof - e.PaidOutXof,
		DeliveredCount: e.DeliveredCount, PickupCount: e.PickupCount, Payouts: make([]Payout, len(rows)),
	}
	for i, p := range rows {
		out.Payouts[i] = Payout{ID: p.ID, AmountXOF: p.AmountXof, Reference: p.Reference, Note: p.Note, CreatedAt: p.CreatedAt}
	}
	return out, nil
}

// Earnings retourne les sommes dues à la pharmacie du titulaire.
func (s *Service) Earnings(ctx context.Context, ownerID uuid.UUID) (Earnings, error) {
	id, err := s.pharmacyIDOf(ctx, ownerID)
	if err != nil {
		return Earnings{}, err
	}
	return s.earnings(ctx, id)
}

// AdminEarnings retourne les sommes dues à une pharmacie.
func (s *Service) AdminEarnings(ctx context.Context, pharmacyID uuid.UUID) (Earnings, error) {
	if _, err := s.q(ctx).GetPharmacy(ctx, pharmacyID); database.IsNoRows(err) {
		return Earnings{}, errPharmacyNotFound
	} else if err != nil {
		return Earnings{}, fmt.Errorf("lecture de la pharmacie : %w", err)
	}
	return s.earnings(ctx, pharmacyID)
}

// RecordPayout enregistre un reversement fait à la pharmacie (admin, journalisé), dans la
// limite du solde dû.
func (s *Service) RecordPayout(ctx context.Context, adminID, pharmacyID uuid.UUID, amount int64, reference, note string) (Earnings, error) {
	reference = validate.Clean(reference)
	note = validate.Clean(note)
	v := validate.New()
	v.Check(amount > 0, "amount_xof", "Montant positif attendu.")
	v.Text("reference", reference, 2, 100)
	v.Check(len(note) <= 300, "note", "300 caractères au plus.")
	if err := v.Err(); err != nil {
		return Earnings{}, err
	}
	err := s.db.InTx(ctx, func(ctx context.Context) error {
		q := s.q(ctx)
		if _, err := q.LockPharmacy(ctx, pharmacyID); database.IsNoRows(err) {
			return errPharmacyNotFound
		} else if err != nil {
			return fmt.Errorf("verrou de la pharmacie : %w", err)
		}
		e, err := s.earnings(ctx, pharmacyID)
		if err != nil {
			return err
		}
		if amount > e.BalanceXOF {
			return apperr.Unprocessable("amount_exceeds_balance", fmt.Sprintf("Le solde dû est de %d FCFA.", e.BalanceXOF))
		}
		p, err := q.InsertPayout(ctx, store.InsertPayoutParams{PharmacyID: pharmacyID, AmountXof: amount, Reference: reference, Note: note, PaidBy: adminID})
		if err != nil {
			return fmt.Errorf("enregistrement du reversement : %w", err)
		}
		if err := s.admin.Record(ctx, admin.AuditEntry{
			AdminID: &adminID, Action: "pharmacy.payout_recorded", TargetType: "pharmacy", TargetID: pharmacyID.String(),
			After: map[string]any{"payout_id": p.ID, "amount_xof": amount, "reference": reference}, Reason: note,
		}); err != nil {
			return err
		}
		ph, err := q.GetPharmacy(ctx, pharmacyID)
		if err != nil {
			return fmt.Errorf("lecture de la pharmacie : %w", err)
		}
		return s.notify.Notify(ctx, notifications.Message{
			UserID: ph.OwnerID, App: notifications.AppPharmacy, Kind: "pharmacy_payout",
			Title: "Reversement effectué", Body: fmt.Sprintf("ivia vous a reversé %d FCFA (réf. %s).", amount, reference),
			Data: map[string]string{"payout_id": p.ID.String()},
		})
	})
	if err != nil {
		return Earnings{}, err
	}
	return s.earnings(ctx, pharmacyID)
}
