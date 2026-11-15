package mapping

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"math"
	"sort"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/redis/go-redis/v9"

	"ivia/backend/internal/admin"
	"ivia/backend/internal/mapping/store"
	"ivia/backend/internal/platform/apperr"
	"ivia/backend/internal/platform/database"
	"ivia/backend/internal/platform/validate"
)

const (
	country        = "TG"
	defaultCity    = "lome"
	googleFallback = 3 // Google seulement si moins de résultats locaux que cela
	reverseTTL     = 30 * 24 * time.Hour
	estimateTTL    = 5 * time.Minute
	tripRetention  = 180 * 24 * time.Hour
)

// Config choisit les fournisseurs (variables d'environnement). Rien d'externe n'est appelé sans
// configuration explicite.
type Config struct {
	Routing, Geocoding, Places string
	OSRMCar, OSRMMoto          string
	NominatimURL               string
	GooglePlacesKey            string
	RedisURL                   string
}

// Service est le GeoService.
type Service struct {
	db      *database.DB
	audit   *admin.Service
	logger  *slog.Logger
	routing RoutingProvider
	fall    RoutingProvider
	geocode GeocodingProvider
	google  PlaceSearchProvider
	drivers DriverLocationStore
	cache   cacheStore
	hub     *hub
	cfg     Config
	events  AdminEvents
}

// AdminEvents pousse un événement aux back-offices ouverts (module notifications).
type AdminEvents interface {
	PublishAdmins(kind string, data map[string]string)
}

// SetEvents branche la diffusion en direct vers le back-office (positions des livreurs).
func (s *Service) SetEvents(e AdminEvents) { s.events = e }

// New assemble le service selon la configuration.
func New(db *database.DB, audit *admin.Service, logger *slog.Logger, cfg Config) (*Service, error) {
	s := &Service{db: db, audit: audit, logger: logger, fall: Haversiner{}, cfg: cfg, hub: newHub()}
	switch cfg.Routing {
	case "", "haversine":
		s.routing = Haversiner{}
	case "osrm":
		if cfg.OSRMCar == "" {
			return nil, errors.New("OSRM_URL manquant pour GEO_ROUTING_PROVIDER=osrm")
		}
		s.routing = NewOSRM(cfg.OSRMCar, cfg.OSRMMoto)
	default:
		return nil, fmt.Errorf("GEO_ROUTING_PROVIDER inconnu : %s", cfg.Routing)
	}
	switch cfg.Geocoding {
	case "", "none":
	case "nominatim":
		if cfg.NominatimURL == "" {
			return nil, errors.New("NOMINATIM_URL manquant pour GEO_GEOCODING_PROVIDER=nominatim")
		}
		s.geocode = NewNominatim(cfg.NominatimURL)
	default:
		return nil, fmt.Errorf("GEO_GEOCODING_PROVIDER inconnu : %s", cfg.Geocoding)
	}
	switch cfg.Places {
	case "", "local":
	case "composite":
		if cfg.GooglePlacesKey == "" {
			return nil, errors.New("GOOGLE_PLACES_API_KEY manquant pour GEO_PLACES_PROVIDER=composite")
		}
		s.google = NewGooglePlaces(cfg.GooglePlacesKey)
	default:
		return nil, fmt.Errorf("GEO_PLACES_PROVIDER inconnu : %s", cfg.Places)
	}
	if cfg.RedisURL != "" {
		opt, err := redis.ParseURL(cfg.RedisURL)
		if err != nil {
			return nil, errors.New("REDIS_URL invalide")
		}
		c := redis.NewClient(opt)
		s.drivers, s.cache = &RedisGeoStore{Client: c}, redisCache{client: c}
	} else {
		s.drivers, s.cache = &MemoryStore{}, &memoryCache{}
	}
	return s, nil
}

func (s *Service) q(ctx context.Context) *store.Queries { return store.New(s.db.Conn(ctx)) }

