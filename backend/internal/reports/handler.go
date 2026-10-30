// Package reports calcule les indicateurs métier du back-office à partir des modules qui
// détiennent les données (commandes, livraisons, paiements). Il n'a pas de table.
package reports

import (
	"context"
	"net/http"
	"time"

	"ivia/backend/internal/delivery"
	"ivia/backend/internal/orders"
	"ivia/backend/internal/payments"
	"ivia/backend/internal/platform/apperr"
	"ivia/backend/internal/platform/httpapi"
	"ivia/backend/internal/platform/identity"
)

// Dashboard regroupe les indicateurs d'une période.
type Dashboard struct {
	From                     string           `json:"from"`
	To                       string           `json:"to"`
	Orders                   orders.Metrics   `json:"orders"`
	Delivery                 delivery.Metrics `json:"delivery"`
	PaymentsPendingOver15Min int64            `json:"payments_pending_over_15_min"`
}

// Handler expose le tableau de bord.
type Handler struct {
	orders   *orders.Service
	delivery *delivery.Service
	payments *payments.Service
}

// NewHandler crée le handler.
func NewHandler(o *orders.Service, d *delivery.Service, p *payments.Service) *Handler {
	return &Handler{orders: o, delivery: d, payments: p}
}

// Register enregistre les routes.
func (h *Handler) Register(rt *httpapi.Router) {
	rt.Roles("GET /v1/admin/metrics", h.metrics, identity.RoleAdmin)
}

// Compute calcule les indicateurs sur une période en dates de Lomé (bornes incluses).
func (h *Handler) Compute(ctx context.Context, from, to time.Time) (Dashboard, error) {
	start := time.Date(from.Year(), from.Month(), from.Day(), 0, 0, 0, 0, delivery.Lome)
	end := time.Date(to.Year(), to.Month(), to.Day(), 0, 0, 0, 0, delivery.Lome).AddDate(0, 0, 1)
	om, err := h.orders.MetricsBetween(ctx, start, end)
	if err != nil {
		return Dashboard{}, err
	}
	dm, err := h.delivery.MetricsBetween(ctx, start, end)
	if err != nil {
		return Dashboard{}, err
	}
	pending, err := h.payments.PendingOlderThan(ctx, 15*time.Minute)
	if err != nil {
		return Dashboard{}, err
	}
	return Dashboard{
		From: from.Format(time.DateOnly), To: to.Format(time.DateOnly),
		Orders: om, Delivery: dm, PaymentsPendingOver15Min: pending,
	}, nil
}

func (h *Handler) metrics(w http.ResponseWriter, r *http.Request) error {
	q := httpapi.NewQuery(r)
	from, to := q.Date("from"), q.Date("to")
	if err := q.Err(); err != nil {
		return err
	}
	now := time.Now().In(delivery.Lome)
	if to == nil {
		to = &now
	}
	if from == nil {
		f := to.AddDate(0, 0, -29)
		from = &f
	}
	if to.Before(*from) || to.Sub(*from) > 366*24*time.Hour {
		return apperr.Validation(map[string]string{"to": "Période invalide (un an au plus)."})
	}
	d, err := h.Compute(r.Context(), *from, *to)
	if err != nil {
		return err
	}
	return httpapi.OK(w, d)
}
