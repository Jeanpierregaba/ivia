-- Extensions utilisées par la recherche (plein texte, floue, sans accents) et la géolocalisation.

-- +goose Up
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS unaccent;

-- +goose Down
DROP EXTENSION IF EXISTS unaccent;
DROP EXTENSION IF EXISTS pg_trgm;
DROP EXTENSION IF EXISTS postgis;
