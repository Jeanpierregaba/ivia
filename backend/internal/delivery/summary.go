package delivery

import (
	"context"
	"fmt"
	"time"

	"github.com/google/uuid"

	"ivia/backend/internal/delivery/store"
)

// PharmacyEarnings lit, dans le module pharmacie, les courses livrées et les espèces avancées
// par un livreur sur une période.
type PharmacyEarnings interface {
	DriverPharmacyTotals(ctx context.Context, driverID uuid.UUID, since, until time.Time) (feesXOF, cashXOF int64, err error)
}

// SetPharmacyEarnings branche le module pharmacie (assemblage de l'app).
func (s *Service) SetPharmacyEarnings(p PharmacyEarnings) { s.pharmacy = p }

// Period est un total sur une période.
type Period struct {
	EarningsXOF   int64 `json:"earnings_xof"`
	OnlineSeconds int64 `json:"online_seconds"`
	DistanceM     int64 `json:"distance_m"`
}

// NextPayout est le prochain versement, chaque lundi pour la semaine écoulée (lundi à dimanche,
// heure de Lomé) : gains des courses livrées et espèces avancées aux pharmacies. Estimation : le
// versement réel est fait par l'équipe ivia.
type NextPayout struct {
	Date        string `json:"date"`
	PeriodStart string `json:"period_start"`
	PeriodEnd   string `json:"period_end"`
	EarningsXOF int64  `json:"earnings_xof"`
	CashXOF     int64  `json:"cash_advanced_xof"`
	AmountXOF   int64  `json:"amount_xof"`
}

// Summary est le tableau de bord du livreur.
type Summary struct {
	Today      Period     `json:"today"`
	Week       Period     `json:"week"`
	Month      Period     `json:"month"`
	NextPayout NextPayout `json:"next_payout"`
}

// startOfWeek : lundi 0 h, heure de Lomé.
func startOfWeek(t time.Time) time.Time {
	d := time.Date(t.Year(), t.Month(), t.Day(), 0, 0, 0, 0, Lome)
	return d.AddDate(0, 0, -((int(d.Weekday()) + 6) % 7))
}

// Summary calcule gains, temps en ligne et distance du jour, de la semaine et du mois, et le
// prochain versement.
func (s *Service) Summary(ctx context.Context, driverID uuid.UUID) (Summary, error) {
	if _, err := s.requireActiveDriver(ctx, driverID); err != nil {
		return Summary{}, err
	}
	now := time.Now().In(Lome)
	day := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, Lome)
	week := startOfWeek(now)
	month := time.Date(now.Year(), now.Month(), 1, 0, 0, 0, 0, Lome)
	var out Summary
	var weekCash int64
	for _, p := range []struct {
		since time.Time
		dst   *Period
		cash  *int64
	}{{day, &out.Today, nil}, {week, &out.Week, &weekCash}, {month, &out.Month, nil}} {
		v, cash, err := s.period(ctx, driverID, p.since, now)
		if err != nil {
			return Summary{}, err
		}
		*p.dst = v
		if p.cash != nil {
			*p.cash = cash
		}
	}
	payday := week.AddDate(0, 0, 7)
	out.NextPayout = NextPayout{
		Date: payday.Format(time.DateOnly), PeriodStart: week.Format(time.DateOnly),
		PeriodEnd: payday.AddDate(0, 0, -1).Format(time.DateOnly), EarningsXOF: out.Week.EarningsXOF,
		CashXOF: weekCash, AmountXOF: out.Week.EarningsXOF + weekCash,
	}
	return out, nil
}

func (s *Service) period(ctx context.Context, driverID uuid.UUID, since, until time.Time) (Period, int64, error) {
	q := store.New(s.db.Conn(ctx))
	fees, err := q.DriverFeesBetween(ctx, store.DriverFeesBetweenParams{DriverID: driverID, Since: &since, Until: &until})
	if err != nil {
		return Period{}, 0, fmt.Errorf("gains du livreur : %w", err)
	}
	online, err := q.DriverOnlineSecondsBetween(ctx, store.DriverOnlineSecondsBetweenParams{DriverID: driverID, Since: since, Until: until})
	if err != nil {
		return Period{}, 0, fmt.Errorf("temps en ligne : %w", err)
	}
	dist, err := q.DriverDistanceBetween(ctx, store.DriverDistanceBetweenParams{DriverID: driverID, Since: since, Until: until})
	if err != nil {
		return Period{}, 0, fmt.Errorf("distance parcourue : %w", err)
	}
	var cash int64
	if s.pharmacy != nil {
		pf, pc, err := s.pharmacy.DriverPharmacyTotals(ctx, driverID, since, until)
		if err != nil {
			return Period{}, 0, err
		}
		fees += pf
		cash = pc
	}
	return Period{EarningsXOF: fees, OnlineSeconds: online, DistanceM: int64(dist + 0.5)}, cash, nil
}
