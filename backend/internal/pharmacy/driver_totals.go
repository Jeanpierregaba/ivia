package pharmacy

import (
	"context"
	"fmt"
	"time"

	"github.com/google/uuid"

	"ivia/backend/internal/pharmacy/store"
)

// DriverPharmacyTotals : gains des courses pharmacie livrées et espèces avancées aux pharmacies par
// un livreur sur une période (delivery.PharmacyEarnings).
func (s *Service) DriverPharmacyTotals(ctx context.Context, driverID uuid.UUID, since, until time.Time) (int64, int64, error) {
	r, err := s.q(ctx).DriverPharmacyTotals(ctx, store.DriverPharmacyTotalsParams{DriverID: driverID, Since: &since, Until: &until})
	if err != nil {
		return 0, 0, fmt.Errorf("courses pharmacie du livreur : %w", err)
	}
	return r.FeesXof, r.CashXof, nil
}
