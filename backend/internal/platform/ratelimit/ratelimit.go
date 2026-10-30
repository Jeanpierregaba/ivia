// Package ratelimit limite le débit par clé (adresse IP, utilisateur) en mémoire, par fenêtre
// glissante approchée. Suffisant pour un seul processus API (ADR 0008) ; les limites par
// destinataire d'OTP, qui doivent survivre aux redémarrages, sont comptées en base par le module auth.
package ratelimit

import (
	"math"
	"sync"
	"time"
)

// Limiter autorise au plus Limit événements par fenêtre Window et par clé.
type Limiter struct {
	limit  int
	window time.Duration
	now    func() time.Time

	mu      sync.Mutex
	buckets map[string]*bucket
	lastGC  time.Time
}

type bucket struct {
	start time.Time
	prev  int
	count int
}

// New crée un limiteur.
func New(limit int, window time.Duration) *Limiter {
	return &Limiter{limit: limit, window: window, now: time.Now, buckets: map[string]*bucket{}}
}

// Allow enregistre un événement pour key. Si la limite est dépassée, retourne false et le nombre
// de secondes à attendre.
func (l *Limiter) Allow(key string) (bool, int) {
	l.mu.Lock()
	defer l.mu.Unlock()

	now := l.now()
	l.gc(now)

	b, ok := l.buckets[key]
	if !ok {
		b = &bucket{start: now}
		l.buckets[key] = b
	}
	// Fenêtre glissante approchée : la fenêtre précédente compte au prorata du temps restant.
	if elapsed := now.Sub(b.start); elapsed >= l.window {
		if elapsed >= 2*l.window {
			b.prev = 0
		} else {
			b.prev = b.count
		}
		b.count = 0
		b.start = b.start.Add(elapsed.Truncate(l.window))
	}
	weight := 1 - float64(now.Sub(b.start))/float64(l.window)
	estimated := float64(b.prev)*weight + float64(b.count)
	if estimated+1 > float64(l.limit) {
		retry := int(math.Ceil(b.start.Add(l.window).Sub(now).Seconds()))
		return false, max(retry, 1)
	}
	b.count++
	return true, 0
}

// gc supprime les clés inactives, au plus une fois par fenêtre.
func (l *Limiter) gc(now time.Time) {
	if now.Sub(l.lastGC) < l.window {
		return
	}
	l.lastGC = now
	for k, b := range l.buckets {
		if now.Sub(b.start) >= 2*l.window {
			delete(l.buckets, k)
		}
	}
}
