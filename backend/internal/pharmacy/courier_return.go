package pharmacy

import (
	"context"
	"fmt"
	"time"

	"github.com/google/uuid"

	"ivia/backend/internal/notifications"
	"ivia/backend/internal/pharmacy/store"
	"ivia/backend/internal/platform/apperr"
	"ivia/backend/internal/platform/validate"
)

// Règles du client injoignable, les mêmes que pour une livraison de boutique.
const (
	// courierMinWait : attente minimale chez le client avant de déclarer l'échec.
	courierMinWait = 10 * time.Minute
	// courierMinCalls : appels minimum au client avant de déclarer l'échec.
	courierMinCalls = 2
)

// CourierArrivedAtPharmacy : le livreur est à la pharmacie (avant la remise).
func (s *Service) CourierArrivedAtPharmacy(ctx context.Context, driverID, deliveryID uuid.UUID) (CourierMission, error) {
	return s.courierStep(ctx, driverID, deliveryID, func(ctx context.Context, d store.PharmacyDelivery) error {
		n, err := s.q(ctx).SetDeliveryArrivedPharmacy(ctx, d.ID)
		if err != nil {
			return fmt.Errorf("arrivée à la pharmacie : %w", err)
		}
		if n == 0 {
			return apperr.Conflict("invalid_transition", "Les produits sont déjà récupérés.")
		}
		return nil
	})
}

// CourierArrivedAtCustomer : le livreur est chez le client (le délai d'attente démarre).
func (s *Service) CourierArrivedAtCustomer(ctx context.Context, driverID, deliveryID uuid.UUID) (CourierMission, error) {
	return s.courierStep(ctx, driverID, deliveryID, func(ctx context.Context, d store.PharmacyDelivery) error {
		n, err := s.q(ctx).SetDeliveryArrivedCustomer(ctx, d.ID)
		if err != nil {
			return fmt.Errorf("arrivée chez le client : %w", err)
		}
		if n == 0 {
			return apperr.Conflict("invalid_transition", "Récupérez d'abord les produits à la pharmacie.")
		}
		return nil
	})
}

// CourierFail : client injoignable après 10 minutes et deux appels ; le livreur rapporte les
// produits à la pharmacie.
func (s *Service) CourierFail(ctx context.Context, driverID, deliveryID uuid.UUID, reason string, callAttempts int32) (CourierMission, error) {
	reason = validate.Clean(reason)
	if reason == "" {
		reason = "Client absent ou injoignable."
	}
	v := validate.New()
	v.Text("reason", reason, 3, 300)
	if err := v.Err(); err != nil {
		return CourierMission{}, err
	}
	return s.courierStep(ctx, driverID, deliveryID, func(ctx context.Context, d store.PharmacyDelivery) error {
		if d.Status != "picked_up" || d.ArrivedCustomerAt == nil {
			return apperr.Conflict("not_at_customer", "Signalez d'abord votre arrivée chez le client.")
		}
		if wait := time.Since(*d.ArrivedCustomerAt); wait < courierMinWait {
			return apperr.Conflict("wait_required", fmt.Sprintf("Attendez encore %d minute(s) avant de déclarer l'échec.", int((courierMinWait-wait).Minutes())+1))
		}
		if callAttempts < courierMinCalls {
			return apperr.Validation(map[string]string{"call_attempts": "Appelez le client au moins deux fois avant de déclarer l'échec."})
		}
		q := s.q(ctx)
		n, err := q.SetDeliveryFailed(ctx, store.SetDeliveryFailedParams{ID: d.ID, Reason: reason, CallAttempts: callAttempts})
		if err != nil {
			return fmt.Errorf("échec de la livraison : %w", err)
		}
		if n == 0 {
			return apperr.Conflict("invalid_transition", "Cette étape est déjà passée.")
		}
		r, err := q.GetReservation(ctx, d.ReservationID)
		if err != nil {
			return fmt.Errorf("lecture de la réservation : %w", err)
		}
		ph, err := q.GetPharmacy(ctx, r.PharmacyID)
		if err != nil {
			return fmt.Errorf("lecture de la pharmacie : %w", err)
		}
		if err := s.notify.Notify(ctx, notifications.Message{
			UserID: ph.OwnerID, App: notifications.AppPharmacy, Kind: "pharmacy_courier_returning",
			Title: "Produits rapportés", Body: "Le client est injoignable : le livreur vous rapporte les produits.",
			Data: map[string]string{"reservation_id": r.ID.String()},
		}); err != nil {
			return err
		}
		return s.notify.Notify(ctx, notifications.Message{
			UserID: r.BuyerID, App: notifications.AppBuyer, Kind: "pharmacy_delivery_failed",
			Title: "Livraison impossible", Body: "Le livreur n'a pas pu vous joindre : vos produits retournent à la pharmacie.",
			Data: map[string]string{"reservation_id": r.ID.String()},
		})
	})
}

