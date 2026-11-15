// Package errtrack remonte les erreurs inattendues (erreurs 500, paniques, tâches de fond en
// échec) vers Sentry. Sans SENTRY_DSN, rien n'est envoyé.
//
// Aucune donnée personnelle n'est transmise (RULES.md) : ni requête (URL, en-têtes, corps), ni
// utilisateur, ni nom de machine. Seuls le message d'erreur, la pile et des étiquettes techniques
// (identifiant de requête, route, type de tâche) partent.
package errtrack

import (
	"context"
	"fmt"
	"time"

	"github.com/getsentry/sentry-go"
)

// Reporter signale une erreur inattendue.
type Reporter interface {
	Report(ctx context.Context, err error, tags map[string]string)
	// Flush envoie les événements en attente avant l'arrêt du processus.
	Flush(timeout time.Duration)
}

// Nop n'envoie rien (local, tests, ou SENTRY_DSN absent).
type Nop struct{}

// Report implémente Reporter.
func (Nop) Report(context.Context, error, map[string]string) {}

// Flush implémente Reporter.
func (Nop) Flush(time.Duration) {}

// Sentry envoie les erreurs à Sentry.
type Sentry struct {
	hub *sentry.Hub
}

// NewSentry crée le client Sentry. release identifie la version déployée (SHA du commit).
func NewSentry(dsn, environment, release string) (*Sentry, error) {
	client, err := sentry.NewClient(sentry.ClientOptions{
		Dsn:              dsn,
		Environment:      environment,
		Release:          release,
		AttachStacktrace: true,
		SendDefaultPII:   false,
		BeforeSend: func(event *sentry.Event, _ *sentry.EventHint) *sentry.Event {
			return scrub(event)
		},
	})
	if err != nil {
		return nil, fmt.Errorf("configuration de Sentry : %w", err)
	}
	return &Sentry{hub: sentry.NewHub(client, sentry.NewScope())}, nil
}

// Report implémente Reporter.
func (s *Sentry) Report(_ context.Context, err error, tags map[string]string) {
	hub := s.hub.Clone()
	hub.WithScope(func(scope *sentry.Scope) {
		for k, v := range tags {
			scope.SetTag(k, v)
		}
		hub.CaptureException(err)
	})
}

// Flush implémente Reporter.
func (s *Sentry) Flush(timeout time.Duration) { s.hub.Flush(timeout) }

// scrub retire tout ce qui pourrait contenir une donnée personnelle.
func scrub(e *sentry.Event) *sentry.Event {
	e.Request = nil
	e.User = sentry.User{}
	e.ServerName = ""
	e.Breadcrumbs = nil
	return e
}
