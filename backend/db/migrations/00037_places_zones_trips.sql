-- Carte et géolocalisation (docs/decisions/0013) : lieux, lieux personnels, zones, traces GPS et
-- compteurs d'usage des fournisseurs. Migration additive.

-- +goose Up
CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE TABLE places (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name          text NOT NULL CHECK (length(name) BETWEEN 2 AND 160),
  aliases       text[] NOT NULL DEFAULT '{}',
  category      text NOT NULL DEFAULT '',
  address_label text NOT NULL DEFAULT '',
  location      geography(Point, 4326) NOT NULL,
  country_code  char(2) NOT NULL DEFAULT 'TG',
  source        text NOT NULL CHECK (source IN ('ivia', 'google', 'osm', 'user')),
  external_id   text,
  usage_count   integer NOT NULL DEFAULT 0,
  is_active     boolean NOT NULL DEFAULT true,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX places_location_gix ON places USING gist (location);
CREATE INDEX places_name_trgm ON places USING gin (name gin_trgm_ops);
CREATE UNIQUE INDEX places_external_idx ON places (source, external_id) WHERE external_id IS NOT NULL;

CREATE TABLE user_places (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  label         text NOT NULL CHECK (length(label) BETWEEN 1 AND 80),
  type          text NOT NULL CHECK (type IN ('home', 'work', 'favorite', 'recent')),
  location      geography(Point, 4326) NOT NULL,
  address_label text NOT NULL DEFAULT '',
  last_used_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX user_places_user_idx ON user_places (user_id, last_used_at DESC);

CREATE TABLE zones (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name       text NOT NULL CHECK (length(name) BETWEEN 2 AND 120),
  type       text NOT NULL CHECK (type IN ('service_area', 'pricing', 'surge', 'airport')),
  area       geography(Polygon, 4326) NOT NULL,
  rules      jsonb NOT NULL DEFAULT '{}',
  is_active  boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX zones_area_gix ON zones USING gist (area);

-- Trace GPS d'une course ou d'une livraison : données personnelles, purgées après 180 jours.
CREATE TABLE trip_points (
  trip_id     uuid NOT NULL,
  recorded_at timestamptz NOT NULL,
  location    geography(Point, 4326) NOT NULL,
  speed       real,
  heading     real
);
CREATE INDEX trip_points_trip_idx ON trip_points (trip_id, recorded_at);
CREATE INDEX trip_points_age_idx ON trip_points (recorded_at);

-- Appels aux fournisseurs et taux de résolution locale, par jour.
CREATE TABLE geo_metrics (
  day    date NOT NULL,
  metric text NOT NULL,
  value  bigint NOT NULL DEFAULT 0,
  PRIMARY KEY (day, metric)
);

-- +goose Down
DROP TABLE geo_metrics;
DROP TABLE trip_points;
DROP TABLE zones;
DROP TABLE user_places;
DROP TABLE places;
