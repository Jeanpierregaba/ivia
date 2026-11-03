package uploads

import (
	"context"
	"fmt"
	"log/slog"
	"sync"
	"time"

	"github.com/google/uuid"
	"github.com/riverqueue/river"

	"ivia/backend/internal/platform/jobs"
	"ivia/backend/internal/platform/storage"
)

// Nettoyage des documents privés (pièces des marchands, dossiers des livreurs), exigé par
// docs/SECURITY.md : rien ne doit survivre à la suppression d'un compte, et un fichier envoyé
// mais jamais rattaché (photo remplacée avant l'envoi, réponse perdue) ne doit pas rester.

// OrphanAge : âge au-delà duquel un fichier privé non rattaché est supprimé. Une URL d'envoi vaut
// 5 minutes et le rattachement suit aussitôt : 24 h laissent une large marge aux nouveaux essais.
const OrphanAge = 24 * time.Hour

// AttachedFunc dit lesquelles de ces clés sont rattachées à un dossier (le module propriétaire
// interroge sa propre table).
type AttachedFunc func(ctx context.Context, keys []string) (map[string]bool, error)

type owners struct {
	mu sync.Mutex
	m  map[Purpose]AttachedFunc
}

// RegisterOwner déclare le module qui rattache les fichiers privés d'un usage : seuls les usages
// déclarés sont purgés.
func (s *Service) RegisterOwner(p Purpose, attached AttachedFunc) {
	if rules[p].vis != storage.Private {
		panic("uploads : seuls les usages privés sont purgés : " + string(p))
	}
	s.owners.mu.Lock()
	defer s.owners.mu.Unlock()
	if s.owners.m == nil {
		s.owners.m = map[Purpose]AttachedFunc{}
	}
	s.owners.m[p] = attached
}

// DeleteAllOf supprime tous les fichiers d'un utilisateur pour un usage privé, rattachés ou non
// (suppression du compte). Renvoie le nombre de fichiers supprimés.
func (s *Service) DeleteAllOf(ctx context.Context, p Purpose, userID uuid.UUID) (int, error) {
	r := rules[p]
	if r.vis != storage.Private {
		return 0, fmt.Errorf("uploads : usage %s non privé", p)
	}
	objs, err := s.store.List(ctx, r.vis, r.prefix+"/"+userID.String()+"/")
	if err != nil {
		return 0, fmt.Errorf("liste des documents : %w", err)
	}
	for _, o := range objs {
		if err := s.store.Delete(ctx, r.vis, o.Key); err != nil {
			return 0, fmt.Errorf("suppression d'un document : %w", err)
		}
	}
	return len(objs), nil
}

// PurgeOrphans supprime, pour chaque usage déclaré, les fichiers privés de plus de OrphanAge
// qu'aucun dossier ne référence. Renvoie le nombre de fichiers supprimés.
func (s *Service) PurgeOrphans(ctx context.Context, now time.Time) (int, error) {
	s.owners.mu.Lock()
	owned := make(map[Purpose]AttachedFunc, len(s.owners.m))
	for p, f := range s.owners.m {
		owned[p] = f
	}
	s.owners.mu.Unlock()

	deleted := 0
	for p, attached := range owned {
		r := rules[p]
		objs, err := s.store.List(ctx, r.vis, r.prefix+"/")
		if err != nil {
			return deleted, fmt.Errorf("liste des documents %s : %w", p, err)
		}
		var old []string
		for _, o := range objs {
			if now.Sub(o.LastModified) >= OrphanAge {
				old = append(old, o.Key)
			}
		}
		// Par lots : la requête du module propriétaire reste bornée.
		for start := 0; start < len(old); start += 500 {
			batch := old[start:min(start+500, len(old))]
			keep, err := attached(ctx, batch)
			if err != nil {
				return deleted, err
			}
			for _, k := range batch {
				if keep[k] {
					continue
				}
				if err := s.store.Delete(ctx, r.vis, k); err != nil {
					return deleted, fmt.Errorf("suppression d'un document orphelin : %w", err)
				}
				deleted++
			}
		}
	}
	return deleted, nil
}

// PurgeOrphansArgs : purge quotidienne des documents privés jamais rattachés.
type PurgeOrphansArgs struct{}

// Kind implémente river.JobArgs.
func (PurgeOrphansArgs) Kind() string { return "uploads.purge_orphans" }

type purgeOrphansWorker struct {
	river.WorkerDefaults[PurgeOrphansArgs]
	svc    *Service
	logger *slog.Logger
}

func (w *purgeOrphansWorker) Work(ctx context.Context, _ *river.Job[PurgeOrphansArgs]) error {
	n, err := w.svc.PurgeOrphans(ctx, time.Now())
	if n > 0 {
		// Nombre seulement : ni clé ni identifiant d'utilisateur dans les journaux.
		w.logger.Info("documents orphelins supprimés", "nombre", n)
	}
	return err
}

// RegisterJobs déclare la purge quotidienne des documents orphelins.
func (s *Service) RegisterJobs(reg *jobs.Registry, logger *slog.Logger) {
	river.AddWorker(reg.Workers, &purgeOrphansWorker{svc: s, logger: logger})
	reg.AddPeriodic(24*time.Hour, func() river.JobArgs { return PurgeOrphansArgs{} })
}
