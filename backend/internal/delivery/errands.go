package delivery

import (
	"context"
	"errors"
	"fmt"

	"github.com/google/uuid"

	"ivia/backend/internal/delivery/store"
	"ivia/backend/internal/platform/apperr"
	"ivia/backend/internal/platform/database"
)

// Courses confiées par d'autres modules (livraison de médicaments, module pharmacy). Le module
// propriétaire tient ses propositions et ses missions ; delivery ne gère que la disponibilité du
// livreur : occupé (busy) pendant la course, il ne reçoit aucune commande (AcceptOffer et
// FindNearestDriver exigent available), et inversement.

// ErrNoErrandDriver : aucun livreur disponible dans le rayon.
var ErrNoErrandDriver = errors.New("aucun livreur disponible")

// NearestErrandDriver retourne le livreur à moto disponible le plus proche du point (lat, lng),
// hors exclude. À appeler dans la transaction qui crée la proposition (SKIP LOCKED).
func (s *Service) NearestErrandDriver(ctx context.Context, lat, lng float64, exclude []uuid.UUID) (uuid.UUID, int32, error) {
	if exclude == nil {
		exclude = []uuid.UUID{}
	}
	d, err := store.New(s.db.Conn(ctx)).FindErrandDriver(ctx, store.FindErrandDriverParams{
		Lat: lat, Lng: lng, MaxDistanceM: MaxDriverDistanceM, Exclude: exclude,
	})
	if database.IsNoRows(err) {
		return uuid.Nil, 0, ErrNoErrandDriver
	}
	if err != nil {
		return uuid.Nil, 0, fmt.Errorf("recherche d'un livreur : %w", err)
	}
	return d.UserID, int32(d.DistanceM + 0.5), nil
}

// ClaimForErrand réserve le livreur pour une course : il doit être validé, en ligne, sans
// proposition ni mission de commande. Il passe occupé.
func (s *Service) ClaimForErrand(ctx context.Context, driverID uuid.UUID) error {
	return s.db.InTx(ctx, func(ctx context.Context) error {
		if _, err := s.requireActiveDriver(ctx, driverID); err != nil {
			return err
		}
		q := store.New(s.db.Conn(ctx))
		cur, err := q.LockDriver(ctx, driverID)
		if err != nil {
			return fmt.Errorf("verrou du livreur : %w", err)
		}
		if cur != Available {
			return apperr.Conflict("driver_not_available", "Passez en ligne et terminez votre mission en cours pour accepter cette course.")
		}
		busy, err := q.HasPendingOfferOrActiveDelivery(ctx, driverID)
		if err != nil {
			return fmt.Errorf("missions en cours : %w", err)
		}
		if busy {
			return apperr.Conflict("driver_not_available", "Vous avez déjà une mission proposée ou en cours.")
		}
		return q.SetAvailability(ctx, store.SetAvailabilityParams{UserID: driverID, Availability: Busy})
	})
}

// ReleaseFromErrand remet en ligne un livreur occupé à la fin d'une course.
func (s *Service) ReleaseFromErrand(ctx context.Context, driverID uuid.UUID) error {
	if err := store.New(s.db.Conn(ctx)).ReleaseBusyDriver(ctx, driverID); err != nil {
		return fmt.Errorf("disponibilité du livreur : %w", err)
	}
	return nil
}
