-- ---------------------------------------------------------------- livreurs

-- name: CreateDriver :exec
INSERT INTO drivers (user_id, vehicle_type, vehicle_plate, vehicle_description)
VALUES ($1, $2, $3, $4);

-- name: UpdateApplication :execrows
-- Une candidature refusée ou en attente peut être corrigée : elle repasse en attente de validation.
UPDATE drivers
SET vehicle_type = $2, vehicle_plate = $3, vehicle_description = $4,
    review_status = 'pending_review', review_note = '', updated_at = now()
WHERE user_id = $1 AND review_status IN ('pending_review', 'rejected');

-- name: GetDriver :one
SELECT d.user_id, d.review_status, d.review_note, d.reviewed_at, d.suspended_at, d.suspension_reason,
       d.availability, d.vehicle_type, d.vehicle_plate, d.vehicle_description, d.last_location_at,
       d.created_at, d.updated_at
FROM drivers d WHERE d.user_id = $1;

-- name: LockDriver :one
SELECT availability FROM drivers WHERE user_id = $1 FOR UPDATE;

-- name: ListDrivers :many
SELECT d.user_id, d.review_status, d.review_note, d.reviewed_at, d.suspended_at, d.suspension_reason,
       d.availability, d.vehicle_type, d.vehicle_plate, d.vehicle_description, d.last_location_at,
       d.created_at, d.updated_at
FROM drivers d
WHERE (sqlc.narg(review_status)::text IS NULL OR d.review_status = sqlc.narg(review_status)::text)
  AND (NOT sqlc.arg(suspended_only)::boolean OR d.suspended_at IS NOT NULL)
ORDER BY d.created_at DESC
LIMIT sqlc.arg(lim) OFFSET sqlc.arg(off);

-- name: SetReview :execrows
UPDATE drivers
SET review_status = sqlc.arg(review_status), review_note = sqlc.arg(note),
    reviewed_at = now(), reviewed_by = sqlc.arg(reviewed_by), updated_at = now()
WHERE user_id = sqlc.arg(user_id) AND review_status = ANY(sqlc.arg(from_statuses)::text[]);

-- name: Suspend :execrows
UPDATE drivers
SET suspended_at = now(), suspension_reason = sqlc.arg(reason), availability = 'offline', updated_at = now()
WHERE user_id = sqlc.arg(user_id) AND suspended_at IS NULL;

-- name: Reinstate :execrows
UPDATE drivers SET suspended_at = NULL, suspension_reason = '', updated_at = now()
WHERE user_id = $1 AND suspended_at IS NOT NULL;

-- name: SetAvailability :exec
UPDATE drivers SET availability = $2, updated_at = now() WHERE user_id = $1;

-- name: UpdateLocation :exec
UPDATE drivers
SET last_location = ST_SetSRID(ST_MakePoint(sqlc.arg(lng)::float8, sqlc.arg(lat)::float8), 4326)::geography,
    last_location_at = sqlc.arg(recorded_at)::timestamptz, updated_at = now()
WHERE user_id = sqlc.arg(user_id);

-- name: InsertPosition :exec
INSERT INTO driver_positions (driver_id, location, accuracy_m, recorded_at)
VALUES (sqlc.arg(driver_id), ST_SetSRID(ST_MakePoint(sqlc.arg(lng)::float8, sqlc.arg(lat)::float8), 4326)::geography,
        sqlc.narg(accuracy_m), sqlc.arg(recorded_at));

-- name: PurgePositions :execrows
DELETE FROM driver_positions WHERE created_at < now() - interval '30 days';

-- name: DeletePositionsOf :exec
DELETE FROM driver_positions WHERE driver_id = $1;

-- name: ForgetLocation :exec
UPDATE drivers SET last_location = NULL, last_location_at = NULL, availability = 'offline', updated_at = now()
WHERE user_id = $1;

-- name: InsertDocument :one
INSERT INTO driver_documents (driver_id, kind, object_key) VALUES ($1, $2, $3) RETURNING *;

