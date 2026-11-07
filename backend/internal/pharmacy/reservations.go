package pharmacy

import (
	"context"
	"crypto/subtle"
	"fmt"
	"math"
	"slices"
	"time"

	"github.com/google/uuid"

	"ivia/backend/internal/admin"
	"ivia/backend/internal/geo"
	"ivia/backend/internal/mapping"
	"ivia/backend/internal/notifications"
	"ivia/backend/internal/orders"
	"ivia/backend/internal/pharmacy/store"
	"ivia/backend/internal/platform/apperr"
	"ivia/backend/internal/platform/database"
	"ivia/backend/internal/platform/jobs"
	"ivia/backend/internal/platform/validate"
)

// Qui met fin à une réservation (décide des remboursements et des messages).
type endedBy int

const (
	byBuyer endedBy = iota
	byPharmacy
	bySystem
)

// Estimations de temps affichées au client (« ≈ 25 min », « 8 min à pied »).
const (
	walkMetersPerMinute = 80  // 4,8 km/h
	motoMetersPerMinute = 333 // 20 km/h en ville
	deliveryOverheadMin = 15  // préparation et trajet du livreur vers la pharmacie
	// maxDeliveryM : distance maximale pharmacie → client pour une livraison ivia.
	maxDeliveryM = 20_000
)

func walkMinutes(m int64) int32 { return int32(math.Ceil(float64(m) / walkMetersPerMinute)) }
func deliveryETA(m int64) int32 {
	return deliveryOverheadMin + int32(math.Ceil(float64(m)/motoMetersPerMinute))
}
func reservationNumber(n *int64) string {
	if n == nil {
		return ""
	}
	return fmt.Sprintf("M-%d", *n)
}

// Timeline : étapes datées d'une réservation (suivi de livraison).
type Timeline struct {
	UnlockedAt  time.Time  `json:"unlocked_at"`
	PaidAt      *time.Time `json:"paid_at"`
	PreparedAt  *time.Time `json:"prepared_at"`
	PickedUpAt  *time.Time `json:"picked_up_at"`
	DeliveredAt *time.Time `json:"delivered_at"`
}

// Reservation est la pharmacie débloquée vue par le client : produits mis de côté, code de
// retrait, choix « Me faire livrer » ou « J'y vais ».
type Reservation struct {
	ID          uuid.UUID      `json:"id"`
	Number      string         `json:"number"`
	AlertID     uuid.UUID      `json:"alert_id"`
	Fulfillment string         `json:"fulfillment"`
	Status      string         `json:"status"`
	Lines       []ResponseLine `json:"lines"`
	// ItemsXOF : total des produits disponibles (payé sur place pour un retrait).
	ItemsXOF       int64 `json:"items_xof"`
	DeliveryFeeXOF int64 `json:"delivery_fee_xof"`
	TotalXOF       int64 `json:"total_xof"`
	// PayInApp : livraison à payer dans l'app (le retrait se paie à la pharmacie).
	PayInApp bool `json:"pay_in_app"`
	// PrescriptionRequired : original de l'ordonnance à présenter (pharmacien ou livreur).
	PrescriptionRequired bool `json:"prescription_required"`
	// HandoverCode : à donner au pharmacien (retrait) ou au livreur (livraison). Client seulement.
	HandoverCode string `json:"handover_code,omitempty"`
	// ExpiresAt : produits mis de côté jusqu'à cette heure (retrait) ou délai de paiement.
	ExpiresAt *time.Time `json:"expires_at"`
	// CourierOffersSent : livreurs sollicités pendant la recherche (du plus proche au plus loin).
	CourierOffersSent int64 `json:"courier_offers_sent"`
	// DistanceM et WalkMinutes : depuis la position de l'alerte jusqu'à la pharmacie.
	DistanceM       int64           `json:"distance_m"`
	WalkMinutes     int32           `json:"walk_minutes"`
	DeliveryAddress string          `json:"delivery_address"`
	DeliveryETA     *int32          `json:"delivery_eta_minutes"`
	CancelReason    string          `json:"cancel_reason"`
	Pharmacy        PharmacyContact `json:"pharmacy"`
	Courier         *CourierContact `json:"courier"`
	Timeline        Timeline        `json:"timeline"`
	CreatedAt       time.Time       `json:"created_at"`
	CompletedAt     *time.Time      `json:"completed_at"`
}

