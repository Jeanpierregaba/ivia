-- Heures de nuit personnalisées par chaque pharmacie. Sans choix de sa part, les réglages généraux
-- (pharmacy_settings) s'appliquent. Migration additive.

-- +goose Up
ALTER TABLE pharmacies
  ADD COLUMN night_from_hour integer CHECK (night_from_hour BETWEEN 0 AND 23),
  ADD COLUMN night_to_hour   integer CHECK (night_to_hour BETWEEN 0 AND 23);

-- +goose StatementBegin
CREATE FUNCTION pharmacy_night_now(p_from integer, p_to integer) RETURNS boolean
LANGUAGE sql STABLE AS $$
  SELECT p_from <> p_to AND CASE
    WHEN p_from < p_to THEN extract(hour FROM now() AT TIME ZONE 'Africa/Lome')::int >= p_from
                        AND extract(hour FROM now() AT TIME ZONE 'Africa/Lome')::int < p_to
    ELSE extract(hour FROM now() AT TIME ZONE 'Africa/Lome')::int >= p_from
      OR extract(hour FROM now() AT TIME ZONE 'Africa/Lome')::int < p_to
  END
$$;
-- +goose StatementEnd

-- +goose Down
DROP FUNCTION pharmacy_night_now(integer, integer);
ALTER TABLE pharmacies DROP COLUMN night_to_hour, DROP COLUMN night_from_hour;
