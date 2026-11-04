-- name: CreateOrder :one
INSERT INTO orders (
  buyer_id, shop_id, status, fulfillment, vehicle_type, parcel_size,
  subtotal_xof, delivery_fee_xof, total_xof, commission_rate_bp, commission_xof,
  delivery_distance_m, delivery_address_text, delivery_neighborhood, delivery_location, delivery_instructions,
  handover_code, client_request_id, payment_deadline_at
) VALUES (
  sqlc.arg(buyer_id), sqlc.arg(shop_id), 'pending_payment', sqlc.arg(fulfillment), sqlc.narg(vehicle_type), sqlc.arg(parcel_size),
  sqlc.arg(subtotal_xof), sqlc.arg(delivery_fee_xof), sqlc.arg(total_xof), sqlc.arg(commission_rate_bp), sqlc.arg(commission_xof),
  sqlc.narg(delivery_distance_m), sqlc.narg(delivery_address_text), sqlc.narg(delivery_neighborhood),
  CASE WHEN sqlc.narg(delivery_lat)::float8 IS NULL THEN NULL
       ELSE ST_SetSRID(ST_MakePoint(sqlc.narg(delivery_lng)::float8, sqlc.narg(delivery_lat)::float8), 4326)::geography END,
  sqlc.narg(delivery_instructions),
  sqlc.arg(handover_code), sqlc.narg(client_request_id), sqlc.arg(payment_deadline_at)
)
RETURNING id;

-- name: InsertItem :exec
INSERT INTO order_items (order_id, product_id, product_name, unit_price_xof, quantity, line_total_xof, parcel_size, stock_mode)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8);

-- name: InsertEvent :exec
INSERT INTO order_status_events (order_id, from_status, to_status, actor_type, actor_id, reason)
VALUES ($1, $2, $3, $4, $5, $6);

-- name: GetOrder :one
SELECT o.id, o.number, o.buyer_id, o.shop_id, o.status, o.fulfillment, o.vehicle_type, o.parcel_size,
       o.subtotal_xof, o.delivery_fee_xof, o.total_xof, o.commission_rate_bp, o.commission_xof,
       o.delivery_distance_m, o.delivery_address_text, o.delivery_neighborhood, o.delivery_instructions,
       (o.delivery_location IS NOT NULL)::boolean AS has_delivery_location,
       coalesce(ST_Y(o.delivery_location::geometry), 0)::float8 AS delivery_lat,
       coalesce(ST_X(o.delivery_location::geometry), 0)::float8 AS delivery_lng,
       o.handover_code, o.handover_attempts, o.stock_released, o.cancel_reason, o.refund_due_xof,
       o.payment_deadline_at, o.seller_deadline_at, o.paid_at, o.accepted_at, o.ready_at, o.picked_up_at,
       o.completed_at, o.cancelled_at, o.refunded_at, o.created_at, o.updated_at
FROM orders o
WHERE o.id = $1;

-- name: LockOrder :one
SELECT status FROM orders WHERE id = $1 FOR UPDATE;

-- name: GetOrderByClientRequest :one
SELECT id FROM orders WHERE buyer_id = $1 AND client_request_id = $2;

-- name: ListItems :many
SELECT * FROM order_items WHERE order_id = $1 ORDER BY product_name;

-- name: ListEvents :many
SELECT * FROM order_status_events WHERE order_id = $1 ORDER BY id;

-- name: UpdateStatus :execrows
UPDATE orders
SET status             = sqlc.arg(to_status),
    updated_at         = now(),
    paid_at            = CASE WHEN sqlc.arg(mark_paid)::boolean THEN coalesce(paid_at, now()) ELSE paid_at END,
    accepted_at        = CASE WHEN sqlc.arg(to_status) = 'accepted' THEN now() ELSE accepted_at END,
    ready_at           = CASE WHEN sqlc.arg(to_status) IN ('ready_for_pickup', 'awaiting_driver') THEN coalesce(ready_at, now()) ELSE ready_at END,
    picked_up_at       = CASE WHEN sqlc.arg(to_status) = 'picked_up' THEN now() ELSE picked_up_at END,
    completed_at       = CASE WHEN sqlc.arg(to_status) IN ('completed', 'delivered') THEN now() ELSE completed_at END,
    cancelled_at       = CASE WHEN sqlc.arg(to_status) = 'cancelled' THEN coalesce(cancelled_at, now()) ELSE cancelled_at END,
    refunded_at        = CASE WHEN sqlc.arg(to_status) = 'refunded' THEN now() ELSE refunded_at END,
    seller_deadline_at = coalesce(sqlc.narg(seller_deadline_at), seller_deadline_at),
    cancel_reason      = CASE WHEN sqlc.arg(to_status) = 'cancelled' THEN sqlc.arg(reason) ELSE cancel_reason END,
    refund_due_xof     = sqlc.arg(refund_due_xof),
    stock_released     = sqlc.arg(stock_released)
