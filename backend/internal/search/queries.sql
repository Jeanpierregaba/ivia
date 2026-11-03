-- name: SearchProducts :many
-- Pertinence : plein texte (français, sans accents) + début du dernier mot (recherche pendant la
-- frappe : « pag » trouve « pagne ») + similarité trigramme (fautes de frappe). tsprefix est
-- construit par le service (lettres et chiffres seulement, « mot1 & mot2:* »), jamais par l'app.
-- distance_m vaut -1 sans position ; main_image_key vaut '' sans photo.
SELECT t.id, t.shop_id, t.name, t.price_xof, t.parcel_size, t.shop_name, t.neighborhood_id,
       coalesce(t.main_image_key, '')::text AS main_image_key,
       coalesce(t.in_stock, false)::boolean AS in_stock,
       coalesce(t.distance_m, -1)::float8 AS distance_m
FROM (
  SELECT sp.*,
         CASE WHEN sqlc.narg(lat)::float8 IS NULL THEN NULL
              ELSE ST_Distance(sp.location, ST_SetSRID(ST_MakePoint(sqlc.narg(lng)::float8, sqlc.narg(lat)::float8), 4326)::geography)
         END::float8 AS distance_m,
         CASE WHEN sqlc.narg(q)::text IS NULL THEN 0
              ELSE ts_rank(sp.search_vector, websearch_to_tsquery('french', immutable_unaccent(sqlc.narg(q)::text)))
                   + coalesce(ts_rank(sp.search_vector, to_tsquery('french', immutable_unaccent(sqlc.narg(tsprefix)::text))), 0)
                   + similarity(immutable_unaccent(lower(sp.name)), immutable_unaccent(lower(sqlc.narg(q)::text)))
         END::float8 AS score
  FROM search_products sp
  WHERE (sqlc.narg(q)::text IS NULL
         OR sp.search_vector @@ websearch_to_tsquery('french', immutable_unaccent(sqlc.narg(q)::text))
         OR (sqlc.narg(tsprefix)::text IS NOT NULL
             AND sp.search_vector @@ to_tsquery('french', immutable_unaccent(sqlc.narg(tsprefix)::text)))
         OR immutable_unaccent(lower(sp.name)) % immutable_unaccent(lower(sqlc.narg(q)::text)))
    AND (sqlc.narg(category_id)::uuid IS NULL
         OR sp.category_id = sqlc.narg(category_id)::uuid OR sp.category_parent_id = sqlc.narg(category_id)::uuid)
    AND (sqlc.narg(shop_id)::uuid IS NULL OR sp.shop_id = sqlc.narg(shop_id)::uuid)
    AND (sqlc.narg(shop_category_id)::uuid IS NULL OR sp.shop_category_id = sqlc.narg(shop_category_id)::uuid)
    AND (sqlc.narg(min_price)::bigint IS NULL OR sp.price_xof >= sqlc.narg(min_price)::bigint)
    AND (sqlc.narg(max_price)::bigint IS NULL OR sp.price_xof <= sqlc.narg(max_price)::bigint)
    AND (sqlc.narg(neighborhood_id)::uuid IS NULL OR sp.neighborhood_id = sqlc.narg(neighborhood_id)::uuid)
    AND (sqlc.narg(radius_m)::float8 IS NULL
         OR ST_DWithin(sp.location, ST_SetSRID(ST_MakePoint(sqlc.narg(lng)::float8, sqlc.narg(lat)::float8), 4326)::geography, sqlc.narg(radius_m)::float8))
    AND (NOT sqlc.arg(in_stock_only)::boolean OR sp.in_stock)
) t
ORDER BY
  CASE WHEN sqlc.arg(sort)::text = 'distance' THEN t.distance_m END ASC NULLS LAST,
  CASE WHEN sqlc.arg(sort)::text = 'price_asc' THEN t.price_xof END ASC,
  CASE WHEN sqlc.arg(sort)::text = 'price_desc' THEN t.price_xof END DESC,
  t.score DESC,
  t.created_at DESC,
  t.id
LIMIT sqlc.arg(lim) OFFSET sqlc.arg(off);

-- name: SearchShops :many
SELECT t.id, t.name, t.description, t.neighborhood_id, t.logo_key, t.accepting_orders,
       t.category_id, coalesce(t.category_name, '')::text AS category_name,
       coalesce(t.distance_m, -1)::float8 AS distance_m
FROM (
  SELECT ss.*,
         CASE WHEN sqlc.narg(lat)::float8 IS NULL THEN NULL
              ELSE ST_Distance(ss.location, ST_SetSRID(ST_MakePoint(sqlc.narg(lng)::float8, sqlc.narg(lat)::float8), 4326)::geography)
         END::float8 AS distance_m,
         CASE WHEN sqlc.narg(q)::text IS NULL THEN 0
              ELSE similarity(immutable_unaccent(lower(ss.name)), immutable_unaccent(lower(sqlc.narg(q)::text)))
         END::float8 AS score
  FROM search_shops ss
  WHERE (sqlc.narg(q)::text IS NULL
         OR immutable_unaccent(lower(ss.name)) % immutable_unaccent(lower(sqlc.narg(q)::text))
         -- q_like : texte de l'app avec \, % et _ échappés (sinon « % » trouverait toutes les boutiques).
         OR immutable_unaccent(lower(ss.name)) LIKE '%' || immutable_unaccent(lower(sqlc.narg(q_like)::text)) || '%' ESCAPE '\')
    AND (sqlc.narg(neighborhood_id)::uuid IS NULL OR ss.neighborhood_id = sqlc.narg(neighborhood_id)::uuid)
    AND (sqlc.narg(shop_category_id)::uuid IS NULL OR ss.category_id = sqlc.narg(shop_category_id)::uuid)
    AND (sqlc.narg(radius_m)::float8 IS NULL
         OR ST_DWithin(ss.location, ST_SetSRID(ST_MakePoint(sqlc.narg(lng)::float8, sqlc.narg(lat)::float8), 4326)::geography, sqlc.narg(radius_m)::float8))
) t
ORDER BY
  CASE WHEN sqlc.arg(sort)::text = 'distance' THEN t.distance_m END ASC NULLS LAST,
  t.score DESC,
  t.created_at DESC,
  t.id
LIMIT sqlc.arg(lim) OFFSET sqlc.arg(off);
