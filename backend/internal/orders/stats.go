package orders

import (
	"context"
	"fmt"
	"time"

	"github.com/google/uuid"

	"ivia/backend/internal/orders/store"
)

// Tableau de bord du marchand (spec 042) : rien d'estimé, tout vient des commandes payées.

// StatsDay est une journée de la période.
type StatsDay struct {
	Date     string `json:"date"`
	Orders   int32  `json:"orders"`
	SalesXOF int64  `json:"sales_xof"`
}

// StatsTotals résume une période.
type StatsTotals struct {
	Orders       int32 `json:"orders"`
	SalesXOF     int64 `json:"sales_xof"`
	AvgBasketXOF int64 `json:"avg_basket_xof"`
	Deliveries   int32 `json:"deliveries"`
	Cancelled    int32 `json:"cancelled"`
	Buyers       int32 `json:"buyers"`
}

// StatsProduct est un des produits les plus vendus.
type StatsProduct struct {
	ProductID uuid.UUID `json:"product_id"`
	Name      string    `json:"name"`
	Quantity  int32     `json:"quantity"`
	SalesXOF  int64     `json:"sales_xof"`
}

// SellerStats est le tableau de bord d'une boutique.
type SellerStats struct {
	Days        int            `json:"days"`
	Series      []StatsDay     `json:"series"`
	Totals      StatsTotals    `json:"totals"`
	Previous    StatsTotals    `json:"previous"`
	Hours       []int32        `json:"hours"`
	TopProducts []StatsProduct `json:"top_products"`
}

var lome = func() *time.Location {
	if l, err := time.LoadLocation("Africa/Lome"); err == nil {
		return l
	}
	return time.UTC
}()

// StatsForSeller calcule le tableau de bord d'une boutique du marchand sur [days] jours (aujourd'hui
// compris), comparé aux [days] jours d'avant.
func (s *Service) StatsForSeller(ctx context.Context, sellerID, shopID uuid.UUID, days int) (SellerStats, error) {
	if _, err := s.shops.RequireOwned(ctx, sellerID, shopID); err != nil {
		return SellerStats{}, err
	}
	now := time.Now().In(lome)
	today := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, lome)
	since := today.AddDate(0, 0, -(days - 1))
	until := today.AddDate(0, 0, 1)
	before := since.AddDate(0, 0, -days)
	st := store.New(s.db.Conn(ctx))

	daily, err := st.SellerStatsDaily(ctx, store.SellerStatsDailyParams{ShopID: shopID, Since: since, Until: until})
	if err != nil {
		return SellerStats{}, fmt.Errorf("ventes par jour : %w", err)
	}
	byDay := map[string]store.SellerStatsDailyRow{}
	for _, d := range daily {
		byDay[d.Day.Format(time.DateOnly)] = d
	}
	out := SellerStats{Days: days, Series: make([]StatsDay, 0, days), Hours: make([]int32, 24), TopProducts: []StatsProduct{}}
	for i := 0; i < days; i++ {
		key := since.AddDate(0, 0, i).Format(time.DateOnly)
		d := byDay[key]
		out.Series = append(out.Series, StatsDay{Date: key, Orders: d.Orders, SalesXOF: d.SalesXof})
	}

	totals := func(from, to time.Time) (StatsTotals, error) {
		t, err := st.SellerStatsTotals(ctx, store.SellerStatsTotalsParams{ShopID: shopID, Since: from, Until: to})
		if err != nil {
			return StatsTotals{}, fmt.Errorf("totaux : %w", err)
		}
		out := StatsTotals{Orders: t.Orders, SalesXOF: t.SalesXof, Deliveries: t.Deliveries, Cancelled: t.Cancelled, Buyers: t.Buyers}
		if t.Orders > 0 {
			out.AvgBasketXOF = t.SalesXof / int64(t.Orders)
		}
		return out, nil
	}
	if out.Totals, err = totals(since, until); err != nil {
		return SellerStats{}, err
	}
	if out.Previous, err = totals(before, since); err != nil {
		return SellerStats{}, err
	}

	hours, err := st.SellerStatsHourly(ctx, store.SellerStatsHourlyParams{ShopID: shopID, Since: since, Until: until})
	if err != nil {
		return SellerStats{}, fmt.Errorf("heures : %w", err)
	}
	for _, h := range hours {
		if h.Hour >= 0 && h.Hour < 24 {
			out.Hours[h.Hour] = h.Orders
		}
	}

	top, err := st.SellerStatsTopProducts(ctx, store.SellerStatsTopProductsParams{ShopID: shopID, Since: since, Until: until})
	if err != nil {
		return SellerStats{}, fmt.Errorf("meilleurs produits : %w", err)
	}
	for _, p := range top {
		out.TopProducts = append(out.TopProducts, StatsProduct{ProductID: p.ProductID, Name: p.Name, Quantity: p.Quantity, SalesXOF: p.SalesXof})
	}
	return out, nil
}
