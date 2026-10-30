// Package jobs enveloppe River (ADR 0005) : création des tâches de fond dans la transaction en
// cours, enregistrement des workers par les modules, démarrage et arrêt du client.
package jobs

import (
	"context"
	"fmt"
	"log/slog"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/riverqueue/river"
	"github.com/riverqueue/river/riverdriver/riverpgxv5"

	"ivia/backend/internal/platform/database"
)

// Enqueuer crée des tâches de fond. Si une transaction est en cours dans ctx, la tâche est créée
// dans cette transaction : elle n'existe que si la donnée métier est validée.
type Enqueuer interface {
	Enqueue(ctx context.Context, args river.JobArgs, opts *river.InsertOpts) error
}

// Registry collecte les workers et les tâches périodiques déclarés par les modules au démarrage.
type Registry struct {
	Workers  *river.Workers
	Periodic []*river.PeriodicJob
}

// NewRegistry crée un registre vide.
func NewRegistry() *Registry { return &Registry{Workers: river.NewWorkers()} }

// AddPeriodic déclare une tâche lancée à intervalle régulier.
func (r *Registry) AddPeriodic(every time.Duration, args func() river.JobArgs) {
	r.Periodic = append(r.Periodic, river.NewPeriodicJob(
		river.PeriodicInterval(every),
		func() (river.JobArgs, *river.InsertOpts) { return args(), nil },
		&river.PeriodicJobOpts{RunOnStart: true},
	))
}

// Options du client.
type Options struct {
	// RunWorkers : false = client en insertion seule (aucune tâche exécutée par ce processus).
	RunWorkers bool
	// PollInterval : délai maximal avant de prendre une tâche planifiée (court dans les tests).
	PollInterval time.Duration
	Logger       *slog.Logger
}

// Queue est le client River partagé par toute l'application.
type Queue struct {
	client     *river.Client[pgx.Tx]
	runWorkers bool
}

// New crée le client River. Les workers doivent tous être enregistrés dans reg avant cet appel.
func New(pool *pgxpool.Pool, reg *Registry, opts Options) (*Queue, error) {
	cfg := &river.Config{
		Logger:      opts.Logger,
		MaxAttempts: 10,
		Workers:     reg.Workers,
		JobTimeout:  time.Minute,
	}
	if opts.RunWorkers {
		cfg.Queues = map[string]river.QueueConfig{river.QueueDefault: {MaxWorkers: 20}}
		cfg.PeriodicJobs = reg.Periodic
		if opts.PollInterval > 0 {
			cfg.FetchPollInterval = opts.PollInterval
			cfg.FetchCooldown = opts.PollInterval / 2
		}
	}
	client, err := river.NewClient(riverpgxv5.New(pool), cfg)
	if err != nil {
		return nil, fmt.Errorf("création du client River : %w", err)
	}
	return &Queue{client: client, runWorkers: opts.RunWorkers}, nil
}

// Enqueue implémente Enqueuer.
func (q *Queue) Enqueue(ctx context.Context, args river.JobArgs, opts *river.InsertOpts) error {
	var err error
	if tx, ok := database.TxFromContext(ctx); ok {
		_, err = q.client.InsertTx(ctx, tx, args, opts)
	} else {
		_, err = q.client.Insert(ctx, args, opts)
	}
	if err != nil {
		return fmt.Errorf("création de la tâche %s : %w", args.Kind(), err)
	}
	return nil
}

// Start démarre l'exécution des tâches (sans effet en insertion seule).
func (q *Queue) Start(ctx context.Context) error {
	if !q.runWorkers {
		return nil
	}
	if err := q.client.Start(ctx); err != nil {
		return fmt.Errorf("démarrage de River : %w", err)
	}
	return nil
}

// Stop attend la fin des tâches en cours, dans la limite de ctx.
func (q *Queue) Stop(ctx context.Context) error {
	if !q.runWorkers {
		return nil
	}
	return q.client.Stop(ctx)
}

// Deferred est un Enqueuer branché après coup sur la Queue. Il résout la dépendance circulaire
// du démarrage : les services ont besoin d'un Enqueuer, et le client River a besoin des workers
// de ces services. Set est appelé une seule fois, avant de servir des requêtes.
type Deferred struct {
	q *Queue
}

// Set branche la file de tâches.
func (d *Deferred) Set(q *Queue) { d.q = q }

// Enqueue implémente Enqueuer.
func (d *Deferred) Enqueue(ctx context.Context, args river.JobArgs, opts *river.InsertOpts) error {
	if d.q == nil {
		return fmt.Errorf("file de tâches non initialisée (tâche %s)", args.Kind())
	}
	return d.q.Enqueue(ctx, args, opts)
}

// At retourne des options de création planifiant la tâche à l'instant t.
func At(t time.Time) *river.InsertOpts { return &river.InsertOpts{ScheduledAt: t} }

// UniqueByArgs évite de créer deux fois la même tâche (mêmes arguments) tant qu'elle n'est pas terminée.
func UniqueByArgs() *river.InsertOpts {
	return &river.InsertOpts{UniqueOpts: river.UniqueOpts{ByArgs: true}}
}
