-- name: InsertSettlement :one
INSERT INTO settlements (shop_id, period_start, period_end, orders_count, gross_xof, commission_xof, net_xof, created_by, note)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
RETURNING *;

-- name: InsertLine :exec
INSERT INTO settlement_lines (settlement_id, order_id, order_number, completed_at, subtotal_xof, commission_xof)
VALUES ($1, $2, $3, $4, $5, $6);

-- name: GetSettlement :one
SELECT * FROM settlements WHERE id = $1;

-- name: ListSettlements :many
SELECT * FROM settlements
WHERE (sqlc.narg(shop_id)::uuid IS NULL OR shop_id = sqlc.narg(shop_id)::uuid)
  AND (sqlc.narg(status)::text IS NULL OR status = sqlc.narg(status)::text)
ORDER BY period_start DESC, created_at DESC
LIMIT sqlc.arg(lim) OFFSET sqlc.arg(off);

-- name: ListLines :many
SELECT * FROM settlement_lines WHERE settlement_id = $1 ORDER BY completed_at;

-- name: AlreadySettledOrders :many
-- Commandes déjà comprises dans un relevé (une commande n'est comptée qu'une fois).
SELECT order_id FROM settlement_lines WHERE order_id = ANY(sqlc.arg(order_ids)::uuid[]);

-- name: MarkSettled :execrows
UPDATE settlements
SET status = 'settled', settled_at = now(), settled_by = sqlc.arg(settled_by),
    settlement_reference = sqlc.arg(reference), note = CASE WHEN sqlc.arg(note)::text = '' THEN note ELSE sqlc.arg(note)::text END
WHERE id = sqlc.arg(id) AND status = 'open';

-- name: DeleteOpenSettlement :execrows
DELETE FROM settlements WHERE id = $1 AND status = 'open';
