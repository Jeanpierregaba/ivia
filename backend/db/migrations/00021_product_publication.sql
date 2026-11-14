-- État de publication d'un produit, pour le catalogue marchand (spec 005) :
--   en vente  : is_active, published_at renseigné, withdrawn_at NULL ;
--   brouillon : jamais publié, published_at et withdrawn_at NULL ;
--   retiré    : publié puis désactivé, published_at et withdrawn_at renseignés.
-- La visibilité reste portée par is_active : la recherche et le panier ne changent pas.
-- published_at est la dernière mise en vente, withdrawn_at le dernier retrait.

-- +goose Up
ALTER TABLE products
  ADD COLUMN published_at timestamptz,
  ADD COLUMN withdrawn_at timestamptz;

-- Avant cette migration, un produit était créé en vente : un inactif a donc été retiré.
UPDATE products SET published_at = created_at;
UPDATE products SET withdrawn_at = updated_at WHERE NOT is_active;

ALTER TABLE products ADD CONSTRAINT products_publication_check CHECK (
  (is_active AND published_at IS NOT NULL AND withdrawn_at IS NULL)
  OR (NOT is_active AND withdrawn_at IS NULL AND published_at IS NULL)
  OR (NOT is_active AND withdrawn_at IS NOT NULL AND published_at IS NOT NULL)
);

-- +goose Down
ALTER TABLE products DROP CONSTRAINT products_publication_check;
ALTER TABLE products DROP COLUMN withdrawn_at, DROP COLUMN published_at;
