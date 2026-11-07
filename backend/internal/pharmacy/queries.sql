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
  photo_retention_days = sqlc.arg(photo_retention_days), radius_options_m = sqlc.arg(radius_options_m)::int[],
  photo_retention_hours = sqlc.arg(photo_retention_hours), auto_widen = sqlc.arg(auto_widen),
  night_from_hour = sqlc.arg(night_from_hour), night_to_hour = sqlc.arg(night_to_hour),
  product_commission_bp = sqlc.arg(product_commission_bp), updated_at = now()
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
-- Dossier modifiable tant qu'il n'est pas envoyé, ou après un retour du back-office.
UPDATE pharmacies SET
  name = sqlc.arg(name), license_number = sqlc.arg(license_number), phone = sqlc.arg(phone),
  address_text = sqlc.arg(address_text), neighborhood_id = sqlc.narg(neighborhood_id),
  location = ST_SetSRID(ST_MakePoint(sqlc.arg(lng)::float8, sqlc.arg(lat)::float8), 4326)::geography,
  opening_hours = sqlc.arg(opening_hours), updated_at = now()
WHERE id = sqlc.arg(id) AND review_status IN ('draft', 'changes_requested', 'rejected');

-- name: UpdateContact :exec
UPDATE pharmacies SET phone = sqlc.arg(phone), opening_hours = sqlc.arg(opening_hours), updated_at = now()
WHERE id = sqlc.arg(id);

-- name: SetOpenStatus :exec
UPDATE pharmacies SET is_open = sqlc.arg(is_open), on_duty = sqlc.arg(on_duty), open_24h = sqlc.arg(open_24h), updated_at = now()
WHERE id = sqlc.arg(id);

-- name: PharmacyIDByOwner :one
SELECT id FROM pharmacies WHERE owner_id = $1;

-- name: GetPharmacy :one
SELECT p.id, p.owner_id, p.name, p.license_number, p.phone, p.address_text, p.neighborhood_id,
       ST_Y(p.location::geometry)::float8 AS lat, ST_X(p.location::geometry)::float8 AS lng,
       p.opening_hours, p.is_open, p.on_duty, p.review_status, p.review_note, p.reviewed_at,
       p.suspended_at, p.suspension_reason, p.created_at, p.updated_at, p.open_24h,
       coalesce((SELECT max(s.ends_at) FROM pharmacy_duty_shifts s
         WHERE s.pharmacy_id = p.id AND s.starts_at <= now() AND s.ends_at > now()), 'epoch')::timestamptz AS duty_until
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
-- Pharmacies validées, non suspendues, de garde (planning en vigueur, 24 h/24, ou déclarées
-- ouvertes / de garde), dans le rayon, pas encore sollicitées.
SELECT p.id, p.owner_id,
       ST_Distance(p.location, ST_SetSRID(ST_MakePoint(sqlc.arg(lng)::float8, sqlc.arg(lat)::float8), 4326)::geography)::float8 AS distance_m
FROM pharmacies p
WHERE p.review_status = 'approved' AND p.suspended_at IS NULL
  AND (p.open_24h OR p.on_duty OR (p.is_open AND NOT pharmacy_night_now(
        coalesce(p.night_from_hour, (SELECT st.night_from_hour FROM pharmacy_settings st WHERE st.id)),
        coalesce(p.night_to_hour, (SELECT st.night_to_hour FROM pharmacy_settings st WHERE st.id)))::boolean) OR EXISTS (
        SELECT 1 FROM pharmacy_duty_shifts s WHERE s.pharmacy_id = p.id AND s.starts_at <= now() AND s.ends_at > now()))
  AND ST_DWithin(p.location, ST_SetSRID(ST_MakePoint(sqlc.arg(lng)::float8, sqlc.arg(lat)::float8), 4326)::geography, sqlc.arg(radius_m)::float8)
  AND NOT EXISTS (SELECT 1 FROM pharmacy_alert_targets t WHERE t.alert_id = sqlc.arg(alert_id) AND t.pharmacy_id = p.id)
