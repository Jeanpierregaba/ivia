package reports

import (
	"context"
	"net/http"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/google/uuid"

	"ivia/backend/internal/admin"
	"ivia/backend/internal/delivery"
	"ivia/backend/internal/orders"
	"ivia/backend/internal/payments"
	"ivia/backend/internal/platform/httpapi"
)

// Vue d'ensemble du back-office (maquette B03) : tout le tableau de bord en un appel, relu par
// la page toutes les 30 s. Chaque module fournit ses chiffres ; reports n'a pas de table.

// Overview est le tableau de bord du moment.
type Overview struct {
	GeneratedAt time.Time               `json:"generated_at"`
	Period      string                  `json:"period"`
	From        string                  `json:"from"`
	To          string                  `json:"to"`
	Todo        OverviewTodo            `json:"todo"`
	KPIs        OverviewKPIs            `json:"kpis"`
	PaidPerDay  []orders.DayByMode      `json:"paid_per_day"`
	Drivers     delivery.DriverOverview `json:"drivers"`
	Payments    payments.Overview       `json:"payments"`
	Active      OverviewActive          `json:"active_orders"`
	Audit       []AuditLine             `json:"audit"`
	Sidebar     OverviewSidebar         `json:"sidebar"`
}

// OverviewTodo : tuiles « À traiter ».
type OverviewTodo struct {
	Refunds        int64      `json:"refunds"`
	RefundsXOF     int64      `json:"refunds_xof"`
	Shops          int64      `json:"shops"`
	ShopsOldest    *time.Time `json:"shops_oldest"`
	Drivers        int64      `json:"drivers"`
	HandoverLocked int64      `json:"handover_locked"`
	// Exemple de commande à code bloqué, pour la tuile (nil s'il n'y en a pas).
	HandoverLockedOrder *OrderRef `json:"handover_locked_order"`
	Unassigned          int64     `json:"unassigned"`
	UnassignedOrder     *OrderRef `json:"unassigned_order"`
}

// OrderRef désigne une commande dans une tuile.
type OrderRef struct {
	ID        uuid.UUID `json:"id"`
	Number    int64     `json:"number"`
	Reference string    `json:"reference"`
	// OffersCount : livreurs sollicités sans succès (commande sans livreur).
	OffersCount int32 `json:"offers_count"`
}

// OverviewKPIs : indicateurs de la période, et taux sur 30 jours (plus stables).
type OverviewKPIs struct {
	PaidOrders     int64 `json:"paid_orders"`
	PaidOrdersPrev int64 `json:"paid_orders_prev"`
	GMVXOF         int64 `json:"gmv_xof"`
	CommissionXOF  int64 `json:"commission_xof"`
	// Sur 30 jours.
	CancellationRatePct           float64 `json:"cancellation_rate_pct"`
	AssignedWithin10MinPct        float64 `json:"assigned_within_10_min_pct"`
	MedianReadyToDeliveredMinutes float64 `json:"median_ready_to_delivered_minutes"`
}

// OverviewActive : commandes en cours, compteurs des puces et lignes du groupe demandé.
type OverviewActive struct {
	Group         string               `json:"group"`
	All           int64                `json:"all"`
	ToAccept      int64                `json:"to_accept"`
	WithoutDriver int64                `json:"without_driver"`
	Locked        int64                `json:"locked"`
	Items         []orders.ActiveOrder `json:"items"`
}

// AuditLine : action du journal, avec l'auteur et la cible lisibles.
type AuditLine struct {
	ID            int64     `json:"id"`
	AdminName     string    `json:"admin_name"`
	AdminInitials string    `json:"admin_initials"`
	Action        string    `json:"action"`
	TargetType    string    `json:"target_type"`
	TargetID      string    `json:"target_id"`
	TargetLabel   string    `json:"target_label"`
	Reason        string    `json:"reason"`
	CreatedAt     time.Time `json:"created_at"`
}

