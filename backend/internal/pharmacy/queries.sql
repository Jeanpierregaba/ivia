-- Requêtes du module pharmacy (tables pharmacy_*, pharmacies).

-- ---------------------------------------------------------------- réglages

-- name: GetSettings :one
SELECT * FROM pharmacy_settings WHERE id;

-- name: UpdateSettings :one
UPDATE pharmacy_settings SET
  enabled = sqlc.arg(enabled), unlock_fee_xof = sqlc.arg(unlock_fee_xof),
  search_radius_m = sqlc.arg(search_radius_m), max_radius_m = sqlc.arg(max_radius_m),
  target_responses = sqlc.arg(target_responses), widen_after_minutes = sqlc.arg(widen_after_minutes),
  response_window_minutes = sqlc.arg(response_window_minutes), pickup_hold_minutes = sqlc.arg(pickup_hold_minutes),
  photo_retention_days = sqlc.arg(photo_retention_days), updated_at = now()
WHERE id
RETURNING *;

-- ---------------------------------------------------------------- pharmacies

-- name: CreatePharmacy :one
INSERT INTO pharmacies (owner_id, name, license_number, phone, address_text, neighborhood_id, location, opening_hours)
VALUES (sqlc.arg(owner_id), sqlc.arg(name), sqlc.arg(license_number), sqlc.arg(phone), sqlc.arg(address_text),
        sqlc.narg(neighborhood_id), ST_SetSRID(ST_MakePoint(sqlc.arg(lng)::float8, sqlc.arg(lat)::float8), 4326)::geography,
        sqlc.arg(opening_hours))
RETURNING id;

-- name: UpdateApplication :execrows
-- Dossier modifiable tant qu'il n'est pas validé ; un dossier refusé repart en vérification.
UPDATE pharmacies SET
  name = sqlc.arg(name), license_number = sqlc.arg(license_number), phone = sqlc.arg(phone),
  address_text = sqlc.arg(address_text), neighborhood_id = sqlc.narg(neighborhood_id),
  location = ST_SetSRID(ST_MakePoint(sqlc.arg(lng)::float8, sqlc.arg(lat)::float8), 4326)::geography,
  opening_hours = sqlc.arg(opening_hours), review_status = 'pending_review', updated_at = now()
WHERE id = sqlc.arg(id) AND review_status IN ('pending_review', 'rejected');

-- name: UpdateContact :exec
UPDATE pharmacies SET phone = sqlc.arg(phone), opening_hours = sqlc.arg(opening_hours), updated_at = now()
WHERE id = sqlc.arg(id);

-- name: SetOpenStatus :exec
UPDATE pharmacies SET is_open = sqlc.arg(is_open), on_duty = sqlc.arg(on_duty), updated_at = now()
WHERE id = sqlc.arg(id);

-- name: PharmacyIDByOwner :one
SELECT id FROM pharmacies WHERE owner_id = $1;

-- name: GetPharmacy :one
SELECT p.id, p.owner_id, p.name, p.license_number, p.phone, p.address_text, p.neighborhood_id,
       ST_Y(p.location::geometry)::float8 AS lat, ST_X(p.location::geometry)::float8 AS lng,
       p.opening_hours, p.is_open, p.on_duty, p.review_status, p.review_note, p.reviewed_at,
       p.suspended_at, p.suspension_reason, p.created_at, p.updated_at
FROM pharmacies p WHERE p.id = $1;

-- name: LockPharmacy :one
SELECT review_status, suspended_at FROM pharmacies WHERE id = $1 FOR UPDATE;

-- name: ListPharmacyIDs :many
SELECT id FROM pharmacies
WHERE (sqlc.narg(review_status)::text IS NULL OR review_status = sqlc.narg(review_status))
  AND (NOT sqlc.arg(suspended_only)::bool OR suspended_at IS NOT NULL)
  AND (sqlc.arg(q)::text = '' OR immutable_unaccent(lower(name)) LIKE '%' || immutable_unaccent(lower(sqlc.arg(q))) || '%')
