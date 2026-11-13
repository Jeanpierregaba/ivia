package delivery

import (
	"context"
	"fmt"
	"net/http"
	"time"

	"github.com/google/uuid"

	"ivia/backend/internal/delivery/store"
	"ivia/backend/internal/platform/database"
	"ivia/backend/internal/platform/httpapi"
)

// FleetDriver est un livreur sur la carte de la flotte (back-office).
type FleetDriver struct {
	ID             uuid.UUID `json:"id"`
	FirstName      string    `json:"first_name"`
	Phone          string    `json:"phone"`
	Availability   string    `json:"availability"`
	VehicleType    string    `json:"vehicle_type"`
	VehiclePlate   string    `json:"vehicle_plate"`
	Suspended      bool      `json:"suspended"`
	Lat            float64   `json:"lat"`
	Lng            float64   `json:"lng"`
	LocatedAt      time.Time `json:"located_at"`
	MissionOrderID *string   `json:"mission_order_id"`
	MissionStatus  string    `json:"mission_status"`
}

// TrailPoint est une position du trajet d'un livreur.
type TrailPoint struct {
	Lat        float64   `json:"lat"`
	Lng        float64   `json:"lng"`
	RecordedAt time.Time `json:"recorded_at"`
}

// Fleet liste les livreurs validés vus depuis moins de hours heures, avec leur dernière position
// et leur mission en cours (carte en direct du back-office).
func (s *Service) Fleet(ctx context.Context, hours int) ([]FleetDriver, error) {
	rows, err := store.New(s.db.Conn(ctx)).Fleet(ctx, int32(hours))
	if err != nil {
		return nil, fmt.Errorf("flotte : %w", err)
	}
	out := make([]FleetDriver, 0, len(rows))
	for _, r := range rows {
		c, err := s.users.Contact(ctx, r.UserID)
		if err != nil {
			return nil, err
		}
		f := FleetDriver{
			ID: r.UserID, FirstName: c.FirstName, Phone: c.Phone, Availability: r.Availability,
			VehicleType: r.VehicleType, VehiclePlate: r.VehiclePlate, Suspended: r.Suspended,
			Lat: r.Lat, Lng: r.Lng, LocatedAt: r.LocatedAt, MissionStatus: r.MissionStatus,
		}
		if r.MissionOrderID != "" {
			f.MissionOrderID = &r.MissionOrderID
		}
		out = append(out, f)
	}
	return out, nil
}

// Trail retourne le trajet récent d'un livreur (positions envoyées en ligne).
func (s *Service) Trail(ctx context.Context, driverID uuid.UUID, hours int) ([]TrailPoint, error) {
	rows, err := store.New(s.db.Conn(ctx)).DriverTrail(ctx, store.DriverTrailParams{DriverID: driverID, Hours: int32(hours)})
	if err != nil {
		return nil, fmt.Errorf("trajet : %w", err)
	}
	out := make([]TrailPoint, len(rows))
	for i, r := range rows {
		out[i] = TrailPoint{Lat: r.Lat, Lng: r.Lng, RecordedAt: r.RecordedAt}
	}
	return out, nil
}

// DeliveredBy retourne le livreur qui a livré la commande ; nil si elle n'a pas été livrée par
// un livreur (avis, spec 035).
func (s *Service) DeliveredBy(ctx context.Context, orderID uuid.UUID) (*uuid.UUID, error) {
	m, err := store.New(s.db.Conn(ctx)).LatestDeliveryForOrder(ctx, orderID)
	if database.IsNoRows(err) {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("mission : %w", err)
	}
	if m.DeliveredAt == nil {
		return nil, nil
	}
	return &m.DriverID, nil
}

func (h *Handler) fleet(w http.ResponseWriter, r *http.Request) error {
	q := httpapi.NewQuery(r)
	hours := q.Int64("hours", 1, 168)
	if err := q.Err(); err != nil {
		return err
	}
	n := 24
	if hours != nil {
		n = int(*hours)
	}
	items, err := h.svc.Fleet(r.Context(), n)
	if err != nil {
		return err
	}
	return httpapi.OK(w, map[string]any{"items": items, "generated_at": time.Now().UTC()})
}

func (h *Handler) trail(w http.ResponseWriter, r *http.Request) error {
	id, err := httpapi.PathUUID(r, "id")
	if err != nil {
		return err
	}
	q := httpapi.NewQuery(r)
	hours := q.Int64("hours", 1, 168)
	if err := q.Err(); err != nil {
		return err
	}
	n := 6
	if hours != nil {
		n = int(*hours)
	}
	items, err := h.svc.Trail(r.Context(), id, n)
	if err != nil {
		return err
	}
	return httpapi.OK(w, map[string]any{"items": items})
}