func (s *Service) bump(ctx context.Context, metric string) {
	// Un compteur raté ne fait pas échouer la demande.
	if err := s.q(ctx).BumpMetric(ctx, store.BumpMetricParams{Metric: metric, Value: 1}); err != nil {
		s.logger.Warn("compteur géo", "metric", metric, "err", err)
	}
}

// Route calcule un itinéraire ; routage indisponible : vol d'oiseau × 1,3, jamais Google.
func (s *Service) Route(ctx context.Context, profile string, points []LatLng) (Route, error) {
	r, err := s.routing.Route(ctx, profile, points)
	if err == nil {
		return r, nil
	}
	s.logger.Warn("routage indisponible, repli à vol d'oiseau", "err", err)
	s.bump(ctx, "routing_fallback")
	return s.fall.Route(ctx, profile, points)
}

// Matrix calcule les durées en un seul appel, avec le même repli.
func (s *Service) Matrix(ctx context.Context, profile string, sources, destinations []LatLng) (Matrix, error) {
	m, err := s.routing.Matrix(ctx, profile, sources, destinations)
	if err == nil {
		return m, nil
	}
	s.logger.Warn("matrice indisponible, repli à vol d'oiseau", "err", err)
	s.bump(ctx, "routing_fallback")
	return s.fall.Matrix(ctx, profile, sources, destinations)
}

// Reverse donne le libellé d'une position : lieu Ivia à moins de 50 m, sinon Nominatim, sinon coordonnées.
func (s *Service) Reverse(ctx context.Context, p LatLng) (Address, error) {
	if name, err := s.q(ctx).NearestPlace(ctx, store.NearestPlaceParams{Lat: p.Lat, Lng: p.Lng}); err == nil {
		return Address{Label: name}, nil
	} else if !database.IsNoRows(err) {
		return Address{}, fmt.Errorf("lieu proche : %w", err)
	}
	coord := fmt.Sprintf("%.5f, %.5f", p.Lat, p.Lng)
	if s.geocode == nil {
		return Address{Label: coord}, nil
	}
	key := fmt.Sprintf("reverse:%.4f:%.4f", p.Lat, p.Lng)
	if v, ok := s.cache.Get(ctx, key); ok {
		s.bump(ctx, "reverse_cache_hit")
		return Address{Label: v}, nil
	}
	s.bump(ctx, "reverse_cache_miss")
	a, err := s.geocode.Reverse(ctx, p)
	if err != nil {
		s.logger.Warn("géocodage indisponible", "err", err)
		return Address{Label: coord}, nil
	}
	s.cache.Set(ctx, key, a.Label, reverseTTL)
	return a, nil
}

// Autocomplete : lieux personnels, base Ivia, puis Google en secours seulement.
func (s *Service) Autocomplete(ctx context.Context, userID uuid.UUID, q string, near *LatLng, session string) ([]Suggestion, error) {
	q = validate.Clean(q)
	if len([]rune(q)) < 3 {
		return []Suggestion{}, nil
	}
	s.bump(ctx, "search_total")
	st := s.q(ctx)
	mine, err := st.ListUserPlaces(ctx, userID)
	if err != nil {
		return nil, fmt.Errorf("lieux personnels : %w", err)
	}
	out := []Suggestion{}
	low := strings.ToLower(q)
	for _, m := range mine {
		if strings.Contains(strings.ToLower(m.Label), low) || strings.Contains(strings.ToLower(m.AddressLabel), low) {
			out = append(out, Suggestion{ID: "personal:" + m.ID.String(), Name: m.Label, Address: m.AddressLabel, Source: "personal", Lat: m.Lat, Lng: m.Lng})
		}
	}
	center := LatLng{Lat: 6.1319, Lng: 1.2228} // Lomé, sans position connue
	if near != nil {
		center = *near
	}
	rows, err := st.SearchPlaces(ctx, store.SearchPlacesParams{Country: country, Q: q, Lat: center.Lat, Lng: center.Lng, Lim: 10})
	if err != nil {
		return nil, fmt.Errorf("recherche de lieux : %w", err)
	}
	for _, r := range rows {
		out = append(out, Suggestion{ID: r.ID.String(), Name: r.Name, Address: r.AddressLabel, Source: "ivia", Lat: r.Lat, Lng: r.Lng})
	}
	if len(out) >= googleFallback || s.google == nil {
		if len(out) > 0 {
			s.bump(ctx, "search_local")
		}
		return out, nil
	}
	s.bump(ctx, "google_autocomplete")
	more, err := s.google.Autocomplete(ctx, q, near, session, country)
	if err != nil {
		s.logger.Warn("recherche externe indisponible", "err", err)
		return out, nil
	}
	return append(out, more...), nil
}