ORDER BY distance_m
LIMIT 50;

-- name: CountReachablePharmacies :one
SELECT count(*)::bigint FROM pharmacies p
WHERE p.review_status = 'approved' AND p.suspended_at IS NULL
  AND (p.open_24h OR p.on_duty OR (p.is_open AND NOT pharmacy_night_now(
        coalesce(p.night_from_hour, (SELECT st.night_from_hour FROM pharmacy_settings st WHERE st.id)),
        coalesce(p.night_to_hour, (SELECT st.night_to_hour FROM pharmacy_settings st WHERE st.id)))::boolean) OR EXISTS (
        SELECT 1 FROM pharmacy_duty_shifts s WHERE s.pharmacy_id = p.id AND s.starts_at <= now() AND s.ends_at > now()))
  AND ST_DWithin(p.location, ST_SetSRID(ST_MakePoint(sqlc.arg(lng)::float8, sqlc.arg(lat)::float8), 4326)::geography, sqlc.arg(radius_m)::float8);

-- name: OnDutyPharmacies :many
-- Pharmacies de garde autour d'un point (liste publique : nom, adresse, téléphone).
SELECT p.id, p.name, p.phone, p.address_text,
       ST_Y(p.location::geometry)::float8 AS lat, ST_X(p.location::geometry)::float8 AS lng,
       p.open_24h, p.is_open, p.on_duty,
       coalesce((SELECT max(d.ends_at) FROM pharmacy_duty_shifts d
         WHERE d.pharmacy_id = p.id AND d.starts_at <= now() AND d.ends_at > now()), 'epoch')::timestamptz AS duty_until,
       ST_Distance(p.location, ST_SetSRID(ST_MakePoint(sqlc.arg(lng)::float8, sqlc.arg(lat)::float8), 4326)::geography)::float8 AS distance_m
FROM pharmacies p
WHERE p.review_status = 'approved' AND p.suspended_at IS NULL
  AND (p.open_24h OR p.is_open OR p.on_duty OR EXISTS (
        SELECT 1 FROM pharmacy_duty_shifts s WHERE s.pharmacy_id = p.id AND s.starts_at <= now() AND s.ends_at > now()))
  AND ST_DWithin(p.location, ST_SetSRID(ST_MakePoint(sqlc.arg(lng)::float8, sqlc.arg(lat)::float8), 4326)::geography, sqlc.arg(radius_m)::float8)
ORDER BY distance_m
LIMIT sqlc.arg(lim);

-- ---------------------------------------------------------------- planning de garde

-- name: InsertDutyShift :one
INSERT INTO pharmacy_duty_shifts (pharmacy_id, starts_at, ends_at, created_by) VALUES ($1, $2, $3, $4) RETURNING *;

-- name: ListDutyShifts :many
SELECT * FROM pharmacy_duty_shifts WHERE pharmacy_id = $1 AND ends_at > sqlc.arg(since)
ORDER BY starts_at LIMIT 200;

-- name: DeleteDutyShift :one
DELETE FROM pharmacy_duty_shifts WHERE id = $1 RETURNING *;

-- ---------------------------------------------------------------- médicaments

-- name: SearchMedicines :many
SELECT * FROM medicines
WHERE is_active
  AND immutable_unaccent(lower(name || ' ' || dosage || ' ' || active_ingredient)) LIKE '%' || immutable_unaccent(lower(sqlc.arg(q)::text)) || '%'
ORDER BY name, dosage
LIMIT sqlc.arg(lim);

-- name: AdminListMedicines :many
SELECT * FROM medicines
WHERE (sqlc.arg(q)::text = '' OR immutable_unaccent(lower(name || ' ' || dosage || ' ' || active_ingredient)) LIKE '%' || immutable_unaccent(lower(sqlc.arg(q)::text)) || '%')
ORDER BY name, dosage
LIMIT sqlc.arg(lim) OFFSET sqlc.arg(off);

-- name: GetMedicine :one
SELECT * FROM medicines WHERE id = $1;

