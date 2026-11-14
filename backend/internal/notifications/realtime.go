package notifications

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"sync"
	"time"

	"github.com/coder/websocket/wsjson"
	"github.com/google/uuid"
	"github.com/riverqueue/river"

	"ivia/backend/internal/platform/httpapi"
	"ivia/backend/internal/platform/identity"
)

// Temps réel (spec 036) : chaque notification, et chaque signal discret (étape d'une course,
// position d'un livreur pour le back-office), est poussé aussitôt aux apps ouvertes de son
// destinataire, sans attendre leur relecture. Publié après la validation de la transaction
// (tâche River) : l'app qui relit voit toujours l'état à jour. En mémoire : le monolithe tourne
// sur un seul serveur (ADR 0004).

// Event est un événement poussé à une app ouverte.
type Event struct {
	ID    string            `json:"id"`
	Kind  string            `json:"kind"`
	Title string            `json:"title,omitempty"`
	Body  string            `json:"body,omitempty"`
	Data  map[string]string `json:"data"`
	At    time.Time         `json:"at"`
}

type busKey struct {
	user uuid.UUID
	app  App
}

// broadcastAdmins : clé des événements de tous les admins.
var broadcastAdmins = busKey{app: AppAdmin}

// Bus diffuse les événements aux connexions ouvertes.
type Bus struct {
	mu   sync.Mutex
	subs map[busKey]map[chan Event]struct{}
}

func newBus() *Bus { return &Bus{subs: map[busKey]map[chan Event]struct{}{}} }

// Subscribe ouvre un abonnement (un admin reçoit aussi les événements de tous les admins).
func (b *Bus) Subscribe(user uuid.UUID, app App) (<-chan Event, func()) {
	c := make(chan Event, 32)
	keys := []busKey{{user, app}}
	if app == AppAdmin {
		keys = append(keys, broadcastAdmins)
	}
	b.mu.Lock()
	for _, k := range keys {
		if b.subs[k] == nil {
			b.subs[k] = map[chan Event]struct{}{}
		}
		b.subs[k][c] = struct{}{}
	}
	b.mu.Unlock()
	return c, func() {
		b.mu.Lock()
		defer b.mu.Unlock()
		for _, k := range keys {
			delete(b.subs[k], c)
			if len(b.subs[k]) == 0 {
				delete(b.subs, k)
			}
		}
	}
}

func (b *Bus) publish(k busKey, e Event) {
	if e.ID == "" {
		e.ID = uuid.NewString()
	}
	if e.At.IsZero() {
		e.At = time.Now().UTC()
	}
	if e.Data == nil {
		e.Data = map[string]string{}
	}
	b.mu.Lock()
	defer b.mu.Unlock()
	for c := range b.subs[k] {
		select {
		case c <- e:
		default: // connexion lente : l'app relira à la reconnexion
		}
	}
}

// PublishAdmins pousse aussitôt un événement à tous les back-offices ouverts (positions en direct,
// rien d'enregistré).
func (s *Service) PublishAdmins(kind string, data map[string]string) {
	s.bus.publish(broadcastAdmins, Event{Kind: kind, Data: data})
}

// Signal pousse un événement discret (sans notification ni push) à une app d'un utilisateur, après
// la validation de la transaction en cours : étape d'une course, commande à relire.
func (s *Service) Signal(ctx context.Context, userID uuid.UUID, app App, kind string, data map[string]string) error {
	return s.jobs.Enqueue(ctx, SignalArgs{UserID: &userID, App: app, EventKind: kind, Data: data}, nil)
}

// SignalAdmins pousse un événement discret à tous les back-offices ouverts.
func (s *Service) SignalAdmins(ctx context.Context, kind string, data map[string]string) error {
	return s.jobs.Enqueue(ctx, SignalArgs{App: AppAdmin, EventKind: kind, Data: data}, nil)
}

// SignalArgs : événement discret publié après la transaction.
type SignalArgs struct {
	UserID    *uuid.UUID        `json:"user_id"`
	App       App               `json:"app"`
	EventKind string            `json:"kind"`
	Data      map[string]string `json:"data"`
}

