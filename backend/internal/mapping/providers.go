// Package mapping est le GeoService d'Ivia (docs/decisions/0013) : le code métier dépend d'interfaces,
// jamais d'un fournisseur, et les apps n'appellent jamais de routage ni de géocodage directement.
package mapping

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"sync"
	"time"
)

// LatLng est le seul type de coordonnées du code. L'ordre longitude, latitude d'OSRM reste dans son
// adaptateur.
type LatLng struct {
	Lat float64 `json:"lat"`
	Lng float64 `json:"lng"`
}

// Route est un itinéraire. Approximate : estimation à vol d'oiseau, le routage étant indisponible.
type Route struct {
	DistanceM   int64  `json:"distance_m"`
	DurationS   int64  `json:"duration_s"`
	Polyline    string `json:"polyline"`
	Approximate bool   `json:"approximate"`
}

// Matrix donne durées et distances de chaque source vers chaque destination.
type Matrix struct {
	DurationsS [][]float64
	DistancesM [][]float64
}

// GpsPoint est un point d'une trace.
type GpsPoint struct {
	LatLng
	At time.Time
}

// MatchedTrace est une trace recalée sur les routes.
type MatchedTrace struct {
	DistanceM   int64   `json:"distance_m"`
	DurationS   int64   `json:"duration_s"`
	Polyline    string  `json:"polyline"`
	Confidence  float64 `json:"confidence"`
	Approximate bool    `json:"approximate"`
}

// Address est le résultat d'un géocodage inverse.
type Address struct {
	Label string `json:"label"`
}

// Suggestion est un résultat de recherche de lieu.
type Suggestion struct {
	ID      string  `json:"id"`
	Name    string  `json:"name"`
	Address string  `json:"address"`
	Source  string  `json:"source"` // personal | ivia | google
	Lat     float64 `json:"lat,omitempty"`
	Lng     float64 `json:"lng,omitempty"`
}

// PlaceDetail est le détail d'un lieu externe.
type PlaceDetail struct {
	ExternalID string
	Name       string
	Address    string
	Location   LatLng
}

// RoutingProvider calcule itinéraires, matrices et traces. Profile : car ou moto.
type RoutingProvider interface {
	Route(ctx context.Context, profile string, points []LatLng) (Route, error)
	Matrix(ctx context.Context, profile string, sources, destinations []LatLng) (Matrix, error)
	MatchTrace(ctx context.Context, profile string, points []GpsPoint) (MatchedTrace, error)
}

// GeocodingProvider donne l'adresse d'une position.
type GeocodingProvider interface {
	Reverse(ctx context.Context, p LatLng) (Address, error)
}

// PlaceSearchProvider cherche des lieux chez un fournisseur externe.
type PlaceSearchProvider interface {
	Autocomplete(ctx context.Context, q string, near *LatLng, session, country string) ([]Suggestion, error)
	Details(ctx context.Context, externalID, session string) (PlaceDetail, error)
}

var errNoData = errors.New("aucun résultat du fournisseur")

// --- Coupe-circuit ----------------------------------------------------------------------------

// breaker cesse d'appeler un fournisseur après 5 échecs de suite, pendant 30 secondes.
type breaker struct {
	mu       sync.Mutex
	failures int
	until    time.Time
}

var errOpen = errors.New("fournisseur indisponible (coupe-circuit)")

func (b *breaker) do(fn func() error) error {
	b.mu.Lock()
	if time.Now().Before(b.until) {
		b.mu.Unlock()
		return errOpen
	}
	b.mu.Unlock()
	err := fn()
	b.mu.Lock()
	defer b.mu.Unlock()
	if err == nil || errors.Is(err, errNoData) {
		b.failures = 0
		return err
	}
	b.failures++
	if b.failures >= 5 {
		b.failures, b.until = 0, time.Now().Add(30*time.Second)
	}
	return err
}

// --- OSRM -------------------------------------------------------------------------------------

// OSRM interroge des serveurs auto-hébergés, un par profil.
type OSRM struct {
	Car, Moto string
	Client    *http.Client
	br        breaker
}

// NewOSRM crée l'adaptateur (délai court : le repli à vol d'oiseau prend le relais).
func NewOSRM(car, moto string) *OSRM {
	return &OSRM{Car: strings.TrimRight(car, "/"), Moto: strings.TrimRight(moto, "/"), Client: &http.Client{Timeout: 500 * time.Millisecond}}
}

