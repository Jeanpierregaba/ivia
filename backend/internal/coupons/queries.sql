-- name: GetCodeByCode :one
SELECT * FROM promo_codes WHERE code = $1;

-- name: GetCode :one
SELECT * FROM promo_codes WHERE id = $1;

-- name: CountUserUses :one
-- Utilisations d'un code par un compte (réservées ou confirmées).
SELECT count(*)::int FROM promo_redemptions
WHERE code_id = $1 AND user_id = $2 AND status <> 'released';

-- name: ReserveUse :execrows
-- Concurrence garantie par la base : jamais plus d'utilisations que permis.
UPDATE promo_codes SET uses_count = uses_count + 1, updated_at = now()
WHERE id = $1 AND status = 'active' AND (max_uses IS NULL OR uses_count < max_uses);

-- name: InsertRedemption :exec
INSERT INTO promo_redemptions (code_id, order_id, user_id, discount_xof)
VALUES ($1, $2, $3, $4);

-- name: ConfirmRedemption :execrows
UPDATE promo_redemptions SET status = 'used', updated_at = now()
WHERE order_id = $1 AND status = 'reserved';

-- name: ReleaseRedemption :one
UPDATE promo_redemptions SET status = 'released', updated_at = now()
WHERE order_id = $1 AND status = 'reserved'
RETURNING code_id;

-- name: DecrementUse :exec
UPDATE promo_codes SET uses_count = greatest(uses_count - 1, 0), updated_at = now() WHERE id = $1;

-- name: CreateCode :one
INSERT INTO promo_codes (
  code, shop_id, funded_by, kind, value, max_discount_xof, min_order_xof, starts_at, ends_at,
  max_uses, max_uses_per_user, visibility, reserved_for, welcome, created_by
) VALUES (
  sqlc.arg(code), sqlc.narg(shop_id), sqlc.arg(funded_by), sqlc.arg(kind), sqlc.arg(value),
  sqlc.narg(max_discount_xof), sqlc.arg(min_order_xof), sqlc.arg(starts_at), sqlc.narg(ends_at),
  sqlc.narg(max_uses), sqlc.arg(max_uses_per_user), sqlc.arg(visibility), sqlc.narg(reserved_for),
  sqlc.arg(welcome), sqlc.narg(created_by)
)
RETURNING id;

-- name: ListCodes :many
-- Codes avec leurs utilisations confirmées et le montant offert. Filtre facultatif par boutique.
SELECT c.*,
       coalesce((SELECT sum(r.discount_xof) FROM promo_redemptions r
                 WHERE r.code_id = c.id AND r.status = 'used'), 0)::bigint AS discount_given_xof,
       (SELECT count(*) FROM promo_redemptions r WHERE r.code_id = c.id AND r.status = 'used')::int AS used_count
FROM promo_codes c
WHERE (sqlc.narg(shop_id)::uuid IS NULL OR c.shop_id = sqlc.narg(shop_id))
  AND (sqlc.arg(include_welcome)::boolean OR NOT c.welcome)
ORDER BY c.created_at DESC
LIMIT sqlc.arg(lim) OFFSET sqlc.arg(off);

-- name: ListUserCoupons :many
-- Codes publics en cours et coupons réservés au compte, encore utilisables par lui.
SELECT c.* FROM promo_codes c
WHERE c.status = 'active'
  AND c.starts_at <= now() AND (c.ends_at IS NULL OR c.ends_at > now())
  AND (c.max_uses IS NULL OR c.uses_count < c.max_uses)
  AND ((c.visibility = 'public' AND c.reserved_for IS NULL) OR c.reserved_for = sqlc.arg(user_id))
  AND (SELECT count(*) FROM promo_redemptions r
       WHERE r.code_id = c.id AND r.user_id = sqlc.arg(user_id) AND r.status <> 'released') < c.max_uses_per_user
ORDER BY c.reserved_for IS NULL, c.ends_at NULLS LAST, c.created_at DESC
LIMIT 50;

-- name: SetCodeStatus :execrows
UPDATE promo_codes SET status = sqlc.arg(status), suspension_reason = sqlc.arg(reason), updated_at = now()
WHERE id = sqlc.arg(id) AND status <> 'ended';

-- name: HasWelcome :one
SELECT EXISTS (SELECT 1 FROM promo_codes WHERE reserved_for = $1 AND welcome)::boolean;

-- name: GetSettings :one
SELECT * FROM coupon_settings WHERE id;

-- name: UpdateSettings :one
UPDATE coupon_settings SET
  welcome_enabled = sqlc.arg(welcome_enabled), welcome_amount_xof = sqlc.arg(welcome_amount_xof),
  welcome_min_order_xof = sqlc.arg(welcome_min_order_xof), welcome_valid_days = sqlc.arg(welcome_valid_days),
  updated_at = now(), updated_by = sqlc.arg(updated_by)
WHERE id
RETURNING *;

-- name: DiscountTotals :one
-- Réductions confirmées sur une période, selon qui les paie (indicateur du back-office).
SELECT coalesce(sum(r.discount_xof) FILTER (WHERE c.funded_by = 'ivia'), 0)::bigint AS ivia_xof,
       coalesce(sum(r.discount_xof) FILTER (WHERE c.funded_by = 'shop'), 0)::bigint AS shops_xof,
       count(*)::int AS uses
FROM promo_redemptions r JOIN promo_codes c ON c.id = r.code_id
WHERE r.status = 'used' AND r.updated_at >= sqlc.arg(from_time)::timestamptz AND r.updated_at < sqlc.arg(to_time)::timestamptz;