ORDER BY created_at DESC
LIMIT sqlc.arg(lim) OFFSET sqlc.arg(off);

-- name: SetReview :execrows
UPDATE pharmacies SET review_status = sqlc.arg(review_status), review_note = sqlc.arg(review_note),
  reviewed_at = now(), reviewed_by = sqlc.arg(reviewed_by), updated_at = now()
WHERE id = sqlc.arg(id);

-- name: Suspend :execrows
UPDATE pharmacies SET suspended_at = now(), suspension_reason = sqlc.arg(reason), is_open = false, on_duty = false,
  updated_at = now()
WHERE id = sqlc.arg(id) AND suspended_at IS NULL;

-- name: Reinstate :execrows
UPDATE pharmacies SET suspended_at = NULL, suspension_reason = '', updated_at = now()
WHERE id = $1 AND suspended_at IS NOT NULL;

-- name: InsertDocument :one
INSERT INTO pharmacy_documents (pharmacy_id, kind, object_key) VALUES ($1, $2, $3) RETURNING *;

-- name: ListDocuments :many
SELECT * FROM pharmacy_documents WHERE pharmacy_id = $1 ORDER BY created_at;

-- name: DocumentKeysIn :many
SELECT object_key FROM pharmacy_documents WHERE object_key = ANY(sqlc.arg(keys)::text[]);

-- name: DeleteDocumentsOf :exec
DELETE FROM pharmacy_documents WHERE pharmacy_id = $1;

-- name: FindReachablePharmacies :many
-- Pharmacies validées, non suspendues, ouvertes ou de garde, dans le rayon, pas encore sollicitées.
SELECT p.id, p.owner_id,
       ST_Distance(p.location, ST_SetSRID(ST_MakePoint(sqlc.arg(lng)::float8, sqlc.arg(lat)::float8), 4326)::geography)::float8 AS distance_m
FROM pharmacies p
WHERE p.review_status = 'approved' AND p.suspended_at IS NULL AND (p.is_open OR p.on_duty)
  AND ST_DWithin(p.location, ST_SetSRID(ST_MakePoint(sqlc.arg(lng)::float8, sqlc.arg(lat)::float8), 4326)::geography, sqlc.arg(radius_m)::float8)
  AND NOT EXISTS (SELECT 1 FROM pharmacy_alert_targets t WHERE t.alert_id = sqlc.arg(alert_id) AND t.pharmacy_id = p.id)
ORDER BY distance_m
LIMIT 50;

-- ---------------------------------------------------------------- alertes

-- name: CreateAlert :one
INSERT INTO pharmacy_alerts (buyer_id, kind, medicine_name, quantity, note, photo_key, location, radius_m, search_ends_at)
VALUES (sqlc.arg(buyer_id), sqlc.arg(kind), sqlc.arg(medicine_name), sqlc.arg(quantity), sqlc.arg(note), sqlc.narg(photo_key),
        ST_SetSRID(ST_MakePoint(sqlc.arg(lng)::float8, sqlc.arg(lat)::float8), 4326)::geography,
        sqlc.arg(radius_m), sqlc.arg(search_ends_at))
RETURNING id;

-- name: GetAlert :one
SELECT a.id, a.buyer_id, a.kind, a.medicine_name, a.quantity, a.note, a.photo_key, a.photo_purged_at,
       ST_Y(a.location::geometry)::float8 AS lat, ST_X(a.location::geometry)::float8 AS lng,
       a.radius_m, a.status, a.search_ends_at, a.widened_at, a.closed_at, a.unlocked_at, a.created_at, a.updated_at
FROM pharmacy_alerts a WHERE a.id = $1;

-- name: LockAlert :one
SELECT status, unlocked_at FROM pharmacy_alerts WHERE id = $1 FOR UPDATE;

-- name: ListBuyerAlertIDs :many
SELECT id FROM pharmacy_alerts WHERE buyer_id = $1 ORDER BY created_at DESC LIMIT sqlc.arg(lim) OFFSET sqlc.arg(off);