func (o *OSRM) base(profile string) string {
	if profile == "moto" && o.Moto != "" {
		return o.Moto
	}
	return o.Car
}

// coords : OSRM attend longitude,latitude.
func coords(points []LatLng) string {
	parts := make([]string, len(points))
	for i, p := range points {
		parts[i] = strconv.FormatFloat(p.Lng, 'f', 6, 64) + "," + strconv.FormatFloat(p.Lat, 'f', 6, 64)
	}
	return strings.Join(parts, ";")
}

func (o *OSRM) get(ctx context.Context, u string, out any) error {
	return o.br.do(func() error {
		req, err := http.NewRequestWithContext(ctx, http.MethodGet, u, nil)
		if err != nil {
			return err
		}
		resp, err := o.Client.Do(req)
		if err != nil {
			return fmt.Errorf("osrm : %w", err)
		}
		defer resp.Body.Close()
		if resp.StatusCode == http.StatusBadRequest {
			return errNoData // point hors réseau routier
		}
		if resp.StatusCode != http.StatusOK {
			return fmt.Errorf("osrm : statut %d", resp.StatusCode)
		}
		return json.NewDecoder(io.LimitReader(resp.Body, 20<<20)).Decode(out)
	})
}

// Route implémente RoutingProvider.
func (o *OSRM) Route(ctx context.Context, profile string, points []LatLng) (Route, error) {
	var r struct {
		Routes []struct {
			Distance float64 `json:"distance"`
			Duration float64 `json:"duration"`
			Geometry string  `json:"geometry"`
		} `json:"routes"`
	}
	u := o.base(profile) + "/route/v1/driving/" + coords(points) + "?overview=full&geometries=polyline6"
	if err := o.get(ctx, u, &r); err != nil {
		return Route{}, err
	}
	if len(r.Routes) == 0 {
		return Route{}, errNoData
	}
	return Route{DistanceM: int64(r.Routes[0].Distance), DurationS: int64(r.Routes[0].Duration), Polyline: r.Routes[0].Geometry}, nil
}

// Matrix implémente RoutingProvider, en un seul appel.
func (o *OSRM) Matrix(ctx context.Context, profile string, sources, destinations []LatLng) (Matrix, error) {
	all := append(append([]LatLng{}, sources...), destinations...)
	idx := func(from, n int) string {
		s := make([]string, n)
		for i := range s {
			s[i] = strconv.Itoa(from + i)
		}
		return strings.Join(s, ";")
	}
	u := o.base(profile) + "/table/v1/driving/" + coords(all) + "?sources=" + idx(0, len(sources)) +
		"&destinations=" + idx(len(sources), len(destinations)) + "&annotations=duration,distance"
	var r struct {
		Durations [][]*float64 `json:"durations"`
		Distances [][]*float64 `json:"distances"`
	}
	if err := o.get(ctx, u, &r); err != nil {
		return Matrix{}, err
	}
	flat := func(in [][]*float64) [][]float64 {
		out := make([][]float64, len(in))
		for i, row := range in {
			out[i] = make([]float64, len(row))
			for j, v := range row {
				out[i][j] = math.Inf(1) // pas de chemin
				if v != nil {
					out[i][j] = *v
				}
			}
		}
		return out
	}
	return Matrix{DurationsS: flat(r.Durations), DistancesM: flat(r.Distances)}, nil
}

// MatchTrace implémente RoutingProvider : distance réellement parcourue.
func (o *OSRM) MatchTrace(ctx context.Context, profile string, points []GpsPoint) (MatchedTrace, error) {
	if len(points) < 2 {
		return MatchedTrace{}, errNoData
	}
	ll := make([]LatLng, len(points))
	ts := make([]string, len(points))
	rad := make([]string, len(points))
	for i, p := range points {
		ll[i], ts[i], rad[i] = p.LatLng, strconv.FormatInt(p.At.Unix(), 10), "25"
	}
	u := o.base(profile) + "/match/v1/driving/" + coords(ll) + "?overview=full&geometries=polyline6&gaps=ignore&timestamps=" +
		strings.Join(ts, ";") + "&radiuses=" + strings.Join(rad, ";")
	var r struct {
		Matchings []struct {
			Distance   float64 `json:"distance"`
			Duration   float64 `json:"duration"`
			Geometry   string  `json:"geometry"`
			Confidence float64 `json:"confidence"`
		} `json:"matchings"`
	}
	if err := o.get(ctx, u, &r); err != nil {
		return MatchedTrace{}, err
	}
	if len(r.Matchings) == 0 {
		return MatchedTrace{}, errNoData
	}
	out := MatchedTrace{Polyline: r.Matchings[0].Geometry, Confidence: r.Matchings[0].Confidence}
	for _, m := range r.Matchings {
		out.DistanceM += int64(m.Distance)
		out.DurationS += int64(m.Duration)
	}
	return out, nil
}