-- name: ListDocuments :many
SELECT * FROM driver_documents WHERE driver_id = $1 ORDER BY created_at;

-- name: CountDocuments :one
SELECT count(*) FROM driver_documents WHERE driver_id = $1;

-- name: DeleteDocumentsOf :exec
DELETE FROM driver_documents WHERE driver_id = $1;

-- ---------------------------------------------------------------- attribution

-- name: StartAssignment :one
-- Démarre (ou rouvre après un désistement) la recherche d'un livreur pour une commande.
INSERT INTO assignment_requests (order_id) VALUES ($1)
ON CONFLICT (order_id) DO UPDATE SET closed_at = NULL
RETURNING *;

-- name: LockAssignment :one
SELECT * FROM assignment_requests WHERE order_id = $1 FOR UPDATE;

-- name: IncrementOffers :exec
UPDATE assignment_requests SET offers_count = offers_count + 1 WHERE order_id = $1;

-- name: MarkAlerted :exec
UPDATE assignment_requests SET alerted_at = now() WHERE order_id = $1 AND alerted_at IS NULL;

-- name: CloseAssignment :exec
UPDATE assignment_requests SET closed_at = now() WHERE order_id = $1 AND closed_at IS NULL;

-- name: ListAlerts :many
SELECT * FROM assignment_requests
WHERE alerted_at IS NOT NULL AND closed_at IS NULL
ORDER BY alerted_at;

-- name: FindNearestDriver :one
-- Livreur disponible le plus proche de la boutique : validé, non suspendu, bon véhicule, position
-- de moins de 2 minutes, sans mission ni proposition en cours, jamais sollicité pour cette commande.
-- SKIP LOCKED : deux attributions simultanées ne choisissent pas le même livreur.
SELECT d.user_id,
       ST_Distance(d.last_location, ST_SetSRID(ST_MakePoint(sqlc.arg(lng)::float8, sqlc.arg(lat)::float8), 4326)::geography)::float8 AS distance_m
FROM drivers d
WHERE d.review_status = 'approved'
  AND d.suspended_at IS NULL
  AND d.availability = 'available'
  AND d.vehicle_type = sqlc.arg(vehicle_type)
  AND d.last_location_at > now() - interval '2 minutes'
  AND ST_DWithin(d.last_location, ST_SetSRID(ST_MakePoint(sqlc.arg(lng)::float8, sqlc.arg(lat)::float8), 4326)::geography, sqlc.arg(max_distance_m)::float8)
  AND NOT EXISTS (SELECT 1 FROM delivery_offers o WHERE o.order_id = sqlc.arg(order_id) AND o.driver_id = d.user_id)
  AND NOT EXISTS (SELECT 1 FROM delivery_offers o WHERE o.driver_id = d.user_id AND o.status = 'pending')
  AND NOT EXISTS (SELECT 1 FROM deliveries x WHERE x.driver_id = d.user_id
                  AND x.status IN ('assigned', 'at_shop', 'picked_up', 'at_customer', 'returning'))
ORDER BY distance_m
LIMIT 1
FOR UPDATE OF d SKIP LOCKED;

-- name: CreateOffer :one
INSERT INTO delivery_offers (order_id, driver_id, distance_to_shop_m, expires_at)
VALUES ($1, $2, $3, $4)
RETURNING *;

-- name: GetOffer :one
SELECT * FROM delivery_offers WHERE id = $1;

-- name: LockOffer :one
SELECT * FROM delivery_offers WHERE id = $1 FOR UPDATE;

-- name: PendingOfferForOrder :one
SELECT * FROM delivery_offers WHERE order_id = $1 AND status = 'pending';

-- name: PendingOfferForDriver :one
SELECT * FROM delivery_offers WHERE driver_id = $1 AND status = 'pending';

-- name: RespondOffer :execrows
UPDATE delivery_offers SET status = sqlc.arg(new_status), responded_at = now()
WHERE id = sqlc.arg(id) AND status = 'pending';

-- name: ExpireOffer :execrows
UPDATE delivery_offers SET status = 'expired', responded_at = now()
WHERE id = $1 AND status = 'pending' AND expires_at <= now();