WHERE id = sqlc.arg(id) AND status = sqlc.arg(from_status);

-- name: RecordLatePayment :execrows
-- Paiement reçu pour une commande annulée avant d'être payée : elle entre dans la file de remboursement.
UPDATE orders SET paid_at = now(), refund_due_xof = total_xof, updated_at = now()
WHERE id = $1 AND status = 'cancelled' AND paid_at IS NULL;

-- name: IncrementHandoverAttempts :one
UPDATE orders SET handover_attempts = handover_attempts + 1, updated_at = now()
WHERE id = $1 AND handover_attempts < sqlc.arg(max_attempts)
RETURNING handover_attempts;

-- name: ResetHandoverAttempts :exec
UPDATE orders SET handover_attempts = 0, updated_at = now() WHERE id = $1;

-- name: ListBuyerOrders :many
SELECT o.id FROM orders o
WHERE o.buyer_id = sqlc.arg(buyer_id)
  -- Groupe d'onglet (en cours, terminées) : liste de statuts, NULL pour toutes.
  AND (sqlc.narg(statuses)::text[] IS NULL OR o.status = ANY(sqlc.narg(statuses)::text[]))
ORDER BY o.created_at DESC
LIMIT sqlc.arg(lim) OFFSET sqlc.arg(off);

-- name: ListShopOrders :many
SELECT o.id FROM orders o
WHERE o.shop_id = ANY(sqlc.arg(shop_ids)::uuid[])
  -- Le marchand ne voit que les commandes payées.
  AND o.paid_at IS NOT NULL
  AND (sqlc.narg(status)::text IS NULL OR o.status = sqlc.narg(status)::text)
  -- Groupe d'onglet (nouvelles, en cours, terminées) : liste de statuts, NULL pour toutes.
  AND (sqlc.narg(statuses)::text[] IS NULL OR o.status = ANY(sqlc.narg(statuses)::text[]))
ORDER BY o.created_at DESC
LIMIT sqlc.arg(lim) OFFSET sqlc.arg(off);

-- name: AdminListOrders :many
SELECT o.id FROM orders o
WHERE (sqlc.narg(status)::text IS NULL OR o.status = sqlc.narg(status)::text)
  AND (sqlc.narg(shop_id)::uuid IS NULL OR o.shop_id = sqlc.narg(shop_id)::uuid)
  AND (sqlc.narg(buyer_id)::uuid IS NULL OR o.buyer_id = sqlc.narg(buyer_id)::uuid)
  AND (sqlc.narg(number)::bigint IS NULL OR o.number = sqlc.narg(number)::bigint)
ORDER BY o.created_at DESC
LIMIT sqlc.arg(lim) OFFSET sqlc.arg(off);

-- name: RefundQueue :many
SELECT o.id FROM orders o
WHERE o.status IN ('cancelled', 'returned_to_shop') AND o.refund_due_xof > 0
ORDER BY o.updated_at
LIMIT sqlc.arg(lim) OFFSET sqlc.arg(off);

-- name: EraseBuyerPersonalData :exec
-- Suppression de compte : adresse de livraison et consignes effacées des commandes de l'acheteur.
UPDATE orders
SET delivery_address_text = NULL, delivery_neighborhood = NULL, delivery_instructions = NULL,
    delivery_location = NULL, personal_data_erased_at = now(), updated_at = now()
WHERE buyer_id = $1 AND personal_data_erased_at IS NULL;

-- name: CountActiveBuyerOrders :one
-- Commandes en cours ou en attente de remboursement (bloquent la suppression du compte).
SELECT count(*) FROM orders
WHERE buyer_id = $1
  AND (status NOT IN ('expired', 'completed', 'delivered', 'cancelled', 'returned_to_shop', 'refunded')
       OR (status IN ('cancelled', 'returned_to_shop') AND refund_due_xof > 0));

-- name: CountActiveShopOrders :one
SELECT count(*) FROM orders
WHERE shop_id = ANY(sqlc.arg(shop_ids)::uuid[])
  AND status NOT IN ('pending_payment', 'expired', 'completed', 'delivered', 'cancelled', 'returned_to_shop', 'refunded');

-- name: CompletedForShop :many
-- Commandes remises (retrait ou livraison) dans une période, pour les relevés marchands.
SELECT id, number, completed_at, subtotal_xof, commission_xof FROM orders
WHERE shop_id = sqlc.arg(shop_id)
  AND status IN ('completed', 'delivered')
  AND completed_at >= sqlc.arg(from_time)::timestamptz AND completed_at < sqlc.arg(to_time)::timestamptz
