package pharmacy

import (
	"context"
	"fmt"
	"math"
	"time"

	"github.com/google/uuid"

	"ivia/backend/internal/pharmacy/store"
)

// Tableau de bord de la pharmacie (spec 042) : tout vient des alertes, réponses et réservations.

// StatsDay est une journée de la période.
type StatsDay struct {
	Date         string `json:"date"`
	Received     int32  `json:"received"`
	Responded    int32  `json:"responded"`
	Reservations int32  `json:"reservations"`
	SalesXOF     int64  `json:"sales_xof"`
}

// StatsTotals résume une période.
type StatsTotals struct {
	Received       int32 `json:"received"`
	Responded      int32 `json:"responded"`
	ResponseRate   int32 `json:"response_rate"`
	AvgResponseMin int32 `json:"avg_response_min"`
	Reservations   int32 `json:"reservations"`
	Completed      int32 `json:"completed"`
	SalesXOF       int64 `json:"sales_xof"`
}

// StatsMedicine est un des médicaments les plus demandés.
type StatsMedicine struct {
	Name         string `json:"name"`
	Responses    int32  `json:"responses"`
	Reservations int32  `json:"reservations"`
}

// Stats est le tableau de bord d'une pharmacie.
type Stats struct {
	Days         int             `json:"days"`
	Series       []StatsDay      `json:"series"`
	Totals       StatsTotals     `json:"totals"`
	Previous     StatsTotals     `json:"previous"`
	Hours        []int32         `json:"hours"`
	TopMedicines []StatsMedicine `json:"top_medicines"`
}

// PharmacyStats calcule le tableau de bord de la pharmacie du titulaire sur [days] jours
// (aujourd'hui compris), comparé aux [days] jours d'avant.
func (s *Service) PharmacyStats(ctx context.Context, ownerID uuid.UUID, days int) (Stats, error) {
	ph, err := s.requireActivePharmacy(ctx, ownerID)
	if err != nil {
		return Stats{}, err
	}
	now := time.Now().In(lome)
	today := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, lome)
	since := today.AddDate(0, 0, -(days - 1))
	until := today.AddDate(0, 0, 1)
	before := since.AddDate(0, 0, -days)
	q := s.q(ctx)

	alerts, err := q.PharmacyStatsDaily(ctx, store.PharmacyStatsDailyParams{PharmacyID: ph.ID, Since: since, Until: until})
	if err != nil {
		return Stats{}, fmt.Errorf("alertes par jour : %w", err)
	}
	sales, err := q.PharmacyStatsSalesDaily(ctx, store.PharmacyStatsSalesDailyParams{PharmacyID: ph.ID, Since: since, Until: until})
	if err != nil {
		return Stats{}, fmt.Errorf("réservations par jour : %w", err)
	}
	byDay := map[string]*StatsDay{}
	out := Stats{Days: days, Series: make([]StatsDay, days), Hours: make([]int32, 24), TopMedicines: []StatsMedicine{}}
	for i := range days {
		out.Series[i] = StatsDay{Date: since.AddDate(0, 0, i).Format(time.DateOnly)}
		byDay[out.Series[i].Date] = &out.Series[i]
	}
	for _, a := range alerts {
		if d := byDay[a.Day.Format(time.DateOnly)]; d != nil {
			d.Received, d.Responded = a.Received, a.Responded
		}
	}
	for _, v := range sales {
		if d := byDay[v.Day.Format(time.DateOnly)]; d != nil {
			d.Reservations, d.SalesXOF = v.Reservations, v.SalesXof
		}
	}

	totals := func(from, to time.Time) (StatsTotals, error) {
		t, err := q.PharmacyStatsTotals(ctx, store.PharmacyStatsTotalsParams{PharmacyID: ph.ID, Since: from, Until: to})
		if err != nil {
			return StatsTotals{}, fmt.Errorf("totaux : %w", err)
		}
		out := StatsTotals{
			Received: t.Received, Responded: t.Responded, AvgResponseMin: int32(math.Round(t.AvgResponseMin)),
			Reservations: t.Reservations, Completed: t.Completed, SalesXOF: t.SalesXof,
		}
		if t.Received > 0 {
			out.ResponseRate = int32(math.Round(float64(t.Responded) * 100 / float64(t.Received)))
		}
		return out, nil
	}
	if out.Totals, err = totals(since, until); err != nil {
		return Stats{}, err
	}
	if out.Previous, err = totals(before, since); err != nil {
		return Stats{}, err
	}

	hours, err := q.PharmacyStatsHourly(ctx, store.PharmacyStatsHourlyParams{PharmacyID: ph.ID, Since: since, Until: until})
	if err != nil {
		return Stats{}, fmt.Errorf("heures : %w", err)
	}
	for _, h := range hours {
		if h.Hour >= 0 && h.Hour < 24 {
			out.Hours[h.Hour] = h.Received
		}
	}
	top, err := q.PharmacyStatsTopMedicines(ctx, store.PharmacyStatsTopMedicinesParams{PharmacyID: ph.ID, Since: since, Until: until})
	if err != nil {
		return Stats{}, fmt.Errorf("médicaments : %w", err)
	}
	for _, m := range top {
		out.TopMedicines = append(out.TopMedicines, StatsMedicine{Name: m.Name, Responses: m.Responses, Reservations: m.Reservations})
	}
	return out, nil
}
