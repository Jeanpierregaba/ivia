package mapping

import (
	"context"
	"net/http"
	"sync"
	"time"

	"github.com/coder/websocket"
	"github.com/coder/websocket/wsjson"
	"github.com/google/uuid"
	"github.com/riverqueue/river"

	"ivia/backend/internal/delivery"
	"ivia/backend/internal/mapping/store"
	"ivia/backend/internal/platform/apperr"
	"ivia/backend/internal/platform/httpapi"
	"ivia/backend/internal/platform/identity"
	"ivia/backend/internal/platform/jobs"
)

func who(r *http.Request) identity.Principal { return identity.MustFromContext(r.Context()) }

// limiter : 120 demandes par minute par compte, pour protéger le budget des API externes.
type limiter struct {
	mu   sync.Mutex
	rows map[uuid.UUID]*window
}

type window struct {
	n  int
	at time.Time
}

func (l *limiter) allow(id uuid.UUID) bool {
	l.mu.Lock()
	defer l.mu.Unlock()
	if l.rows == nil || len(l.rows) > 50000 {
		l.rows = map[uuid.UUID]*window{}
	}
	w := l.rows[id]
	if w == nil || time.Since(w.at) > time.Minute {
		l.rows[id] = &window{n: 1, at: time.Now()}
		return true
	}
	w.n++
	return w.n <= 120
}

// Register enregistre les routes. Toutes demandent un compte : les API derrière coûtent de l'argent.
func (s *Service) Register(rt *httpapi.Router, drivers *delivery.Service) {
	lim := &limiter{}
	limited := func(h httpapi.HandlerFunc) httpapi.HandlerFunc {
		return func(w http.ResponseWriter, r *http.Request) error {
			if !lim.allow(who(r).UserID) {
				return apperr.TooManyRequests("rate_limited", "Trop de recherches : réessayez dans une minute.", 60)
			}
			return h(w, r)
		}
	}
	rt.Auth("GET /v1/geo/places/autocomplete", limited(func(w http.ResponseWriter, r *http.Request) error {
		q := httpapi.NewQuery(r)
		text := q.String("q", 120)
		session := q.String("session", 64)
		lat, lng := q.Float("lat", -90, 90), q.Float("lng", -180, 180)
		if err := q.Err(); err != nil {
			return err
		}
		var near *LatLng
		if lat != nil && lng != nil {
			near = &LatLng{Lat: *lat, Lng: *lng}
		}
		items, err := s.Autocomplete(r.Context(), who(r).UserID, text, near, session)
		if err != nil {
			return err
		}
		return httpapi.OK(w, map[string]any{"items": items})
	}))
	rt.Auth("GET /v1/geo/places/{id}", limited(func(w http.ResponseWriter, r *http.Request) error {
		q := httpapi.NewQuery(r)
		session := q.String("session", 64)
		if err := q.Err(); err != nil {
			return err
		}
		v, err := s.PlaceDetails(r.Context(), r.PathValue("id"), session)
		if err != nil {
			return err
		}
		return httpapi.OK(w, v)
	}))
	rt.Auth("GET /v1/geo/reverse", limited(func(w http.ResponseWriter, r *http.Request) error {
		q := httpapi.NewQuery(r)
		lat, lng := q.Float("lat", -90, 90), q.Float("lng", -180, 180)
		if err := q.Err(); err != nil {
			return err
		}
		if lat == nil || lng == nil {
			return apperr.Validation(map[string]string{"lat": "Position attendue."})
		}
		a, err := s.Reverse(r.Context(), LatLng{Lat: *lat, Lng: *lng})
		if err != nil {
			return err
		}
		return httpapi.OK(w, a)
	}))
	rt.Auth("POST /v1/geo/route", limited(func(w http.ResponseWriter, r *http.Request) error {
		var in struct {
			Origin      LatLng   `json:"origin"`
			Destination LatLng   `json:"destination"`
			Waypoints   []LatLng `json:"waypoints"`
			Profile     string   `json:"profile"`
		}
		if err := httpapi.Decode(r, &in); err != nil {
			return err
		}
		if len(in.Waypoints) > 10 {
			return apperr.Validation(map[string]string{"waypoints": "10 étapes au plus."})
		}
		pts := append(append([]LatLng{in.Origin}, in.Waypoints...), in.Destination)
		route, err := s.Route(r.Context(), in.Profile, pts)
		if err != nil {
			return err
		}
		return httpapi.OK(w, route)
	}))
	rt.Auth("POST /v1/rides/estimate", limited(func(w http.ResponseWriter, r *http.Request) error {
		var in struct {
			Origin      LatLng `json:"origin"`
			Destination LatLng `json:"destination"`
			Vehicle     string `json:"vehicle"`
		}
		if err := httpapi.Decode(r, &in); err != nil {
			return err
		}
		e, err := s.Estimate(r.Context(), in.Origin, in.Destination, in.Vehicle)
		if err != nil {
			return err
		}
		return httpapi.OK(w, e)
	}))

	rt.Auth("GET /v1/geo/my-places", func(w http.ResponseWriter, r *http.Request) error {
		items, err := s.UserPlaces(r.Context(), who(r).UserID)
		if err != nil {
			return err
		}
		return httpapi.OK(w, map[string]any{"items": items})
	})
	rt.Auth("POST /v1/geo/my-places", func(w http.ResponseWriter, r *http.Request) error {
		var in UserPlace
		if err := httpapi.Decode(r, &in); err != nil {
			return err
		}
		p, err := s.AddUserPlace(r.Context(), who(r).UserID, in)
		if err != nil {
			return err
		}
		return httpapi.Created(w, p)
	})
	rt.Auth("DELETE /v1/geo/my-places/{id}", func(w http.ResponseWriter, r *http.Request) error {
		id, err := httpapi.PathUUID(r, "id")
		if err != nil {
			return err
		}
		if err := s.DeleteUserPlace(r.Context(), who(r).UserID, id); err != nil {
			return err
		}
		return httpapi.NoContent(w)
	})

	s.registerAdmin(rt)
	s.registerWS(rt, drivers)
}