ORDER BY completed_at;

-- name: Metrics :one
SELECT
  count(*) FILTER (WHERE paid_at IS NOT NULL)::bigint AS paid_orders,
  count(*) FILTER (WHERE status IN ('completed', 'delivered'))::bigint AS completed_orders,
  count(*) FILTER (WHERE paid_at IS NOT NULL AND status IN ('cancelled', 'refunded', 'returned_to_shop'))::bigint AS cancelled_after_payment,
  count(*) FILTER (WHERE status = 'expired')::bigint AS expired_orders,
  coalesce(sum(total_xof) FILTER (WHERE status IN ('completed', 'delivered')), 0)::bigint AS gmv_xof,
  coalesce(sum(commission_xof) FILTER (WHERE status IN ('completed', 'delivered')), 0)::bigint AS commission_xof,
  coalesce(percentile_cont(0.5) WITHIN GROUP (ORDER BY extract(epoch FROM completed_at - ready_at))
    FILTER (WHERE status = 'delivered' AND ready_at IS NOT NULL), 0)::float8 AS median_ready_to_delivered_s
FROM orders
WHERE created_at >= sqlc.arg(from_time)::timestamptz AND created_at < sqlc.arg(to_time)::timestamptz;

-- name: PaidOrdersPerDay :many
SELECT (paid_at AT TIME ZONE 'Africa/Lome')::date AS day, count(*)::bigint AS orders
FROM orders
WHERE paid_at >= sqlc.arg(from_time)::timestamptz AND paid_at < sqlc.arg(to_time)::timestamptz
GROUP BY 1 ORDER BY 1;

-- name: OverviewCounts :one
-- Compteurs du tableau de bord : commandes en cours et leurs groupes, codes bloqués, file de
-- remboursement (même définition que RefundQueue).
SELECT
  count(*) FILTER (WHERE status IN ('awaiting_seller', 'accepted', 'preparing', 'ready_for_pickup',
                                    'awaiting_driver', 'driver_assigned', 'picked_up'))::bigint AS active,
  count(*) FILTER (WHERE status = 'awaiting_seller')::bigint AS to_accept,
  count(*) FILTER (WHERE status = 'awaiting_driver')::bigint AS without_driver,
  count(*) FILTER (WHERE handover_attempts >= 5
                     AND status IN ('ready_for_pickup', 'driver_assigned', 'picked_up'))::bigint AS handover_locked,
  count(*) FILTER (WHERE status IN ('cancelled', 'returned_to_shop') AND refund_due_xof > 0)::bigint AS refunds,
  coalesce(sum(refund_due_xof) FILTER (WHERE status IN ('cancelled', 'returned_to_shop') AND refund_due_xof > 0), 0)::bigint AS refunds_xof
FROM orders;

-- name: PaidPerDayByMode :many
-- Commandes payées par jour (heure de Lomé) et par mode, sur une période.
SELECT (paid_at AT TIME ZONE 'Africa/Lome')::date AS day, fulfillment, count(*)::bigint AS n
FROM orders
WHERE paid_at >= sqlc.arg(from_time)::timestamptz AND paid_at < sqlc.arg(to_time)::timestamptz
GROUP BY 1, 2
ORDER BY 1;

-- name: ActiveOrdersOverview :many
-- Commandes en cours du tableau de bord, filtrées par groupe ; since : dernier changement de statut.
SELECT o.id, o.number, o.shop_id, o.buyer_id, o.fulfillment, o.total_xof, o.status, o.handover_attempts,
       coalesce((SELECT max(e.created_at) FROM order_status_events e WHERE e.order_id = o.id), o.updated_at)::timestamptz AS since
FROM orders o
WHERE o.status = ANY(sqlc.arg(statuses)::text[])
  AND (NOT sqlc.arg(locked_only)::boolean OR o.handover_attempts >= 5)
ORDER BY o.number DESC
LIMIT sqlc.arg(lim);

-- name: ProductSales :many
-- Ventes payées des produits donnés sur [from, to) (statistiques publicitaires).
SELECT i.product_id, count(DISTINCT o.id)::bigint AS orders, coalesce(sum(i.quantity), 0)::bigint AS units,
       coalesce(sum(i.line_total_xof), 0)::bigint AS revenue_xof
FROM order_items i
JOIN orders o ON o.id = i.order_id
WHERE i.product_id = ANY(sqlc.arg(product_ids)::uuid[])
  AND o.paid_at >= sqlc.arg(from_time)::timestamptz AND o.paid_at < sqlc.arg(to_time)::timestamptz
GROUP BY i.product_id;
