package promo

import (
	"cmp"
	"context"
	"fmt"
	"slices"
	"time"

	"github.com/google/uuid"

	"ivia/backend/internal/promo/store"
)

// Stats : performance de la publicité sur une période.
type Stats struct {
	From string `json:"from"`
	To   string `json:"to"`
	// Totaux : affichages, fermetures, clics (commander, voir le produit, site officiel),
	// commandes déclarées par les apps après un clic, sessions touchées.
	Impressions   int64   `json:"impressions"`
	Dismissals    int64   `json:"dismissals"`
	OrderClicks   int64   `json:"order_clicks"`
	ProductClicks int64   `json:"product_clicks"`
	SiteClicks    int64   `json:"site_clicks"`
	Orders        int64   `json:"orders"`
	Sessions      int64   `json:"sessions"`
	CTRPct        float64 `json:"ctr_pct"`
	ConversionPct float64 `json:"conversion_pct"`

	PerDay   []DayStats     `json:"per_day"`
	Visuals  []VisualStats  `json:"visuals"`
	Products []ProductStats `json:"products"`
}

// DayStats : affichages et clics d'un jour (dates de Lomé).
type DayStats struct {
	Day         string `json:"day"`
	Impressions int64  `json:"impressions"`
	Clicks      int64  `json:"clicks"`
}

// VisualStats : performance d'un visuel (campagne).
type VisualStats struct {
	VisualID    uuid.UUID `json:"visual_id"`
	Title       string    `json:"title"`
	Kind        string    `json:"kind"`
	Live        bool      `json:"live"`
	Impressions int64     `json:"impressions"`
	Dismissals  int64     `json:"dismissals"`
	Clicks      int64     `json:"clicks"`
	SiteClicks  int64     `json:"site_clicks"`
	Orders      int64     `json:"orders"`
	CTRPct      float64   `json:"ctr_pct"`
}

// ProductStats : performance d'un produit mis en avant ou promu. Les ventes viennent des
// commandes payées (toutes origines), les autres chiffres des événements publicitaires.
type ProductStats struct {
	ProductID    uuid.UUID `json:"product_id"`
	Name         string    `json:"name"`
	Impressions  int64     `json:"impressions"`
	Views        int64     `json:"views"`
	OrderClicks  int64     `json:"order_clicks"`
	AdOrders     int64     `json:"ad_orders"`
	PaidOrders   int64     `json:"paid_orders"`
	UnitsSold    int64     `json:"units_sold"`
	RevenueXOF   int64     `json:"revenue_xof"`
	FeaturedRank *int32    `json:"featured_rank"`
}

func pct(n, d int64) float64 {
	if d == 0 {
		return 0
	}
	return float64(n) * 100 / float64(d)
}

// Stats calcule les statistiques sur [from, to).
func (s *Service) Stats(ctx context.Context, from, to time.Time) (Stats, error) {
	q := store.New(s.db.Conn(ctx))
	since, until := from, to
	out := Stats{From: from.Format(time.DateOnly), To: to.AddDate(0, 0, -1).Format(time.DateOnly),
		PerDay: []DayStats{}, Visuals: []VisualStats{}, Products: []ProductStats{}}

	totals, err := q.EventTotals(ctx, store.EventTotalsParams{Since: since, Until: until})
	if err != nil {
		return out, fmt.Errorf("totaux publicitaires : %w", err)
	}
	for _, t := range totals {
		switch t.Kind {
		case "impression":
			out.Impressions, out.Sessions = t.Events, t.Sessions
		case "dismiss":
			out.Dismissals = t.Events
		case "click_order":
			out.OrderClicks = t.Events
		case "click_product":
			out.ProductClicks = t.Events
		case "click_site":
			out.SiteClicks = t.Events
		case "order":
			out.Orders = t.Events
		}
	}
	clicks := out.OrderClicks + out.ProductClicks + out.SiteClicks
	out.CTRPct, out.ConversionPct = pct(clicks, out.Impressions), pct(out.Orders, clicks)

	days, err := q.EventsPerDay(ctx, store.EventsPerDayParams{Since: since, Until: until})
	if err != nil {
		return out, fmt.Errorf("publicité par jour : %w", err)
	}
	for _, d := range days {
		out.PerDay = append(out.PerDay, DayStats{Day: d.Day.Format(time.DateOnly), Impressions: d.Impressions, Clicks: d.Clicks})
	}

	visuals, err := s.ListVisuals(ctx)
	if err != nil {
		return out, err
	}
	byVisual, err := q.EventsByVisual(ctx, store.EventsByVisualParams{Since: since, Until: until})
	if err != nil {
		return out, fmt.Errorf("publicité par visuel : %w", err)
	}
	vs := map[uuid.UUID]store.EventsByVisualRow{}
	for _, r := range byVisual {
		vs[r.VisualID] = r
	}
	for _, v := range visuals {
		r := vs[v.ID]
		out.Visuals = append(out.Visuals, VisualStats{
			VisualID: v.ID, Title: v.Title, Kind: v.Kind, Live: v.Live, Impressions: r.Impressions,
			Dismissals: r.Dismissals, Clicks: r.Clicks, SiteClicks: r.SiteClicks, Orders: r.Orders,
			CTRPct: pct(r.Clicks, r.Impressions),
		})
	}
	slices.SortStableFunc(out.Visuals, func(a, b VisualStats) int { return cmp.Compare(b.Impressions, a.Impressions) })

	byProduct, err := q.EventsByProduct(ctx, store.EventsByProductParams{Since: since, Until: until})
	if err != nil {
		return out, fmt.Errorf("publicité par produit : %w", err)
	}
	// Produits suivis : mis en avant, promus, liés à un visuel, ou cités dans les événements.
	ids := []uuid.UUID{}
	add := func(id uuid.UUID) {
		if !slices.Contains(ids, id) {
			ids = append(ids, id)
		}
	}
	featured, err := s.catalog.AdminList(ctx, nil, "", 200, 0)
	if err != nil {
		return out, err
	}
	names := map[uuid.UUID]string{}
	ranks := map[uuid.UUID]*int32{}
	for _, p := range featured {
		names[p.ID], ranks[p.ID] = p.Name, p.FeaturedRank
		if p.FeaturedRank != nil || p.PromoPriceXOF != nil || len(p.Badges) > 0 {
			add(p.ID)
		}
	}
	for _, v := range visuals {
		if v.ProductID != nil {
			add(*v.ProductID)
		}
	}
	ev := map[uuid.UUID]store.EventsByProductRow{}
	for _, r := range byProduct {
		ev[r.ProductID] = r
		add(r.ProductID)
	}
	sales, err := s.orders.ProductSales(ctx, ids, since, until)
	if err != nil {
		return out, err
	}
	for _, id := range ids {
		name, ok := names[id]
		if !ok {
			if p, err := s.catalog.AdminGet(ctx, id); err == nil {
				name, ranks[id] = p.Name, p.FeaturedRank
			}
		}
		e, sale := ev[id], sales[id]
		out.Products = append(out.Products, ProductStats{
			ProductID: id, Name: name, Impressions: e.Impressions, Views: e.Views, OrderClicks: e.OrderClicks,
			AdOrders: e.Orders, PaidOrders: sale.Orders, UnitsSold: sale.Units, RevenueXOF: sale.RevenueXOF,
			FeaturedRank: ranks[id],
		})
	}
	slices.SortStableFunc(out.Products, func(a, b ProductStats) int {
		if c := cmp.Compare(b.PaidOrders, a.PaidOrders); c != 0 {
			return c
		}
		return cmp.Compare(b.Impressions, a.Impressions)
	})
	return out, nil
}