// PharmacyReservation est une réservation vue par la pharmacie (prénom du client seulement).
type PharmacyReservation struct {
	ID                   uuid.UUID       `json:"id"`
	Number               string          `json:"number"`
	AlertID              uuid.UUID       `json:"alert_id"`
	Fulfillment          string          `json:"fulfillment"`
	Status               string          `json:"status"`
	Lines                []ResponseLine  `json:"lines"`
	ItemsXOF             int64           `json:"items_xof"`
	CommissionXOF        int64           `json:"commission_xof"`
	PharmacyDueXOF       int64           `json:"pharmacy_due_xof"`
	PrescriptionRequired bool            `json:"prescription_required"`
	BuyerFirstName       string          `json:"buyer_first_name"`
	ExpiresAt            *time.Time      `json:"expires_at"`
	PreparedAt           *time.Time      `json:"prepared_at"`
	CancelReason         string          `json:"cancel_reason"`
	Courier              *CourierContact `json:"courier"`
	CreatedAt            time.Time       `json:"created_at"`
	CompletedAt          *time.Time      `json:"completed_at"`
	// PickedUpAt : remise au livreur validée ; CashPaidXOF : espèces reçues du livreur (ADR 0014).
	PickedUpAt  *time.Time `json:"picked_up_at"`
	CashPaidXOF *int64     `json:"cash_paid_xof"`
	// RefundFeeXOF : forfait de déblocage payé par le client, remboursé si la pharmacie annule.
	RefundFeeXOF int64 `json:"refund_fee_xof"`
}

// CourierContact : le livreur ivia d'une livraison (téléphone pendant la course seulement).
type CourierContact struct {
	FirstName    string `json:"first_name"`
	Phone        string `json:"phone"`
	VehicleType  string `json:"vehicle_type"`
	VehiclePlate string `json:"vehicle_plate"`
	Status       string `json:"status"`
	// EtaMinutes : arrivée estimée du livreur chez la pharmacie, tant qu'il est en route et que sa
	// position est récente ; nil sinon.
	EtaMinutes *int `json:"eta_minutes"`
}

