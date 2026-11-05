-- Biens immobiliers (vente, location) affichés dans l'app acheteur. Annonces publiées par
-- l'équipe ivia ou un agent, contact par téléphone. Migration additive.

-- +goose Up
CREATE TABLE properties (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title         text NOT NULL CHECK (length(title) BETWEEN 3 AND 120),
  kind          text NOT NULL CHECK (kind IN ('sale', 'rent')),
  property_type text NOT NULL CHECK (property_type IN ('house', 'villa', 'apartment', 'land', 'office', 'room')),
  price_xof     bigint NOT NULL CHECK (price_xof > 0),
  bedrooms      integer NOT NULL DEFAULT 0 CHECK (bedrooms BETWEEN 0 AND 30),
  surface_m2    integer NOT NULL DEFAULT 0 CHECK (surface_m2 BETWEEN 0 AND 100000),
  neighborhood  text NOT NULL DEFAULT '' CHECK (length(neighborhood) <= 80),
  address_text  text NOT NULL DEFAULT '' CHECK (length(address_text) <= 300),
  location      geography(Point, 4326) NOT NULL,
  description   text NOT NULL DEFAULT '' CHECK (length(description) <= 2000),
  photo_keys    text[] NOT NULL DEFAULT '{}',
  contact_name  text NOT NULL DEFAULT '' CHECK (length(contact_name) <= 80),
  contact_phone text NOT NULL CHECK (contact_phone ~ '^\+228[0-9]{8}$'),
  is_active     boolean NOT NULL DEFAULT true,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  UNIQUE (title, neighborhood)
);
CREATE INDEX properties_location_idx ON properties USING gist (location) WHERE is_active;

-- +goose Down
DROP TABLE properties;
