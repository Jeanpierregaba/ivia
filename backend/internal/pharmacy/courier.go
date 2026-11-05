package pharmacy

import (
	"context"
	"crypto/subtle"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"

	"ivia/backend/internal/delivery"
	"ivia/backend/internal/geo"
	"ivia/backend/internal/notifications"
	"ivia/backend/internal/pharmacy/store"
	"ivia/backend/internal/platform/apperr"
	"ivia/backend/internal/platform/database"
	"ivia/backend/internal/platform/jobs"
	"ivia/backend/internal/platform/validate"
)

// CourierOffer est une course pharmacie proposée à un livreur.
type CourierOffer struct {
	ID                  uuid.UUID `json:"id"`
	ReservationID       uuid.UUID `json:"reservation_id"`
	PharmacyName        string    `json:"pharmacy_name"`
	PharmacyAddress     string    `json:"pharmacy_address"`
	DistanceToPharmacyM int32     `json:"distance_to_pharmacy_m"`
	PharmacyToClientM   int64     `json:"pharmacy_to_client_m"`
	EarningXOF          int64     `json:"earning_xof"`
	ExpiresAt           time.Time `json:"expires_at"`
}

// CourierMission est la course vue par le livreur.
type CourierMission struct {
	ID            uuid.UUID      `json:"id"`
	ReservationID uuid.UUID      `json:"reservation_id"`
	Number        string         `json:"number"`
	Status        string         `json:"status"`
	FeeXOF        int64          `json:"fee_xof"`
	Lines         []ResponseLine `json:"lines"`
	// PrescriptionCheckRequired : vérifier l'original de l'ordonnance avant de remettre les produits.
	PrescriptionCheckRequired bool       `json:"prescription_check_required"`
	PreparedAt                *time.Time `json:"prepared_at"`
	Pharmacy                  MissionPOI `json:"pharmacy"`
	// Client : coordonnées données seulement pendant la course.
	Client      *MissionPOI `json:"client"`
	AssignedAt  time.Time   `json:"assigned_at"`
	PickedUpAt  *time.Time  `json:"picked_up_at"`
	DeliveredAt *time.Time  `json:"delivered_at"`
}

// MissionPOI est un lieu de la course.
type MissionPOI struct {
	Name         string    `json:"name"`
	Phone        string    `json:"phone"`
	AddressText  string    `json:"address_text"`
	Location     geo.Point `json:"location"`
	Instructions string    `json:"instructions"`
}

type assignOutcome int

const (
	assignDone assignOutcome = iota
	assignNoDriver
)

var errMissionNotFound = apperr.NotFound("mission_not_found", "Course introuvable.")

