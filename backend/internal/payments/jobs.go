package payments

import (
	"context"
	"time"

	"github.com/google/uuid"
	"github.com/riverqueue/river"

	"ivia/backend/internal/platform/jobs"
)

// ProcessEventArgs : traitement d'un événement du prestataire enregistré.
type ProcessEventArgs struct {
	EventID int64 `json:"event_id"`
}

// Kind implémente river.JobArgs.
func (ProcessEventArgs) Kind() string { return "payments.process_event" }

// RecheckArgs : revérification périodique des paiements en attente.
type RecheckArgs struct{}

// Kind implémente river.JobArgs.
func (RecheckArgs) Kind() string { return "payments.recheck" }

// ExecuteRefundArgs : exécution d'un remboursement décidé par un admin.
type ExecuteRefundArgs struct {
	PaymentID   uuid.UUID `json:"payment_id"`
	OrderID     uuid.UUID `json:"order_id"`
	AmountXOF   int64     `json:"amount_xof"`
	Duplicate   bool      `json:"duplicate"`
	Reference   string    `json:"reference"`
	Reason      string    `json:"reason"`
	RequestedBy uuid.UUID `json:"requested_by"`
	RequestedAt time.Time `json:"requested_at"`
}

// Kind implémente river.JobArgs.
func (ExecuteRefundArgs) Kind() string { return "payments.execute_refund" }

type processEventWorker struct {
	river.WorkerDefaults[ProcessEventArgs]
	svc *Service
}

func (w *processEventWorker) Work(ctx context.Context, job *river.Job[ProcessEventArgs]) error {
	return w.svc.processEvent(ctx, job.Args.EventID)
}

type recheckWorker struct {
	river.WorkerDefaults[RecheckArgs]
	svc *Service
}

func (w *recheckWorker) Work(ctx context.Context, _ *river.Job[RecheckArgs]) error {
	return w.svc.Recheck(ctx)
}

type refundWorker struct {
	river.WorkerDefaults[ExecuteRefundArgs]
	svc *Service
}

func (w *refundWorker) Work(ctx context.Context, job *river.Job[ExecuteRefundArgs]) error {
	return w.svc.executeRefund(ctx, job.Args)
}

// RegisterJobs déclare les tâches de fond du module.
func (s *Service) RegisterJobs(reg *jobs.Registry) {
	river.AddWorker(reg.Workers, &processEventWorker{svc: s})
	river.AddWorker(reg.Workers, &recheckWorker{svc: s})
	river.AddWorker(reg.Workers, &refundWorker{svc: s})
	reg.AddPeriodic(time.Minute, func() river.JobArgs { return RecheckArgs{} })
}