// DeliveryQuote : frais et délai d'une livraison vers une adresse, avant de la choisir.
type DeliveryQuote struct {
	DistanceM      int64  `json:"distance_m"`
	VehicleType    string `json:"vehicle_type"`
	DeliveryFeeXOF int64  `json:"delivery_fee_xof"`
	ItemsXOF       int64  `json:"items_xof"`
	TotalXOF       int64  `json:"total_xof"`
	ETAMinutes     int32  `json:"eta_minutes"`
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

// holdProducts crée la mise de côté d'une réponse débloquée : retrait par défaut, code de
// retrait, expiration après la durée de mise de côté. Dans une transaction.
func (s *Service) holdProducts(ctx context.Context, a store.GetAlertRow, resp store.PharmacyResponse, unlockPaymentID *uuid.UUID) (uuid.UUID, error) {
	q := s.q(ctx)
	settings, err := s.Settings(ctx)
	if err != nil {
		return uuid.Nil, err
	}
	lines, err := s.responseLines(ctx, resp.ID)
	if err != nil {
		return uuid.Nil, err
	}
	var items int64
	rx := false
	for _, l := range lines {
		items += l.LineTotalXOF
		rx = rx || (l.Available && l.PrescriptionRequired)
	}
	photos, err := q.ListAlertPhotos(ctx, a.ID)
	if err != nil {
		return uuid.Nil, fmt.Errorf("photos de l'alerte : %w", err)
	}
	for _, p := range photos {
		rx = rx || p.Kind == PhotoPrescription
	}
	code, err := newCode()
	if err != nil {
		return uuid.Nil, err
	}
	expires := time.Now().Add(time.Duration(settings.PickupHoldMinutes) * time.Minute)
	id, err := q.CreateReservation(ctx, store.CreateReservationParams{
		AlertID: a.ID, ResponseID: resp.ID, PharmacyID: resp.PharmacyID, BuyerID: a.BuyerID, Fulfillment: Pickup,
		Status: ResReserved, Quantity: 1, UnitPriceXof: items, ItemsXof: items, TotalXof: items, HandoverCode: code,
		ExpiresAt: &expires, UnlockPaymentID: unlockPaymentID, PrescriptionRequired: rx,
	})
	if database.IsUniqueViolation(err, "pharmacy_reservations_one_active_per_response") {
		return uuid.Nil, apperr.Conflict("reservation_exists", "Ces produits sont déjà mis de côté pour vous.")
	}
	if err != nil {
		return uuid.Nil, fmt.Errorf("mise de côté : %w", err)
	}
	if err := s.jobs.Enqueue(ctx, ExpireReservationArgs{ReservationID: id}, jobs.At(expires)); err != nil {
		return uuid.Nil, err
	}
	ph, err := q.GetPharmacy(ctx, resp.PharmacyID)
	if err != nil {
		return uuid.Nil, fmt.Errorf("lecture de la pharmacie : %w", err)
	}
	if err := s.notify.Notify(ctx, notifications.Message{
		UserID: ph.OwnerID, App: notifications.AppPharmacy, Kind: "pharmacy_reservation",
		Title: "Produits à mettre de côté",
		Body:  fmt.Sprintf("Un client a choisi votre pharmacie : gardez ses produits %d min.", settings.PickupHoldMinutes),
		Data:  map[string]string{"reservation_id": id.String()},
	}); err != nil {
		return uuid.Nil, err
	}
	return id, nil
}

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

func (s *Service) buyerReservation(ctx context.Context, buyerID, id uuid.UUID) (store.GetReservationRow, error) {
	r, err := s.reservationRow(ctx, id)
	if err == nil && r.BuyerID != buyerID {
		return r, errReservationNotFound
	}
	return r, err
}

// courierOf retourne le livreur de la dernière course (nil sans course) et sa course.
func (s *Service) courierOf(ctx context.Context, reservationID uuid.UUID) (*CourierContact, *store.PharmacyDelivery, error) {
	d, err := s.q(ctx).LatestDeliveryForReservation(ctx, reservationID)
	if database.IsNoRows(err) {
		return nil, nil, nil
	}
	if err != nil {
		return nil, nil, fmt.Errorf("livraison de la réservation : %w", err)
	}
	if d.Status == "cancelled" {
		return nil, &d, nil
	}
	c, err := s.users.Contact(ctx, d.DriverID)
	if err != nil {
		return nil, nil, err
	}
	out := &CourierContact{FirstName: c.FirstName, Status: d.Status}
	if drv, err := s.drivers.Me(ctx, d.DriverID); err == nil {
		out.VehicleType, out.VehiclePlate = drv.VehicleType, drv.VehiclePlate
	}
	if d.Status == "assigned" || d.Status == "picked_up" {
		out.Phone = c.Phone // numéro donné seulement pendant la course
	}
	if d.Status == "assigned" {
		out.EtaMinutes = s.courierEta(ctx, d.DriverID, reservationID)
	}
	return out, &d, nil
}

// courierStaleAfter : au-delà, la position du livreur ne sert plus à estimer son arrivée.
const courierStaleAfter = 10 * time.Minute

// courierEta estime en minutes le trajet du livreur jusqu'à la pharmacie ; nil sans position
// récente ou sans calcul possible (l'app affiche alors « en route »).
func (s *Service) courierEta(ctx context.Context, driverID, reservationID uuid.UUID) *int {
	if s.router == nil {
		return nil
	}
	loc, err := s.drivers.LastLocation(ctx, driverID)
	if err != nil || loc == nil || time.Since(loc.RecordedAt) > courierStaleAfter {
		return nil
	}
	r, err := s.q(ctx).GetReservation(ctx, reservationID)
	if err != nil {
		return nil
	}
	ph, err := s.q(ctx).GetPharmacy(ctx, r.PharmacyID)
	if err != nil {
		return nil
	}
	profile := "car"
	if loc.VehicleType == "motorbike" || loc.VehicleType == "bicycle" {
		profile = "moto"
	}
	route, err := s.router.Route(ctx, profile, []mapping.LatLng{
		{Lat: loc.Point.Lat, Lng: loc.Point.Lng}, {Lat: ph.Lat, Lng: ph.Lng},
	})
	if err != nil {
		return nil
	}
	minutes := int((route.DurationS + 59) / 60)
	if minutes < 1 {
		minutes = 1
	}
	return &minutes
}

func pharmacyContact(ph store.GetPharmacyRow) PharmacyContact {
	return PharmacyContact{
		ID: ph.ID, Name: ph.Name, Phone: ph.Phone, AddressText: ph.AddressText, Location: geo.Point{Lat: ph.Lat, Lng: ph.Lng},
		OnDuty: ph.OnDuty, Open24h: ph.Open24h, DutyUntil: dutyUntil(ph.DutyUntil),
	}
}

// GetReservation retourne une réservation du client.
func (s *Service) GetReservation(ctx context.Context, buyerID, id uuid.UUID) (Reservation, error) {
	r, err := s.buyerReservation(ctx, buyerID, id)
	if err != nil {
		return Reservation{}, err
	}
	q := s.q(ctx)
	lines, err := s.responseLines(ctx, r.ResponseID)
	if err != nil {
		return Reservation{}, err
	}
	ph, err := q.GetPharmacy(ctx, r.PharmacyID)
	if err != nil {
		return Reservation{}, fmt.Errorf("lecture de la pharmacie : %w", err)
	}
	a, err := q.GetAlert(ctx, r.AlertID)
	if err != nil {
		return Reservation{}, fmt.Errorf("lecture de l'alerte : %w", err)
	}
	dist, err := s.geo.DistanceMeters(ctx, geo.Point{Lat: a.Lat, Lng: a.Lng}, geo.Point{Lat: ph.Lat, Lng: ph.Lng})
	if err != nil {
		return Reservation{}, err
	}
	courier, d, err := s.courierOf(ctx, r.ID)
	if err != nil {
		return Reservation{}, err
	}
	out := Reservation{
		ID: r.ID, Number: reservationNumber(r.Number), AlertID: r.AlertID, Fulfillment: r.Fulfillment, Status: r.Status,
		Lines: lines, ItemsXOF: r.ItemsXof, DeliveryFeeXOF: r.DeliveryFeeXof, TotalXOF: r.TotalXof, PayInApp: r.Fulfillment == Delivery,
		PrescriptionRequired: r.PrescriptionRequired, ExpiresAt: r.ExpiresAt, DistanceM: dist, WalkMinutes: walkMinutes(dist),
		DeliveryAddress: r.DeliveryAddress, CancelReason: r.CancelReason, Pharmacy: pharmacyContact(ph), Courier: courier,
		Timeline: Timeline{UnlockedAt: r.CreatedAt, PaidAt: r.PaidAt, PreparedAt: r.PreparedAt}, CreatedAt: r.CreatedAt,
		CompletedAt: r.CompletedAt,
	}
	if d != nil && d.Status != "cancelled" {
		out.Timeline.PickedUpAt, out.Timeline.DeliveredAt = d.PickedUpAt, d.DeliveredAt
	}
	if r.Fulfillment == Delivery {
		toClient, err := s.geo.DistanceMeters(ctx, geo.Point{Lat: ph.Lat, Lng: ph.Lng}, geo.Point{Lat: r.DeliveryLat, Lng: r.DeliveryLng})
		if err != nil {
			return Reservation{}, err
		}
		eta := deliveryETA(toClient)
		out.DeliveryETA = &eta
	}
	if slices.Contains([]string{ResReserved, ResPaid, ResCourierAssigned, ResPickedUp}, r.Status) {
		out.HandoverCode = r.HandoverCode
	}
	if r.Fulfillment == Delivery {
		if out.CourierOffersSent, err = q.CountCourierOffers(ctx, r.ID); err != nil {
			return Reservation{}, fmt.Errorf("livreurs sollicités : %w", err)
		}
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

// quote calcule les frais de livraison vers une adresse du client.
func (s *Service) quote(ctx context.Context, buyerID uuid.UUID, r store.GetReservationRow, addressID uuid.UUID) (DeliveryQuote, quoteDetail, error) {
	addr, err := s.users.GetAddress(ctx, buyerID, addressID)
	if err != nil {
		return DeliveryQuote{}, quoteDetail{}, err
	}
	ph, err := s.q(ctx).GetPharmacy(ctx, r.PharmacyID)
	if err != nil {
		return DeliveryQuote{}, quoteDetail{}, fmt.Errorf("lecture de la pharmacie : %w", err)
	}
	dist, err := s.geo.DistanceMeters(ctx, geo.Point{Lat: ph.Lat, Lng: ph.Lng}, addr.Location)
	if err != nil {
		return DeliveryQuote{}, quoteDetail{}, err
	}
	if dist > maxDeliveryM {
		return DeliveryQuote{}, quoteDetail{}, apperr.Unprocessable("too_far",
			"Cette pharmacie est trop loin pour une livraison : allez-y vous-même ou choisissez une pharmacie plus proche.")
	}
	platform, err := s.admin.Settings(ctx)
	if err != nil {
		return DeliveryQuote{}, quoteDetail{}, err
	}
	settings, err := s.Settings(ctx)
	if err != nil {
		return DeliveryQuote{}, quoteDetail{}, err
	}
	fee := orders.DeliveryFee(platform, orders.VehicleMotorbike, dist)
	// Pas de commission par défaut : le forfait de déblocage rémunère ivia.
	commission := orders.Commission(r.ItemsXof, settings.ProductCommissionBP)
	return DeliveryQuote{
			DistanceM: dist, VehicleType: string(orders.VehicleMotorbike), DeliveryFeeXOF: fee, ItemsXOF: r.ItemsXof,
			TotalXOF: r.ItemsXof + fee, ETAMinutes: deliveryETA(dist),
		}, quoteDetail{commission: commission, address: addr.AddressText, instructions: addr.Instructions, lat: addr.Location.Lat, lng: addr.Location.Lng},
		nil
}

type quoteDetail struct {
	commission            int64
	address, instructions string
	lat, lng              float64
}

// DeliveryQuote retourne les frais et le délai d'une livraison (écran « Comment récupérer vos
// produits ? »).
func (s *Service) DeliveryQuote(ctx context.Context, buyerID, id, addressID uuid.UUID) (DeliveryQuote, error) {
	r, err := s.buyerReservation(ctx, buyerID, id)
	if err != nil {
		return DeliveryQuote{}, err
	}
	q, _, err := s.quote(ctx, buyerID, r, addressID)
	return q, err
}

// ChooseDelivery : « Livreur ivia ». La recherche du livreur part tout de suite : la course est
// proposée aux livreurs disponibles les plus proches de la pharmacie, du plus proche au plus loin.
// Dès qu'un livreur accepte, le client paie produits et livraison (POST /pay) ; le livreur va
// ensuite à la pharmacie. Possible sur ordonnance : le livreur vérifie l'original à la remise.
func (s *Service) ChooseDelivery(ctx context.Context, buyerID, id, addressID uuid.UUID) (Reservation, error) {
	r, err := s.buyerReservation(ctx, buyerID, id)
	if err != nil {
		return Reservation{}, err
	}
	if r.Status != ResReserved {
		return Reservation{}, apperr.Conflict("invalid_transition", "Le mode de remise ne peut plus être changé.")
	}
	quote, d, err := s.quote(ctx, buyerID, r, addressID)
	if err != nil {
		return Reservation{}, err
	}
	err = s.db.InTx(ctx, func(ctx context.Context) error {
		n, err := s.q(ctx).ChooseDelivery(ctx, store.ChooseDeliveryParams{
			ID: id, DeliveryFeeXof: quote.DeliveryFeeXOF, CommissionXof: d.commission, PharmacyDueXof: r.ItemsXof - d.commission,
			DeliveryAddress: d.address, DeliveryInstructions: d.instructions, Lat: d.lat, Lng: d.lng,
		})
		if err != nil {
			return fmt.Errorf("choix de la livraison : %w", err)
		}
		if n == 0 {
			return apperr.Conflict("invalid_transition", "Le mode de remise ne peut plus être changé.")
		}
		// Recherche immédiate : livreurs disponibles les plus proches de la pharmacie, l'un après l'autre.
		return s.jobs.Enqueue(ctx, AssignCourierArgs{ReservationID: id}, nil)
	})
	if err != nil {
		return Reservation{}, err
	}
	return s.GetReservation(ctx, buyerID, id)
}

// ChoosePickup : « J'y vais » (retour au retrait tant que la livraison n'est pas payée) : la
// recherche s'arrête et le livreur qui avait accepté est libéré.
func (s *Service) ChoosePickup(ctx context.Context, buyerID, id uuid.UUID) (Reservation, error) {
	r, err := s.buyerReservation(ctx, buyerID, id)
	if err != nil {
		return Reservation{}, err
	}
	if r.Status == ResReserved {
		return s.GetReservation(ctx, buyerID, id)
	}
	if _, err := s.q(ctx).PendingOrderPayment(ctx, &id); err == nil {
		return Reservation{}, apperr.Conflict("payment_in_progress", "Un paiement est en cours : validez-le ou annulez-le d'abord.")
	} else if !database.IsNoRows(err) {
		return Reservation{}, fmt.Errorf("paiement en cours : %w", err)
	}
	err = s.db.InTx(ctx, func(ctx context.Context) error {
		q := s.q(ctx)
		if _, err := q.LockReservation(ctx, id); err != nil {
			return fmt.Errorf("verrou de la réservation : %w", err)
		}
		n, err := q.ChoosePickup(ctx, id)
		if err != nil {
			return fmt.Errorf("choix du retrait : %w", err)
		}
		if n == 0 {
			return apperr.Conflict("invalid_transition", "La livraison est déjà payée.")
		}
		return s.stopCourier(ctx, id, "Le client passe lui-même à la pharmacie.")
	})
	if err != nil {
		return Reservation{}, err
	}
	return s.GetReservation(ctx, buyerID, id)
}

// stopCourier annule les propositions de course et libère le livreur engagé. Dans une transaction.
func (s *Service) stopCourier(ctx context.Context, reservationID uuid.UUID, why string) error {
	q := s.q(ctx)
	if err := q.CancelCourierOffers(ctx, reservationID); err != nil {
		return fmt.Errorf("propositions de course : %w", err)
	}
	d, err := q.ActiveDeliveryForReservation(ctx, reservationID)
	if database.IsNoRows(err) {
		return nil
	}
	if err != nil {
		return fmt.Errorf("course en cours : %w", err)
	}
	if _, err := q.SetDeliveryStatus(ctx, store.SetDeliveryStatusParams{ID: d.ID, NewStatus: "cancelled", FromStatuses: []string{"assigned", "picked_up"}}); err != nil {
		return fmt.Errorf("annulation de la course : %w", err)
	}
	if err := s.drivers.ReleaseFromErrand(ctx, d.DriverID); err != nil {
		return err
	}
	return s.notify.Notify(ctx, notifications.Message{
		UserID: d.DriverID, App: notifications.AppDriver, Kind: "pharmacy_mission_cancelled",
		Title: "Course annulée", Body: why + " Vous êtes de nouveau disponible.",
		Data: map[string]string{"delivery_id": d.ID.String()},
	})
}

func (s *Service) pharmacyReservationView(ctx context.Context, r store.GetReservationRow) (PharmacyReservation, error) {
	lines, err := s.responseLines(ctx, r.ResponseID)
	if err != nil {
		return PharmacyReservation{}, err
	}
	buyer, err := s.users.Contact(ctx, r.BuyerID)
	if err != nil {
		return PharmacyReservation{}, err
	}
	courier, d, err := s.courierOf(ctx, r.ID)
	if err != nil {
		return PharmacyReservation{}, err
	}
	out := PharmacyReservation{
		ID: r.ID, Number: reservationNumber(r.Number), AlertID: r.AlertID, Fulfillment: r.Fulfillment, Status: r.Status,
		Lines: lines, ItemsXOF: r.ItemsXof, CommissionXOF: r.CommissionXof, PharmacyDueXOF: r.PharmacyDueXof,
		PrescriptionRequired: r.PrescriptionRequired, BuyerFirstName: buyer.FirstName, ExpiresAt: r.ExpiresAt,
		PreparedAt: r.PreparedAt, CancelReason: r.CancelReason, Courier: courier, CreatedAt: r.CreatedAt, CompletedAt: r.CompletedAt,
	}
	if d != nil && d.Status != "cancelled" {
		out.PickedUpAt, out.CashPaidXOF = d.PickedUpAt, d.CashPaidXof
	}
	if r.UnlockPaymentID != nil {
		pay, err := s.q(ctx).GetPayment(ctx, *r.UnlockPaymentID)
		if err != nil {
			return PharmacyReservation{}, fmt.Errorf("forfait de la commande : %w", err)
		}
		if pay.Status != "failed" && pay.Status != "expired" && pay.Status != "pending" {
			out.RefundFeeXOF = pay.AmountXof
		}
	}
	return out, nil
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

// MarkPrepared : la pharmacie a préparé les produits (« Préparée par la pharmacie »).
func (s *Service) MarkPrepared(ctx context.Context, ownerID, id uuid.UUID) (PharmacyReservation, error) {
	r, _, err := s.ownReservation(ctx, ownerID, id)
	if err != nil {
		return PharmacyReservation{}, err
	}
	err = s.db.InTx(ctx, func(ctx context.Context) error {
		n, err := s.q(ctx).MarkPrepared(ctx, id)
		if err != nil {
			return fmt.Errorf("préparation : %w", err)
		}
		if n == 0 {
			return apperr.Conflict("invalid_transition", "Déjà préparée, ou réservation terminée.")
		}
		body := "Vos produits sont prêts à la pharmacie."
		if r.Fulfillment == Delivery {
			body = "Vos produits sont prêts : le livreur va les récupérer."
		}
		return s.notify.Notify(ctx, notifications.Message{
			UserID: r.BuyerID, App: notifications.AppBuyer, Kind: "pharmacy_prepared", Title: "Commande préparée", Body: body,
			Data: map[string]string{"reservation_id": r.ID.String()},
		})
	})
	if err != nil {
		return PharmacyReservation{}, err
	}
	return s.PharmacyGetReservation(ctx, ownerID, id)
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
			Title: "Produits retirés", Body: "Merci d'avoir utilisé l'alerte médicament ivia. Prompt rétablissement !",
			Data: map[string]string{"reservation_id": r.ID.String()},
		})
	})
	if err != nil {
		return PharmacyReservation{}, err
	}
	return s.PharmacyGetReservation(ctx, ownerID, id)
}