-- name: ListAlertIDs :many
SELECT id FROM pharmacy_alerts
WHERE (sqlc.narg(status)::text IS NULL OR status = sqlc.narg(status))
ORDER BY created_at DESC LIMIT sqlc.arg(lim) OFFSET sqlc.arg(off);

-- name: SetAlertStatus :execrows
UPDATE pharmacy_alerts SET status = sqlc.arg(new_status),
  closed_at = CASE WHEN sqlc.arg(new_status) IN ('searching') THEN closed_at ELSE coalesce(closed_at, now()) END,
  updated_at = now()
WHERE id = sqlc.arg(id) AND status = ANY(sqlc.arg(from_statuses)::text[]);

-- name: WidenAlert :exec
UPDATE pharmacy_alerts SET radius_m = sqlc.arg(radius_m), widened_at = now(), updated_at = now() WHERE id = sqlc.arg(id);

-- name: MarkUnlocked :execrows
UPDATE pharmacy_alerts SET unlocked_at = now(),
  status = CASE WHEN status = 'answered' THEN 'unlocked' ELSE status END, updated_at = now()
WHERE id = $1 AND unlocked_at IS NULL;

-- name: AlertPhotosToPurge :many
SELECT id, photo_key FROM pharmacy_alerts
WHERE photo_key IS NOT NULL AND photo_purged_at IS NULL
  AND coalesce(closed_at, created_at) < sqlc.arg(before)
LIMIT 200;

-- name: MarkPhotoPurged :exec
UPDATE pharmacy_alerts SET photo_key = NULL, photo_purged_at = now(), updated_at = now() WHERE id = $1;

-- name: BuyerPhotoKeys :many
SELECT id, photo_key FROM pharmacy_alerts WHERE buyer_id = $1 AND photo_key IS NOT NULL;

-- ---------------------------------------------------------------- pharmacies sollicitées

-- name: InsertTarget :execrows
INSERT INTO pharmacy_alert_targets (alert_id, pharmacy_id, distance_m) VALUES ($1, $2, $3)
ON CONFLICT DO NOTHING;

-- name: CountTargets :one
SELECT count(*)::bigint FROM pharmacy_alert_targets WHERE alert_id = $1;

-- name: GetTarget :one
SELECT * FROM pharmacy_alert_targets WHERE alert_id = $1 AND pharmacy_id = $2;

-- name: SetTargetStatus :exec
UPDATE pharmacy_alert_targets SET status = sqlc.arg(status), responded_at = now()
WHERE alert_id = sqlc.arg(alert_id) AND pharmacy_id = sqlc.arg(pharmacy_id);

-- name: ExpirePendingTargets :exec
UPDATE pharmacy_alert_targets SET status = 'expired' WHERE alert_id = $1 AND status = 'pending';

-- name: Inbox :many
-- Alertes adressées à la pharmacie (sans aucune donnée du client).
SELECT t.alert_id, t.distance_m, t.status AS target_status, t.notified_at,
       a.kind, a.medicine_name, a.quantity, a.note, a.photo_key, a.status AS alert_status, a.search_ends_at
FROM pharmacy_alert_targets t
JOIN pharmacy_alerts a ON a.id = t.alert_id
WHERE t.pharmacy_id = sqlc.arg(pharmacy_id)
  AND (NOT sqlc.arg(open_only)::bool OR (t.status IN ('pending', 'responded') AND a.status IN ('searching', 'answered', 'unlocked')))
ORDER BY t.notified_at DESC
LIMIT sqlc.arg(lim) OFFSET sqlc.arg(off);

-- name: InboxItem :one
SELECT t.alert_id, t.distance_m, t.status AS target_status, t.notified_at,
       a.kind, a.medicine_name, a.quantity, a.note, a.photo_key, a.status AS alert_status, a.search_ends_at
FROM pharmacy_alert_targets t
JOIN pharmacy_alerts a ON a.id = t.alert_id
WHERE t.alert_id = $1 AND t.pharmacy_id = $2;

-- ---------------------------------------------------------------- réponses

