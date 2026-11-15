-- Publicité dans les apps (IVI et AWU-IVI d'abord) : visuels publiés par l'admin (affiches,
-- bannières, visuels de bienvenue ou du mois, fenêtres et pages d'interstitiel), réglages de
-- diffusion (fréquence, intervalle, plafond par session, rotation) et événements anonymes
-- (affichage, fermeture, clics) pour les statistiques. Aucune donnée personnelle dans les
-- événements : un identifiant de session tiré au hasard par l'app, sans lien avec le compte.

-- +goose Up
CREATE TABLE promo_visuals (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kind         text NOT NULL CHECK (kind IN ('banner', 'modal', 'interstitial', 'welcome', 'monthly', 'poster')),
  title        text NOT NULL CHECK (length(title) BETWEEN 2 AND 80),
  subtitle     text NOT NULL DEFAULT '' CHECK (length(subtitle) <= 140),
  body         text NOT NULL DEFAULT '' CHECK (length(body) <= 600),
  image_key    text NOT NULL CHECK (length(image_key) BETWEEN 1 AND 300),
  -- Produit commandable depuis le visuel (bouton « Commander maintenant »).
  product_id   uuid REFERENCES products (id) ON DELETE SET NULL,
  cta_label    text NOT NULL DEFAULT '' CHECK (length(cta_label) <= 30),
  -- Lien externe (site officiel) ; https uniquement, vérifié par le service.
  external_url text NOT NULL DEFAULT '' CHECK (length(external_url) <= 300),
  placements   text[] NOT NULL DEFAULT '{}' CHECK (
    placements <@ ARRAY['home_hero', 'home_feed', 'catalog_feed', 'modal', 'interstitial', 'splash']::text[]
  ),
  apps         text[] NOT NULL DEFAULT '{buyer}' CHECK (
    cardinality(apps) >= 1 AND apps <@ ARRAY['buyer', 'seller', 'driver']::text[]
  ),
  priority     integer NOT NULL DEFAULT 0 CHECK (priority BETWEEN 0 AND 100),
  weight       integer NOT NULL DEFAULT 1 CHECK (weight BETWEEN 1 AND 100),
  starts_at    timestamptz,
  ends_at      timestamptz,
  is_active    boolean NOT NULL DEFAULT true,
  created_by   uuid REFERENCES users (id),
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now(),
  CHECK (starts_at IS NULL OR ends_at IS NULL OR ends_at > starts_at)
);
CREATE INDEX promo_visuals_active_idx ON promo_visuals (priority DESC, created_at DESC) WHERE is_active;

-- Une seule ligne de réglages.
CREATE TABLE promo_settings (
  id                   boolean PRIMARY KEY DEFAULT true CHECK (id),
  enabled              boolean NOT NULL DEFAULT true,
  banners_enabled      boolean NOT NULL DEFAULT true,
  modal_enabled        boolean NOT NULL DEFAULT true,
  interstitial_enabled boolean NOT NULL DEFAULT true,
  -- Délai avant la première fenêtre, intervalle minimal entre deux, plafond par session.
  first_delay_seconds  integer NOT NULL DEFAULT 20 CHECK (first_delay_seconds BETWEEN 0 AND 600),
  min_interval_seconds integer NOT NULL DEFAULT 90 CHECK (min_interval_seconds BETWEEN 15 AND 3600),
  max_per_session      integer NOT NULL DEFAULT 5 CHECK (max_per_session BETWEEN 0 AND 50),
  -- Un produit mis en avant revient toutes les feed_every cartes dans les listes.
  feed_every           integer NOT NULL DEFAULT 6 CHECK (feed_every BETWEEN 3 AND 50),
  rotation             text NOT NULL DEFAULT 'weighted' CHECK (rotation IN ('weighted', 'random', 'priority')),
  official_url         text NOT NULL DEFAULT '' CHECK (length(official_url) <= 300),
  updated_by           uuid REFERENCES users (id),
  updated_at           timestamptz NOT NULL DEFAULT now()
);
INSERT INTO promo_settings (official_url) VALUES ('https://www.eaumineraleivi.com');

CREATE TABLE promo_events (
  id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  kind       text NOT NULL CHECK (kind IN ('impression', 'dismiss', 'click_order', 'click_product', 'click_site', 'order')),
  visual_id  uuid REFERENCES promo_visuals (id) ON DELETE SET NULL,
  product_id uuid REFERENCES products (id) ON DELETE SET NULL,
  placement  text NOT NULL DEFAULT '' CHECK (length(placement) <= 30),
  app        text NOT NULL CHECK (app IN ('buyer', 'seller', 'driver')),
  session_id text NOT NULL CHECK (length(session_id) BETWEEN 8 AND 64),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX promo_events_created_idx ON promo_events (created_at);
CREATE INDEX promo_events_visual_idx ON promo_events (visual_id, created_at) WHERE visual_id IS NOT NULL;
CREATE INDEX promo_events_product_idx ON promo_events (product_id, created_at) WHERE product_id IS NOT NULL;

-- +goose Down
DROP TABLE promo_events;
DROP TABLE promo_settings;
DROP TABLE promo_visuals;