// PlaceView est un lieu résolu.
type PlaceView struct {
	ID       string `json:"id"`
	Name     string `json:"name"`
	Address  string `json:"address"`
	Location LatLng `json:"location"`
	Source   string `json:"source"`
}

// PlaceDetails résout un lieu ; un lieu Google choisi entre dans la base Ivia.
func (s *Service) PlaceDetails(ctx context.Context, id, session string) (PlaceView, error) {
	notFound := apperr.NotFound("place_not_found", "Lieu introuvable.")
	if ext, ok := strings.CutPrefix(id, "google:"); ok {
		if s.google == nil {
			return PlaceView{}, notFound
		}
		s.bump(ctx, "google_details")
		d, err := s.google.Details(ctx, ext, session)
		if err != nil {
			s.logger.Warn("détail du lieu externe indisponible", "err", err)
			return PlaceView{}, apperr.Unavailable("places_unavailable", "Recherche indisponible pour le moment.")
		}
		pid, err := s.q(ctx).LearnGooglePlace(ctx, store.LearnGooglePlaceParams{
			Name: d.Name, AddressLabel: d.Address, Lat: d.Location.Lat, Lng: d.Location.Lng, Country: country, ExternalID: &d.ExternalID,
		})
		if err != nil {
			return PlaceView{}, fmt.Errorf("apprentissage du lieu : %w", err)
		}
		return PlaceView{ID: pid.String(), Name: d.Name, Address: d.Address, Location: d.Location, Source: "google"}, nil
	}
	pid, err := uuid.Parse(id)
	if err != nil {
		return PlaceView{}, notFound
	}
	r, err := s.q(ctx).GetPlace(ctx, pid)
	if database.IsNoRows(err) {
		return PlaceView{}, notFound
	}
	if err != nil {
		return PlaceView{}, fmt.Errorf("lieu : %w", err)
	}
	if err := s.q(ctx).TouchPlace(ctx, pid); err != nil {
		s.logger.Warn("compteur du lieu", "err", err)
	}
	return PlaceView{ID: r.ID.String(), Name: r.Name, Address: r.AddressLabel, Location: LatLng{Lat: r.Lat, Lng: r.Lng}, Source: r.Source}, nil
}

// UserPlace est un lieu personnel.
type UserPlace struct {
	ID       uuid.UUID `json:"id"`
	Label    string    `json:"label"`
	Type     string    `json:"type"`
	Address  string    `json:"address"`
	Location LatLng    `json:"location"`
}

// UserPlaces retourne les lieux personnels, Maison et Travail d'abord.
func (s *Service) UserPlaces(ctx context.Context, userID uuid.UUID) ([]UserPlace, error) {
	rows, err := s.q(ctx).ListUserPlaces(ctx, userID)
	if err != nil {
		return nil, fmt.Errorf("lieux personnels : %w", err)
	}
	out := make([]UserPlace, len(rows))
	for i, r := range rows {
		out[i] = UserPlace{ID: r.ID, Label: r.Label, Type: r.Type, Address: r.AddressLabel, Location: LatLng{Lat: r.Lat, Lng: r.Lng}}
	}
	return out, nil
}