// Kind implémente river.JobArgs.
func (SignalArgs) Kind() string { return "notifications.signal" }

// InsertOpts : un signal manqué est rattrapé par la relecture des apps.
func (SignalArgs) InsertOpts() river.InsertOpts { return river.InsertOpts{MaxAttempts: 1} }

type signalWorker struct {
	river.WorkerDefaults[SignalArgs]
	svc *Service
}

func (w *signalWorker) Work(_ context.Context, job *river.Job[SignalArgs]) error {
	a := job.Args
	k := broadcastAdmins
	if a.UserID != nil {
		k = busKey{*a.UserID, a.App}
	}
	w.svc.bus.publish(k, Event{Kind: a.EventKind, Data: a.Data})
	return nil
}

// publishNotification pousse une notification enregistrée à l'app ouverte de son destinataire.
func (s *Service) publishNotification(n Notification, userID uuid.UUID) {
	data := map[string]string{"notification_id": n.ID.String()}
	for k, v := range n.Data {
		data[k] = v
	}
	s.bus.publish(busKey{userID, n.App}, Event{ID: n.ID.String(), Kind: n.Kind, Title: n.Title, Body: n.Body, Data: data, At: n.CreatedAt})
}

// --- Connexions -------------------------------------------------------------------------------

const keepAlive = 25 * time.Second

// events : WebSocket des événements d'une app (?app=buyer|seller|driver|pharmacy|admin). Le
// navigateur passe le jeton dans le sous-protocole (jamais dans l'URL).
func (h *Handler) events(w http.ResponseWriter, r *http.Request) error {
	q := httpapi.NewQuery(r)
	app, err := appParam(r, q)
	if err != nil {
		return err
	}
	user := identity.MustFromContext(r.Context()).UserID
	conn, err := httpapi.AcceptWebSocket(w, r)
	if err != nil {
		return nil // réponse déjà écrite
	}
	defer conn.CloseNow()
	ctx := conn.CloseRead(r.Context())
	events, stop := h.svc.bus.Subscribe(user, app)
	defer stop()
	if err := wsjson.Write(ctx, conn, Event{ID: uuid.NewString(), Kind: "ready", Data: map[string]string{}, At: time.Now().UTC()}); err != nil {
		return nil
	}
	tick := time.NewTicker(keepAlive)
	defer tick.Stop()
	for {
		select {
		case <-ctx.Done():
			return nil
		case e := <-events:
			if err := wsjson.Write(ctx, conn, e); err != nil {
				return nil
			}
		case <-tick.C:
			c, cancel := context.WithTimeout(ctx, 10*time.Second)
			err := conn.Ping(c)
			cancel()
			if err != nil {
				return nil
			}
		}
	}
}

// adminStream : flux SSE du back-office (relayé par son serveur Next.js) : notifications des
// admins, étapes des courses, positions des livreurs.
func (h *Handler) adminStream(w http.ResponseWriter, r *http.Request) error {
	rc := http.NewResponseController(w)
	_ = rc.SetWriteDeadline(time.Time{}) // flux sans fin : pas de délai d'écriture
	user := identity.MustFromContext(r.Context()).UserID
	events, stop := h.svc.bus.Subscribe(user, AppAdmin)
	defer stop()
	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("X-Accel-Buffering", "no")
	w.WriteHeader(http.StatusOK)
	write := func(e Event) bool {
		b, err := json.Marshal(e)
		if err != nil {
			return true
		}
		if _, err := fmt.Fprintf(w, "data: %s\n\n", b); err != nil {
			return false
		}
		return rc.Flush() == nil
	}
	if !write(Event{ID: uuid.NewString(), Kind: "ready", Data: map[string]string{}, At: time.Now().UTC()}) {
		return nil
	}
	tick := time.NewTicker(keepAlive)
	defer tick.Stop()
	for {
		select {
		case <-r.Context().Done():
			return nil
		case e := <-events:
			if !write(e) {
				return nil
			}
		case <-tick.C:
			if _, err := fmt.Fprint(w, ": keep-alive\n\n"); err != nil || rc.Flush() != nil {
				return nil
			}
		}
	}
}
