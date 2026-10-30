-- name: GetSettings :one
SELECT * FROM settings WHERE id;

-- name: UpdateSettings :one
UPDATE settings
SET commission_rate_bp              = sqlc.arg(commission_rate_bp),
    motorbike_base_fee_xof          = sqlc.arg(motorbike_base_fee_xof),
    motorbike_per_km_xof            = sqlc.arg(motorbike_per_km_xof),
    car_base_fee_xof                = sqlc.arg(car_base_fee_xof),
    car_per_km_xof                  = sqlc.arg(car_per_km_xof),
    distance_coefficient_pct        = sqlc.arg(distance_coefficient_pct),
    payment_timeout_minutes         = sqlc.arg(payment_timeout_minutes),
    seller_response_timeout_minutes = sqlc.arg(seller_response_timeout_minutes),
    driver_offer_timeout_seconds    = sqlc.arg(driver_offer_timeout_seconds),
    assignment_max_offers           = sqlc.arg(assignment_max_offers),
    assignment_alert_minutes        = sqlc.arg(assignment_alert_minutes),
    updated_at                      = now(),
    updated_by                      = sqlc.arg(updated_by)
WHERE id
RETURNING *;

-- name: InsertAudit :exec
INSERT INTO admin_audit_log (admin_id, action, target_type, target_id, before, after, reason)
VALUES ($1, $2, $3, $4, $5, $6, $7);

-- name: ListAudit :many
SELECT * FROM admin_audit_log
WHERE (sqlc.narg(admin_id)::uuid IS NULL OR admin_id = sqlc.narg(admin_id)::uuid)
  AND (sqlc.narg(target_type)::text IS NULL OR target_type = sqlc.narg(target_type)::text)
  AND (sqlc.narg(target_id)::text IS NULL OR target_id = sqlc.narg(target_id)::text)
ORDER BY id DESC
LIMIT sqlc.arg(lim) OFFSET sqlc.arg(off);
