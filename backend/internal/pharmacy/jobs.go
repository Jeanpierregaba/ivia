package pharmacy

import (
	"context"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/riverqueue/river"

	"ivia/backend/internal/pharmacy/store"
	"ivia/backend/internal/platform/apperr"
	"ivia/backend/internal/platform/jobs"
	"ivia/backend/internal/uploads"
)

// WidenArgs : élargissement de la recherche si les réponses manquent.
type WidenArgs struct {
	AlertID uuid.UUID `json:"alert_id"`
}

// Kind implémente river.JobArgs.
func (WidenArgs) Kind() string { return "pharmacy.widen" }

// CloseSearchArgs : fin de la fenêtre de réponse d'une alerte.
type CloseSearchArgs struct {
	AlertID uuid.UUID `json:"alert_id"`
}

// Kind implémente river.JobArgs.
func (CloseSearchArgs) Kind() string { return "pharmacy.close_search" }

// ExpireReservationArgs : retrait non effectué ou livraison non payée dans le délai.
type ExpireReservationArgs struct {
	ReservationID uuid.UUID `json:"reservation_id"`
}

// Kind implémente river.JobArgs.
func (ExpireReservationArgs) Kind() string { return "pharmacy.expire_reservation" }

// AssignCourierArgs : recherche d'un livreur pour une livraison payée.
type AssignCourierArgs struct {
	ReservationID uuid.UUID `json:"reservation_id"`
}

// Kind implémente river.JobArgs.
func (AssignCourierArgs) Kind() string { return "pharmacy.assign_courier" }

// CourierOfferTimeoutArgs : fin du délai de réponse d'une proposition de course.
type CourierOfferTimeoutArgs struct {
	OfferID uuid.UUID `json:"offer_id"`
}

// Kind implémente river.JobArgs.
func (CourierOfferTimeoutArgs) Kind() string { return "pharmacy.courier_offer_timeout" }

// RecheckPaymentsArgs : revérification périodique des paiements en attente.
type RecheckPaymentsArgs struct{}

// Kind implémente river.JobArgs.
func (RecheckPaymentsArgs) Kind() string { return "pharmacy.recheck_payments" }

// RefundArgs : exécution d'un remboursement.
type RefundArgs struct {
	PaymentID uuid.UUID `json:"payment_id"`
}

// Kind implémente river.JobArgs.
func (RefundArgs) Kind() string { return "pharmacy.refund" }

// PurgePhotosArgs : suppression horaire des photos d'ordonnance et de boîte arrivées à échéance.
type PurgePhotosArgs struct{}

// Kind implémente river.JobArgs.
func (PurgePhotosArgs) Kind() string { return "pharmacy.purge_photos" }

type worker[T river.JobArgs] struct {
	river.WorkerDefaults[T]
	fn func(ctx context.Context, args T) error
}

func (w *worker[T]) Work(ctx context.Context, job *river.Job[T]) error { return w.fn(ctx, job.Args) }

func add[T river.JobArgs](reg *jobs.Registry, fn func(ctx context.Context, args T) error) {
	river.AddWorker(reg.Workers, &worker[T]{fn: fn})
}

// RegisterJobs déclare les tâches de fond du module.
func (s *Service) RegisterJobs(reg *jobs.Registry) {
	add(reg, func(ctx context.Context, a WidenArgs) error { return s.widen(ctx, a.AlertID) })
	add(reg, func(ctx context.Context, a CloseSearchArgs) error { return s.closeSearch(ctx, a.AlertID) })
	add(reg, func(ctx context.Context, a ExpireReservationArgs) error {
		return s.expireReservation(ctx, a.ReservationID)
	})
	add(reg, func(ctx context.Context, a AssignCourierArgs) error {
		outcome, err := s.assignCourier(ctx, a.ReservationID)
		if err != nil {
			return err
		}
		if outcome == assignNoDriver {
			return river.JobSnooze(retryCourierAfter)
		}
		return nil
	})
	add(reg, func(ctx context.Context, a CourierOfferTimeoutArgs) error {
		return s.expireCourierOffer(ctx, a.OfferID)
	})
	add(reg, func(ctx context.Context, _ RecheckPaymentsArgs) error { return s.Recheck(ctx) })
	add(reg, func(ctx context.Context, a RefundArgs) error { return s.executeRefund(ctx, a.PaymentID) })
	add(reg, func(ctx context.Context, _ PurgePhotosArgs) error { return s.PurgePhotos(ctx) })
	reg.AddPeriodic(2*time.Minute, func() river.JobArgs { return RecheckPaymentsArgs{} })
	reg.AddPeriodic(time.Hour, func() river.JobArgs { return PurgePhotosArgs{} })
}