// OverviewSidebar : pastilles de la barre latérale.
type OverviewSidebar struct {
	Orders  int64 `json:"orders"`
	Refunds int64 `json:"refunds"`
	Shops   int64 `json:"shops"`
	Drivers int64 `json:"drivers"`
}

// periods : période affichée et période de comparaison (même durée, juste avant ; pour
// « aujourd'hui », le même jour la semaine précédente).
func periods(period string, today time.Time) (from, to, prevFrom, prevTo time.Time) {
	switch period {
	case "7d":
		return today.AddDate(0, 0, -6), today, today.AddDate(0, 0, -13), today.AddDate(0, 0, -7)
	case "30d":
		return today.AddDate(0, 0, -29), today, today.AddDate(0, 0, -59), today.AddDate(0, 0, -30)
	default:
		return today, today, today.AddDate(0, 0, -7), today.AddDate(0, 0, -7)
	}
}

func (h *Handler) overview(w http.ResponseWriter, r *http.Request) error {
	q := httpapi.NewQuery(r)
	period := q.Enum("period", "today", "today", "7d", "30d")
	group := q.Enum("group", "", "to_accept", "without_driver", "locked")
	if err := q.Err(); err != nil {
		return err
	}
	o, err := h.Overview(r.Context(), period, group, time.Now())
	if err != nil {
		return err
	}
	return httpapi.OK(w, o)
}

// Overview calcule le tableau de bord à l'instant now.
func (h *Handler) Overview(ctx context.Context, period, group string, now time.Time) (Overview, error) {
	local := now.In(delivery.Lome)
	today := time.Date(local.Year(), local.Month(), local.Day(), 0, 0, 0, 0, delivery.Lome)
	from, to, prevFrom, prevTo := periods(period, today)
	out := Overview{GeneratedAt: now, Period: period, From: from.Format(time.DateOnly), To: to.Format(time.DateOnly)}

	cur, err := h.Compute(ctx, from, to)
	if err != nil {
		return out, err
	}
	prev, err := h.orders.MetricsBetween(ctx, prevFrom, prevTo.AddDate(0, 0, 1))
	if err != nil {
		return out, err
	}
	month := cur
	if period != "30d" {
		if month, err = h.Compute(ctx, today.AddDate(0, 0, -29), today); err != nil {
			return out, err
		}
	}
	out.KPIs = OverviewKPIs{
		PaidOrders: cur.Orders.PaidOrders, PaidOrdersPrev: prev.PaidOrders,
		GMVXOF: cur.Orders.GMVXOF, CommissionXOF: cur.Orders.CommissionXOF,
		CancellationRatePct:           month.Orders.CancellationRatePct,
		AssignedWithin10MinPct:        month.Delivery.AssignedWithin10MinPct,
		MedianReadyToDeliveredMinutes: month.Orders.MedianReadyToDeliveredMin,
	}

	if out.PaidPerDay, err = h.orders.PaidPerDayByMode(ctx, today, 14, delivery.Lome); err != nil {
		return out, err
	}
	if out.Drivers, err = h.delivery.Overview(ctx); err != nil {
		return out, err
	}
	if out.Payments, err = h.payments.Overview(ctx, from, to.AddDate(0, 0, 1)); err != nil {
		return out, err
	}

	counts, err := h.orders.Overview(ctx)
	if err != nil {
		return out, err
	}
	shopsPending, oldest, err := h.shops.PendingOverview(ctx)
	if err != nil {
		return out, err
	}
	alerts, err := h.delivery.Alerts(ctx)
	if err != nil {
		return out, err
	}
	out.Todo = OverviewTodo{
		Refunds: counts.Refunds, RefundsXOF: counts.RefundsXOF, Shops: shopsPending, ShopsOldest: oldest,
		Drivers: out.Drivers.PendingReview, HandoverLocked: counts.HandoverLocked, Unassigned: int64(len(alerts)),
	}
	if counts.HandoverLocked > 0 {
		if locked, err := h.orders.ActiveOrders(ctx, "locked", 1); err == nil && len(locked) > 0 {
			out.Todo.HandoverLockedOrder = &OrderRef{ID: locked[0].ID, Number: locked[0].Number, Reference: locked[0].Reference}
		}
	}
	if len(alerts) > 0 {
		if o, err := h.orders.AdminGet(ctx, alerts[0].OrderID); err == nil {
			out.Todo.UnassignedOrder = &OrderRef{ID: o.ID, Number: o.Number, Reference: o.Reference, OffersCount: alerts[0].OffersCount}
		}
	}

	items, err := h.orders.ActiveOrders(ctx, group, 20)
	if err != nil {
		return out, err
	}
	out.Active = OverviewActive{
		Group: group, All: counts.Active, ToAccept: counts.ToAccept, WithoutDriver: counts.WithoutDriver,
		Locked: counts.HandoverLocked, Items: items,
	}
	out.Sidebar = OverviewSidebar{Orders: counts.Active, Refunds: counts.Refunds, Shops: shopsPending, Drivers: out.Drivers.PendingReview}

	if out.Audit, err = h.auditLines(ctx, 5); err != nil {
		return out, err
	}
	return out, nil
}