// AddUserPlace enregistre un lieu personnel ; seules les 10 dernières destinations sont gardées.
func (s *Service) AddUserPlace(ctx context.Context, userID uuid.UUID, in UserPlace) (UserPlace, error) {
	in.Label, in.Address = validate.Clean(in.Label), validate.Clean(in.Address)
	v := validate.New()
	v.Text("label", in.Label, 1, 80)
	v.Text("address", in.Address, 0, 300)
	v.Check(in.Type == "home" || in.Type == "work" || in.Type == "favorite" || in.Type == "recent", "type", "Type inconnu.")
	v.Coordinates("location.", in.Location.Lat, in.Location.Lng)
	if err := v.Err(); err != nil {
		return UserPlace{}, err
	}
	err := s.db.InTx(ctx, func(ctx context.Context) error {
		q := s.q(ctx)
		id, err := q.CreateUserPlace(ctx, store.CreateUserPlaceParams{UserID: userID, Label: in.Label, Type: in.Type, Lat: in.Location.Lat, Lng: in.Location.Lng, AddressLabel: in.Address})
		if err != nil {
			return fmt.Errorf("lieu personnel : %w", err)
		}
		in.ID = id
		return q.TrimRecentPlaces(ctx, userID)
	})
	return in, err
}

// DeleteUserPlace retire un lieu personnel du compte.
func (s *Service) DeleteUserPlace(ctx context.Context, userID, id uuid.UUID) error {
	n, err := s.q(ctx).DeleteUserPlace(ctx, store.DeleteUserPlaceParams{ID: id, UserID: userID})
	if err != nil {
		return fmt.Errorf("lieu personnel : %w", err)
	}
	if n == 0 {
		return apperr.NotFound("place_not_found", "Lieu introuvable.")
	}
	return nil
}

// OnAccountDeleted efface les lieux personnels (users.DeletionHook).
func (s *Service) OnAccountDeleted(ctx context.Context, userID uuid.UUID) error {
	if err := s.q(ctx).DeleteUserPlacesOf(ctx, userID); err != nil {
		return fmt.Errorf("effacement des lieux personnels : %w", err)
	}
	return nil
}

// --- Estimation et matching ---------------------------------------------------------------------

// Rules est le tarif d'une zone, saisi au back-office : aucun prix n'est inscrit dans le code.
type Rules struct {
	BaseXOF    int64   `json:"base_xof"`
	PerKmXOF   int64   `json:"per_km_xof"`
	PerMinXOF  int64   `json:"per_min_xof"`
	Multiplier float64 `json:"multiplier"`
}

// Estimate est un prix avant commande.
type Estimate struct {
	Route       Route  `json:"route"`
	PriceXOF    int64  `json:"price_xof"`
	Zone        string `json:"zone"`
	DriversNear int    `json:"drivers_near"`
	PickupEtaS  int64  `json:"pickup_eta_s,omitempty"`
}

