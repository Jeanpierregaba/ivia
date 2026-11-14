package orders

import (
	"context"
	"errors"
	"time"

	"github.com/google/uuid"
	"github.com/riverqueue/river"

	"ivia/backend/internal/platform/jobs"
)

// ExpirePaymentArgs : expiration d'une commande non payée, planifiée à la fin du délai de paiement.
type ExpirePaymentArgs struct {
	OrderID uuid.UUID `json:"order_id"`
}

// Kind implémente river.JobArgs.
func (ExpirePaymentArgs) Kind() string { return "orders.expire_payment" }

// SellerTimeoutArgs : annulation d'une commande sans réponse du marchand.
type SellerTimeoutArgs struct {
	OrderID uuid.UUID `json:"order_id"`
}

// Kind implémente river.JobArgs.
func (SellerTimeoutArgs) Kind() string { return "orders.seller_timeout" }

// StatusChangedArgs signale au module delivery un changement de statut qui le concerne
// (commande prête à livrer, annulée, revenue en boutique). Le worker est déclaré par delivery :
// orders ne dépend pas de delivery.
type StatusChangedArgs struct {
	OrderID uuid.UUID `json:"order_id"`
	Status  Status    `json:"status"`
}

// Kind implémente river.JobArgs.
func (StatusChangedArgs) Kind() string { return "orders.status_changed" }

func atTime(t time.Time) *river.InsertOpts { return jobs.At(t) }

type expireWorker struct {
	river.WorkerDefaults[ExpirePaymentArgs]
	svc *Service
}

func (w *expireWorker) Work(ctx context.Context, job *river.Job[ExpirePaymentArgs]) error {
	return snoozeIfEarly(w.svc.ExpirePayment(ctx, job.Args.OrderID))
}

type sellerTimeoutWorker struct {
	river.WorkerDefaults[SellerTimeoutArgs]
	svc *Service
}

func (w *sellerTimeoutWorker) Work(ctx context.Context, job *river.Job[SellerTimeoutArgs]) error {
	return snoozeIfEarly(w.svc.SellerTimeout(ctx, job.Args.OrderID))
}

// snoozeIfEarly repousse une tâche exécutée avant son heure (horloges décalées).
func snoozeIfEarly(err error) error {
	var early errRetryLater
	if errors.As(err, &early) {
		return river.JobSnooze(max(time.Until(early.at), time.Second))
	}
	return err
}

// RegisterJobs déclare les tâches de fond du module.
func (s *Service) RegisterJobs(reg *jobs.Registry) {
	river.AddWorker(reg.Workers, &expireWorker{svc: s})
	river.AddWorker(reg.Workers, &sellerTimeoutWorker{svc: s})
}