// assignCourier propose la course au livreur libre le plus proche de la pharmacie. Idempotente.
func (s *Service) assignCourier(ctx context.Context, reservationID uuid.UUID) (assignOutcome, error) {
	platform, err := s.admin.Settings(ctx)
	if err != nil {
		return assignDone, err
	}
	outcome := assignDone
	err = s.db.InTx(ctx, func(ctx context.Context) error {
		q := s.q(ctx)
		cur, err := q.LockReservation(ctx, reservationID)
		if database.IsNoRows(err) {
			return nil
		}
		if err != nil {
			return fmt.Errorf("verrou de la réservation : %w", err)
		}
		if cur != ResCourierSearch && cur != ResPaid {
			return nil
		}
		if _, err := q.PendingCourierOfferForReservation(ctx, reservationID); err == nil {
			return nil
		} else if !database.IsNoRows(err) {
			return fmt.Errorf("proposition en cours : %w", err)
		}
		r, err := q.GetReservation(ctx, reservationID)
		if err != nil {
			return fmt.Errorf("lecture de la réservation : %w", err)
		}
		ph, err := q.GetPharmacy(ctx, r.PharmacyID)
		if err != nil {
			return fmt.Errorf("lecture de la pharmacie : %w", err)
		}
		offered, err := q.OfferedDrivers(ctx, reservationID)
		if err != nil {
			return fmt.Errorf("livreurs sollicités : %w", err)
		}
		driverID, dist, err := s.drivers.NearestErrandDriver(ctx, ph.Lat, ph.Lng, offered)
		if errors.Is(err, delivery.ErrNoErrandDriver) {
			outcome = assignNoDriver
			return nil
		}
		if err != nil {
			return err
		}
		expires := time.Now().Add(platform.DriverOfferTimeout())
		offer, err := q.CreateCourierOffer(ctx, store.CreateCourierOfferParams{
			ReservationID: reservationID, DriverID: driverID, DistanceM: dist, ExpiresAt: expires,
		})
		if database.IsUniqueViolation(err, "") {
			return nil
		}
		if err != nil {
			return fmt.Errorf("création de la proposition : %w", err)
		}
		if err := s.jobs.Enqueue(ctx, CourierOfferTimeoutArgs{OfferID: offer.ID}, jobs.At(expires)); err != nil {
			return err
		}
		count, err := q.CountCourierOffers(ctx, reservationID)
		if err != nil {
			return fmt.Errorf("décompte des propositions : %w", err)
		}
		if count == int64(platform.AssignmentMaxOffers) {
			if err := s.notify.NotifyAdmins(ctx, "pharmacy_courier_alert", "Livraison de médicament sans livreur",
				fmt.Sprintf("%d livreur(s) sollicité(s) sans succès pour une livraison pharmacie.", count),
				map[string]string{"reservation_id": reservationID.String()}); err != nil {
				return err
			}
		}
		return s.notify.Notify(ctx, notifications.Message{
			UserID: driverID, App: notifications.AppDriver, Kind: "pharmacy_courier_offer",
			Title: "Course pharmacie", Body: fmt.Sprintf("%s · %s de vous. Répondez vite !", ph.Name, formatDistance(dist)),
			Data: map[string]string{"pharmacy_offer_id": offer.ID.String()},
		})
	})
	return outcome, err
}

// CurrentCourierOffer retourne la proposition en attente du livreur (nil sinon).
func (s *Service) CurrentCourierOffer(ctx context.Context, driverID uuid.UUID) (*CourierOffer, error) {
	q := s.q(ctx)
	o, err := q.PendingCourierOfferForDriver(ctx, driverID)
	if database.IsNoRows(err) {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("proposition en cours : %w", err)
	}
	if time.Now().After(o.ExpiresAt) {
		return nil, nil
	}
	r, err := q.GetReservation(ctx, o.ReservationID)
	if err != nil {
		return nil, fmt.Errorf("lecture de la réservation : %w", err)
	}
	ph, err := q.GetPharmacy(ctx, r.PharmacyID)
	if err != nil {
		return nil, fmt.Errorf("lecture de la pharmacie : %w", err)
	}
	toClient, err := s.geo.DistanceMeters(ctx, geo.Point{Lat: ph.Lat, Lng: ph.Lng}, geo.Point{Lat: r.DeliveryLat, Lng: r.DeliveryLng})
	if err != nil {
		return nil, err
	}
	return &CourierOffer{
		ID: o.ID, ReservationID: r.ID, PharmacyName: ph.Name, PharmacyAddress: ph.AddressText,
		DistanceToPharmacyM: o.DistanceM, PharmacyToClientM: toClient, EarningXOF: r.DeliveryFeeXof, ExpiresAt: o.ExpiresAt,
	}, nil
}