// PurgePhotos supprime les photos d'alerte (ordonnances, boîtes) plus anciennes que la durée de
// conservation, comptée depuis le lancement de l'alerte (24 h par défaut).
func (s *Service) PurgePhotos(ctx context.Context) error {
	settings, err := s.Settings(ctx)
	if err != nil {
		return err
	}
	before := time.Now().Add(-time.Duration(settings.PhotoRetentionHours) * time.Hour)
	q := s.q(ctx)
	rows, err := q.AlertPhotosDue(ctx, before)
	if err != nil {
		return fmt.Errorf("photos à supprimer : %w", err)
	}
	for _, r := range rows {
		if err := s.purgeAlertPhoto(ctx, r.ID, r.ObjectKey); err != nil {
			return err
		}
	}
	// Photos des alertes antérieures à 00028 (une photo par alerte).
	legacy, err := q.AlertPhotosToPurge(ctx, &before)
	if err != nil {
		return fmt.Errorf("photos à supprimer : %w", err)
	}
	for _, r := range legacy {
		if err := s.purgePhoto(ctx, r.ID, r.PhotoKey); err != nil {
			return err
		}
	}
	return nil
}

func (s *Service) purgeAlertPhoto(ctx context.Context, photoID uuid.UUID, key *string) error {
	if key != nil {
		if err := s.uploads.Delete(ctx, uploads.PharmacyAlertPhoto, *key); err != nil {
			return err
		}
	}
	if err := s.q(ctx).MarkAlertPhotoPurged(ctx, photoID); err != nil {
		return fmt.Errorf("photo supprimée : %w", err)
	}
	return nil
}

func (s *Service) purgePhoto(ctx context.Context, alertID uuid.UUID, key *string) error {
	if key != nil {
		if err := s.uploads.Delete(ctx, uploads.PharmacyAlertPhoto, *key); err != nil {
			return err
		}
	}
	if err := s.q(ctx).MarkPhotoPurged(ctx, alertID); err != nil {
		return fmt.Errorf("photo supprimée : %w", err)
	}
	return nil
}

// CheckAccountDeletable refuse la suppression d'un compte avec une livraison payée en cours
// (client ou titulaire de pharmacie) : users.DeletionGuard.
func (s *Service) CheckAccountDeletable(ctx context.Context, userID uuid.UUID) error {
	n, err := s.q(ctx).CountActiveReservationsOf(ctx, userID)
	if err != nil {
		return fmt.Errorf("réservations en cours : %w", err)
	}
	if n > 0 {
		return apperr.Conflict("pharmacy_delivery_in_progress", "Une livraison de médicament payée est en cours : attendez sa fin.")
	}
	return nil
}

// OnAccountDeleted efface les photos d'alerte du client ; pour un titulaire, suspend la pharmacie
// et efface ses pièces (users.DeletionHook).
func (s *Service) OnAccountDeleted(ctx context.Context, userID uuid.UUID) error {
	q := s.q(ctx)
	photos, err := q.BuyerPhotoKeys(ctx, userID)
	if err != nil {
		return fmt.Errorf("photos du client : %w", err)
	}
	for _, p := range photos {
		if err := s.purgePhoto(ctx, p.ID, p.PhotoKey); err != nil {
			return err
		}
	}
	current, err := q.BuyerAlertPhotos(ctx, userID)
	if err != nil {
		return fmt.Errorf("photos du client : %w", err)
	}
	for _, p := range current {
		if err := s.purgeAlertPhoto(ctx, p.ID, p.ObjectKey); err != nil {
			return err
		}
	}
	id, err := s.pharmacyIDOf(ctx, userID)
	if apperr.IsCode(err, "pharmacy_not_found") {
		return nil
	}
	if err != nil {
		return err
	}
	if _, err := q.Suspend(ctx, store.SuspendParams{ID: id, Reason: "Compte du titulaire supprimé."}); err != nil {
		return fmt.Errorf("suspension de la pharmacie : %w", err)
	}
	docs, err := q.ListDocuments(ctx, id)
	if err != nil {
		return fmt.Errorf("pièces de la pharmacie : %w", err)
	}
	for _, d := range docs {
		if err := s.uploads.Delete(ctx, uploads.PharmacyDocument, d.ObjectKey); err != nil {
			return err
		}
	}
	return q.DeleteDocumentsOf(ctx, id)
}