// Estimate calcule le prix au tarif de la zone du départ, multiplicateur éventuel compris.
func (s *Service) Estimate(ctx context.Context, origin, destination LatLng, vehicle string) (Estimate, error) {
	v := validate.New()
	v.Coordinates("origin.", origin.Lat, origin.Lng)
	v.Coordinates("destination.", destination.Lat, destination.Lng)
	v.Check(vehicle == "car" || vehicle == "moto", "vehicle", "Véhicule attendu : car ou moto.")
	if err := v.Err(); err != nil {
		return Estimate{}, err
	}
	key := fmt.Sprintf("estimate:%.4f:%.4f:%.4f:%.4f:%s", origin.Lat, origin.Lng, destination.Lat, destination.Lng, vehicle)
	var out Estimate
	if raw, ok := s.cache.Get(ctx, key); ok && json.Unmarshal([]byte(raw), &out) == nil {
		return s.withDrivers(ctx, out, origin, vehicle), nil
	}
	q := s.q(ctx)
	zones, err := q.ZonesAt(ctx, store.ZonesAtParams{Lat: origin.Lat, Lng: origin.Lng})
	if err != nil {
		return Estimate{}, fmt.Errorf("zones du départ : %w", err)
	}
	var tariff *Rules
	multiplier, served := 1.0, false
	for _, z := range zones {
		var r Rules
		if err := json.Unmarshal(z.Rules, &r); err != nil {
			return Estimate{}, fmt.Errorf("tarif de la zone : %w", err)
		}
		switch z.Type {
		case "service_area":
			served = true
		case "surge":
			if r.Multiplier > multiplier {
				multiplier = r.Multiplier
			}
		case "pricing", "airport":
			if tariff == nil || z.Type == "airport" {
				t := r
				tariff, out.Zone = &t, z.Name
			}
		}
	}
	areas, err := q.CountServiceAreas(ctx)
	if err != nil {
		return Estimate{}, fmt.Errorf("zones desservies : %w", err)
	}
	if areas > 0 && !served {
		return Estimate{}, apperr.Unprocessable("zone_not_served", "Ce point de départ n'est pas encore desservi.")
	}
	if tariff == nil {
		return Estimate{}, apperr.Unprocessable("pricing_missing", "Aucun tarif n'est défini pour ce point de départ.")
	}
	if out.Route, err = s.Route(ctx, vehicle, []LatLng{origin, destination}); err != nil {
		return Estimate{}, err
	}
	price := float64(tariff.BaseXOF) + float64(out.Route.DistanceM)/1000*float64(tariff.PerKmXOF) + float64(out.Route.DurationS)/60*float64(tariff.PerMinXOF)
	if tariff.Multiplier > 0 {
		multiplier *= tariff.Multiplier
	}
	// Arrondi aux 5 F, la plus petite pièce courante.
	out.PriceXOF = int64(math.Round(price*multiplier/5)) * 5
	if raw, err := json.Marshal(out); err == nil {
		s.cache.Set(ctx, key, string(raw), estimateTTL)
	}
	return s.withDrivers(ctx, out, origin, vehicle), nil
}

func (s *Service) withDrivers(ctx context.Context, e Estimate, origin LatLng, vehicle string) Estimate {
	near, err := s.MatchDrivers(ctx, origin, vehicle, 1)
	if err != nil {
		s.logger.Warn("livreurs proches", "err", err)
		return e
	}
	e.DriversNear = len(near)
	if len(near) > 0 {
		e.PickupEtaS = near[0].EtaS
	}
	return e
}

// MatchDrivers cherche par paliers (3, 5, 8 km), puis classe par durée réelle en un seul appel.
func (s *Service) MatchDrivers(ctx context.Context, pickup LatLng, vehicle string, limit int) ([]DriverCandidate, error) {
	var found []DriverCandidate
	for _, r := range []float64{3000, 5000, 8000} {
		rows, err := s.drivers.Nearby(ctx, defaultCity, vehicle, pickup, r, 20)
		if err != nil {
			return nil, err
		}
		found = found[:0]
		for _, c := range rows {
			if c.Status == "available" {
				found = append(found, c)
			}
		}
		if len(found) > 0 {
			break
		}
	}
	if len(found) == 0 {
		return []DriverCandidate{}, nil
	}
	sources := make([]LatLng, len(found))
	for i, c := range found {
		sources[i] = c.Position
	}
	m, err := s.Matrix(ctx, vehicle, sources, []LatLng{pickup})
	if err != nil {
		return nil, err
	}
	for i := range found {
		if !math.IsInf(m.DurationsS[i][0], 1) {
			found[i].EtaS = int64(m.DurationsS[i][0])
		}
	}
	sort.SliceStable(found, func(i, j int) bool { return found[i].EtaS < found[j].EtaS })
	if len(found) > limit {
		found = found[:limit]
	}
	return found, nil
}

