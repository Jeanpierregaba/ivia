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

-- name: ListImages :many
SELECT * FROM product_images WHERE product_id = ANY(sqlc.arg(product_ids)::uuid[]) ORDER BY product_id, position;

-- name: DeleteImages :exec
DELETE FROM product_images WHERE product_id = $1;

-- name: InsertImage :exec
INSERT INTO product_images (product_id, object_key, position) VALUES ($1, $2, $3);
