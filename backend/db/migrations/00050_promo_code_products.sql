-- Codes promo limités à certains produits (spec 041) : un code sans ligne ici vaut pour toute sa
-- boutique ; sinon la réduction ne porte que sur les produits listés (un seul ou plusieurs).

-- +goose Up
CREATE TABLE promo_code_products (
  code_id    uuid NOT NULL REFERENCES promo_codes (id) ON DELETE CASCADE,
  product_id uuid NOT NULL REFERENCES products (id) ON DELETE CASCADE,
  PRIMARY KEY (code_id, product_id)
);
CREATE INDEX promo_code_products_product_idx ON promo_code_products (product_id);

-- +goose Down
DROP TABLE promo_code_products;