// AcceptCourierOffer : le livreur accepte la course ; il passe occupé (aucune commande en parallèle).
func (s *Service) AcceptCourierOffer(ctx context.Context, driverID, offerID uuid.UUID) (CourierMission, error) {
	var deliveryID uuid.UUID
	err := s.db.InTx(ctx, func(ctx context.Context) error {
		q := s.q(ctx)
		o, err := q.LockCourierOffer(ctx, offerID)
		if database.IsNoRows(err) || (err == nil && o.DriverID != driverID) {
			return apperr.NotFound("offer_not_found", "Proposition introuvable.")
		}
		if err != nil {
			return fmt.Errorf("verrou de la proposition : %w", err)
		}
		if o.Status != "pending" || time.Now().After(o.ExpiresAt) {
			return apperr.Conflict("offer_expired", "Cette proposition n'est plus disponible.")
		}
		cur, err := q.LockReservation(ctx, o.ReservationID)
		if err != nil {
			return fmt.Errorf("verrou de la réservation : %w", err)
		}
		if cur != ResCourierSearch && cur != ResPaid {
			return apperr.Conflict("offer_expired", "Cette course n'attend plus de livreur.")
		}
		// Recherche avant paiement : le client paie maintenant ; déjà payé (désistement) : en route.
		next := ResAwaitingPayment
		if cur == ResPaid {
			next = ResCourierAssigned
		}
		if err := s.drivers.ClaimForErrand(ctx, driverID); err != nil {
			return err
		}
		if _, err := q.RespondCourierOffer(ctx, store.RespondCourierOfferParams{ID: offerID, NewStatus: "accepted"}); err != nil {
			return fmt.Errorf("acceptation : %w", err)
		}
		r, err := q.GetReservation(ctx, o.ReservationID)
		if err != nil {
			return fmt.Errorf("lecture de la réservation : %w", err)
		}
		d, err := q.CreateDelivery(ctx, store.CreateDeliveryParams{ReservationID: r.ID, DriverID: driverID, OfferID: &o.ID, FeeXof: r.DeliveryFeeXof})
		if database.IsUniqueViolation(err, "") {
			return apperr.Conflict("offer_expired", "Cette course a déjà été attribuée.")
		}
		if err != nil {
			return fmt.Errorf("création de la course : %w", err)
		}
		deliveryID = d.ID
		if _, err := q.SetReservationStatus(ctx, store.SetReservationStatusParams{ID: r.ID, NewStatus: next, FromStatuses: []string{cur}}); err != nil {
			return fmt.Errorf("réservation attribuée : %w", err)
		}
		courier, err := s.users.Contact(ctx, driverID)
		if err != nil {
			return err
		}
		ph, err := q.GetPharmacy(ctx, r.PharmacyID)
		if err != nil {
			return fmt.Errorf("lecture de la pharmacie : %w", err)
		}
		if err := s.notify.Notify(ctx, notifications.Message{
			UserID: ph.OwnerID, App: notifications.AppPharmacy, Kind: "pharmacy_courier_assigned",
			Title: "Livreur en route", Body: courier.FirstName + " arrive pour récupérer la commande.",
			Data: map[string]string{"reservation_id": r.ID.String()},
		}); err != nil {
			return err
		}
		body := courier.FirstName + " va chercher vos produits à la pharmacie."
		if next == ResAwaitingPayment {
			body = courier.FirstName + " a accepté votre livraison. Payez maintenant pour qu'il parte à la pharmacie."
		}
		return s.notify.Notify(ctx, notifications.Message{
			UserID: r.BuyerID, App: notifications.AppBuyer, Kind: "pharmacy_courier_assigned",
			Title: "Livreur trouvé", Body: body,
			Data: map[string]string{"reservation_id": r.ID.String()},
		})
	})
	if err != nil {
		return CourierMission{}, err
	}
	return s.missionView(ctx, deliveryID)
}

// DeclineCourierOffer : le livreur refuse ; la course est proposée au suivant.
func (s *Service) DeclineCourierOffer(ctx context.Context, driverID, offerID uuid.UUID) error {
	return s.db.InTx(ctx, func(ctx context.Context) error {
		q := s.q(ctx)
		o, err := q.LockCourierOffer(ctx, offerID)
		if database.IsNoRows(err) || (err == nil && o.DriverID != driverID) {
			return apperr.NotFound("offer_not_found", "Proposition introuvable.")
		}
		if err != nil {
			return fmt.Errorf("verrou de la proposition : %w", err)
		}
		n, err := q.RespondCourierOffer(ctx, store.RespondCourierOfferParams{ID: offerID, NewStatus: "declined"})
		if err != nil {
			return fmt.Errorf("refus : %w", err)
		}
		if n == 0 {
			return nil
		}
		return s.jobs.Enqueue(ctx, AssignCourierArgs{ReservationID: o.ReservationID}, nil)
	})
}

