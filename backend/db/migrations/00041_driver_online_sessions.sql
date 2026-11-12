-- Temps en ligne des livreurs : une ligne par période en ligne (disponible ou en mission), tenue
-- par un déclencheur sur `drivers.availability`, quel que soit le code qui change l'état.

-- +goose Up
CREATE TABLE driver_online_sessions (
  id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  driver_id  uuid NOT NULL REFERENCES drivers (user_id),
  started_at timestamptz NOT NULL DEFAULT now(),
  ended_at   timestamptz,
  CHECK (ended_at IS NULL OR ended_at >= started_at)
);
CREATE UNIQUE INDEX driver_online_sessions_one_open ON driver_online_sessions (driver_id) WHERE ended_at IS NULL;
CREATE INDEX driver_online_sessions_driver_idx ON driver_online_sessions (driver_id, started_at DESC);

-- +goose StatementBegin
CREATE FUNCTION driver_online_session_track() RETURNS trigger AS $$
BEGIN
  IF OLD.availability = 'offline' AND NEW.availability <> 'offline' THEN
    INSERT INTO driver_online_sessions (driver_id) VALUES (NEW.user_id) ON CONFLICT DO NOTHING;
  ELSIF OLD.availability <> 'offline' AND NEW.availability = 'offline' THEN
    UPDATE driver_online_sessions SET ended_at = now() WHERE driver_id = NEW.user_id AND ended_at IS NULL;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
-- +goose StatementEnd

CREATE TRIGGER drivers_online_session_track
  AFTER UPDATE OF availability ON drivers
  FOR EACH ROW EXECUTE FUNCTION driver_online_session_track();

INSERT INTO driver_online_sessions (driver_id) SELECT user_id FROM drivers WHERE availability <> 'offline';

-- +goose Down
DROP TRIGGER drivers_online_session_track ON drivers;
DROP FUNCTION driver_online_session_track();
DROP TABLE driver_online_sessions;