func (s *Service) registerAdmin(rt *httpapi.Router) {
	ad := identity.RoleAdmin
	rt.Roles("GET /v1/admin/geo/metrics", func(w http.ResponseWriter, r *http.Request) error {
		m, err := s.AdminMetrics(r.Context())
		if err != nil {
			return err
		}
		return httpapi.OK(w, m)
	}, ad)
	rt.Roles("GET /v1/admin/places", func(w http.ResponseWriter, r *http.Request) error {
		q := httpapi.NewQuery(r)
		p := q.Page()
		text := q.String("q", 120)
		if err := q.Err(); err != nil {
			return err
		}
		var search *string
		if text != "" {
			search = &text
		}
		items, err := s.AdminPlaces(r.Context(), search, p.FetchLimit(), int32(p.Offset))
		if err != nil {
			return err
		}
		return httpapi.OK(w, httpapi.NewList(items, p))
	}, ad)
	rt.Roles("POST /v1/admin/places", func(w http.ResponseWriter, r *http.Request) error {
		var in PlaceInput
		if err := httpapi.Decode(r, &in); err != nil {
			return err
		}
		id, err := s.SavePlace(r.Context(), who(r).UserID, nil, in)
		if err != nil {
			return err
		}
		return httpapi.Created(w, map[string]any{"id": id})
	}, ad)
	rt.Roles("PUT /v1/admin/places/{id}", func(w http.ResponseWriter, r *http.Request) error {
		id, err := httpapi.PathUUID(r, "id")
		if err != nil {
			return err
		}
		var in PlaceInput
		if err := httpapi.Decode(r, &in); err != nil {
			return err
		}
		if _, err := s.SavePlace(r.Context(), who(r).UserID, &id, in); err != nil {
			return err
		}
		return httpapi.OK(w, map[string]any{"id": id})
	}, ad)
	rt.Roles("GET /v1/admin/zones", func(w http.ResponseWriter, r *http.Request) error {
		items, err := s.Zones(r.Context())
		if err != nil {
			return err
		}
		return httpapi.OK(w, map[string]any{"items": items})
	}, ad)
	rt.Roles("POST /v1/admin/zones", func(w http.ResponseWriter, r *http.Request) error {
		var in ZoneInput
		if err := httpapi.Decode(r, &in); err != nil {
			return err
		}
		id, err := s.SaveZone(r.Context(), who(r).UserID, nil, in)
		if err != nil {
			return err
		}
		return httpapi.Created(w, map[string]any{"id": id})
	}, ad)
	rt.Roles("PUT /v1/admin/zones/{id}", func(w http.ResponseWriter, r *http.Request) error {
		id, err := httpapi.PathUUID(r, "id")
		if err != nil {
			return err
		}
		var in ZoneInput
		if err := httpapi.Decode(r, &in); err != nil {
			return err
		}
		if _, err := s.SaveZone(r.Context(), who(r).UserID, &id, in); err != nil {
			return err
		}
		return httpapi.OK(w, map[string]any{"id": id})
	}, ad)
	rt.Roles("DELETE /v1/admin/zones/{id}", func(w http.ResponseWriter, r *http.Request) error {
		id, err := httpapi.PathUUID(r, "id")
		if err != nil {
			return err
		}
		if err := s.DeleteZone(r.Context(), who(r).UserID, id); err != nil {
			return err
		}
		return httpapi.NoContent(w)
	}, ad)
}