func (s *Service) expireCourierOffer(ctx context.Context, offerID uuid.UUID) error {
	return s.db.InTx(ctx, func(ctx context.Context) error {
		q := s.q(ctx)
		o, err := q.LockCourierOffer(ctx, offerID)
		if database.IsNoRows(err) {
			return nil
		}
		if err != nil {
			return fmt.Errorf("verrou de la proposition : %w", err)
		}
		n, err := q.ExpireCourierOffer(ctx, offerID)
		if err != nil || n == 0 {
			return err
		}
		return s.jobs.Enqueue(ctx, AssignCourierArgs{ReservationID: o.ReservationID}, nil)
	})
}

func (s *Service) missionView(ctx context.Context, deliveryID uuid.UUID) (CourierMission, error) {
	q := s.q(ctx)
	d, err := q.GetDelivery(ctx, deliveryID)
	if database.IsNoRows(err) {
		return CourierMission{}, errMissionNotFound
	}
	if err != nil {
		return CourierMission{}, fmt.Errorf("lecture de la course : %w", err)
	}
	r, err := q.GetReservation(ctx, d.ReservationID)
	if err != nil {
		return CourierMission{}, fmt.Errorf("lecture de la réservation : %w", err)
	}
	lines, err := s.responseLines(ctx, r.ResponseID)
	if err != nil {
		return CourierMission{}, err
	}
	available := lines[:0:0]
	for _, l := range lines {
		if l.Available {
			available = append(available, l)
		}
	}
	ph, err := q.GetPharmacy(ctx, r.PharmacyID)
	if err != nil {
		return CourierMission{}, fmt.Errorf("lecture de la pharmacie : %w", err)
	}
	m := CourierMission{
		ID: d.ID, ReservationID: r.ID, Number: reservationNumber(r.Number), Status: d.Status, FeeXOF: d.FeeXof, Lines: available,
		PrescriptionCheckRequired: r.PrescriptionRequired, PreparedAt: r.PreparedAt,
		Pharmacy: MissionPOI{
			Name: ph.Name, Phone: ph.Phone, AddressText: ph.AddressText, Location: geo.Point{Lat: ph.Lat, Lng: ph.Lng},
		},
		AssignedAt: d.AssignedAt, PickedUpAt: d.PickedUpAt, DeliveredAt: d.DeliveredAt,
	}
	if d.Status == "assigned" || d.Status == "picked_up" {
		c, err := s.users.Contact(ctx, r.BuyerID)
		if err != nil {
			return CourierMission{}, err
		}
		m.Client = &MissionPOI{
			Name: c.FirstName, Phone: c.Phone, AddressText: r.DeliveryAddress,
			Location: geo.Point{Lat: r.DeliveryLat, Lng: r.DeliveryLng}, Instructions: r.DeliveryInstructions,
		}
	}
	return m, nil
}

// CurrentCourierMission retourne la course en cours du livreur (nil sinon).
func (s *Service) CurrentCourierMission(ctx context.Context, driverID uuid.UUID) (*CourierMission, error) {
	d, err := s.q(ctx).ActiveDeliveryForDriver(ctx, driverID)
	if database.IsNoRows(err) {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("course en cours : %w", err)
	}
	m, err := s.missionView(ctx, d.ID)
	if err != nil {
		return nil, err
	}
	return &m, nil
}

