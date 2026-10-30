-- Module users : comptes, rôles, adresses de livraison, jetons push.

-- +goose Up
CREATE TABLE users (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  -- NULL après suppression du compte (anonymisation).
  email      text UNIQUE CHECK (email = lower(email)),
  phone      text UNIQUE CHECK (phone ~ '^\+228[0-9]{8}$'),
  first_name text NOT NULL DEFAULT '' CHECK (length(first_name) <= 100),
  last_name  text NOT NULL DEFAULT '' CHECK (length(last_name) <= 100),
  deleted_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE user_roles (
  user_id    uuid NOT NULL REFERENCES users (id),
  role       text NOT NULL CHECK (role IN ('buyer', 'seller', 'driver', 'admin')),
  granted_by uuid REFERENCES users (id),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, role)
);

CREATE TABLE addresses (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         uuid NOT NULL REFERENCES users (id),
  label           text NOT NULL CHECK (length(label) BETWEEN 1 AND 50),
  address_text    text NOT NULL CHECK (length(address_text) BETWEEN 1 AND 300),
  neighborhood_id uuid REFERENCES neighborhoods (id),
  location        geography(Point, 4326) NOT NULL,
  instructions    text NOT NULL DEFAULT '' CHECK (length(instructions) <= 300),
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX addresses_user_id_idx ON addresses (user_id);

CREATE TABLE device_tokens (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      uuid NOT NULL REFERENCES users (id),
  token        text NOT NULL UNIQUE CHECK (length(token) BETWEEN 1 AND 4096),
  platform     text NOT NULL CHECK (platform IN ('android', 'ios')),
  app          text NOT NULL CHECK (app IN ('buyer', 'seller', 'driver')),
  created_at   timestamptz NOT NULL DEFAULT now(),
  last_seen_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX device_tokens_user_app_idx ON device_tokens (user_id, app);

-- +goose Down
DROP TABLE device_tokens;
DROP TABLE addresses;
DROP TABLE user_roles;
DROP TABLE users;
