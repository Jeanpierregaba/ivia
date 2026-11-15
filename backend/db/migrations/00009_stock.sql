-- Module stock : quantité disponible des produits à stock suivi et journal des mouvements.
-- La quantité vit dans une table du module stock (et non dans products) pour qu'aucun autre
-- module n'écrive dans les tables du catalogue.

-- +goose Up
CREATE TABLE stock_levels (
  product_id uuid PRIMARY KEY REFERENCES products (id),
  -- La contrainte rend la survente impossible : une réservation qui ferait passer sous zéro échoue.
  quantity   integer NOT NULL CHECK (quantity >= 0),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE stock_movements (
  id             bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  product_id     uuid NOT NULL REFERENCES products (id),
  delta          integer NOT NULL CHECK (delta <> 0),
  quantity_after integer NOT NULL CHECK (quantity_after >= 0),
  reason         text NOT NULL CHECK (reason IN ('initial', 'adjustment', 'order_reserved', 'order_released')),
  order_id       uuid,
  actor_id       uuid REFERENCES users (id),
  note           text NOT NULL DEFAULT '' CHECK (length(note) <= 300),
  created_at     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX stock_movements_product_idx ON stock_movements (product_id, created_at DESC);
CREATE INDEX stock_movements_order_idx ON stock_movements (order_id) WHERE order_id IS NOT NULL;

CREATE TRIGGER stock_movements_append_only
  BEFORE UPDATE OR DELETE ON stock_movements
  FOR EACH ROW EXECUTE FUNCTION forbid_mutation();

-- +goose Down
DROP TABLE stock_movements;
DROP TABLE stock_levels;
