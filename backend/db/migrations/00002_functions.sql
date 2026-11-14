-- Fonctions utilitaires partagées par les migrations suivantes.

-- +goose Up

-- unaccent() n'est pas IMMUTABLE : impossible de l'utiliser dans un index ou une colonne générée.
-- Cette enveloppe fixe le dictionnaire, ce qui la rend déterministe.
-- +goose StatementBegin
CREATE FUNCTION immutable_unaccent(text) RETURNS text
LANGUAGE sql IMMUTABLE PARALLEL SAFE STRICT
AS $$ SELECT public.unaccent('public.unaccent'::regdictionary, $1) $$;
-- +goose StatementEnd

-- Interdit toute modification ou suppression sur une table en ajout seul (journaux, trace financière).
-- +goose StatementBegin
CREATE FUNCTION forbid_mutation() RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  RAISE EXCEPTION 'table % en ajout seul : % interdit', TG_TABLE_NAME, TG_OP
    USING ERRCODE = 'restrict_violation';
END
$$;
-- +goose StatementEnd

-- +goose Down
DROP FUNCTION IF EXISTS forbid_mutation();
DROP FUNCTION IF EXISTS immutable_unaccent(text);
