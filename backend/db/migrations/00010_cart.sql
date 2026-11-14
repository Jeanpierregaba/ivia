-- Module cart : un panier par acheteur, lié à une seule boutique.

-- +goose Up
CREATE TABLE carts (
  buyer_id   uuid PRIMARY KEY REFERENCES users (id),
  shop_id    uuid NOT NULL REFERENCES shops (id),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE cart_items (
  buyer_id   uuid NOT NULL REFERENCES carts (buyer_id) ON DELETE CASCADE,
  product_id uuid NOT NULL REFERENCES products (id),
  quantity   integer NOT NULL CHECK (quantity BETWEEN 1 AND 99),
  added_at   timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (buyer_id, product_id)
);

-- +goose Down
DROP TABLE cart_items;
DROP TABLE carts;