-- name: InsertMedicine :one
INSERT INTO medicines (name, dosage, form, active_ingredient) VALUES ($1, $2, $3, $4) RETURNING *;

-- name: UpdateMedicine :one
UPDATE medicines SET name = sqlc.arg(name), dosage = sqlc.arg(dosage), form = sqlc.arg(form),
  active_ingredient = sqlc.arg(active_ingredient), is_active = sqlc.arg(is_active), updated_at = now()
WHERE id = sqlc.arg(id)
RETURNING *;

-- ---------------------------------------------------------------- alertes

-- name: CreateAlert :one
INSERT INTO pharmacy_alerts (buyer_id, kind, medicine_name, quantity, note, location, radius_m, search_ends_at,
                             generic_accepted, relaunched_from)
VALUES (sqlc.arg(buyer_id), sqlc.arg(kind), sqlc.arg(medicine_name), 1, sqlc.arg(note),
        ST_SetSRID(ST_MakePoint(sqlc.arg(lng)::float8, sqlc.arg(lat)::float8), 4326)::geography,
        sqlc.arg(radius_m), sqlc.arg(search_ends_at), sqlc.arg(generic_accepted), sqlc.narg(relaunched_from))
RETURNING id;

-- name: InsertAlertItem :exec
INSERT INTO pharmacy_alert_items (alert_id, position, medicine_id, name, form, quantity)
VALUES (sqlc.arg(alert_id), sqlc.arg(position), sqlc.narg(medicine_id), sqlc.arg(name), sqlc.arg(form), sqlc.arg(quantity));

-- name: ListAlertItems :many
SELECT * FROM pharmacy_alert_items WHERE alert_id = $1 ORDER BY position;

-- name: InsertAlertPhoto :exec
INSERT INTO pharmacy_alert_photos (alert_id, kind, position, object_key) VALUES ($1, $2, $3, $4);

-- name: ListAlertPhotos :many
SELECT * FROM pharmacy_alert_photos WHERE alert_id = $1 ORDER BY position;

-- name: AlertPhotoKeysIn :many
SELECT object_key::text AS object_key FROM pharmacy_alert_photos WHERE object_key = ANY(sqlc.arg(keys)::text[])
UNION ALL
SELECT photo_key::text FROM pharmacy_alerts WHERE photo_key = ANY(sqlc.arg(keys)::text[]);

-- name: AlertPhotosDue :many
-- Photos à supprimer : alertes lancées avant le seuil (durée de conservation).
SELECT ph.id, ph.object_key FROM pharmacy_alert_photos ph
JOIN pharmacy_alerts a ON a.id = ph.alert_id
WHERE ph.object_key IS NOT NULL AND a.created_at < sqlc.arg(before)
LIMIT 200;

-- name: BuyerAlertPhotos :many
SELECT ph.id, ph.object_key FROM pharmacy_alert_photos ph
JOIN pharmacy_alerts a ON a.id = ph.alert_id
WHERE a.buyer_id = $1 AND ph.object_key IS NOT NULL;

-- name: MarkAlertPhotoPurged :exec
UPDATE pharmacy_alert_photos SET object_key = NULL, purged_at = now() WHERE id = $1;

-- name: AlertStats :one
SELECT count(*)::bigint AS notified,
       count(*) FILTER (WHERE t.seen_at IS NOT NULL OR t.status IN ('responded', 'declined'))::bigint AS seen,
       count(*) FILTER (WHERE t.status = 'responded')::bigint AS responded
FROM pharmacy_alert_targets t WHERE t.alert_id = $1;

-- name: GetAlert :one
SELECT a.id, a.buyer_id, a.kind, a.medicine_name, a.quantity, a.note, a.photo_key, a.photo_purged_at,
       ST_Y(a.location::geometry)::float8 AS lat, ST_X(a.location::geometry)::float8 AS lng,
       a.radius_m, a.status, a.search_ends_at, a.widened_at, a.closed_at, a.unlocked_at, a.created_at, a.updated_at,
       a.generic_accepted, a.relaunched_from, a.number
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