// --- Temps réel -------------------------------------------------------------------------------

// Tracked est une position diffusée à celui qui suit sa commande.
type Tracked struct {
	Lat     float64   `json:"lat"`
	Lng     float64   `json:"lng"`
	Heading float64   `json:"heading"`
	Speed   float64   `json:"speed"`
	At      time.Time `json:"at"`
}

// hub diffuse en mémoire : le monolithe tourne sur un seul serveur (ADR 0004, 0008).
type hub struct {
	mu   sync.Mutex
	subs map[uuid.UUID]map[chan Tracked]struct{}
}

func newHub() *hub { return &hub{subs: map[uuid.UUID]map[chan Tracked]struct{}{}} }

func (h *hub) subscribe(id uuid.UUID) (chan Tracked, func()) {
	c := make(chan Tracked, 4)
	h.mu.Lock()
	defer h.mu.Unlock()
	if h.subs[id] == nil {
		h.subs[id] = map[chan Tracked]struct{}{}
	}
	h.subs[id][c] = struct{}{}
	return c, func() {
		h.mu.Lock()
		defer h.mu.Unlock()
		delete(h.subs[id], c)
		if len(h.subs[id]) == 0 {
			delete(h.subs, id)
		}
	}
}

func (h *hub) publish(id uuid.UUID, t Tracked) {
	h.mu.Lock()
	defer h.mu.Unlock()
	for c := range h.subs[id] {
		select {
		case c <- t:
		default: // abonné lent : la position suivante le rattrapera
		}
	}
}

type locationMsg struct {
	Lat      float64 `json:"lat"`
	Lng      float64 `json:"lng"`
	Heading  float64 `json:"heading"`
	Speed    float64 `json:"speed"`
	Accuracy *int32  `json:"accuracy"`
}