// CourierHandover : la pharmacie valide la remise au livreur avec son code de retrait et confirme
// qu'il l'a payée en espèces (ADR 0014). Commande et course passent « récupérées » ; l'avance du
// livreur est enregistrée. Essais de code limités par le handler.
func (s *Service) CourierHandover(ctx context.Context, ownerID, id uuid.UUID, code string, cashPaid bool) (PharmacyReservation, error) {
	r, _, err := s.ownReservation(ctx, ownerID, id)
	if err != nil {
		return PharmacyReservation{}, err
	}
	if r.Fulfillment != Delivery {
		return PharmacyReservation{}, apperr.Conflict("not_delivery", "Cette commande est retirée au comptoir par le client.")
	}
	if !cashPaid {
		return PharmacyReservation{}, apperr.Unprocessable("cash_not_confirmed", "Confirmez que le livreur vous a payé en espèces.")
	}
	err = s.db.InTx(ctx, func(ctx context.Context) error {
		q := s.q(ctx)
		cur, err := q.LockReservation(ctx, r.ID)
		if err != nil {
			return fmt.Errorf("verrou de la réservation : %w", err)
		}
		switch cur {
		case ResCourierAssigned:
		case ResAwaitingPayment:
			return apperr.Conflict("awaiting_payment", "Le client n'a pas encore payé : ne remettez pas encore les produits.")
		default:
			return apperr.Conflict("invalid_transition", "Cette commande n'attend pas de remise au livreur.")
		}
		d, err := q.ActiveDeliveryForReservation(ctx, r.ID)
		if database.IsNoRows(err) {
			return apperr.Conflict("invalid_transition", "Aucun livreur n'est en route pour cette commande.")
		}
		if err != nil {
			return fmt.Errorf("livraison de la réservation : %w", err)
		}
		if d.PickupCode == nil {
			return apperr.Conflict("no_pickup_code", "Ce livreur confirme la récupération dans son app.")
		}
		if subtle.ConstantTimeCompare([]byte(code), []byte(*d.PickupCode)) != 1 {
			return apperr.Validation(map[string]string{"code": "Code incorrect."})
		}
		n, err := q.RecordCourierHandover(ctx, store.RecordCourierHandoverParams{ID: d.ID, CashPaidXof: &r.PharmacyDueXof})
		if err != nil {
			return fmt.Errorf("remise au livreur : %w", err)
		}
		if n == 0 {
			return apperr.Conflict("invalid_transition", "Cette remise est déjà faite.")
		}
		if _, err := q.SetReservationStatus(ctx, store.SetReservationStatusParams{ID: r.ID, NewStatus: ResPickedUp, FromStatuses: []string{ResCourierAssigned}}); err != nil {
			return fmt.Errorf("réservation récupérée : %w", err)
		}
		if err := s.notify.Notify(ctx, notifications.Message{
			UserID: d.DriverID, App: notifications.AppDriver, Kind: "pharmacy_handover_done",
			Title: "Remise validée", Body: "La pharmacie a validé la remise. Livrez le client.",
			Data: map[string]string{"mission_id": d.ID.String()},
		}); err != nil {
			return err
		}
		return s.notify.Notify(ctx, notifications.Message{
			UserID: r.BuyerID, App: notifications.AppBuyer, Kind: "pharmacy_picked_up",
			Title: "Médicament en route", Body: "Votre livreur a récupéré le médicament. Préparez votre code de remise.",
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

// CancelReservation : le client annule (avant que le livreur ait les produits). Une livraison
// déjà payée est remboursée ; le forfait de déblocage reste acquis.
func (s *Service) CancelReservation(ctx context.Context, buyerID, id uuid.UUID, reason string) (Reservation, error) {
	r, err := s.buyerReservation(ctx, buyerID, id)
	if err != nil {
		return Reservation{}, err
	}
	if !slices.Contains([]string{ResReserved, ResCourierSearch, ResAwaitingPayment, ResPaid}, r.Status) {
		return Reservation{}, apperr.Conflict("not_cancellable", "Un livreur est déjà en route : la réservation ne peut plus être annulée.")
	}
	reason = validate.Clean(reason)
	if reason == "" {
		reason = "Annulée par le client."
	}
	if err := s.db.InTx(ctx, func(ctx context.Context) error {
		return s.endReservation(ctx, r, ResCancelled, reason, byBuyer)
	}); err != nil {
		return Reservation{}, err
	}
	return s.GetReservation(ctx, buyerID, id)
}

// PharmacyCancelReservation : la pharmacie n'a finalement plus les produits (avant la remise au
// livreur). Sa réponse est retirée ; le client est remboursé du forfait et de ce qu'il a payé.
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
	if !slices.Contains([]string{ResReserved, ResCourierSearch, ResAwaitingPayment, ResPaid, ResCourierAssigned}, r.Status) {
		return PharmacyReservation{}, apperr.Conflict("not_cancellable", "Les produits ont déjà été remis : la réservation ne peut plus être annulée.")
	}
	err = s.db.InTx(ctx, func(ctx context.Context) error {
		if err := s.endReservation(ctx, r, ResCancelled, "Annulée par la pharmacie : "+reason, byPharmacy); err != nil {
			return err
		}
		return s.q(ctx).WithdrawResponse(ctx, r.ResponseID)
	})
	if err != nil {
		return PharmacyReservation{}, err
	}
	return s.PharmacyGetReservation(ctx, ownerID, id)
}

// expireReservation : mise de côté écoulée sans retrait ni livraison payée (tâche).
func (s *Service) expireReservation(ctx context.Context, id uuid.UUID) error {
	r, err := s.reservationRow(ctx, id)
	if err != nil {
		return err
	}
	if !slices.Contains([]string{ResReserved, ResCourierSearch, ResAwaitingPayment}, r.Status) {
		return nil
	}
	if r.ExpiresAt != nil && time.Now().Before(*r.ExpiresAt) {
		return nil
	}
	return s.db.InTx(ctx, func(ctx context.Context) error {
		err := s.endReservation(ctx, r, ResExpired, "Délai de mise de côté dépassé.", bySystem)
		if apperr.IsCode(err, "invalid_transition") {
			return nil // payée ou retirée entre-temps
		}
		return err
	})
}

// endReservation annule ou expire une réservation en cours : propositions de course annulées,
// livreur libéré, remboursements (livraison payée ; forfait si la pharmacie annule), parties
// prévenues. Dans une transaction.
func (s *Service) endReservation(ctx context.Context, r store.GetReservationRow, to, reason string, by endedBy) error {
	q := s.q(ctx)
	cur, err := q.LockReservation(ctx, r.ID)
	if err != nil {
		return fmt.Errorf("verrou de la réservation : %w", err)
	}
	from := []string{ResReserved, ResCourierSearch, ResAwaitingPayment, ResPaid, ResCourierAssigned}
	if to == ResExpired {
		from = []string{ResReserved, ResCourierSearch, ResAwaitingPayment}
	}
	n, err := q.SetReservationStatus(ctx, store.SetReservationStatusParams{ID: r.ID, NewStatus: to, Reason: reason, FromStatuses: from})
	if err != nil {
		return fmt.Errorf("fin de la réservation : %w", err)
	}
	if n == 0 {
		return apperr.Conflict("invalid_transition", "Cette réservation n'est plus annulable.")
	}
	if err := s.stopCourier(ctx, r.ID, "La course pharmacie a été annulée."); err != nil {
		return err
	}
	refunded := false
	// Livraison payée : remboursée.
	if slices.Contains([]string{ResPaid, ResCourierAssigned}, cur) {
		pay, err := q.SucceededOrderPayment(ctx, &r.ID)
		if err == nil {
			if err := s.startRefund(ctx, nil, pay, reason); err != nil {
				return err
			}
			refunded = true
		} else if !database.IsNoRows(err) {
			return fmt.Errorf("paiement de la réservation : %w", err)
		}
	}
	// La pharmacie annule : le forfait de déblocage est remboursé.
	if by == byPharmacy && r.UnlockPaymentID != nil {
		pay, err := q.GetPayment(ctx, *r.UnlockPaymentID)
		if err != nil {
			return fmt.Errorf("paiement du déblocage : %w", err)
		}
		if pay.Status == PaySucceeded {
			if err := s.startRefund(ctx, nil, pay, "Pharmacie débloquée qui a annulé : "+reason); err != nil {
				return err
			}
			refunded = true
		}
	}
	ph, err := q.GetPharmacy(ctx, r.PharmacyID)
	if err != nil {
		return fmt.Errorf("lecture de la pharmacie : %w", err)
	}
	if by == byBuyer {
		return s.notify.Notify(ctx, notifications.Message{
			UserID: ph.OwnerID, App: notifications.AppPharmacy, Kind: "pharmacy_reservation_cancelled",
			Title: "Réservation annulée", Body: "Le client a annulé : vous pouvez remettre ses produits en rayon.",
			Data: map[string]string{"reservation_id": r.ID.String()},
		})
	}
	title, body := "Réservation annulée", "La pharmacie n'a plus vos produits. Débloquez une autre pharmacie qui a répondu."
	if to == ResExpired {
		title, body = "Mise de côté terminée", "Le délai est dépassé : les produits ne sont plus réservés."
		if err := s.notify.Notify(ctx, notifications.Message{
			UserID: ph.OwnerID, App: notifications.AppPharmacy, Kind: "pharmacy_reservation_expired",
			Title: "Mise de côté terminée", Body: "Le client n'est pas venu : vous pouvez remettre les produits en rayon.",
			Data: map[string]string{"reservation_id": r.ID.String()},
		}); err != nil {
			return err
		}
	}
	if refunded {
		body += " Vous êtes remboursé."
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
