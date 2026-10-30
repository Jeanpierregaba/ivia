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
INSERT INTO products (shop_id, category_id, name, description, price_xof, parcel_size, stock_mode)
VALUES ($1, $2, $3, $4, $5, $6, $7)
RETURNING id;

-- name: GetProduct :one
SELECT * FROM products WHERE id = $1;

-- name: UpdateProduct :exec
UPDATE products
SET category_id = $2, name = $3, description = $4, price_xof = $5, parcel_size = $6, is_active = $7,
    updated_at = now()
WHERE id = $1;

-- name: ListProductsByShop :many
SELECT * FROM products
WHERE shop_id = sqlc.arg(shop_id) AND (sqlc.arg(include_inactive)::boolean OR is_active)
ORDER BY created_at DESC
LIMIT sqlc.arg(lim) OFFSET sqlc.arg(off);

-- name: GetProductsByIDs :many
SELECT * FROM products WHERE id = ANY(sqlc.arg(ids)::uuid[]);

-- name: ListImages :many
SELECT * FROM product_images WHERE product_id = ANY(sqlc.arg(product_ids)::uuid[]) ORDER BY product_id, position;

-- name: DeleteImages :exec
DELETE FROM product_images WHERE product_id = $1;

-- name: InsertImage :exec
INSERT INTO product_images (product_id, object_key, position) VALUES ($1, $2, $3);
