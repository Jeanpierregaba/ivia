package pharmacy

import (
	"context"
	"fmt"
	"time"

	"github.com/google/uuid"

	"ivia/backend/internal/pharmacy/store"
)

// OwnsCourierMission indique si la course pharmacie est celle du livreur (signalements).
func (s *Service) OwnsCourierMission(ctx context.Context, driverID, missionID uuid.UUID) (bool, error) {
	ok, err := s.q(ctx).CourierMissionOwnedBy(ctx, store.CourierMissionOwnedByParams{ID: missionID, DriverID: driverID})
	if err != nil {
		return false, fmt.Errorf("course du livreur : %w", err)
	}
	return ok, nil
}

// DriverPharmacyTotals : gains des courses pharmacie livrées et espèces avancées aux pharmacies par
// un livreur sur une période (delivery.PharmacyEarnings).
func (s *Service) DriverPharmacyTotals(ctx context.Context, driverID uuid.UUID, since, until time.Time) (int64, int64, error) {
	r, err := s.q(ctx).DriverPharmacyTotals(ctx, store.DriverPharmacyTotalsParams{DriverID: driverID, Since: &since, Until: &until})
	if err != nil {
		return 0, 0, fmt.Errorf("courses pharmacie du livreur : %w", err)
	}
	return r.FeesXof, r.CashXof, nil
}
