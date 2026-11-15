-- Module settlements : relevés des sommes dues aux marchands. Un relevé réglé n'est plus modifiable.

-- +goose Up
CREATE TABLE settlements (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  shop_id              uuid NOT NULL REFERENCES shops (id),
  -- Période en dates de Lomé, bornes incluses.
  period_start         date NOT NULL,
  period_end           date NOT NULL,
  orders_count         integer NOT NULL CHECK (orders_count >= 0),
  gross_xof            bigint NOT NULL CHECK (gross_xof >= 0),
  commission_xof       bigint NOT NULL CHECK (commission_xof >= 0),
  net_xof              bigint NOT NULL,
  status               text NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'settled')),
  created_by           uuid NOT NULL REFERENCES users (id),
  created_at           timestamptz NOT NULL DEFAULT now(),
  settled_at           timestamptz,
  settled_by           uuid REFERENCES users (id),
  settlement_reference text NOT NULL DEFAULT '',
  note                 text NOT NULL DEFAULT '',
  CHECK (period_end >= period_start),
  CHECK (net_xof = gross_xof - commission_xof),
  CHECK ((status = 'settled') = (settled_at IS NOT NULL))
);
CREATE INDEX settlements_shop_idx ON settlements (shop_id, period_start DESC);

CREATE TABLE settlement_lines (
  settlement_id  uuid NOT NULL REFERENCES settlements (id) ON DELETE CASCADE,
  -- Une commande n'apparaît que dans un seul relevé.
  order_id       uuid NOT NULL UNIQUE REFERENCES orders (id),
  order_number   bigint NOT NULL,
  completed_at   timestamptz NOT NULL,
  subtotal_xof   bigint NOT NULL,
  commission_xof bigint NOT NULL,
  PRIMARY KEY (settlement_id, order_id)
);

-- Un relevé réglé (et ses lignes) est figé.
-- +goose StatementBegin
CREATE FUNCTION forbid_settled_settlement_change() RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_TABLE_NAME = 'settlements' THEN
    IF OLD.status = 'settled' THEN
      RAISE EXCEPTION 'relevé % déjà réglé : % interdit', OLD.id, TG_OP USING ERRCODE = 'restrict_violation';
    END IF;
  ELSE
    IF TG_OP = 'UPDATE' OR EXISTS (
      SELECT 1 FROM settlements WHERE id = OLD.settlement_id AND status = 'settled'
    ) THEN
      RAISE EXCEPTION 'ligne de relevé figée : % interdit', TG_OP USING ERRCODE = 'restrict_violation';
    END IF;
  END IF;
  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END
$$;
-- +goose StatementEnd

CREATE TRIGGER settlements_frozen_when_settled
  BEFORE UPDATE OR DELETE ON settlements
  FOR EACH ROW EXECUTE FUNCTION forbid_settled_settlement_change();
CREATE TRIGGER settlement_lines_frozen
  BEFORE UPDATE OR DELETE ON settlement_lines
  FOR EACH ROW EXECUTE FUNCTION forbid_settled_settlement_change();

-- +goose Down
DROP TABLE settlement_lines;
DROP TABLE settlements;
DROP FUNCTION forbid_settled_settlement_change();
