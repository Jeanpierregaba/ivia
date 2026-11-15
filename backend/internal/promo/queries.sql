-- name: ListVisuals :many
SELECT * FROM promo_visuals
WHERE (NOT sqlc.arg(active_only)::boolean
       OR (is_active AND (starts_at IS NULL OR starts_at <= now()) AND (ends_at IS NULL OR ends_at > now())))
ORDER BY priority DESC, created_at DESC
LIMIT 200;

-- name: GetVisual :one
SELECT * FROM promo_visuals WHERE id = $1;

-- name: CreateVisual :one
INSERT INTO promo_visuals (kind, title, subtitle, body, image_key, product_id, cta_label, external_url,
                           placements, apps, priority, weight, starts_at, ends_at, is_active, created_by)
VALUES (sqlc.arg(kind), sqlc.arg(title), sqlc.arg(subtitle), sqlc.arg(body), sqlc.arg(image_key),
        sqlc.narg(product_id), sqlc.arg(cta_label), sqlc.arg(external_url), sqlc.arg(placements)::text[],
        sqlc.arg(apps)::text[], sqlc.arg(priority), sqlc.arg(weight), sqlc.narg(starts_at), sqlc.narg(ends_at),
        sqlc.arg(is_active), sqlc.narg(created_by))
RETURNING *;

-- name: UpdateVisual :one
UPDATE promo_visuals SET
  kind = sqlc.arg(kind), title = sqlc.arg(title), subtitle = sqlc.arg(subtitle), body = sqlc.arg(body),
  image_key = sqlc.arg(image_key), product_id = sqlc.narg(product_id), cta_label = sqlc.arg(cta_label),
  external_url = sqlc.arg(external_url), placements = sqlc.arg(placements)::text[], apps = sqlc.arg(apps)::text[],
  priority = sqlc.arg(priority), weight = sqlc.arg(weight), starts_at = sqlc.narg(starts_at),
  ends_at = sqlc.narg(ends_at), is_active = sqlc.arg(is_active), updated_at = now()
WHERE id = sqlc.arg(id)
RETURNING *;

-- name: DeleteVisual :exec
DELETE FROM promo_visuals WHERE id = $1;

-- name: GetSettings :one
SELECT * FROM promo_settings WHERE id;

-- name: UpdateSettings :one
UPDATE promo_settings SET
  enabled = sqlc.arg(enabled), banners_enabled = sqlc.arg(banners_enabled), modal_enabled = sqlc.arg(modal_enabled),
  interstitial_enabled = sqlc.arg(interstitial_enabled), first_delay_seconds = sqlc.arg(first_delay_seconds),
  min_interval_seconds = sqlc.arg(min_interval_seconds), max_per_session = sqlc.arg(max_per_session),
  feed_every = sqlc.arg(feed_every), rotation = sqlc.arg(rotation), official_url = sqlc.arg(official_url),
  updated_by = sqlc.narg(updated_by), updated_at = now()
WHERE id
RETURNING *;

-- name: InsertEvent :exec
INSERT INTO promo_events (kind, visual_id, product_id, placement, app, session_id)
VALUES (sqlc.arg(kind), sqlc.narg(visual_id), sqlc.narg(product_id), sqlc.arg(placement), sqlc.arg(app), sqlc.arg(session_id));

-- name: EventTotals :many
SELECT kind, count(*)::bigint AS events, count(DISTINCT session_id)::bigint AS sessions
FROM promo_events
WHERE created_at >= sqlc.arg(since) AND created_at < sqlc.arg(until)
GROUP BY kind;

-- name: EventsByVisual :many
SELECT visual_id::uuid AS visual_id,
       count(*) FILTER (WHERE kind = 'impression')::bigint AS impressions,
       count(*) FILTER (WHERE kind = 'dismiss')::bigint AS dismissals,
       count(*) FILTER (WHERE kind IN ('click_order', 'click_product', 'click_site'))::bigint AS clicks,
       count(*) FILTER (WHERE kind = 'click_site')::bigint AS site_clicks,
       count(*) FILTER (WHERE kind = 'order')::bigint AS orders
FROM promo_events
WHERE visual_id IS NOT NULL AND created_at >= sqlc.arg(since) AND created_at < sqlc.arg(until)
GROUP BY visual_id;

-- name: EventsByProduct :many
SELECT product_id::uuid AS product_id,
       count(*) FILTER (WHERE kind = 'impression')::bigint AS impressions,
       count(*) FILTER (WHERE kind = 'click_product')::bigint AS views,
       count(*) FILTER (WHERE kind = 'click_order')::bigint AS order_clicks,
       count(*) FILTER (WHERE kind = 'order')::bigint AS orders
FROM promo_events
WHERE product_id IS NOT NULL AND created_at >= sqlc.arg(since) AND created_at < sqlc.arg(until)
GROUP BY product_id;

-- name: EventsPerDay :many
SELECT (created_at AT TIME ZONE 'Africa/Lome')::date AS day,
       count(*) FILTER (WHERE kind = 'impression')::bigint AS impressions,
       count(*) FILTER (WHERE kind IN ('click_order', 'click_product', 'click_site'))::bigint AS clicks
FROM promo_events
WHERE created_at >= sqlc.arg(since) AND created_at < sqlc.arg(until)
GROUP BY 1 ORDER BY 1;
