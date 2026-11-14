package ratelimit

import (
	"testing"
	"time"
)

func TestLimiter(t *testing.T) {
	now := time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC)
	l := New(3, time.Minute)
	l.now = func() time.Time { return now }

	for i := range 3 {
		if ok, _ := l.Allow("ip"); !ok {
			t.Fatalf("événement %d refusé", i+1)
		}
	}
	ok, retry := l.Allow("ip")
	if ok || retry <= 0 || retry > 60 {
		t.Fatalf("4e événement : ok=%v retry=%d", ok, retry)
	}
	if ok, _ := l.Allow("autre"); !ok {
		t.Fatal("les clés sont indépendantes")
	}

	// Deux fenêtres plus tard, tout est oublié.
	now = now.Add(2 * time.Minute)
	if ok, _ := l.Allow("ip"); !ok {
		t.Fatal("la limite doit se réinitialiser")
	}
}
