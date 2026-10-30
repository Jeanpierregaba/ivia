-- name: InitLevel :exec
INSERT INTO stock_levels (product_id, quantity) VALUES ($1, $2);

-- name: GetLevelForUpdate :one
SELECT quantity FROM stock_levels WHERE product_id = $1 FOR UPDATE;

-- name: ListLevels :many
SELECT product_id, quantity FROM stock_levels WHERE product_id = ANY(sqlc.arg(product_ids)::uuid[]);

-- name: SetLevel :exec
UPDATE stock_levels SET quantity = $2, updated_at = now() WHERE product_id = $1;

-- name: Decrement :one
-- Réservation : ne réussit que si la quantité suffit (aucune survente, même en concurrence).
UPDATE stock_levels SET quantity = quantity - sqlc.arg(qty)::integer, updated_at = now()
WHERE product_id = sqlc.arg(product_id) AND quantity >= sqlc.arg(qty)::integer
RETURNING quantity;

-- name: Increment :one
UPDATE stock_levels SET quantity = quantity + sqlc.arg(qty)::integer, updated_at = now()
WHERE product_id = sqlc.arg(product_id)
RETURNING quantity;

-- name: InsertMovement :exec
INSERT INTO stock_movements (product_id, delta, quantity_after, reason, order_id, actor_id, note)
VALUES ($1, $2, $3, $4, $5, $6, $7);

-- name: ListMovements :many
SELECT * FROM stock_movements WHERE product_id = $1
ORDER BY id DESC
LIMIT sqlc.arg(lim) OFFSET sqlc.arg(off);