// CourierHistory retourne les courses pharmacie du livreur (sans données du client).
func (s *Service) CourierHistory(ctx context.Context, driverID uuid.UUID, limit, offset int32) ([]CourierMission, error) {
	rows, err := s.q(ctx).ListDriverDeliveries(ctx, store.ListDriverDeliveriesParams{DriverID: driverID, Lim: limit, Off: offset})
	if err != nil {
		return nil, fmt.Errorf("courses du livreur : %w", err)
	}
	out := make([]CourierMission, 0, len(rows))
	for _, d := range rows {
		m, err := s.missionView(ctx, d.ID)
		if err != nil {
			return nil, err
		}
		if d.Status != "assigned" && d.Status != "picked_up" {
			m.Client = nil
		}
		out = append(out, m)
	}
	return out, nil
}

func (s *Service) ownMission(ctx context.Context, driverID, deliveryID uuid.UUID) (store.PharmacyDelivery, error) {
	d, err := s.q(ctx).LockDelivery(ctx, deliveryID)
	if database.IsNoRows(err) || (err == nil && d.DriverID != driverID) {
		return d, errMissionNotFound
	}
	if err != nil {
		return d, fmt.Errorf("verrou de la course : %w", err)
	}
	return d, nil
}

// CourierPickedUp : le livreur a le médicament.
func (s *Service) CourierPickedUp(ctx context.Context, driverID, deliveryID uuid.UUID) (CourierMission, error) {
	err := s.db.InTx(ctx, func(ctx context.Context) error {
		q := s.q(ctx)
		d, err := s.ownMission(ctx, driverID, deliveryID)
		if err != nil {
			return err
		}
		cur, err := q.LockReservation(ctx, d.ReservationID)
		if err != nil {
			return fmt.Errorf("verrou de la réservation : %w", err)
		}
		if cur == ResAwaitingPayment {
			return apperr.Conflict("awaiting_payment", "Le client n'a pas encore payé : attendez la confirmation avant de récupérer les produits.")
		}
		n, err := q.SetDeliveryStatus(ctx, store.SetDeliveryStatusParams{ID: d.ID, NewStatus: "picked_up", FromStatuses: []string{"assigned"}})
		if err != nil {
			return fmt.Errorf("récupération : %w", err)
		}
		if n == 0 {
			return apperr.Conflict("invalid_transition", "Cette étape est déjà passée.")
		}
		if _, err := q.SetReservationStatus(ctx, store.SetReservationStatusParams{ID: d.ReservationID, NewStatus: ResPickedUp, FromStatuses: []string{ResCourierAssigned}}); err != nil {
			return fmt.Errorf("réservation récupérée : %w", err)
		}
		r, err := q.GetReservation(ctx, d.ReservationID)
		if err != nil {
			return fmt.Errorf("lecture de la réservation : %w", err)
		}
		return s.notify.Notify(ctx, notifications.Message{
			UserID: r.BuyerID, App: notifications.AppBuyer, Kind: "pharmacy_picked_up",
			Title: "Médicament en route", Body: "Votre livreur a récupéré le médicament. Préparez votre code de remise.",
			Data: map[string]string{"reservation_id": r.ID.String()},
		})
	})
	if err != nil {
		return CourierMission{}, err
	}
	return s.missionView(ctx, deliveryID)
}

