-- Ivia Business : un compte peut ouvrir plusieurs espaces, un par activité (boutique, agence
-- immobilière, artisan, restaurant). Chaque espace a son dossier, ses justificatifs et son compte
-- de versement, et passe par la validation du back-office. Migration additive.

-- +goose Up
CREATE TABLE business_spaces (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id        uuid NOT NULL REFERENCES users (id),
  sector          text NOT NULL CHECK (sector IN ('shop', 'real_estate', 'artisan', 'restaurant')),
  name            text NOT NULL CHECK (length(name) BETWEEN 2 AND 120),
  -- Champs propres au secteur (catégorie, RCCM, métiers, cuisine, horaires, position, photos).
  details         jsonb NOT NULL DEFAULT '{}',
  -- Boutique et restaurant : le catalogue et les commandes reposent sur une boutique.
  shop_id         uuid UNIQUE REFERENCES shops (id),
  status          text NOT NULL DEFAULT 'draft'
                  CHECK (status IN ('draft', 'pending_review', 'needs_changes', 'rejected', 'approved', 'suspended')),
  status_reason   text NOT NULL DEFAULT '',
  payout_operator text CHECK (payout_operator IN ('flooz', 'tmoney')),
  payout_phone    text CHECK (payout_phone ~ '^\+228[0-9]{8}$'),
  payout_holder   text NOT NULL DEFAULT '',
  submitted_at    timestamptz,
  reviewed_at     timestamptz,
  reviewed_by     uuid REFERENCES users (id),
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX business_spaces_owner_idx ON business_spaces (owner_id);
CREATE INDEX business_spaces_status_idx ON business_spaces (status, created_at);

-- Justificatifs : stockage privé, une pièce par nature.
CREATE TABLE business_documents (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  space_id   uuid NOT NULL REFERENCES business_spaces (id) ON DELETE CASCADE,
  kind       text NOT NULL CHECK (kind IN ('id_card', 'selfie', 'rccm', 'business_registration', 'trade_proof', 'hygiene_certificate')),
  object_key text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (space_id, kind)
);

-- Biens et services préparés par une agence ou un artisan (invisibles avant la validation).
CREATE TABLE business_items (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  space_id    uuid NOT NULL REFERENCES business_spaces (id) ON DELETE CASCADE,
  title       text NOT NULL CHECK (length(title) BETWEEN 2 AND 120),
  description text NOT NULL DEFAULT '' CHECK (length(description) <= 2000),
  price_xof   bigint NOT NULL DEFAULT 0 CHECK (price_xof >= 0),
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX business_items_space_idx ON business_items (space_id, created_at);

-- Code PIN du compte : confirme le changement du compte de versement et les retraits.
CREATE TABLE business_pins (
  user_id         uuid PRIMARY KEY REFERENCES users (id) ON DELETE CASCADE,
  pin_hash        text NOT NULL,
  failed_attempts integer NOT NULL DEFAULT 0,
  locked_until    timestamptz,
  updated_at      timestamptz NOT NULL DEFAULT now()
);

-- Espace ouvert par une session : l'accès en découle, selon le statut de l'espace.
CREATE TABLE business_sessions (
  session_id uuid PRIMARY KEY REFERENCES sessions (id) ON DELETE CASCADE,
  space_id   uuid NOT NULL REFERENCES business_spaces (id) ON DELETE CASCADE,
  opened_at  timestamptz NOT NULL DEFAULT now()
);

-- Chaque boutique existante devient un espace, avec le statut qu'elle a déjà.
INSERT INTO business_spaces (owner_id, sector, name, shop_id, status, status_reason, submitted_at, reviewed_at, created_at)
SELECT s.owner_id,
       CASE WHEN c.name = 'Restauration' THEN 'restaurant' ELSE 'shop' END,
       s.name, s.id,
       CASE s.status WHEN 'published' THEN 'approved' WHEN 'pending_review' THEN 'pending_review'
                     WHEN 'rejected' THEN 'rejected' ELSE 'suspended' END,
       s.status_reason, s.created_at, s.reviewed_at, s.created_at
FROM shops s LEFT JOIN shop_categories c ON c.id = s.category_id;

-- +goose Down
DROP TABLE business_sessions;
DROP TABLE business_pins;
DROP TABLE business_items;
DROP TABLE business_documents;
DROP TABLE business_spaces;
