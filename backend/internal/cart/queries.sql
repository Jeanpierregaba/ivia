-- name: GetCart :one
SELECT * FROM carts WHERE buyer_id = $1;

-- name: UpsertCart :exec
INSERT INTO carts (buyer_id, shop_id) VALUES ($1, $2)
ON CONFLICT (buyer_id) DO UPDATE SET shop_id = EXCLUDED.shop_id, updated_at = now();

-- name: ListItems :many
SELECT * FROM cart_items WHERE buyer_id = $1 ORDER BY added_at;

-- name: CountItems :one
SELECT count(*) FROM cart_items WHERE buyer_id = $1;

-- name: SetItem :exec
INSERT INTO cart_items (buyer_id, product_id, quantity) VALUES ($1, $2, $3)
ON CONFLICT (buyer_id, product_id) DO UPDATE SET quantity = EXCLUDED.quantity;

-- name: DeleteItem :exec
DELETE FROM cart_items WHERE buyer_id = $1 AND product_id = $2;

-- name: DeleteCart :exec
DELETE FROM carts WHERE buyer_id = $1;