-- name: CancelPendingOffersForOrder :exec
UPDATE delivery_offers SET status = 'cancelled', responded_at = now()
WHERE order_id = $1 AND status = 'pending';

-- name: CancelPendingOffersForDriver :exec
UPDATE delivery_offers SET status = 'cancelled', responded_at = now()
WHERE driver_id = $1 AND status = 'pending';

-- ---------------------------------------------------------------- missions

-- name: CreateDelivery :one
INSERT INTO deliveries (order_id, driver_id, offer_id, fee_xof)
VALUES ($1, $2, $3, $4)
RETURNING *;

-- name: GetDelivery :one
SELECT * FROM deliveries WHERE id = $1;

-- name: LockDelivery :one
SELECT * FROM deliveries WHERE id = $1 FOR UPDATE;

-- name: ActiveDeliveryForDriver :one
SELECT * FROM deliveries
WHERE driver_id = $1 AND status IN ('assigned', 'at_shop', 'picked_up', 'at_customer', 'returning');

-- name: ActiveDeliveryForOrder :one
SELECT * FROM deliveries
WHERE order_id = $1 AND status IN ('assigned', 'at_shop', 'picked_up', 'at_customer', 'returning');

-- name: LatestDeliveryForOrder :one
SELECT * FROM deliveries WHERE order_id = $1 ORDER BY created_at DESC LIMIT 1;

-- name: SetDeliveryStatus :execrows
UPDATE deliveries
SET status              = sqlc.arg(new_status),
    arrived_shop_at     = CASE WHEN sqlc.arg(new_status) = 'at_shop' THEN now() ELSE arrived_shop_at END,
    picked_up_at        = CASE WHEN sqlc.arg(new_status) = 'picked_up' THEN now() ELSE picked_up_at END,
    arrived_customer_at = CASE WHEN sqlc.arg(new_status) = 'at_customer' THEN now() ELSE arrived_customer_at END,
    delivered_at        = CASE WHEN sqlc.arg(new_status) = 'delivered' THEN now() ELSE delivered_at END,
    failed_at           = CASE WHEN sqlc.arg(new_status) = 'returning' THEN now() ELSE failed_at END,
    failure_reason      = CASE WHEN sqlc.arg(new_status) = 'returning' THEN sqlc.arg(failure_reason) ELSE failure_reason END,
    call_attempts       = greatest(call_attempts, sqlc.arg(call_attempts)::integer),
    ended_at            = CASE WHEN sqlc.arg(new_status) IN ('delivered', 'returned', 'withdrawn', 'cancelled') THEN now() ELSE ended_at END,
    updated_at          = now()
WHERE id = sqlc.arg(id) AND status = ANY(sqlc.arg(from_statuses)::text[]);

-- name: ListDriverDeliveries :many
SELECT * FROM deliveries WHERE driver_id = $1
ORDER BY created_at DESC
LIMIT sqlc.arg(lim) OFFSET sqlc.arg(off);

-- name: ExportDeliveries :many
-- Missions par livreur sur une période (base de la paie, faite hors application).
SELECT d.driver_id,
       count(*) FILTER (WHERE d.status = 'delivered')::bigint AS delivered,
       count(*) FILTER (WHERE d.status IN ('returning', 'returned'))::bigint AS failed,
       count(*) FILTER (WHERE d.status = 'withdrawn')::bigint AS withdrawn,
       coalesce(sum(d.fee_xof) FILTER (WHERE d.status = 'delivered'), 0)::bigint AS delivered_fees_xof
FROM deliveries d
WHERE d.assigned_at >= sqlc.arg(from_time)::timestamptz AND d.assigned_at < sqlc.arg(to_time)::timestamptz
GROUP BY d.driver_id
ORDER BY delivered DESC;

-- name: AssignmentMetrics :one
SELECT
  count(*)::bigint AS assigned,
  count(*) FILTER (WHERE x.assigned_at - a.started_at <= interval '10 minutes')::bigint AS assigned_within_10_min,
  coalesce(percentile_cont(0.5) WITHIN GROUP (ORDER BY extract(epoch FROM x.assigned_at - a.started_at)), 0)::float8 AS median_assignment_s