// Haversine renvoie la distance à vol d'oiseau en mètres.
func Haversine(a, b LatLng) float64 {
	const r = 6371000
	dLat := (b.Lat - a.Lat) * math.Pi / 180
	dLng := (b.Lng - a.Lng) * math.Pi / 180
	s := math.Sin(dLat/2)*math.Sin(dLat/2) + math.Cos(a.Lat*math.Pi/180)*math.Cos(b.Lat*math.Pi/180)*math.Sin(dLng/2)*math.Sin(dLng/2)
	return 2 * r * math.Asin(math.Sqrt(s))
}

const (
	detourFactor = 1.3
	citySpeedMS  = 8.3 // 30 km/h en ville
)

// Haversiner est le repli : vol d'oiseau × 1,3. Aucun appel externe, jamais de bascule vers Google.
type Haversiner struct{}

// Route implémente RoutingProvider.
func (Haversiner) Route(_ context.Context, _ string, points []LatLng) (Route, error) {
	var d float64
	for i := 1; i < len(points); i++ {
		d += Haversine(points[i-1], points[i]) * detourFactor
	}
	return Route{DistanceM: int64(d), DurationS: int64(d / citySpeedMS), Approximate: true}, nil
}

// Matrix implémente RoutingProvider.
func (Haversiner) Matrix(_ context.Context, _ string, sources, destinations []LatLng) (Matrix, error) {
	m := Matrix{DurationsS: make([][]float64, len(sources)), DistancesM: make([][]float64, len(sources))}
	for i, s := range sources {
		m.DurationsS[i], m.DistancesM[i] = make([]float64, len(destinations)), make([]float64, len(destinations))
		for j, d := range destinations {
			dist := Haversine(s, d) * detourFactor
			m.DistancesM[i][j], m.DurationsS[i][j] = dist, dist/citySpeedMS
		}
	}
	return m, nil
}

// MatchTrace implémente RoutingProvider : somme des segments, sans coefficient (la trace suit déjà la route).
func (Haversiner) MatchTrace(_ context.Context, _ string, points []GpsPoint) (MatchedTrace, error) {
	out := MatchedTrace{Approximate: true}
	for i := 1; i < len(points); i++ {
		out.DistanceM += int64(Haversine(points[i-1].LatLng, points[i].LatLng))
	}
	if len(points) > 1 {
		out.DurationS = int64(points[len(points)-1].At.Sub(points[0].At).Seconds())
	}
	return out, nil
}

// --- Nominatim --------------------------------------------------------------------------------

// Nominatim interroge un serveur auto-hébergé, jamais le serveur public.
type Nominatim struct {
	URL    string
	Client *http.Client
	br     breaker
}

// NewNominatim crée l'adaptateur.
func NewNominatim(u string) *Nominatim {
	return &Nominatim{URL: strings.TrimRight(u, "/"), Client: &http.Client{Timeout: 2 * time.Second}}
}

// Reverse implémente GeocodingProvider.
func (n *Nominatim) Reverse(ctx context.Context, p LatLng) (Address, error) {
	var r struct {
		DisplayName string            `json:"display_name"`
		Address     map[string]string `json:"address"`
	}
	err := n.br.do(func() error {
		u := n.URL + "/reverse?format=jsonv2&accept-language=fr&lat=" + strconv.FormatFloat(p.Lat, 'f', 6, 64) + "&lon=" + strconv.FormatFloat(p.Lng, 'f', 6, 64)
		req, err := http.NewRequestWithContext(ctx, http.MethodGet, u, nil)
		if err != nil {
			return err
		}
		resp, err := n.Client.Do(req)
		if err != nil {
			return fmt.Errorf("nominatim : %w", err)
		}
		defer resp.Body.Close()
		if resp.StatusCode != http.StatusOK {
			return fmt.Errorf("nominatim : statut %d", resp.StatusCode)
		}
		return json.NewDecoder(io.LimitReader(resp.Body, 1<<20)).Decode(&r)
	})
	if err != nil {
		return Address{}, err
	}
	// Rue puis quartier : plus lisible que l'adresse complète.
	var parts []string
	for _, k := range []string{"road", "neighbourhood", "suburb", "city_district", "city", "town", "village"} {
		if v := r.Address[k]; v != "" && len(parts) < 2 {
			parts = append(parts, v)
		}
	}
	if len(parts) > 0 {
		return Address{Label: strings.Join(parts, ", ")}, nil
	}
	if r.DisplayName == "" {
		return Address{}, errNoData
	}
	return Address{Label: r.DisplayName}, nil
}

