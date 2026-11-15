-- name: InsertMessage :one
INSERT INTO chat_messages (order_id, thread, sender_id, sender_role, body)
VALUES ($1, $2, $3, $4, $5)
RETURNING *;

-- name: ListMessages :many
SELECT * FROM chat_messages
WHERE order_id = $1 AND thread = $2
ORDER BY created_at
LIMIT 300;

-- name: MarkRead :exec
INSERT INTO chat_reads (order_id, thread, user_id, last_read_at)
VALUES ($1, $2, $3, now())
ON CONFLICT (order_id, thread, user_id) DO UPDATE SET last_read_at = now();

-- name: LastRead :one
SELECT last_read_at FROM chat_reads WHERE order_id = $1 AND thread = $2 AND user_id = $3;

-- name: CountUnread :one
SELECT count(*)::int FROM chat_messages m
WHERE m.order_id = $1 AND m.thread = $2 AND m.sender_id <> sqlc.arg(user_id)
  AND m.created_at > coalesce(
    (SELECT r.last_read_at FROM chat_reads r WHERE r.order_id = $1 AND r.thread = $2 AND r.user_id = sqlc.arg(user_id)),
    '-infinity'::timestamptz);