// CourierReturned : produits rendus à la pharmacie. La réservation est annulée, le client est
// remboursé de ses produits (les frais de livraison restent acquis) et le livreur est libéré ;
// les espèces qu'il a avancées lui restent dues.
func (s *Service) CourierReturned(ctx context.Context, driverID, deliveryID uuid.UUID) (CourierMission, error) {
	return s.courierStep(ctx, driverID, deliveryID, func(ctx context.Context, d store.PharmacyDelivery) error {
		q := s.q(ctx)
		n, err := q.SetDeliveryStatus(ctx, store.SetDeliveryStatusParams{ID: d.ID, NewStatus: "returned", FromStatuses: []string{"returning"}})
		if err != nil {
			return fmt.Errorf("retour à la pharmacie : %w", err)
		}
		if n == 0 {
			return apperr.Conflict("invalid_transition", "Cette course n'est pas en retour vers la pharmacie.")
		}
		const reason = "Client injoignable : produits rendus à la pharmacie."
		if _, err := q.SetReservationStatus(ctx, store.SetReservationStatusParams{
			ID: d.ReservationID, NewStatus: ResCancelled, Reason: reason, FromStatuses: []string{ResPickedUp},
		}); err != nil {
			return fmt.Errorf("fin de la réservation : %w", err)
		}
		r, err := q.GetReservation(ctx, d.ReservationID)
		if err != nil {
			return fmt.Errorf("lecture de la réservation : %w", err)
		}
		refunded := int64(0)
		if pay, err := q.SucceededOrderPayment(ctx, &r.ID); err == nil {
			amount := min(r.ItemsXof, pay.AmountXof)
			if err := q.SetPaymentRefundAmount(ctx, store.SetPaymentRefundAmountParams{ID: pay.ID, AmountXof: &amount}); err != nil {
				return fmt.Errorf("montant du remboursement : %w", err)
			}
			if err := s.startRefund(ctx, nil, pay, reason); err != nil {
				return err
			}
			refunded = amount
		}
		if err := s.drivers.ReleaseFromErrand(ctx, driverID); err != nil {
			return err
		}
		ph, err := q.GetPharmacy(ctx, r.PharmacyID)
		if err != nil {
			return fmt.Errorf("lecture de la pharmacie : %w", err)
		}
		if err := s.notify.Notify(ctx, notifications.Message{
			UserID: ph.OwnerID, App: notifications.AppPharmacy, Kind: "pharmacy_courier_returned",
			Title: "Produits rendus", Body: "Le livreur indique vous avoir rendu les produits : vérifiez-les et remettez-les en rayon.",
			Data: map[string]string{"reservation_id": r.ID.String()},
		}); err != nil {
			return err
		}
		body := "Vos produits sont retournés à la pharmacie."
		if refunded > 0 {
			body = fmt.Sprintf("Vos produits sont retournés à la pharmacie : %d FCFA vous sont remboursés, hors frais de livraison.", refunded)
		}
		if err := s.notify.Notify(ctx, notifications.Message{
			UserID: r.BuyerID, App: notifications.AppBuyer, Kind: "pharmacy_reservation_cancelled",
			Title: "Commande annulée", Body: body,
			Data: map[string]string{"reservation_id": r.ID.String(), "alert_id": r.AlertID.String()},
		}); err != nil {
			return err
		}
		return s.notify.NotifyAdmins(ctx, "pharmacy_courier_returned", "Course pharmacie rapportée",
			"Client injoignable : produits rendus à la pharmacie, espèces avancées dues au livreur.",
			map[string]string{"reservation_id": r.ID.String(), "delivery_id": d.ID.String()})
	})
}

// courierStep verrouille la course du livreur, applique l'étape puis renvoie la course à jour.
func (s *Service) courierStep(ctx context.Context, driverID, deliveryID uuid.UUID, step func(context.Context, store.PharmacyDelivery) error) (CourierMission, error) {
	err := s.db.InTx(ctx, func(ctx context.Context) error {
		d, err := s.ownMission(ctx, driverID, deliveryID)
		if err != nil {
			return err
		}
		return step(ctx, d)
	})
	if err != nil {
		return CourierMission{}, err
	}
	return s.missionView(ctx, deliveryID)
}