-- name: MarkTargetSeen :exec
UPDATE pharmacy_alert_targets SET seen_at = coalesce(seen_at, now()) WHERE alert_id = $1 AND pharmacy_id = $2;

-- name: ExpirePendingTargets :exec
UPDATE pharmacy_alert_targets SET status = 'expired' WHERE alert_id = $1 AND status = 'pending';

-- name: Inbox :many
-- Alertes adressées à la pharmacie (sans aucune donnée du client).
SELECT t.alert_id, t.distance_m, t.status AS target_status, t.notified_at,
       a.kind, a.medicine_name, a.quantity, a.note, a.photo_key, a.status AS alert_status, a.search_ends_at,
       a.generic_accepted, t.seen_at, a.number,
       -- Position du client : sert seulement à trouver son quartier, jamais renvoyée à la pharmacie.
       ST_Y(a.location::geometry)::float8 AS lat, ST_X(a.location::geometry)::float8 AS lng
FROM pharmacy_alert_targets t
JOIN pharmacy_alerts a ON a.id = t.alert_id
WHERE t.pharmacy_id = sqlc.arg(pharmacy_id)
  AND (NOT sqlc.arg(open_only)::bool OR (t.status IN ('pending', 'responded') AND a.status IN ('searching', 'answered', 'unlocked')))
ORDER BY t.notified_at DESC
LIMIT sqlc.arg(lim) OFFSET sqlc.arg(off);

-- name: InboxItem :one
SELECT t.alert_id, t.distance_m, t.status AS target_status, t.notified_at,
       a.kind, a.medicine_name, a.quantity, a.note, a.photo_key, a.status AS alert_status, a.search_ends_at,
       a.generic_accepted, t.seen_at, a.number,
       -- Position du client : sert seulement à trouver son quartier, jamais renvoyée à la pharmacie.
       ST_Y(a.location::geometry)::float8 AS lat, ST_X(a.location::geometry)::float8 AS lng
FROM pharmacy_alert_targets t
JOIN pharmacy_alerts a ON a.id = t.alert_id
WHERE t.alert_id = $1 AND t.pharmacy_id = $2;

-- ---------------------------------------------------------------- réponses

-- name: UpsertResponse :one
INSERT INTO pharmacy_responses (alert_id, pharmacy_id, product_name, unit_price_xof, quantity_available,
                                prescription_required, note, distance_m, total_xof, available_count, line_count)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
ON CONFLICT (alert_id, pharmacy_id) DO UPDATE SET
  product_name = EXCLUDED.product_name, unit_price_xof = EXCLUDED.unit_price_xof,
  quantity_available = EXCLUDED.quantity_available, prescription_required = EXCLUDED.prescription_required,
  note = EXCLUDED.note, total_xof = EXCLUDED.total_xof, available_count = EXCLUDED.available_count,
  line_count = EXCLUDED.line_count, status = 'active', updated_at = now()
RETURNING *;

-- name: DeleteResponseLines :exec
DELETE FROM pharmacy_response_lines WHERE response_id = $1;

-- name: InsertResponseLine :exec
INSERT INTO pharmacy_response_lines (response_id, position, alert_item_id, name, quantity, unit_price_xof, available, prescription_required)
VALUES (sqlc.arg(response_id), sqlc.arg(position), sqlc.narg(alert_item_id), sqlc.arg(name), sqlc.arg(quantity),
        sqlc.arg(unit_price_xof), sqlc.arg(available), sqlc.arg(prescription_required));

-- name: ListResponseLines :many
SELECT * FROM pharmacy_response_lines WHERE response_id = $1 ORDER BY position;

-- name: MarkResponseUnlocked :execrows
UPDATE pharmacy_responses SET unlocked_at = now(), updated_at = now() WHERE id = $1 AND unlocked_at IS NULL;

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
       r.note, r.distance_m, r.status, r.created_at, r.updated_at, r.total_xof, r.available_count, r.line_count, r.unlocked_at,
       p.name AS pharmacy_name, p.phone AS pharmacy_phone, p.address_text AS pharmacy_address,
       ST_Y(p.location::geometry)::float8 AS pharmacy_lat, ST_X(p.location::geometry)::float8 AS pharmacy_lng,
       p.on_duty AS pharmacy_on_duty, p.open_24h AS pharmacy_open_24h,
       coalesce((SELECT max(s.ends_at) FROM pharmacy_duty_shifts s
         WHERE s.pharmacy_id = p.id AND s.starts_at <= now() AND s.ends_at > now()), 'epoch')::timestamptz AS pharmacy_duty_until
