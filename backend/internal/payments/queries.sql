-- name: CreatePayment :one
INSERT INTO payments (order_id, buyer_id, provider, reference, amount_xof, operator, payer_phone)
VALUES ($1, $2, $3, $4, $5, $6, $7)
RETURNING *;

-- name: GetPayment :one
SELECT * FROM payments WHERE id = $1;

-- name: GetPaymentByReference :one
SELECT * FROM payments WHERE reference = $1;

-- name: LockPayment :one
SELECT * FROM payments WHERE id = $1 FOR UPDATE;

-- name: PendingPaymentForOrder :one
SELECT * FROM payments WHERE order_id = $1 AND status = 'pending';

-- name: SetProviderRef :exec
UPDATE payments SET provider_ref = $2, updated_at = now() WHERE id = $1;

-- name: SetPaymentStatus :execrows
-- Transition conditionnelle : échoue si le statut a changé entre-temps.
UPDATE payments
SET status         = sqlc.arg(new_status),
    failure_reason = sqlc.arg(failure_reason),
    succeeded_at   = CASE WHEN sqlc.arg(new_status) = 'succeeded' THEN coalesce(succeeded_at, now()) ELSE succeeded_at END,
    is_duplicate   = is_duplicate OR sqlc.arg(is_duplicate)::boolean,
    updated_at     = now()
WHERE id = sqlc.arg(id) AND status = ANY(sqlc.arg(from_statuses)::text[]);

-- name: ListOrderPayments :many
SELECT * FROM payments WHERE order_id = $1 ORDER BY created_at DESC;

-- name: RefundablePaymentForOrder :one
SELECT * FROM payments
WHERE order_id = $1 AND status = 'succeeded' AND NOT is_duplicate
ORDER BY succeeded_at
LIMIT 1;

-- name: ListPayments :many
SELECT * FROM payments
WHERE (sqlc.narg(status)::text IS NULL OR status = sqlc.narg(status)::text)
  AND (sqlc.narg(order_id)::uuid IS NULL OR order_id = sqlc.narg(order_id)::uuid)
  AND (NOT sqlc.arg(duplicates_only)::boolean OR (is_duplicate AND status = 'succeeded'))
ORDER BY created_at DESC
LIMIT sqlc.arg(lim) OFFSET sqlc.arg(off);

-- name: StalePendingPayments :many
-- Paiements en attente depuis plus de 2 minutes : à revérifier auprès du prestataire.
SELECT * FROM payments
WHERE status = 'pending' AND created_at < now() - interval '2 minutes'
ORDER BY created_at
LIMIT 100;

-- name: InsertEvent :one
-- Idempotence : un événement déjà reçu n'est pas réenregistré (aucune ligne retournée).
INSERT INTO payment_events (provider, source, event_id, reference, status, amount_xof, currency, payload)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
ON CONFLICT (provider, event_id) DO NOTHING
RETURNING id;

-- name: GetEvent :one
SELECT * FROM payment_events WHERE id = $1;

-- name: ListEventsByReference :many
SELECT id, provider, source, event_id, reference, status, amount_xof, currency, received_at
FROM payment_events WHERE reference = $1 ORDER BY id;

-- name: InsertRefund :one
INSERT INTO refunds (payment_id, order_id, reference, amount_xof, status, provider_ref, failure_reason, reason, requested_by, requested_at)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
RETURNING *;

-- name: ListRefunds :many
SELECT * FROM refunds
WHERE (sqlc.narg(order_id)::uuid IS NULL OR order_id = sqlc.narg(order_id)::uuid)
ORDER BY created_at DESC
LIMIT sqlc.arg(lim) OFFSET sqlc.arg(off);

-- name: PendingPaymentsOlderThan :one
SELECT count(*) FROM payments WHERE status = 'pending' AND created_at < sqlc.arg(before)::timestamptz;
