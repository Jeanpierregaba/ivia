-- Codes promo (spec 034) : codes des boutiques (à leurs frais), codes de la boutique officielle IVI
-- gérés au back-office et coupon de bienvenue offert par ivia. Une réduction porte sur les
-- produits ; un seul code par commande.

-- +goose Up
CREATE TABLE promo_codes (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code              text NOT NULL UNIQUE CHECK (code ~ '^[A-Z0-9-]{3,24}$'),
  -- NULL : coupon de la plateforme (bienvenue), utilisable dans toutes les boutiques.
  shop_id           uuid REFERENCES shops (id),
  funded_by         text NOT NULL CHECK (funded_by IN ('shop', 'ivia')),
  kind              text NOT NULL CHECK (kind IN ('percent', 'fixed')),
  value             integer NOT NULL CHECK (value > 0),
  max_discount_xof  bigint CHECK (max_discount_xof > 0),
  min_order_xof     bigint NOT NULL DEFAULT 0 CHECK (min_order_xof >= 0),
  starts_at         timestamptz NOT NULL DEFAULT now(),
  ends_at           timestamptz,
  max_uses          integer CHECK (max_uses > 0),
  max_uses_per_user integer NOT NULL DEFAULT 1 CHECK (max_uses_per_user > 0),
  visibility        text NOT NULL DEFAULT 'public' CHECK (visibility IN ('public', 'private')),
  -- Coupon réservé à un compte (bienvenue) : invisible et inutilisable pour les autres.
  reserved_for      uuid REFERENCES users (id),
  welcome           boolean NOT NULL DEFAULT false,
  status            text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'suspended', 'ended')),
  suspension_reason text NOT NULL DEFAULT '' CHECK (length(suspension_reason) <= 300),
  uses_count        integer NOT NULL DEFAULT 0 CHECK (uses_count >= 0),
  created_by        uuid REFERENCES users (id),
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  CHECK (kind <> 'percent' OR value <= 90),
  CHECK (ends_at IS NULL OR ends_at > starts_at),
  -- Garantie de concurrence : jamais plus d'utilisations (réservées comprises) que permis.
  CHECK (max_uses IS NULL OR uses_count <= max_uses),
  CHECK ((shop_id IS NULL) = (funded_by = 'ivia' AND welcome))
);
CREATE INDEX promo_codes_shop_idx ON promo_codes (shop_id, created_at DESC);
CREATE UNIQUE INDEX promo_codes_one_welcome_per_user ON promo_codes (reserved_for) WHERE welcome;

-- Utilisation d'un code par une commande : réservée à la création, confirmée au paiement,
-- libérée si la commande expire ou est annulée avant paiement.
CREATE TABLE promo_redemptions (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code_id      uuid NOT NULL REFERENCES promo_codes (id),
  order_id     uuid NOT NULL UNIQUE REFERENCES orders (id),
  user_id      uuid NOT NULL REFERENCES users (id),
  discount_xof bigint NOT NULL CHECK (discount_xof > 0),
  status       text NOT NULL DEFAULT 'reserved' CHECK (status IN ('reserved', 'used', 'released')),
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX promo_redemptions_user_idx ON promo_redemptions (code_id, user_id) WHERE status <> 'released';

-- Réglages du coupon de bienvenue (désactivé tant qu'il n'est pas réglé).
CREATE TABLE coupon_settings (
  id                    boolean PRIMARY KEY DEFAULT true CHECK (id),
  welcome_enabled       boolean NOT NULL DEFAULT false,
  welcome_amount_xof    bigint NOT NULL DEFAULT 0 CHECK (welcome_amount_xof >= 0),
  welcome_min_order_xof bigint NOT NULL DEFAULT 0 CHECK (welcome_min_order_xof >= 0),
  welcome_valid_days    integer NOT NULL DEFAULT 30 CHECK (welcome_valid_days BETWEEN 1 AND 365),
  updated_at            timestamptz NOT NULL DEFAULT now(),
  updated_by            uuid REFERENCES users (id)
);
INSERT INTO coupon_settings DEFAULT VALUES;

-- Réduction portée par la commande ; le total payé la retire.
ALTER TABLE orders
  ADD COLUMN promo_code_id      uuid REFERENCES promo_codes (id),
  ADD COLUMN promo_code         text,
  ADD COLUMN discount_xof       bigint NOT NULL DEFAULT 0 CHECK (discount_xof >= 0),
  ADD COLUMN discount_funded_by text CHECK (discount_funded_by IN ('shop', 'ivia'));
ALTER TABLE orders DROP CONSTRAINT orders_check;
ALTER TABLE orders ADD CONSTRAINT orders_total_check
  CHECK (total_xof = subtotal_xof + delivery_fee_xof - discount_xof);
ALTER TABLE orders ADD CONSTRAINT orders_discount_check
  CHECK (discount_xof <= subtotal_xof AND (discount_xof = 0) = (promo_code_id IS NULL));

-- +goose Down
ALTER TABLE orders DROP CONSTRAINT orders_discount_check;
ALTER TABLE orders DROP CONSTRAINT orders_total_check;
ALTER TABLE orders ADD CONSTRAINT orders_check CHECK (total_xof = subtotal_xof + delivery_fee_xof);
ALTER TABLE orders
  DROP COLUMN discount_funded_by, DROP COLUMN discount_xof, DROP COLUMN promo_code, DROP COLUMN promo_code_id;
DROP TABLE coupon_settings;
DROP TABLE promo_redemptions;
DROP TABLE promo_codes;