-- name: UpsertResponse :one
INSERT INTO pharmacy_responses (alert_id, pharmacy_id, product_name, unit_price_xof, quantity_available,
                                prescription_required, note, distance_m)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
ON CONFLICT (alert_id, pharmacy_id) DO UPDATE SET
  product_name = EXCLUDED.product_name, unit_price_xof = EXCLUDED.unit_price_xof,
  quantity_available = EXCLUDED.quantity_available, prescription_required = EXCLUDED.prescription_required,
  note = EXCLUDED.note, status = 'active', updated_at = now()
RETURNING *;

-- name: GetResponse :one
SELECT * FROM pharmacy_responses WHERE id = $1;

-- name: ResponseOf :one
SELECT * FROM pharmacy_responses WHERE alert_id = $1 AND pharmacy_id = $2;

-- name: WithdrawResponse :exec
UPDATE pharmacy_responses SET status = 'withdrawn', updated_at = now() WHERE id = $1;

-- name: CountActiveResponses :one
SELECT count(*)::bigint FROM pharmacy_responses WHERE alert_id = $1 AND status = 'active';

-- name: ListResponses :many
-- Réponses classées par distance, avec la pharmacie (masquée par le service avant déblocage).
SELECT r.id, r.pharmacy_id, r.product_name, r.unit_price_xof, r.quantity_available, r.prescription_required,
       r.note, r.distance_m, r.status, r.created_at,
       p.name AS pharmacy_name, p.phone AS pharmacy_phone, p.address_text AS pharmacy_address,
       ST_Y(p.location::geometry)::float8 AS pharmacy_lat, ST_X(p.location::geometry)::float8 AS pharmacy_lng,
       p.on_duty AS pharmacy_on_duty
FROM pharmacy_responses r
JOIN pharmacies p ON p.id = r.pharmacy_id
WHERE r.alert_id = $1
ORDER BY r.status = 'withdrawn', r.distance_m, r.created_at;

-- ---------------------------------------------------------------- réservations

-- name: CreateReservation :one
INSERT INTO pharmacy_reservations (alert_id, response_id, pharmacy_id, buyer_id, fulfillment, status, quantity,
  unit_price_xof, items_xof, delivery_fee_xof, commission_xof, total_xof, pharmacy_due_xof, handover_code,
  delivery_address, delivery_location, delivery_instructions, expires_at)
VALUES (sqlc.arg(alert_id), sqlc.arg(response_id), sqlc.arg(pharmacy_id), sqlc.arg(buyer_id), sqlc.arg(fulfillment),
  sqlc.arg(status), sqlc.arg(quantity), sqlc.arg(unit_price_xof), sqlc.arg(items_xof), sqlc.arg(delivery_fee_xof),
  sqlc.arg(commission_xof), sqlc.arg(total_xof), sqlc.arg(pharmacy_due_xof), sqlc.arg(handover_code),
  sqlc.arg(delivery_address),
  CASE WHEN sqlc.arg(has_location)::bool
       THEN ST_SetSRID(ST_MakePoint(sqlc.arg(lng)::float8, sqlc.arg(lat)::float8), 4326)::geography END,
  sqlc.arg(delivery_instructions), sqlc.narg(expires_at))
RETURNING id;

-- name: GetReservation :one
SELECT r.id, r.alert_id, r.response_id, r.pharmacy_id, r.buyer_id, r.fulfillment, r.status, r.quantity,
       r.unit_price_xof, r.items_xof, r.delivery_fee_xof, r.commission_xof, r.total_xof, r.pharmacy_due_xof,
       r.handover_code, r.delivery_address,
       coalesce(ST_Y(r.delivery_location::geometry), 0)::float8 AS delivery_lat,
       coalesce(ST_X(r.delivery_location::geometry), 0)::float8 AS delivery_lng,
       r.delivery_instructions, r.expires_at, r.cancel_reason, r.completed_at, r.created_at, r.updated_at
FROM pharmacy_reservations r WHERE r.id = $1;

-- name: LockReservation :one
SELECT status FROM pharmacy_reservations WHERE id = $1 FOR UPDATE;

