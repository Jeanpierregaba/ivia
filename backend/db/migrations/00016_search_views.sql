-- Module search : vues en lecture seule sur le catalogue publié (ADR 0009). Seul le module search
-- les interroge ; elles ne contiennent que des données publiques (boutiques publiées, produits actifs).

-- +goose Up
CREATE VIEW search_products AS
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

-- +goose Down
DROP VIEW search_shops;
DROP VIEW search_products;