FROM pharmacy_responses r
JOIN pharmacies p ON p.id = r.pharmacy_id
WHERE r.alert_id = $1
ORDER BY r.status = 'withdrawn', r.distance_m, r.created_at;

-- ---------------------------------------------------------------- réservations

-- name: CreateReservation :one
INSERT INTO pharmacy_reservations (alert_id, response_id, pharmacy_id, buyer_id, fulfillment, status, quantity,
  unit_price_xof, items_xof, delivery_fee_xof, commission_xof, total_xof, pharmacy_due_xof, handover_code,
  delivery_address, delivery_location, delivery_instructions, expires_at, unlock_payment_id, prescription_required)
VALUES (sqlc.arg(alert_id), sqlc.arg(response_id), sqlc.arg(pharmacy_id), sqlc.arg(buyer_id), sqlc.arg(fulfillment),
  sqlc.arg(status), sqlc.arg(quantity), sqlc.arg(unit_price_xof), sqlc.arg(items_xof), sqlc.arg(delivery_fee_xof),
  sqlc.arg(commission_xof), sqlc.arg(total_xof), sqlc.arg(pharmacy_due_xof), sqlc.arg(handover_code),
  sqlc.arg(delivery_address),
  CASE WHEN sqlc.arg(has_location)::bool
       THEN ST_SetSRID(ST_MakePoint(sqlc.arg(lng)::float8, sqlc.arg(lat)::float8), 4326)::geography END,
  sqlc.arg(delivery_instructions), sqlc.narg(expires_at), sqlc.narg(unlock_payment_id), sqlc.arg(prescription_required))
RETURNING id;

-- name: GetReservation :one
SELECT r.id, r.alert_id, r.response_id, r.pharmacy_id, r.buyer_id, r.fulfillment, r.status, r.quantity,
       r.unit_price_xof, r.items_xof, r.delivery_fee_xof, r.commission_xof, r.total_xof, r.pharmacy_due_xof,
       r.handover_code, r.delivery_address,
       coalesce(ST_Y(r.delivery_location::geometry), 0)::float8 AS delivery_lat,
       coalesce(ST_X(r.delivery_location::geometry), 0)::float8 AS delivery_lng,
       r.delivery_instructions, r.expires_at, r.cancel_reason, r.completed_at, r.created_at, r.updated_at,
       r.number, r.unlock_payment_id, r.prescription_required, r.paid_at, r.prepared_at
FROM pharmacy_reservations r WHERE r.id = $1;

-- name: LockReservation :one
SELECT status FROM pharmacy_reservations WHERE id = $1 FOR UPDATE;

-- name: ActiveReservationsForAlert :many
SELECT id FROM pharmacy_reservations
WHERE alert_id = $1 AND status IN ('reserved', 'courier_search', 'awaiting_payment', 'paid', 'courier_assigned', 'picked_up')
ORDER BY created_at;

-- name: LatestReservationForResponse :one
SELECT id FROM pharmacy_reservations WHERE response_id = $1 ORDER BY created_at DESC LIMIT 1;

-- name: ChooseDelivery :execrows
UPDATE pharmacy_reservations SET fulfillment = 'delivery', status = 'courier_search',
  delivery_fee_xof = sqlc.arg(delivery_fee_xof), commission_xof = sqlc.arg(commission_xof),
  pharmacy_due_xof = sqlc.arg(pharmacy_due_xof), total_xof = items_xof + sqlc.arg(delivery_fee_xof),
  delivery_address = sqlc.arg(delivery_address), delivery_instructions = sqlc.arg(delivery_instructions),
  delivery_location = ST_SetSRID(ST_MakePoint(sqlc.arg(lng)::float8, sqlc.arg(lat)::float8), 4326)::geography,
  updated_at = now()