-- name: ActiveReservationForAlert :one
SELECT id FROM pharmacy_reservations
WHERE alert_id = $1 AND status IN ('reserved', 'awaiting_payment', 'paid', 'courier_assigned', 'picked_up');

-- name: LatestReservationForAlert :one
SELECT id FROM pharmacy_reservations WHERE alert_id = $1 ORDER BY created_at DESC LIMIT 1;

-- name: SetReservationStatus :execrows
UPDATE pharmacy_reservations SET status = sqlc.arg(new_status),
  cancel_reason = CASE WHEN sqlc.arg(reason)::text <> '' THEN sqlc.arg(reason)::text ELSE cancel_reason END,
  completed_at = CASE WHEN sqlc.arg(new_status) = 'completed' THEN now() ELSE completed_at END,
  updated_at = now()
WHERE id = sqlc.arg(id) AND status = ANY(sqlc.arg(from_statuses)::text[]);

-- name: ListBuyerReservationIDs :many
SELECT id FROM pharmacy_reservations WHERE buyer_id = $1 ORDER BY created_at DESC LIMIT sqlc.arg(lim) OFFSET sqlc.arg(off);

-- name: ListPharmacyReservationIDs :many
SELECT id FROM pharmacy_reservations
WHERE pharmacy_id = sqlc.arg(pharmacy_id)
  AND (NOT sqlc.arg(active_only)::bool OR status IN ('reserved', 'awaiting_payment', 'paid', 'courier_assigned', 'picked_up'))
ORDER BY created_at DESC LIMIT sqlc.arg(lim) OFFSET sqlc.arg(off);

-- name: CountActiveReservationsOf :one
-- Réservations en cours d'un client ou de la pharmacie d'un titulaire (suppression de compte).
SELECT count(*)::bigint FROM pharmacy_reservations r
WHERE r.status IN ('paid', 'courier_assigned', 'picked_up')
  AND (r.buyer_id = $1 OR r.pharmacy_id IN (SELECT id FROM pharmacies WHERE owner_id = $1));

-- name: PharmacyEarnings :one
SELECT
  coalesce((SELECT sum(r1.pharmacy_due_xof) FROM pharmacy_reservations r1
            WHERE r1.pharmacy_id = sqlc.arg(pharmacy_id) AND r1.status = 'completed' AND r1.fulfillment = 'delivery'), 0)::bigint AS due_xof,
  coalesce((SELECT count(*) FROM pharmacy_reservations r2
            WHERE r2.pharmacy_id = sqlc.arg(pharmacy_id) AND r2.status = 'completed' AND r2.fulfillment = 'delivery'), 0)::bigint AS delivered_count,
  coalesce((SELECT count(*) FROM pharmacy_reservations r3
            WHERE r3.pharmacy_id = sqlc.arg(pharmacy_id) AND r3.status = 'completed' AND r3.fulfillment = 'pickup'), 0)::bigint AS pickup_count,
  coalesce((SELECT sum(po.amount_xof) FROM pharmacy_payouts po WHERE po.pharmacy_id = sqlc.arg(pharmacy_id)), 0)::bigint AS paid_out_xof;

-- name: InsertPayout :one
INSERT INTO pharmacy_payouts (pharmacy_id, amount_xof, reference, note, paid_by) VALUES ($1, $2, $3, $4, $5)
RETURNING *;

-- name: ListPayouts :many
SELECT * FROM pharmacy_payouts WHERE pharmacy_id = $1 ORDER BY created_at DESC LIMIT 100;

-- ---------------------------------------------------------------- paiements

-- name: CreatePayment :one
INSERT INTO pharmacy_payments (purpose, alert_id, reservation_id, buyer_id, provider, reference, amount_xof, operator, payer_phone)
VALUES (sqlc.arg(purpose), sqlc.arg(alert_id), sqlc.narg(reservation_id), sqlc.arg(buyer_id), sqlc.arg(provider),
        sqlc.arg(reference), sqlc.arg(amount_xof), sqlc.arg(operator), sqlc.arg(payer_phone))
RETURNING *;

