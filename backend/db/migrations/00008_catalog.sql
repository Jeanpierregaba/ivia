-- Module catalog : catégories, produits, photos.

-- +goose Up
CREATE TABLE categories (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name       text NOT NULL UNIQUE CHECK (length(name) BETWEEN 1 AND 100),
  parent_id  uuid REFERENCES categories (id),
  position   integer NOT NULL DEFAULT 0,
  is_active  boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (parent_id IS DISTINCT FROM id)
);

CREATE TABLE products (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  shop_id       uuid NOT NULL REFERENCES shops (id),
  category_id   uuid NOT NULL REFERENCES categories (id),
  name          text NOT NULL CHECK (length(name) BETWEEN 2 AND 150),
  description   text NOT NULL DEFAULT '' CHECK (length(description) <= 5000),
  price_xof     bigint NOT NULL CHECK (price_xof > 0 AND price_xof <= 100000000),
  parcel_size   text NOT NULL CHECK (parcel_size IN ('small', 'medium', 'large')),
  stock_mode    text NOT NULL CHECK (stock_mode IN ('tracked', 'untracked')),
  is_active     boolean NOT NULL DEFAULT true,
  -- Recherche plein texte : français, sans accents, le nom pèse plus que la description.
  search_vector tsvector GENERATED ALWAYS AS (
    setweight(to_tsvector('french', immutable_unaccent(name)), 'A') ||
    setweight(to_tsvector('french', immutable_unaccent(description)), 'B')
  ) STORED,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX products_shop_id_idx ON products (shop_id, created_at DESC);
CREATE INDEX products_category_id_idx ON products (category_id);
CREATE INDEX products_price_idx ON products (price_xof);
CREATE INDEX products_search_idx ON products USING gin (search_vector);
CREATE INDEX products_name_trgm_idx ON products USING gin (immutable_unaccent(lower(name)) gin_trgm_ops);

CREATE TABLE product_images (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id uuid NOT NULL REFERENCES products (id) ON DELETE CASCADE,
  object_key text NOT NULL,
  -- 0 = photo principale.
  position   integer NOT NULL CHECK (position BETWEEN 0 AND 9),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (product_id, position)
);

-- +goose Down
DROP TABLE product_images;
DROP TABLE products;
DROP TABLE categories;
