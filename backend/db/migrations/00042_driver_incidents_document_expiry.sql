-- Signalements des livreurs (colis endommagé, adresse introuvable, code refusé, accident) avec
-- photo et position facultatives, traités dans le back-office ; date d'expiration des pièces,
-- saisie par l'équipe ivia à la vérification (décision du 2026-11-12).

-- +goose Up
CREATE TABLE driver_incidents (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  driver_id        uuid NOT NULL REFERENCES drivers (user_id),
  kind             text NOT NULL CHECK (kind IN ('damaged_parcel', 'address_not_found', 'code_refused', 'accident', 'other')),
  mission_type     text CHECK (mission_type IN ('shop', 'pharmacy')),
  mission_id       uuid,
  note             text NOT NULL DEFAULT '' CHECK (length(note) <= 500),
  -- Photo dans le compartiment privé (dossier du livreur), jamais publique.
  photo_key        text,
  location         geography(Point, 4326),
  status           text NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'resolved')),
  resolution_note  text NOT NULL DEFAULT '' CHECK (length(resolution_note) <= 500),
  resolved_at      timestamptz,
  resolved_by      uuid REFERENCES users (id),
  created_at       timestamptz NOT NULL DEFAULT now(),
  CHECK ((mission_type IS NULL) = (mission_id IS NULL)),
  CHECK ((status = 'resolved') = (resolved_at IS NOT NULL))
);
CREATE INDEX driver_incidents_open_idx ON driver_incidents (created_at DESC) WHERE status = 'open';
CREATE INDEX driver_incidents_driver_idx ON driver_incidents (driver_id, created_at DESC);

ALTER TABLE driver_documents ADD COLUMN expires_on date;

-- +goose Down
ALTER TABLE driver_documents DROP COLUMN expires_on;
DROP TABLE driver_incidents;