// TraceOf recale la trace d'un trajet : distance réellement parcourue, pour la facturation et les litiges.
func (s *Service) TraceOf(ctx context.Context, tripID uuid.UUID, profile string) (MatchedTrace, error) {
	rows, err := s.q(ctx).ListTripPoints(ctx, tripID)
	if err != nil {
		return MatchedTrace{}, fmt.Errorf("trace : %w", err)
	}
	pts := make([]GpsPoint, len(rows))
	for i, r := range rows {
		pts[i] = GpsPoint{LatLng: LatLng{Lat: r.Lat, Lng: r.Lng}, At: r.RecordedAt}
	}
	m, err := s.routing.MatchTrace(ctx, profile, pts)
	if err == nil {
		return m, nil
	}
	s.logger.Warn("recalage indisponible, somme des segments", "err", err)
	return s.fall.MatchTrace(ctx, profile, pts)
}

// PurgeTrips efface les traces de plus de 180 jours : ce sont des données personnelles.
func (s *Service) PurgeTrips(ctx context.Context) error {
	if _, err := s.q(ctx).PurgeTripPoints(ctx, time.Now().Add(-tripRetention)); err != nil {
		return fmt.Errorf("purge des traces : %w", err)
	}
	return nil
}

// --- Back-office ------------------------------------------------------------------------------

// AdminPlace est un lieu vu par le back-office.
type AdminPlace struct {
	ID         uuid.UUID `json:"id"`
	Name       string    `json:"name"`
	Aliases    []string  `json:"aliases"`
	Category   string    `json:"category"`
	Address    string    `json:"address"`
	Source     string    `json:"source"`
	UsageCount int32     `json:"usage_count"`
	IsActive   bool      `json:"is_active"`
	Location   LatLng    `json:"location"`
}

// PlaceInput est la saisie d'un lieu.
type PlaceInput struct {
	Name     string   `json:"name"`
	Aliases  []string `json:"aliases"`
	Category string   `json:"category"`
	Address  string   `json:"address"`
	Location LatLng   `json:"location"`
	IsActive bool     `json:"is_active"`
}

func (in *PlaceInput) clean() error {
	in.Name, in.Category, in.Address = validate.Clean(in.Name), validate.Clean(in.Category), validate.Clean(in.Address)
	if in.Aliases == nil {
		in.Aliases = []string{}
	}
	v := validate.New()
	v.Text("name", in.Name, 2, 160)
	v.Text("category", in.Category, 0, 60)
	v.Text("address", in.Address, 0, 300)
	v.Check(len(in.Aliases) <= 20, "aliases", "20 noms au plus.")
	v.Coordinates("location.", in.Location.Lat, in.Location.Lng)
	return v.Err()
}

// AdminPlaces liste les lieux.
func (s *Service) AdminPlaces(ctx context.Context, q *string, limit, offset int32) ([]AdminPlace, error) {
	rows, err := s.q(ctx).AdminListPlaces(ctx, store.AdminListPlacesParams{Q: q, Lim: limit, Off: offset})
	if err != nil {
		return nil, fmt.Errorf("lieux : %w", err)
	}
	out := make([]AdminPlace, len(rows))
	for i, r := range rows {
		out[i] = AdminPlace{ID: r.ID, Name: r.Name, Aliases: r.Aliases, Category: r.Category, Address: r.AddressLabel, Source: r.Source, UsageCount: r.UsageCount, IsActive: r.IsActive, Location: LatLng{Lat: r.Lat, Lng: r.Lng}}
	}
	return out, nil
}

