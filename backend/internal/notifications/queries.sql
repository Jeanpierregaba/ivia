-- name: CreateNotification :one
INSERT INTO notifications (user_id, app, kind, title, body, data)
VALUES ($1, $2, $3, $4, $5, $6)
RETURNING id;

-- name: GetNotification :one
SELECT * FROM notifications WHERE id = $1;

-- name: ListNotifications :many
SELECT * FROM notifications
WHERE user_id = $1 AND app = $2
ORDER BY created_at DESC
LIMIT sqlc.arg(lim) OFFSET sqlc.arg(off);

-- name: CountUnread :one
SELECT count(*) FROM notifications WHERE user_id = $1 AND app = $2 AND read_at IS NULL;

-- name: MarkRead :execrows
UPDATE notifications SET read_at = coalesce(read_at, now())
WHERE id = sqlc.arg(id) AND user_id = sqlc.arg(user_id);

-- name: MarkAllRead :exec
UPDATE notifications SET read_at = now()
WHERE user_id = $1 AND app = $2 AND read_at IS NULL;

-- name: MarkPushSent :exec
UPDATE notifications SET push_sent_at = now() WHERE id = $1;

-- name: DeleteNotification :execrows
DELETE FROM notifications WHERE id = sqlc.arg(id) AND user_id = sqlc.arg(user_id);

-- name: DeleteAppNotifications :exec
DELETE FROM notifications WHERE user_id = $1 AND app = $2;

-- name: DeleteUserNotifications :exec
DELETE FROM notifications WHERE user_id = $1;