// auditLines : dernières actions du journal, avec le prénom de l'admin et une cible lisible.
func (h *Handler) auditLines(ctx context.Context, limit int32) ([]AuditLine, error) {
	recs, err := h.admin.ListAudit(ctx, admin.AuditFilter{Limit: limit})
	if err != nil {
		return nil, err
	}
	names := map[uuid.UUID][2]string{}
	out := make([]AuditLine, len(recs))
	for i, a := range recs {
		line := AuditLine{
			ID: a.ID, Action: a.Action, TargetType: a.TargetType, TargetID: a.TargetID,
			TargetLabel: h.targetLabel(ctx, a.TargetType, a.TargetID), Reason: a.Reason, CreatedAt: a.CreatedAt,
			AdminName: "Système", AdminInitials: "SY",
		}
		if a.AdminID != nil {
			n, ok := names[*a.AdminID]
			if !ok {
				n = [2]string{"Admin", "AD"}
				if u, err := h.users.Get(ctx, *a.AdminID); err == nil {
					n = [2]string{firstNonEmpty(u.FirstName, "Admin"), initials(u.FirstName, u.LastName)}
				}
				names[*a.AdminID] = n
			}
			line.AdminName, line.AdminInitials = n[0], n[1]
		}
		out[i] = line
	}
	return out, nil
}

// targetLabel : nom de la boutique, référence de la commande ou prénom du livreur ; vide sinon.
func (h *Handler) targetLabel(ctx context.Context, targetType, targetID string) string {
	id, err := uuid.Parse(targetID)
	if err != nil {
		return ""
	}
	switch targetType {
	case "shop":
		if s, err := h.shops.Get(ctx, id); err == nil {
			return s.Name
		}
	case "order":
		if o, err := h.orders.AdminGet(ctx, id); err == nil {
			return o.Reference
		}
	case "driver", "user":
		if u, err := h.users.Get(ctx, id); err == nil {
			return strings.TrimSpace(u.FirstName + " " + initial(u.LastName))
		}
	}
	return ""
}

func initials(first, last string) string {
	out := strings.ToUpper(initial(first) + initial(last))
	out = strings.ReplaceAll(out, ".", "")
	if out == "" {
		return "AD"
	}
	return out
}

func initial(s string) string {
	r, _ := utf8.DecodeRuneInString(strings.TrimSpace(s))
	if r == utf8.RuneError {
		return ""
	}
	return strings.ToUpper(string(r)) + "."
}

func firstNonEmpty(v, def string) string {
	if strings.TrimSpace(v) == "" {
		return def
	}
	return v
}
