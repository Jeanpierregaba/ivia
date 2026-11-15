package delivery

import (
	"context"
	"fmt"
	"time"

	"github.com/google/uuid"

	"ivia/backend/internal/admin"
	"ivia/backend/internal/delivery/store"
)

// ExportRow est le bilan d'un livreur sur une période (base de la paie, faite hors application).
type ExportRow struct {
	DriverID         uuid.UUID `json:"driver_id"`
	FirstName        string    `json:"first_name"`
	VehicleType      string    `json:"vehicle_type"`
	Delivered        int64     `json:"delivered"`
	Failed           int64     `json:"failed"`
	Withdrawn        int64     `json:"withdrawn"`
	DeliveredFeesXOF int64     `json:"delivered_fees_xof"`
}

// Export compte les missions de chaque livreur sur [from, to).
func (s *Service) Export(ctx context.Context, from, to time.Time) ([]ExportRow, error) {
	q := store.New(s.db.Conn(ctx))
	rows, err := q.ExportDeliveries(ctx, store.ExportDeliveriesParams{FromTime: from, ToTime: to})
	if err != nil {
		return nil, fmt.Errorf("export des livraisons : %w", err)
	}
	out := make([]ExportRow, len(rows))
	for i, r := range rows {
		c, err := s.users.Contact(ctx, r.DriverID)
		if err != nil {
			return nil, err
		}
		d, err := q.GetDriver(ctx, r.DriverID)
		if err != nil {
			return nil, fmt.Errorf("lecture du livreur : %w", err)
		}
		out[i] = ExportRow{
			DriverID: r.DriverID, FirstName: c.FirstName, VehicleType: d.VehicleType,
			Delivered: r.Delivered, Failed: r.Failed, Withdrawn: r.Withdrawn, DeliveredFeesXOF: r.DeliveredFeesXof,
		}
	}
	return out, nil
}

// Alert est une commande pour laquelle aucun livreur n'a été trouvé à temps.
type Alert struct {
	OrderID     uuid.UUID `json:"order_id"`
	StartedAt   time.Time `json:"started_at"`
	OffersCount int32     `json:"offers_count"`
	AlertedAt   time.Time `json:"alerted_at"`
}

// Alerts liste les recherches de livreur en échec non résolues.
func (s *Service) Alerts(ctx context.Context) ([]Alert, error) {
	rows, err := store.New(s.db.Conn(ctx)).ListAlerts(ctx)
	if err != nil {
		return nil, fmt.Errorf("alertes d'attribution : %w", err)
	}
	out := make([]Alert, len(rows))
	for i, r := range rows {
		out[i] = Alert{OrderID: r.OrderID, StartedAt: r.StartedAt, OffersCount: r.OffersCount, AlertedAt: *r.AlertedAt}
	}
	return out, nil
}

// Metrics regroupe les indicateurs d'attribution.
type Metrics struct {
	Assigned               int64   `json:"assigned"`
	AssignedWithin10MinPct float64 `json:"assigned_within_10_min_pct"`
	MedianAssignmentMin    float64 `json:"median_assignment_minutes"`
}

// MetricsBetween calcule les indicateurs d'attribution des missions de [from, to).
func (s *Service) MetricsBetween(ctx context.Context, from, to time.Time) (Metrics, error) {
	r, err := store.New(s.db.Conn(ctx)).AssignmentMetrics(ctx, store.AssignmentMetricsParams{FromTime: from, ToTime: to})
	if err != nil {
		return Metrics{}, fmt.Errorf("indicateurs d'attribution : %w", err)
	}
	m := Metrics{Assigned: r.Assigned, MedianAssignmentMin: r.MedianAssignmentS / 60}
	if r.Assigned > 0 {
		m.AssignedWithin10MinPct = float64(r.AssignedWithin10Min) * 100 / float64(r.Assigned)
	}
	return m, nil
}

func adminAudit(adminID uuid.UUID, action string, orderID, driverID uuid.UUID, reason string) admin.AuditEntry {
	return admin.AuditEntry{
		AdminID: &adminID, Action: action, TargetType: "order", TargetID: orderID.String(),
		Before: map[string]any{"driver_id": driverID}, Reason: reason,
	}
}

// DriverOverview : livreurs maintenant (tableau de bord).
type DriverOverview struct {
	Available     int64 `json:"available"`
	Busy          int64 `json:"busy"`
	Offline       int64 `json:"offline"`
	Suspended     int64 `json:"suspended"`
	PendingReview int64 `json:"pending_review"`
}

// Overview retourne la répartition des livreurs et les dossiers à valider.
func (s *Service) Overview(ctx context.Context) (DriverOverview, error) {
	r, err := store.New(s.db.Conn(ctx)).DriverOverview(ctx)
	if err != nil {
		return DriverOverview{}, fmt.Errorf("répartition des livreurs : %w", err)
	}
	return DriverOverview{Available: r.Available, Busy: r.Busy, Offline: r.Offline, Suspended: r.Suspended, PendingReview: r.PendingReview}, nil
}
