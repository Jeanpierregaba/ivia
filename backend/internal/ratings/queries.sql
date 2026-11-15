-- name: InsertDeliveryRating :one
INSERT INTO delivery_ratings (order_id, driver_id, rater_id, rater_role, stars, tags, comment)
VALUES ($1, $2, $3, $4, $5, $6, $7)
RETURNING *;

-- name: GetDeliveryRating :one
SELECT * FROM delivery_ratings WHERE order_id = $1 AND rater_role = $2;

-- name: InsertAppFeedback :one
INSERT INTO app_feedback (user_id, app, stars, comment) VALUES ($1, $2, $3, $4)
RETURNING *;

-- name: LastAppFeedback :one
SELECT * FROM app_feedback WHERE user_id = $1 AND app = $2 ORDER BY created_at DESC LIMIT 1;

-- name: ListDeliveryRatings :many
SELECT * FROM delivery_ratings
WHERE (sqlc.narg(driver_id)::uuid IS NULL OR driver_id = sqlc.narg(driver_id))
ORDER BY created_at DESC
LIMIT sqlc.arg(lim) OFFSET sqlc.arg(off);

-- name: ListAppFeedback :many
SELECT * FROM app_feedback ORDER BY created_at DESC LIMIT sqlc.arg(lim) OFFSET sqlc.arg(off);

-- name: DriverAverages :many
SELECT driver_id, avg(stars)::float8 AS average, count(*)::int AS ratings,
       count(*) FILTER (WHERE stars <= 2)::int AS low
FROM delivery_ratings
GROUP BY driver_id
ORDER BY count(*) DESC
LIMIT 100;

-- name: DriverAverage :one
SELECT coalesce(avg(stars), 0)::float8 AS average, count(*)::int AS ratings
FROM delivery_ratings WHERE driver_id = $1;

-- name: AppAverages :many
SELECT app, avg(stars)::float8 AS average, count(*)::int AS ratings
FROM app_feedback GROUP BY app ORDER BY app;