// SavePlace crée (id nul) ou modifie un lieu, journalisé.
func (s *Service) SavePlace(ctx context.Context, adminID uuid.UUID, id *uuid.UUID, in PlaceInput) (uuid.UUID, error) {
	if err := in.clean(); err != nil {
		return uuid.Nil, err
	}
	var out uuid.UUID
	err := s.db.InTx(ctx, func(ctx context.Context) error {
		q := s.q(ctx)
		if id == nil {
			pid, err := q.CreatePlace(ctx, store.CreatePlaceParams{Name: in.Name, Aliases: in.Aliases, Category: in.Category, AddressLabel: in.Address, Lat: in.Location.Lat, Lng: in.Location.Lng, Country: country, Source: "ivia"})
			if err != nil {
				return fmt.Errorf("création du lieu : %w", err)
			}
			out = pid
		} else {
			n, err := q.UpdatePlace(ctx, store.UpdatePlaceParams{ID: *id, Name: in.Name, Aliases: in.Aliases, Category: in.Category, AddressLabel: in.Address, Lat: in.Location.Lat, Lng: in.Location.Lng, IsActive: in.IsActive})
			if err != nil {
				return fmt.Errorf("modification du lieu : %w", err)
			}
			if n == 0 {
				return apperr.NotFound("place_not_found", "Lieu introuvable.")
			}
			out = *id
		}
		return s.audit.Record(ctx, admin.AuditEntry{AdminID: &adminID, Action: "place.saved", TargetType: "place", TargetID: out.String(), After: in})
	})
	return out, err
}

// ImportPlace ajoute un lieu d'import (source osm ou ivia), sans doublon par identifiant externe.
func (s *Service) ImportPlace(ctx context.Context, source, externalID string, in PlaceInput) error {
	if err := in.clean(); err != nil {
		return err
	}
	var ext *string
	if externalID != "" {
		ext = &externalID
	}
	_, err := s.q(ctx).CreatePlace(ctx, store.CreatePlaceParams{Name: in.Name, Aliases: in.Aliases, Category: in.Category, AddressLabel: in.Address, Lat: in.Location.Lat, Lng: in.Location.Lng, Country: country, Source: source, ExternalID: ext})
	if err != nil {
		return fmt.Errorf("import du lieu : %w", err)
	}
	return nil
}

// Zone est une zone vue par le back-office.
type Zone struct {
	ID       uuid.UUID       `json:"id"`
	Name     string          `json:"name"`
	Type     string          `json:"type"`
	Rules    json.RawMessage `json:"rules"`
	IsActive bool            `json:"is_active"`
	GeoJSON  json.RawMessage `json:"geojson"`
}

// ZoneInput est la saisie d'une zone. GeoJSON : un polygone.
type ZoneInput struct {
	Name     string          `json:"name"`
	Type     string          `json:"type"`
	Rules    json.RawMessage `json:"rules"`
	IsActive bool            `json:"is_active"`
	GeoJSON  json.RawMessage `json:"geojson"`
}

// Zones liste les zones.
func (s *Service) Zones(ctx context.Context) ([]Zone, error) {
	rows, err := s.q(ctx).ListZones(ctx)
	if err != nil {
		return nil, fmt.Errorf("zones : %w", err)
	}
	out := make([]Zone, len(rows))
	for i, r := range rows {
		out[i] = Zone{ID: r.ID, Name: r.Name, Type: r.Type, Rules: r.Rules, IsActive: r.IsActive, GeoJSON: json.RawMessage(r.Geojson)}
	}
	return out, nil
}

func (in *ZoneInput) clean() error {
	in.Name = validate.Clean(in.Name)
	v := validate.New()
	v.Text("name", in.Name, 2, 120)
	v.Check(in.Type == "service_area" || in.Type == "pricing" || in.Type == "surge" || in.Type == "airport", "type", "Type de zone inconnu.")
	var shape struct {
		Type string `json:"type"`
	}
	v.Check(json.Unmarshal(in.GeoJSON, &shape) == nil && shape.Type == "Polygon", "geojson", "Un polygone GeoJSON est attendu.")
	if len(in.Rules) == 0 {
		in.Rules = json.RawMessage("{}")
	}
	var r Rules
	if json.Unmarshal(in.Rules, &r) != nil {
		v.Add("rules", "Tarif invalide.")
	} else {
		v.Check(r.BaseXOF >= 0 && r.PerKmXOF >= 0 && r.PerMinXOF >= 0 && r.Multiplier >= 0 && r.Multiplier <= 10, "rules", "Tarif invalide.")
	}
	return v.Err()
}

