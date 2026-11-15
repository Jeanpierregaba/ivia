package mapping

import (
	"context"
	"fmt"
	"sort"
	"strconv"
	"sync"
	"time"

	"github.com/redis/go-redis/v9"
)

// Un livreur sans position depuis 60 secondes est considéré hors ligne.
const driverStale = 60 * time.Second

// DriverPosition est la dernière position connue d'un livreur.
type DriverPosition struct {
	DriverID string
	City     string
	Vehicle  string
	Position LatLng
	Heading  float64
	Speed    float64
	Status   string // available | busy | offline
}

// DriverCandidate est un livreur proche.
type DriverCandidate struct {
	DriverID string `json:"driver_id"`
	Position LatLng `json:"position"`
	DistM    int64  `json:"distance_m"`
	Status   string `json:"status"`
	EtaS     int64  `json:"eta_s,omitempty"`
}

// DriverLocationStore garde les positions en temps réel.
type DriverLocationStore interface {
	Upsert(ctx context.Context, p DriverPosition) error
	Nearby(ctx context.Context, city, vehicle string, at LatLng, radiusM float64, limit int) ([]DriverCandidate, error)
	Remove(ctx context.Context, city, vehicle, driverID string) error
}

// RedisGeoStore : GEOADD par ville et véhicule, hash par livreur pour le statut et l'horodatage.
type RedisGeoStore struct {
	Client *redis.Client
}

func geoKey(city, vehicle string) string { return "drivers:" + city + ":" + vehicle }

// Upsert implémente DriverLocationStore.
func (s *RedisGeoStore) Upsert(ctx context.Context, p DriverPosition) error {
	pipe := s.Client.Pipeline()
	pipe.GeoAdd(ctx, geoKey(p.City, p.Vehicle), &redis.GeoLocation{Name: p.DriverID, Longitude: p.Position.Lng, Latitude: p.Position.Lat})
	h := "driver:" + p.DriverID
	pipe.HSet(ctx, h, "status", p.Status, "at", time.Now().Unix(), "heading", p.Heading, "speed", p.Speed)
	pipe.Expire(ctx, h, 10*time.Minute)
	_, err := pipe.Exec(ctx)
	if err != nil {
		return fmt.Errorf("redis : %w", err)
	}
	return nil
}

// Nearby implémente DriverLocationStore ; les positions périmées sont ignorées et retirées.
func (s *RedisGeoStore) Nearby(ctx context.Context, city, vehicle string, at LatLng, radiusM float64, limit int) ([]DriverCandidate, error) {
	key := geoKey(city, vehicle)
	rows, err := s.Client.GeoSearchLocation(ctx, key, &redis.GeoSearchLocationQuery{
		GeoSearchQuery: redis.GeoSearchQuery{Longitude: at.Lng, Latitude: at.Lat, Radius: radiusM, RadiusUnit: "m", Sort: "ASC", Count: limit},
		WithCoord:      true, WithDist: true,
	}).Result()
	if err != nil {
		return nil, fmt.Errorf("redis : %w", err)
	}
	out := make([]DriverCandidate, 0, len(rows))
	for _, r := range rows {
		vals, err := s.Client.HMGet(ctx, "driver:"+r.Name, "status", "at").Result()
		if err != nil {
			return nil, fmt.Errorf("redis : %w", err)
		}
		status, _ := vals[0].(string)
		raw, _ := vals[1].(string)
		ts, _ := strconv.ParseInt(raw, 10, 64)
		if time.Since(time.Unix(ts, 0)) > driverStale {
			s.Client.ZRem(ctx, key, r.Name)
			continue
		}
		out = append(out, DriverCandidate{DriverID: r.Name, Position: LatLng{Lat: r.Latitude, Lng: r.Longitude}, DistM: int64(r.Dist), Status: status})
	}
	return out, nil
}

// Remove implémente DriverLocationStore.
func (s *RedisGeoStore) Remove(ctx context.Context, city, vehicle, driverID string) error {
	pipe := s.Client.Pipeline()
	pipe.ZRem(ctx, geoKey(city, vehicle), driverID)
	pipe.Del(ctx, "driver:"+driverID)
	if _, err := pipe.Exec(ctx); err != nil {
		return fmt.Errorf("redis : %w", err)
	}
	return nil
}

// MemoryStore remplace Redis en local : même contrat, sur un seul processus.
type MemoryStore struct {
	mu   sync.Mutex
	rows map[string]memoryRow
}

type memoryRow struct {
	p  DriverPosition
	at time.Time
}

// Upsert implémente DriverLocationStore.
func (s *MemoryStore) Upsert(_ context.Context, p DriverPosition) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.rows == nil {
		s.rows = map[string]memoryRow{}
	}
	s.rows[p.DriverID] = memoryRow{p: p, at: time.Now()}
	return nil
}

// Nearby implémente DriverLocationStore.
func (s *MemoryStore) Nearby(_ context.Context, city, vehicle string, at LatLng, radiusM float64, limit int) ([]DriverCandidate, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	var out []DriverCandidate
	for id, r := range s.rows {
		if time.Since(r.at) > driverStale {
			delete(s.rows, id)
			continue
		}
		if r.p.City != city || r.p.Vehicle != vehicle {
			continue
		}
		if d := Haversine(at, r.p.Position); d <= radiusM {
			out = append(out, DriverCandidate{DriverID: id, Position: r.p.Position, DistM: int64(d), Status: r.p.Status})
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].DistM < out[j].DistM })
	if len(out) > limit {
		out = out[:limit]
	}
	return out, nil
}

// Remove implémente DriverLocationStore.
func (s *MemoryStore) Remove(_ context.Context, _, _, driverID string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	delete(s.rows, driverID)
	return nil
}

// cacheStore garde les résultats coûteux : Redis, ou mémoire en local.
type cacheStore interface {
	Get(ctx context.Context, key string) (string, bool)
	Set(ctx context.Context, key, value string, ttl time.Duration)
}

type redisCache struct{ client *redis.Client }

func (c redisCache) Get(ctx context.Context, key string) (string, bool) {
	v, err := c.client.Get(ctx, key).Result()
	return v, err == nil
}

func (c redisCache) Set(ctx context.Context, key, value string, ttl time.Duration) {
	// Un cache en panne ne bloque pas la réponse.
	_ = c.client.Set(ctx, key, value, ttl).Err()
}

type memoryCache struct {
	mu   sync.Mutex
	rows map[string]memoryEntry
}

type memoryEntry struct {
	v  string
	to time.Time
}

func (c *memoryCache) Get(_ context.Context, key string) (string, bool) {
	c.mu.Lock()
	defer c.mu.Unlock()
	e, ok := c.rows[key]
	if !ok || time.Now().After(e.to) {
		return "", false
	}
	return e.v, true
}

func (c *memoryCache) Set(_ context.Context, key, value string, ttl time.Duration) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.rows == nil || len(c.rows) > 20000 {
		c.rows = map[string]memoryEntry{}
	}
	c.rows[key] = memoryEntry{v: value, to: time.Now().Add(ttl)}
}