FROM deliveries x
JOIN assignment_requests a ON a.order_id = x.order_id
WHERE x.assigned_at >= sqlc.arg(from_time)::timestamptz AND x.assigned_at < sqlc.arg(to_time)::timestamptz;

-- name: DriverDocumentKeysIn :many
-- Clés rattachées parmi celles données (purge des fichiers jamais rattachés).
SELECT object_key FROM driver_documents WHERE object_key = ANY(sqlc.arg(keys)::text[]);

-- name: DriverOverview :one
-- Livreurs maintenant (tableau de bord) : validés et non suspendus par disponibilité, suspendus,
-- dossiers à valider.
SELECT
  count(*) FILTER (WHERE review_status = 'approved' AND suspended_at IS NULL AND availability = 'available')::bigint AS available,
  count(*) FILTER (WHERE review_status = 'approved' AND suspended_at IS NULL AND availability = 'busy')::bigint AS busy,
  count(*) FILTER (WHERE review_status = 'approved' AND suspended_at IS NULL AND availability = 'offline')::bigint AS offline,
  count(*) FILTER (WHERE suspended_at IS NOT NULL)::bigint AS suspended,
  count(*) FILTER (WHERE review_status = 'pending_review' AND suspended_at IS NULL)::bigint AS pending_review
FROM drivers;

-- ---------------------------------------------------------------- courses des autres modules

-- name: FindErrandDriver :one
-- Livreur disponible le plus proche d'un point de retrait (course pharmacie) : mêmes conditions
-- que FindNearestDriver, hors livreurs déjà sollicités pour cette course (exclude).
SELECT d.user_id,
       ST_Distance(d.last_location, ST_SetSRID(ST_MakePoint(sqlc.arg(lng)::float8, sqlc.arg(lat)::float8), 4326)::geography)::float8 AS distance_m
FROM drivers d
WHERE d.review_status = 'approved'
  AND d.suspended_at IS NULL
  AND d.availability = 'available'
  AND d.vehicle_type = 'motorbike'
  AND d.last_location_at > now() - interval '2 minutes'
  AND ST_DWithin(d.last_location, ST_SetSRID(ST_MakePoint(sqlc.arg(lng)::float8, sqlc.arg(lat)::float8), 4326)::geography, sqlc.arg(max_distance_m)::float8)
  AND NOT (d.user_id = ANY(sqlc.arg(exclude)::uuid[]))
  AND NOT EXISTS (SELECT 1 FROM delivery_offers o WHERE o.driver_id = d.user_id AND o.status = 'pending')
  AND NOT EXISTS (SELECT 1 FROM deliveries x WHERE x.driver_id = d.user_id
                  AND x.status IN ('assigned', 'at_shop', 'picked_up', 'at_customer', 'returning'))
ORDER BY distance_m
LIMIT 1
FOR UPDATE OF d SKIP LOCKED;

-- name: HasPendingOfferOrActiveDelivery :one
SELECT (EXISTS (SELECT 1 FROM delivery_offers o WHERE o.driver_id = $1 AND o.status = 'pending')
     OR EXISTS (SELECT 1 FROM deliveries x WHERE x.driver_id = $1
                AND x.status IN ('assigned', 'at_shop', 'picked_up', 'at_customer', 'returning')))::bool AS busy;

-- name: ReleaseBusyDriver :exec
UPDATE drivers SET availability = 'available', updated_at = now()
WHERE user_id = $1 AND availability = 'busy';

-- name: DriverLastLocation :one
-- Dernière position connue d'un livreur (arrivée estimée chez la pharmacie).
SELECT ST_Y(last_location::geometry)::float8 AS lat, ST_X(last_location::geometry)::float8 AS lng,
       last_location_at::timestamptz AS recorded_at, vehicle_type
FROM drivers
WHERE user_id = $1 AND last_location IS NOT NULL AND last_location_at IS NOT NULL;