-- name: GetPayment :one
SELECT * FROM pharmacy_payments WHERE id = $1;

-- name: GetPaymentByReference :one
SELECT * FROM pharmacy_payments WHERE reference = $1;

-- name: LockPayment :one
SELECT * FROM pharmacy_payments WHERE id = $1 FOR UPDATE;

-- name: PendingUnlockPayment :one
SELECT * FROM pharmacy_payments WHERE alert_id = $1 AND purpose = 'unlock' AND status = 'pending';

-- name: PendingOrderPayment :one
SELECT * FROM pharmacy_payments WHERE reservation_id = $1 AND purpose = 'order' AND status = 'pending';

-- name: SucceededOrderPayment :one
SELECT * FROM pharmacy_payments WHERE reservation_id = $1 AND purpose = 'order' AND status = 'succeeded'
ORDER BY created_at LIMIT 1;

-- name: SetPaymentStatus :execrows
UPDATE pharmacy_payments SET status = sqlc.arg(new_status), failure_reason = sqlc.arg(failure_reason),
  succeeded_at = CASE WHEN sqlc.arg(new_status) = 'succeeded' THEN coalesce(succeeded_at, now()) ELSE succeeded_at END,
  updated_at = now()
WHERE id = sqlc.arg(id) AND status = ANY(sqlc.arg(from_statuses)::text[]);

-- name: SetProviderRef :exec
UPDATE pharmacy_payments SET provider_ref = $2, updated_at = now() WHERE id = $1;

-- name: SetRefundReference :exec
UPDATE pharmacy_payments SET refund_reference = $2, updated_at = now() WHERE id = $1;

-- name: RecentRequestsByBuyer :one
SELECT count(*)::bigint FROM pharmacy_payments WHERE buyer_id = $1 AND created_at > sqlc.arg(since);

-- name: PaymentsToRecheck :many
SELECT * FROM pharmacy_payments WHERE status = 'pending' ORDER BY created_at LIMIT 100;

-- name: ListPayments :many
SELECT * FROM pharmacy_payments
WHERE (sqlc.narg(status)::text IS NULL OR status = sqlc.narg(status))
  AND (sqlc.narg(alert_id)::uuid IS NULL OR alert_id = sqlc.narg(alert_id))
ORDER BY created_at DESC LIMIT sqlc.arg(lim) OFFSET sqlc.arg(off);

-- name: ListAlertPayments :many
SELECT * FROM pharmacy_payments WHERE alert_id = $1 ORDER BY created_at;

-- ---------------------------------------------------------------- livreurs

-- name: CreateCourierOffer :one
INSERT INTO pharmacy_courier_offers (reservation_id, driver_id, distance_m, expires_at) VALUES ($1, $2, $3, $4)
RETURNING *;

-- name: LockCourierOffer :one
SELECT * FROM pharmacy_courier_offers WHERE id = $1 FOR UPDATE;

-- name: PendingCourierOfferForDriver :one
SELECT * FROM pharmacy_courier_offers WHERE driver_id = $1 AND status = 'pending';

-- name: PendingCourierOfferForReservation :one
SELECT * FROM pharmacy_courier_offers WHERE reservation_id = $1 AND status = 'pending';

-- name: OfferedDrivers :many
SELECT DISTINCT driver_id FROM pharmacy_courier_offers WHERE reservation_id = $1;

-- name: CountCourierOffers :one
SELECT count(*)::bigint FROM pharmacy_courier_offers WHERE reservation_id = $1;

-- name: RespondCourierOffer :execrows
UPDATE pharmacy_courier_offers SET status = sqlc.arg(new_status), responded_at = now()
WHERE id = sqlc.arg(id) AND status = 'pending';

-- name: ExpireCourierOffer :execrows
UPDATE pharmacy_courier_offers SET status = 'expired', responded_at = now()
WHERE id = $1 AND status = 'pending' AND expires_at <= now();

-- name: CancelCourierOffers :exec
UPDATE pharmacy_courier_offers SET status = 'cancelled', responded_at = now()
WHERE reservation_id = $1 AND status = 'pending';