// SaveZone crée (id nul) ou modifie une zone, journalisé.
func (s *Service) SaveZone(ctx context.Context, adminID uuid.UUID, id *uuid.UUID, in ZoneInput) (uuid.UUID, error) {
	if err := in.clean(); err != nil {
		return uuid.Nil, err
	}
	var out uuid.UUID
	err := s.db.InTx(ctx, func(ctx context.Context) error {
		q := s.q(ctx)
		if id == nil {
			zid, err := q.CreateZone(ctx, store.CreateZoneParams{Name: in.Name, Type: in.Type, Geojson: string(in.GeoJSON), Rules: in.Rules, IsActive: in.IsActive})
			if err != nil {
				return apperr.Validation(map[string]string{"geojson": "Polygone refusé : vérifiez qu'il est fermé et valide."})
			}
			out = zid
		} else {
			n, err := q.UpdateZone(ctx, store.UpdateZoneParams{ID: *id, Name: in.Name, Type: in.Type, Geojson: string(in.GeoJSON), Rules: in.Rules, IsActive: in.IsActive})
			if err != nil {
				return apperr.Validation(map[string]string{"geojson": "Polygone refusé : vérifiez qu'il est fermé et valide."})
			}
			if n == 0 {
				return apperr.NotFound("zone_not_found", "Zone introuvable.")
			}
			out = *id
		}
		return s.audit.Record(ctx, admin.AuditEntry{AdminID: &adminID, Action: "zone.saved", TargetType: "zone", TargetID: out.String(), After: map[string]any{"name": in.Name, "type": in.Type, "rules": in.Rules}})
	})
	return out, err
}

// DeleteZone retire une zone, journalisé.
func (s *Service) DeleteZone(ctx context.Context, adminID, id uuid.UUID) error {
	return s.db.InTx(ctx, func(ctx context.Context) error {
		n, err := s.q(ctx).DeleteZone(ctx, id)
		if err != nil {
			return fmt.Errorf("suppression de la zone : %w", err)
		}
		if n == 0 {
			return apperr.NotFound("zone_not_found", "Zone introuvable.")
		}
		return s.audit.Record(ctx, admin.AuditEntry{AdminID: &adminID, Action: "zone.deleted", TargetType: "zone", TargetID: id.String()})
	})
}

// Metrics résume 30 jours : appels aux fournisseurs et taux de résolution locale.
type Metrics struct {
	Routing   string           `json:"routing"`
	Geocoding string           `json:"geocoding"`
	Places    string           `json:"places"`
	Redis     bool             `json:"redis"`
	Totals    map[string]int64 `json:"totals"`
	Days      []MetricDay      `json:"days"`
}

// MetricDay est un compteur d'un jour.
type MetricDay struct {
	Day    string `json:"day"`
	Metric string `json:"metric"`
	Value  int64  `json:"value"`
}

// AdminMetrics retourne les compteurs et les fournisseurs actifs (jamais les clés).
func (s *Service) AdminMetrics(ctx context.Context) (Metrics, error) {
	rows, err := s.q(ctx).ListMetrics(ctx, time.Now().AddDate(0, 0, -30))
	if err != nil {
		return Metrics{}, fmt.Errorf("compteurs géo : %w", err)
	}
	or := func(v, def string) string {
		if v == "" {
			return def
		}
		return v
	}
	out := Metrics{Routing: or(s.cfg.Routing, "haversine"), Geocoding: or(s.cfg.Geocoding, "none"), Places: or(s.cfg.Places, "local"), Redis: s.cfg.RedisURL != "", Totals: map[string]int64{}, Days: make([]MetricDay, len(rows))}
	for i, r := range rows {
		out.Totals[r.Metric] += r.Value
		out.Days[i] = MetricDay{Day: r.Day.Format("2006-01-02"), Metric: r.Metric, Value: r.Value}
	}
	return out, nil
}