// CourierDeliver : le client donne son code au livreur (et montre l'original de l'ordonnance si
// besoin) ; course terminée, pharmacie créditée.
func (s *Service) CourierDeliver(ctx context.Context, driverID, deliveryID uuid.UUID, code string, prescriptionChecked bool) (CourierMission, error) {
	err := s.db.InTx(ctx, func(ctx context.Context) error {
		q := s.q(ctx)
		d, err := s.ownMission(ctx, driverID, deliveryID)
		if err != nil {
			return err
		}
		if d.Status != "picked_up" {
			return apperr.Conflict("invalid_transition", "Récupérez d'abord le médicament à la pharmacie.")
		}
		r, err := q.GetReservation(ctx, d.ReservationID)
		if err != nil {
			return fmt.Errorf("lecture de la réservation : %w", err)
		}
		if subtle.ConstantTimeCompare([]byte(code), []byte(r.HandoverCode)) != 1 {
			return apperr.Validation(map[string]string{"code": "Code incorrect."})
		}
		if r.PrescriptionRequired {
			if !prescriptionChecked {
				return apperr.Unprocessable("prescription_check_required",
					"Médicament sur ordonnance : vérifiez l'original de l'ordonnance avant de remettre les produits.")
			}
			if err := q.SetPrescriptionChecked(ctx, d.ID); err != nil {
				return fmt.Errorf("ordonnance vérifiée : %w", err)
			}
		}
		if _, err := q.SetDeliveryStatus(ctx, store.SetDeliveryStatusParams{ID: d.ID, NewStatus: "delivered", FromStatuses: []string{"picked_up"}}); err != nil {
			return fmt.Errorf("livraison : %w", err)
		}
		if err := s.complete(ctx, r, []string{ResPickedUp}); err != nil {
			return err
		}
		if err := s.drivers.ReleaseFromErrand(ctx, driverID); err != nil {
			return err
		}
		ph, err := q.GetPharmacy(ctx, r.PharmacyID)
		if err != nil {
			return fmt.Errorf("lecture de la pharmacie : %w", err)
		}
		if err := s.notify.Notify(ctx, notifications.Message{
			UserID: ph.OwnerID, App: notifications.AppPharmacy, Kind: "pharmacy_delivered",
			Title: "Commande livrée", Body: fmt.Sprintf("%d FCFA ajoutés à votre solde ivia.", r.PharmacyDueXof),
			Data: map[string]string{"reservation_id": r.ID.String()},
		}); err != nil {
			return err
		}
		return s.notify.Notify(ctx, notifications.Message{
			UserID: r.BuyerID, App: notifications.AppBuyer, Kind: "pharmacy_completed",
			Title: "Produits livrés", Body: "Merci d'avoir utilisé l'alerte médicament ivia. Prompt rétablissement !",
			Data: map[string]string{"reservation_id": r.ID.String()},
		})
	})
	if err != nil {
		return CourierMission{}, err
	}
	return s.missionView(ctx, deliveryID)
}

// CourierWithdraw : le livreur se désiste avant la récupération ; la course repart à l'attribution.
func (s *Service) CourierWithdraw(ctx context.Context, driverID, deliveryID uuid.UUID, reason string) error {
	reason = validate.Clean(reason)
	return s.db.InTx(ctx, func(ctx context.Context) error {
		q := s.q(ctx)
		d, err := s.ownMission(ctx, driverID, deliveryID)
		if err != nil {
			return err
		}
		n, err := q.SetDeliveryStatus(ctx, store.SetDeliveryStatusParams{ID: d.ID, NewStatus: "cancelled", FromStatuses: []string{"assigned"}})
		if err != nil {
			return fmt.Errorf("désistement : %w", err)
		}
		if n == 0 {
			return apperr.Conflict("invalid_transition", "Le médicament est récupéré : terminez la livraison.")
		}
		// Payé : nouvelle recherche, livraison déjà réglée. Pas encore payé : recherche avant paiement.
		if _, err := q.SetReservationStatus(ctx, store.SetReservationStatusParams{ID: d.ReservationID, NewStatus: ResPaid, FromStatuses: []string{ResCourierAssigned}}); err != nil {
			return fmt.Errorf("réservation : %w", err)
		}
		if _, err := q.SetReservationStatus(ctx, store.SetReservationStatusParams{ID: d.ReservationID, NewStatus: ResCourierSearch, FromStatuses: []string{ResAwaitingPayment}}); err != nil {
			return fmt.Errorf("réservation : %w", err)
		}
		if err := s.drivers.ReleaseFromErrand(ctx, driverID); err != nil {
			return err
		}
		s.logger.Info("désistement d'un livreur sur une course pharmacie", "delivery_id", d.ID, "reason_len", len(reason))
		return s.jobs.Enqueue(ctx, AssignCourierArgs{ReservationID: d.ReservationID}, nil)
	})
}