-- name: CreateDelivery :one
INSERT INTO pharmacy_deliveries (reservation_id, driver_id, offer_id, fee_xof) VALUES ($1, $2, $3, $4)
RETURNING *;

-- name: GetDelivery :one
SELECT * FROM pharmacy_deliveries WHERE id = $1;

-- name: LockDelivery :one
SELECT * FROM pharmacy_deliveries WHERE id = $1 FOR UPDATE;

-- name: ActiveDeliveryForDriver :one
SELECT * FROM pharmacy_deliveries WHERE driver_id = $1 AND status IN ('assigned', 'picked_up');

-- name: ActiveDeliveryForReservation :one
SELECT * FROM pharmacy_deliveries WHERE reservation_id = $1 AND status IN ('assigned', 'picked_up');

-- name: LatestDeliveryForReservation :one
SELECT * FROM pharmacy_deliveries WHERE reservation_id = $1 ORDER BY created_at DESC LIMIT 1;

-- name: SetDeliveryStatus :execrows
UPDATE pharmacy_deliveries SET status = sqlc.arg(new_status),
  picked_up_at = CASE WHEN sqlc.arg(new_status) = 'picked_up' THEN now() ELSE picked_up_at END,
  delivered_at = CASE WHEN sqlc.arg(new_status) = 'delivered' THEN now() ELSE delivered_at END,
  ended_at = CASE WHEN sqlc.arg(new_status) IN ('delivered', 'cancelled') THEN now() ELSE ended_at END,
  updated_at = now()
WHERE id = sqlc.arg(id) AND status = ANY(sqlc.arg(from_statuses)::text[]);

-- name: ListDriverDeliveries :many
SELECT * FROM pharmacy_deliveries WHERE driver_id = $1 ORDER BY created_at DESC LIMIT sqlc.arg(lim) OFFSET sqlc.arg(off);

-- ---------------------------------------------------------------- tableau de bord

-- name: Overview :one
SELECT
  (SELECT count(*) FROM pharmacies p1 WHERE p1.review_status = 'pending_review')::bigint AS pending_review,
  (SELECT count(*) FROM pharmacies p2 WHERE p2.review_status = 'approved' AND p2.suspended_at IS NULL)::bigint AS approved,
  (SELECT count(*) FROM pharmacies p3 WHERE p3.review_status = 'approved' AND p3.suspended_at IS NULL
                                        AND (p3.is_open OR p3.on_duty))::bigint AS reachable,
  (SELECT count(*) FROM pharmacy_alerts a1 WHERE a1.created_at >= sqlc.arg(from_time) AND a1.created_at < sqlc.arg(to_time))::bigint AS alerts,
  (SELECT count(*) FROM pharmacy_alerts a2 WHERE a2.created_at >= sqlc.arg(from_time) AND a2.created_at < sqlc.arg(to_time)
                                             AND a2.status = 'no_response')::bigint AS alerts_without_response,
  (SELECT count(*) FROM pharmacy_alerts a3 WHERE a3.created_at >= sqlc.arg(from_time) AND a3.created_at < sqlc.arg(to_time)
                                             AND a3.unlocked_at IS NOT NULL)::bigint AS unlocked,
  (SELECT coalesce(sum(y.amount_xof), 0) FROM pharmacy_payments y WHERE y.status = 'succeeded' AND y.purpose = 'unlock'
     AND y.succeeded_at >= sqlc.arg(from_time) AND y.succeeded_at < sqlc.arg(to_time))::bigint AS unlock_revenue_xof,
  (SELECT coalesce(sum(r1.commission_xof), 0) FROM pharmacy_reservations r1 WHERE r1.status = 'completed'
     AND r1.completed_at >= sqlc.arg(from_time) AND r1.completed_at < sqlc.arg(to_time))::bigint AS commission_xof,
  (SELECT count(*) FROM pharmacy_reservations r2 WHERE r2.status = 'completed'
     AND r2.completed_at >= sqlc.arg(from_time) AND r2.completed_at < sqlc.arg(to_time))::bigint AS completed;
