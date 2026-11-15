-- Module search : la catégorie de boutique devient un critère de recherche des boutiques et des
-- produits (ADR 0009 : vues en lecture seule ; colonnes ajoutées en fin de vue).

-- +goose Up
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
       s.category_id AS shop_category_id
FROM products p
JOIN shops s ON s.id = p.shop_id
JOIN categories c ON c.id = p.category_id
LEFT JOIN stock_levels l ON l.product_id = p.id
WHERE p.is_active AND s.status = 'published';

CREATE OR REPLACE VIEW search_shops AS
SELECT s.id, s.name, s.description, s.neighborhood_id, s.location, s.logo_key, s.accepting_orders, s.created_at,
       s.category_id,
       coalesce(sc.name, '') AS category_name
FROM shops s
LEFT JOIN shop_categories sc ON sc.id = s.category_id
WHERE s.status = 'published';

-- +goose Down
DROP VIEW search_shops;
DROP VIEW search_products;
CREATE VIEW search_products AS
SELECT p.id, p.shop_id, p.category_id, c.parent_id AS category_parent_id, p.name, p.price_xof, p.parcel_size,
       p.search_vector, p.created_at, s.name AS shop_name, s.neighborhood_id, s.location,
       (SELECT i.object_key FROM product_images i WHERE i.product_id = p.id ORDER BY i.position LIMIT 1) AS main_image_key,
       (p.stock_mode = 'untracked' OR coalesce(l.quantity, 0) > 0) AS in_stock
FROM products p
JOIN shops s ON s.id = p.shop_id
JOIN categories c ON c.id = p.category_id
LEFT JOIN stock_levels l ON l.product_id = p.id
WHERE p.is_active AND s.status = 'published';
CREATE VIEW search_shops AS
SELECT s.id, s.name, s.description, s.neighborhood_id, s.location, s.logo_key, s.accepting_orders, s.created_at
FROM shops s
WHERE s.status = 'published';