// --- Google Places (New) ----------------------------------------------------------------------

// GooglePlaces n'est appelé qu'en secours, par le serveur seulement.
type GooglePlaces struct {
	APIKey string
	Client *http.Client
	br     breaker
}

// NewGooglePlaces crée l'adaptateur.
func NewGooglePlaces(key string) *GooglePlaces {
	return &GooglePlaces{APIKey: key, Client: &http.Client{Timeout: 2 * time.Second}}
}

// Autocomplete implémente PlaceSearchProvider. Le session token regroupe la facturation.
func (g *GooglePlaces) Autocomplete(ctx context.Context, q string, near *LatLng, session, country string) ([]Suggestion, error) {
	body := map[string]any{"input": q, "sessionToken": session, "includedRegionCodes": []string{strings.ToLower(country)}, "languageCode": "fr"}
	if near != nil {
		body["locationBias"] = map[string]any{"circle": map[string]any{
			"center": map[string]float64{"latitude": near.Lat, "longitude": near.Lng}, "radius": 30000.0,
		}}
	}
	raw, err := json.Marshal(body)
	if err != nil {
		return nil, err
	}
	var r struct {
		Suggestions []struct {
			PlacePrediction struct {
				PlaceID    string `json:"placeId"`
				Structured struct {
					Main struct {
						Text string `json:"text"`
					} `json:"mainText"`
					Secondary struct {
						Text string `json:"text"`
					} `json:"secondaryText"`
				} `json:"structuredFormat"`
			} `json:"placePrediction"`
		} `json:"suggestions"`
	}
	err = g.br.do(func() error {
		req, err := http.NewRequestWithContext(ctx, http.MethodPost, "https://places.googleapis.com/v1/places:autocomplete", bytes.NewReader(raw))
		if err != nil {
			return err
		}
		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("X-Goog-Api-Key", g.APIKey)
		return g.do(req, &r)
	})
	if err != nil {
		return nil, err
	}
	out := make([]Suggestion, 0, len(r.Suggestions))
	for _, s := range r.Suggestions {
		p := s.PlacePrediction
		if p.PlaceID != "" {
			out = append(out, Suggestion{ID: "google:" + p.PlaceID, Name: p.Structured.Main.Text, Address: p.Structured.Secondary.Text, Source: "google"})
		}
	}
	return out, nil
}

// Details implémente PlaceSearchProvider, avec le masque de champs minimal : il fixe le prix.
func (g *GooglePlaces) Details(ctx context.Context, externalID, session string) (PlaceDetail, error) {
	var r struct {
		ID          string `json:"id"`
		DisplayName struct {
			Text string `json:"text"`
		} `json:"displayName"`
		Formatted string `json:"formattedAddress"`
		Location  struct {
			Latitude  float64 `json:"latitude"`
			Longitude float64 `json:"longitude"`
		} `json:"location"`
	}
	err := g.br.do(func() error {
		u := "https://places.googleapis.com/v1/places/" + url.PathEscape(externalID) + "?sessionToken=" + url.QueryEscape(session) + "&languageCode=fr"
		req, err := http.NewRequestWithContext(ctx, http.MethodGet, u, nil)
		if err != nil {
			return err
		}
		req.Header.Set("X-Goog-Api-Key", g.APIKey)
		req.Header.Set("X-Goog-FieldMask", "id,displayName,formattedAddress,location")
		return g.do(req, &r)
	})
	if err != nil {
		return PlaceDetail{}, err
	}
	return PlaceDetail{ExternalID: r.ID, Name: r.DisplayName.Text, Address: r.Formatted, Location: LatLng{Lat: r.Location.Latitude, Lng: r.Location.Longitude}}, nil
}

func (g *GooglePlaces) do(req *http.Request, out any) error {
	resp, err := g.Client.Do(req)
	if err != nil {
		// L'URL peut porter des données de recherche : seul le type d'erreur remonte.
		return errors.New("google places : appel impossible")
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("google places : statut %d", resp.StatusCode)
	}
	return json.NewDecoder(io.LimitReader(resp.Body, 1<<20)).Decode(out)
}
