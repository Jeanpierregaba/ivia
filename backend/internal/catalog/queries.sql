-- name: ListCategories :many
SELECT * FROM categories
WHERE (sqlc.arg(include_inactive)::boolean OR is_active)
ORDER BY position, name;

-- name: GetCategory :one
SELECT * FROM categories WHERE id = $1;

-- name: CreateCategory :one
INSERT INTO categories (name, parent_id, position) VALUES ($1, $2, $3) RETURNING *;

-- name: UpdateCategory :one
UPDATE categories
SET name = $2, parent_id = $3, position = $4, is_active = $5, updated_at = now()
WHERE id = $1
RETURNING *;

-- name: CreateProduct :one
-- Créé inactif : brouillon (jamais publié).
INSERT INTO products (shop_id, category_id, name, description, price_xof, parcel_size, stock_mode,
                      is_active, published_at)
VALUES (sqlc.arg(shop_id), sqlc.arg(category_id), sqlc.arg(name), sqlc.arg(description),
        sqlc.arg(price_xof), sqlc.arg(parcel_size), sqlc.arg(stock_mode), sqlc.arg(is_active),
        CASE WHEN sqlc.arg(is_active)::boolean THEN now() END)
RETURNING id;

-- name: GetProduct :one
SELECT * FROM products WHERE id = $1;

-- name: UpdateProduct :exec
-- Les dates suivent le passage d'un état à l'autre ; à droite de SET, is_active est l'ancienne
-- valeur : mise en vente -> nouvelle date de publication ; retrait -> date de retrait ; un
-- brouillon gardé inactif reste un brouillon (products_publication_check).
UPDATE products
SET category_id = sqlc.arg(category_id), name = sqlc.arg(name), description = sqlc.arg(description),
    price_xof = sqlc.arg(price_xof), parcel_size = sqlc.arg(parcel_size), is_active = sqlc.arg(is_active),
    published_at = CASE WHEN sqlc.arg(is_active)::boolean AND NOT is_active THEN now() ELSE published_at END,
    withdrawn_at = CASE
      WHEN sqlc.arg(is_active)::boolean THEN NULL
      WHEN is_active THEN now()
      ELSE withdrawn_at
    END,
    updated_at = now()
WHERE id = sqlc.arg(id);

-- name: ListActiveProductsByShop :many
-- Produits en vente d'une boutique (vue publique). Le marchand a ListSellerProducts.
SELECT * FROM products
WHERE shop_id = sqlc.arg(shop_id) AND is_active
ORDER BY created_at DESC, id
LIMIT sqlc.arg(lim) OFFSET sqlc.arg(off);

-- name: ListSellerProducts :many
-- Produits d'une boutique pour son marchand. status : vide (tous), active, draft ou withdrawn.
-- q : texte déjà échappé pour LIKE (\, %, _), comparé sans accents ni majuscules.
SELECT * FROM products
WHERE shop_id = sqlc.arg(shop_id)
  AND CASE sqlc.arg(status)::text
        WHEN 'active' THEN is_active
        WHEN 'draft' THEN NOT is_active AND published_at IS NULL
        WHEN 'withdrawn' THEN NOT is_active AND published_at IS NOT NULL
        ELSE true
      END
  AND (sqlc.arg(q)::text = ''
       OR immutable_unaccent(lower(name)) LIKE '%' || immutable_unaccent(lower(sqlc.arg(q)::text)) || '%' ESCAPE '\')
  -- category_id : la catégorie ou l'une de ses sous-catégories ; NULL : toutes.
  AND (sqlc.narg(category_id)::uuid IS NULL
       OR category_id = sqlc.narg(category_id)::uuid
       OR category_id IN (SELECT c.id FROM categories c WHERE c.parent_id = sqlc.narg(category_id)::uuid))
ORDER BY CASE WHEN sqlc.arg(status)::text = 'withdrawn' THEN withdrawn_at END DESC NULLS LAST,
         created_at DESC, id
LIMIT sqlc.arg(lim) OFFSET sqlc.arg(off);

-- name: CountSellerProducts :one
SELECT count(*) FILTER (WHERE is_active) AS active,
       count(*) FILTER (WHERE NOT is_active AND published_at IS NULL) AS draft,
       count(*) FILTER (WHERE NOT is_active AND published_at IS NOT NULL) AS withdrawn
FROM products
WHERE shop_id = $1;

-- name: GetProductsByIDs :many
SELECT * FROM products WHERE id = ANY(sqlc.arg(ids)::uuid[]);

-- name: ListShopMedia :many
-- Photos déjà utilisées par les produits d'une boutique (bibliothèque du marchand), la plus
-- récente d'abord, sans doublon.
SELECT pi.object_key, max(pi.created_at)::timestamptz AS last_used
FROM product_images pi
JOIN products p ON p.id = pi.product_id
WHERE p.shop_id = $1
GROUP BY pi.object_key
ORDER BY last_used DESC, pi.object_key
LIMIT 120;

-- name: ListImages :many
SELECT * FROM product_images WHERE product_id = ANY(sqlc.arg(product_ids)::uuid[]) ORDER BY product_id, position;

-- name: DeleteImages :exec
DELETE FROM product_images WHERE product_id = $1;

-- name: InsertImage :exec
INSERT INTO product_images (product_id, object_key, position) VALUES ($1, $2, $3);

-- name: SetProductMarketing :exec
-- Promotion et mise en avant d'un produit (admin) ; contrôles en base (products_promo_check…).
UPDATE products
SET promo_price_xof = sqlc.narg(promo_price_xof), promo_starts_at = sqlc.narg(promo_starts_at),
    promo_ends_at = sqlc.narg(promo_ends_at), badges = sqlc.arg(badges)::text[],
    featured_rank = sqlc.narg(featured_rank), features = sqlc.arg(features)::text[], updated_at = now()
WHERE id = sqlc.arg(id);

-- name: AdminListProducts :many
-- Tous les produits (back-office), d'une boutique ou de toutes, avec recherche dans le nom ; les
-- produits mis en avant d'abord.
SELECT * FROM products
WHERE (sqlc.narg(shop_id)::uuid IS NULL OR shop_id = sqlc.narg(shop_id)::uuid)
  AND (sqlc.narg(q)::text IS NULL
       OR immutable_unaccent(lower(name)) LIKE '%' || immutable_unaccent(lower(sqlc.narg(q)::text)) || '%' ESCAPE '\')
ORDER BY featured_rank NULLS LAST, created_at DESC, id
LIMIT sqlc.arg(lim) OFFSET sqlc.arg(off);

-- name: FeaturedProducts :many
-- Produits mis en avant en vente, par rang (la boutique publiée est vérifiée par le service).
SELECT * FROM products
WHERE featured_rank IS NOT NULL AND is_active
ORDER BY featured_rank, created_at DESC
LIMIT sqlc.arg(lim);
