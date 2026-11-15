package errtrack

import (
	"testing"

	"github.com/getsentry/sentry-go"
)

func TestScrubRemovesPersonalData(t *testing.T) {
	e := &sentry.Event{
		Request:     &sentry.Request{URL: "https://api/v1/search?lat=6.1&lng=1.2", Headers: map[string]string{"Authorization": "Bearer x"}},
		User:        sentry.User{Email: "ama@example.tg", IPAddress: "1.2.3.4"},
		ServerName:  "vps-1",
		Breadcrumbs: []*sentry.Breadcrumb{{Message: "ama@example.tg"}},
		Message:     "erreur interne",
	}
	out := scrub(e)
	if out.Request != nil || out.User.Email != "" || out.User.IPAddress != "" || out.ServerName != "" || out.Breadcrumbs != nil {
		t.Fatalf("données personnelles restantes : %+v", out)
	}
	if out.Message != "erreur interne" {
		t.Fatal("le message d'erreur doit être conservé")
	}
}

func TestNewSentryRejectsInvalidDSN(t *testing.T) {
	if _, err := NewSentry("pas-un-dsn", "test", ""); err == nil {
		t.Fatal("un DSN invalide doit être refusé au démarrage")
	}
}