WHERE id = sqlc.arg(id) AND status = 'reserved';

-- name: ChoosePickup :execrows
UPDATE pharmacy_reservations SET fulfillment = 'pickup', status = 'reserved', delivery_fee_xof = 0, commission_xof = 0,
  pharmacy_due_xof = 0, total_xof = items_xof, delivery_address = '', delivery_instructions = '', delivery_location = NULL,
  updated_at = now()
WHERE id = $1 AND status IN ('courier_search', 'awaiting_payment');

-- name: MarkPrepared :execrows
UPDATE pharmacy_reservations SET prepared_at = now(), updated_at = now()
WHERE id = $1 AND prepared_at IS NULL
  AND status IN ('reserved', 'courier_search', 'awaiting_payment', 'paid', 'courier_assigned');

-- name: SetReservationStatus :execrows
UPDATE pharmacy_reservations SET status = sqlc.arg(new_status),
  cancel_reason = CASE WHEN sqlc.arg(reason)::text <> '' THEN sqlc.arg(reason)::text ELSE cancel_reason END,
  completed_at = CASE WHEN sqlc.arg(new_status) = 'completed' THEN now() ELSE completed_at END,
  paid_at = CASE WHEN sqlc.arg(new_status) IN ('paid', 'courier_assigned') THEN coalesce(paid_at, now()) ELSE paid_at END,
  updated_at = now()
WHERE id = sqlc.arg(id) AND status = ANY(sqlc.arg(from_statuses)::text[]);

-- name: ListBuyerReservationIDs :many
SELECT id FROM pharmacy_reservations WHERE buyer_id = $1 ORDER BY created_at DESC LIMIT sqlc.arg(lim) OFFSET sqlc.arg(off);

-- name: ListPharmacyReservationIDs :many
SELECT id FROM pharmacy_reservations
WHERE pharmacy_id = sqlc.arg(pharmacy_id)
  AND (NOT sqlc.arg(active_only)::bool OR status IN ('reserved', 'courier_search', 'awaiting_payment', 'paid', 'courier_assigned', 'picked_up'))
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
INSERT INTO pharmacy_payments (purpose, alert_id, reservation_id, response_id, buyer_id, provider, reference, amount_xof, operator, payer_phone)
VALUES (sqlc.arg(purpose), sqlc.arg(alert_id), sqlc.narg(reservation_id), sqlc.narg(response_id), sqlc.arg(buyer_id), sqlc.arg(provider),
        sqlc.arg(reference), sqlc.arg(amount_xof), sqlc.arg(operator), sqlc.arg(payer_phone))
RETURNING *;

-- name: GetPayment :one
SELECT * FROM pharmacy_payments WHERE id = $1;

-- name: GetPaymentByReference :one
SELECT * FROM pharmacy_payments WHERE reference = $1;

-- name: LockPayment :one
SELECT * FROM pharmacy_payments WHERE id = $1 FOR UPDATE;

-- name: PendingUnlockPayment :one
SELECT * FROM pharmacy_payments WHERE response_id = $1 AND purpose = 'unlock' AND status = 'pending';

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

