package delivery

import (
	"context"
	"time"

	"github.com/google/uuid"
	"github.com/riverqueue/river"

	"ivia/backend/internal/orders"
	"ivia/backend/internal/platform/jobs"
)

// AssignArgs : recherche d'un livreur pour une commande.
type AssignArgs struct {
	OrderID uuid.UUID `json:"order_id"`
}

// Kind implémente river.JobArgs.
func (AssignArgs) Kind() string { return "delivery.assign" }

// OfferTimeoutArgs : fin du délai de réponse d'une proposition.
type OfferTimeoutArgs struct {
	OfferID uuid.UUID `json:"offer_id"`
}

// Kind implémente river.JobArgs.
func (OfferTimeoutArgs) Kind() string { return "delivery.offer_timeout" }

// PurgePositionsArgs : purge quotidienne des positions de plus de 30 jours.
type PurgePositionsArgs struct{}

// Kind implémente river.JobArgs.
func (PurgePositionsArgs) Kind() string { return "delivery.purge_positions" }

type assignWorker struct {
	river.WorkerDefaults[AssignArgs]
	svc *Service
}

// Work cherche un livreur ; sans livreur disponible, la tâche se reprogramme tant que la commande
// attend (elle s'arrête d'elle-même dès qu'une proposition est faite ou que la commande change).
func (w *assignWorker) Work(ctx context.Context, job *river.Job[AssignArgs]) error {
	outcome, err := w.svc.assign(ctx, job.Args.OrderID)
	if err != nil {
		return err
	}
	if outcome == assignNoDriver {
		return river.JobSnooze(RetryAssignmentAfter)
	}
	return nil
}

type offerTimeoutWorker struct {
	river.WorkerDefaults[OfferTimeoutArgs]
	svc *Service
}

func (w *offerTimeoutWorker) Work(ctx context.Context, job *river.Job[OfferTimeoutArgs]) error {
	return w.svc.ExpireOffer(ctx, job.Args.OfferID)
}

type statusChangedWorker struct {
	river.WorkerDefaults[orders.StatusChangedArgs]
	svc *Service
}

func (w *statusChangedWorker) Work(ctx context.Context, job *river.Job[orders.StatusChangedArgs]) error {
	return w.svc.onOrderStatusChanged(ctx, job.Args.OrderID, job.Args.Status)
}

type purgeWorker struct {
	river.WorkerDefaults[PurgePositionsArgs]
	svc *Service
}

func (w *purgeWorker) Work(ctx context.Context, _ *river.Job[PurgePositionsArgs]) error {
	return w.svc.PurgePositions(ctx)
}

// RegisterJobs déclare les tâches de fond du module, dont la réaction aux changements de statut
// des commandes (orders.StatusChangedArgs).
func (s *Service) RegisterJobs(reg *jobs.Registry) {
	river.AddWorker(reg.Workers, &assignWorker{svc: s})
	river.AddWorker(reg.Workers, &offerTimeoutWorker{svc: s})
	river.AddWorker(reg.Workers, &statusChangedWorker{svc: s})
	river.AddWorker(reg.Workers, &purgeWorker{svc: s})
	reg.AddPeriodic(24*time.Hour, func() river.JobArgs { return PurgePositionsArgs{} })
}