func (s *Service) registerWS(rt *httpapi.Router, drivers *delivery.Service) {
	// Positions du livreur, toutes les 3 à 5 s en ligne. Les positions restent refusées hors service.
	rt.Roles("GET /v1/ws/driver/location", func(w http.ResponseWriter, r *http.Request) error {
		userID := who(r).UserID
		d, err := drivers.Me(r.Context(), userID)
		if err != nil {
			return err
		}
		conn, err := websocket.Accept(w, r, nil)
		if err != nil {
			return nil // réponse déjà écrite par Accept
		}
		defer conn.CloseNow()
		conn.SetReadLimit(1024)
		vehicle := "moto"
		if d.VehicleType == "car" {
			vehicle = "car"
		}
		ctx := r.Context()
		defer func() {
			// Le contexte de la demande est peut-être déjà annulé.
			c, cancel := context.WithTimeout(context.Background(), 2*time.Second)
			defer cancel()
			if err := s.drivers.Remove(c, defaultCity, vehicle, userID.String()); err != nil {
				s.logger.Warn("retrait de la position", "err", err)
			}
		}()
		var (
			trip, order uuid.UUID
			checked     time.Time
		)
		for {
			var m locationMsg
			if err := wsjson.Read(ctx, conn, &m); err != nil {
				return nil
			}
			if err := drivers.UpdateLocation(ctx, userID, delivery.LocationInput{Lat: m.Lat, Lng: m.Lng, AccuracyM: m.Accuracy}); err != nil {
				// Trop fréquent : la position reste utile au temps réel. Hors ligne : rien n'est gardé.
				if !apperr.IsCode(err, "rate_limited") {
					conn.Close(websocket.StatusPolicyViolation, "hors service")
					return nil
				}
			}
			if time.Since(checked) > 30*time.Second {
				checked = time.Now()
				trip, order = uuid.Nil, uuid.Nil
				mission, err := drivers.CurrentMission(ctx, userID)
				if err != nil {
					s.logger.Warn("mission en cours", "err", err)
				} else if mission != nil {
					trip, order = mission.ID, mission.OrderID
				}
			}
			status := "available"
			if trip != uuid.Nil {
				status = "busy"
			}
			pos := DriverPosition{DriverID: userID.String(), City: defaultCity, Vehicle: vehicle, Position: LatLng{Lat: m.Lat, Lng: m.Lng}, Heading: m.Heading, Speed: m.Speed, Status: status}
			if err := s.drivers.Upsert(ctx, pos); err != nil {
				s.logger.Warn("position temps réel", "err", err)
			}
			if trip != uuid.Nil {
				now := time.Now()
				speed, heading := float32(m.Speed), float32(m.Heading)
				if err := s.q(ctx).InsertTripPoint(ctx, store.InsertTripPointParams{TripID: trip, RecordedAt: now, Lat: m.Lat, Lng: m.Lng, Speed: &speed, Heading: &heading}); err != nil {
					s.logger.Warn("trace du trajet", "err", err)
				}
				s.hub.publish(order, Tracked{Lat: m.Lat, Lng: m.Lng, Heading: m.Heading, Speed: m.Speed, At: now})
			}
		}
	}, identity.RoleDriver)

	// Suivi d'une commande par son acheteur : la position n'est partagée que le temps de la livraison.
	rt.Auth("GET /v1/ws/orders/{id}/tracking", func(w http.ResponseWriter, r *http.Request) error {
		id, err := httpapi.PathUUID(r, "id")
		if err != nil {
			return err
		}
		info, err := drivers.InfoForBuyer(r.Context(), who(r).UserID, id)
		if err != nil {
			return err
		}
		if info == nil {
			return apperr.NotFound("delivery_not_found", "Pas de livraison en cours.")
		}
		conn, err := websocket.Accept(w, r, nil)
		if err != nil {
			return nil
		}
		defer conn.CloseNow()
		ctx := conn.CloseRead(r.Context())
		updates, stop := s.hub.subscribe(id)
		defer stop()
		for {
			select {
			case <-ctx.Done():
				return nil
			case t := <-updates:
				if err := wsjson.Write(ctx, conn, t); err != nil {
					return nil
				}
			}
		}
	})
}

// PurgeArgs efface les traces trop anciennes.
type PurgeArgs struct{}

// Kind implémente river.JobArgs.
func (PurgeArgs) Kind() string { return "mapping.purge_trips" }

type purgeWorker struct {
	river.WorkerDefaults[PurgeArgs]
	s *Service
}

// Work implémente river.Worker.
func (w *purgeWorker) Work(ctx context.Context, _ *river.Job[PurgeArgs]) error {
	return w.s.PurgeTrips(ctx)
}

// RegisterJobs enregistre la purge quotidienne.
func (s *Service) RegisterJobs(reg *jobs.Registry) {
	river.AddWorker(reg.Workers, &purgeWorker{s: s})
	reg.AddPeriodic(24*time.Hour, func() river.JobArgs { return PurgeArgs{} })
}
