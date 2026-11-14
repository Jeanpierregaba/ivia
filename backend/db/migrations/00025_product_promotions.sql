-- Promotions et mise en avant des produits (produits IVI et AWU-IVI d'abord, ouvert à tous) :
-- prix promotionnel daté, badges, rang de mise en avant, caractéristiques. Un brouillon jamais
-- publié peut avoir un prix à 0 (« à renseigner ») : la mise en vente exige un prix.
-- La vue de recherche expose le prix effectif (promotion comprise) et la mise en avant (ADR 0009 :
-- colonnes ajoutées en fin de vue).

-- +goose Up
ALTER TABLE products
  ADD COLUMN promo_price_xof bigint,
  ADD COLUMN promo_starts_at timestamptz,
  ADD COLUMN promo_ends_at   timestamptz,
  ADD COLUMN badges          text[] NOT NULL DEFAULT '{}',
  ADD COLUMN featured_rank   integer,
  ADD COLUMN features        text[] NOT NULL DEFAULT '{}';

ALTER TABLE products DROP CONSTRAINT products_price_xof_check;
ALTER TABLE products ADD CONSTRAINT products_price_xof_check CHECK (
  price_xof >= 0 AND price_xof <= 100000000
  AND (price_xof > 0 OR (NOT is_active AND published_at IS NULL))
);
ALTER TABLE products ADD CONSTRAINT products_promo_check CHECK (
  promo_price_xof IS NULL OR (promo_price_xof > 0 AND promo_price_xof < price_xof)
);
ALTER TABLE products ADD CONSTRAINT products_promo_dates_check CHECK (
  promo_starts_at IS NULL OR promo_ends_at IS NULL OR promo_ends_at > promo_starts_at
);
ALTER TABLE products ADD CONSTRAINT products_badges_check CHECK (
  badges <@ ARRAY['promotion', 'special_offer', 'featured', 'best_seller']::text[]
);
ALTER TABLE products ADD CONSTRAINT products_featured_rank_check CHECK (featured_rank BETWEEN 1 AND 1000);
ALTER TABLE products ADD CONSTRAINT products_features_check CHECK (cardinality(features) <= 12);
CREATE INDEX products_featured_idx ON products (featured_rank) WHERE featured_rank IS NOT NULL;

CREATE OR REPLACE VIEW search_products AS
SELECT p.id,
       p.shop_id,
       p.category_id,
       c.parent_id AS category_parent_id,
       p.name,
       p.price_xof,
       p.parcel_size,
       p.search_vector,
       p.created_at,
       s.name AS shop_name,
       s.neighborhood_id,
       s.location,
       (SELECT i.object_key FROM product_images i WHERE i.product_id = p.id ORDER BY i.position LIMIT 1) AS main_image_key,
       (p.stock_mode = 'untracked' OR coalesce(l.quantity, 0) > 0) AS in_stock,
       s.category_id AS shop_category_id,
       CASE WHEN p.promo_price_xof IS NOT NULL
                 AND (p.promo_starts_at IS NULL OR p.promo_starts_at <= now())
                 AND (p.promo_ends_at IS NULL OR p.promo_ends_at > now())
            THEN p.promo_price_xof ELSE p.price_xof END AS effective_price_xof,
       p.badges,
       p.featured_rank
FROM products p
JOIN shops s ON s.id = p.shop_id
JOIN categories c ON c.id = p.category_id
LEFT JOIN stock_levels l ON l.product_id = p.id
WHERE p.is_active AND s.status = 'published';

-- +goose Down
DROP VIEW search_products;
CREATE VIEW search_products AS
SELECT p.id, p.shop_id, p.category_id, c.parent_id AS category_parent_id, p.name, p.price_xof, p.parcel_size,
       p.search_vector, p.created_at, s.name AS shop_name, s.neighborhood_id, s.location,
       (SELECT i.object_key FROM product_images i WHERE i.product_id = p.id ORDER BY i.position LIMIT 1) AS main_image_key,
       (p.stock_mode = 'untracked' OR coalesce(l.quantity, 0) > 0) AS in_stock,
       s.category_id AS shop_category_id
FROM products p
JOIN shops s ON s.id = p.shop_id
JOIN categories c ON c.id = p.category_id
LEFT JOIN stock_levels l ON l.product_id = p.id
WHERE p.is_active AND s.status = 'published';
DROP INDEX products_featured_idx;
ALTER TABLE products
  DROP CONSTRAINT products_features_check,
  DROP CONSTRAINT products_featured_rank_check,
  DROP CONSTRAINT products_badges_check,
  DROP CONSTRAINT products_promo_dates_check,
  DROP CONSTRAINT products_promo_check,
  DROP CONSTRAINT products_price_xof_check;
ALTER TABLE products ADD CONSTRAINT products_price_xof_check CHECK (price_xof > 0 AND price_xof <= 100000000);
ALTER TABLE products
  DROP COLUMN features, DROP COLUMN featured_rank, DROP COLUMN badges,
  DROP COLUMN promo_ends_at, DROP COLUMN promo_starts_at, DROP COLUMN promo_price_xof;