-- name: SetPrescriptionChecked :exec
UPDATE pharmacy_deliveries SET prescription_checked = true, updated_at = now() WHERE id = $1;

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
                                        AND (p3.open_24h OR p3.is_open OR p3.on_duty OR EXISTS (
                                          SELECT 1 FROM pharmacy_duty_shifts s3 WHERE s3.pharmacy_id = p3.id
                                            AND s3.starts_at <= now() AND s3.ends_at > now())))::bigint AS reachable,
  (SELECT count(*) FROM pharmacy_alerts a1 WHERE a1.created_at >= sqlc.arg(from_time) AND a1.created_at < sqlc.arg(to_time))::bigint AS alerts,
  (SELECT count(*) FROM pharmacy_alerts a2 WHERE a2.created_at >= sqlc.arg(from_time) AND a2.created_at < sqlc.arg(to_time)
                                             AND a2.status = 'no_response')::bigint AS alerts_without_response,
  (SELECT count(*) FROM pharmacy_responses u1 WHERE u1.unlocked_at >= sqlc.arg(from_time)
                                               AND u1.unlocked_at < sqlc.arg(to_time))::bigint AS unlocked,
  (SELECT coalesce(sum(y.amount_xof), 0) FROM pharmacy_payments y WHERE y.status = 'succeeded' AND y.purpose = 'unlock'
     AND y.succeeded_at >= sqlc.arg(from_time) AND y.succeeded_at < sqlc.arg(to_time))::bigint AS unlock_revenue_xof,
  (SELECT coalesce(sum(r1.commission_xof), 0) FROM pharmacy_reservations r1 WHERE r1.status = 'completed'
     AND r1.completed_at >= sqlc.arg(from_time) AND r1.completed_at < sqlc.arg(to_time))::bigint AS commission_xof,
  (SELECT count(*) FROM pharmacy_reservations r2 WHERE r2.status = 'completed'
     AND r2.completed_at >= sqlc.arg(from_time) AND r2.completed_at < sqlc.arg(to_time))::bigint AS completed;

-- name: MoveAlertPhotos :exec
-- Relance : les photos encore présentes passent à la nouvelle alerte.
UPDATE pharmacy_alert_photos SET alert_id = sqlc.arg(to_alert)
WHERE alert_id = sqlc.arg(from_alert) AND object_key IS NOT NULL;

-- name: DevUpsertPharmacy :one
-- Démonstration locale uniquement (manage seed-demo) : pharmacie validée, ouverte et de garde.
INSERT INTO pharmacies (owner_id, name, license_number, phone, address_text, location, is_open, on_duty,
                        review_status, reviewed_at)
VALUES (sqlc.arg(owner_id), sqlc.arg(name), sqlc.arg(license_number), sqlc.arg(phone), sqlc.arg(address_text),
        ST_SetSRID(ST_MakePoint(sqlc.arg(lng)::float8, sqlc.arg(lat)::float8), 4326)::geography,
        true, true, 'approved', now())
ON CONFLICT (owner_id) DO UPDATE SET is_open = true, on_duty = true, review_status = 'approved',
  suspended_at = NULL, updated_at = now()
RETURNING id;

-- name: PharmacyDossier :one
SELECT p.submitted_at, p.payout_operator, p.payout_phone, p.payout_holder, p.email,
       coalesce(p.night_from_hour, st.night_from_hour)::int AS night_from,
       coalesce(p.night_to_hour, st.night_to_hour)::int AS night_to
FROM pharmacies p CROSS JOIN pharmacy_settings st
WHERE p.id = $1 AND st.id;

-- name: SetPharmacyPayout :execrows
UPDATE pharmacies SET payout_operator = $2, payout_phone = $3, payout_holder = $4, updated_at = now()
WHERE id = $1 AND review_status IN ('draft', 'changes_requested', 'rejected');

-- name: MarkPharmacySubmitted :exec
UPDATE pharmacies SET review_status = 'pending_review', review_note = '', submitted_at = now(), updated_at = now() WHERE id = $1;

-- name: ClearPharmacyPayout :exec
UPDATE pharmacies SET payout_operator = NULL, payout_phone = NULL, payout_holder = '', updated_at = now() WHERE owner_id = $1;

-- name: DeleteOwnDutyShift :one
DELETE FROM pharmacy_duty_shifts WHERE id = $1 AND pharmacy_id = $2 RETURNING *;

-- name: SetPharmacyEmail :exec
UPDATE pharmacies SET email = $2, updated_at = now() WHERE id = $1;

-- name: ClearPharmacyEmail :exec
UPDATE pharmacies SET email = '', updated_at = now() WHERE owner_id = $1;

-- name: SetPharmacyNightHours :exec
UPDATE pharmacies SET night_from_hour = $2, night_to_hour = $3, updated_at = now() WHERE id = $1;
