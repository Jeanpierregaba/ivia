-- Module payments : paiements Mobile Money, événements reçus du prestataire, remboursements.
-- payment_events et refunds sont en ajout seul : un remboursement est écrit une fois son résultat
-- connu ; l'état « remboursement en cours » est porté par payments.status = 'refund_pending'.

-- +goose Up
CREATE TABLE payments (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id       uuid NOT NULL REFERENCES orders (id),
  buyer_id       uuid NOT NULL REFERENCES users (id),
  provider       text NOT NULL,
  -- Notre référence, transmise au prestataire et renvoyée dans ses webhooks.
  reference      text NOT NULL UNIQUE,
  provider_ref   text,
  amount_xof     bigint NOT NULL CHECK (amount_xof > 0),
  currency       text NOT NULL DEFAULT 'XOF' CHECK (currency = 'XOF'),
  operator       text NOT NULL CHECK (operator IN ('flooz', 'tmoney')),
  payer_phone    text NOT NULL CHECK (payer_phone ~ '^\+228[0-9]{8}$'),
  status         text NOT NULL DEFAULT 'pending' CHECK (status IN (
                   'pending', 'succeeded', 'failed', 'expired', 'refund_pending', 'refunded')),
  failure_reason text NOT NULL DEFAULT '',
  -- Paiement réussi alors que la commande était déjà payée par un autre paiement : à rembourser.
  is_duplicate   boolean NOT NULL DEFAULT false,
  succeeded_at   timestamptz,
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now(),
  UNIQUE (provider, provider_ref)
);
-- Un seul paiement en cours par commande.
CREATE UNIQUE INDEX payments_one_pending_per_order ON payments (order_id) WHERE status = 'pending';
CREATE INDEX payments_order_idx ON payments (order_id, created_at DESC);
CREATE INDEX payments_status_idx ON payments (status, created_at);

CREATE TABLE payment_events (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  provider    text NOT NULL,
  -- 'webhook' : notification signée ; 'verify' : revérification par l'API du prestataire.
  source      text NOT NULL CHECK (source IN ('webhook', 'verify')),
  event_id    text NOT NULL,
  reference   text NOT NULL,
  status      text NOT NULL,
  amount_xof  bigint NOT NULL,
  currency    text NOT NULL,
  payload     jsonb NOT NULL,
  received_at timestamptz NOT NULL DEFAULT now(),
  -- Idempotence : un même événement reçu deux fois n'est enregistré (et traité) qu'une fois.
  UNIQUE (provider, event_id)
);
CREATE INDEX payment_events_reference_idx ON payment_events (reference, id);

CREATE TRIGGER payment_events_append_only
  BEFORE UPDATE OR DELETE ON payment_events
  FOR EACH ROW EXECUTE FUNCTION forbid_mutation();
CREATE TRIGGER payment_events_no_truncate
  BEFORE TRUNCATE ON payment_events
  FOR EACH STATEMENT EXECUTE FUNCTION forbid_mutation();

CREATE TABLE refunds (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  payment_id     uuid NOT NULL REFERENCES payments (id),
  order_id       uuid NOT NULL REFERENCES orders (id),
  -- Référence de transfert transmise au prestataire (idempotence côté prestataire).
  reference      text NOT NULL,
  amount_xof     bigint NOT NULL CHECK (amount_xof > 0),
  status         text NOT NULL CHECK (status IN ('succeeded', 'failed')),
  provider_ref   text,
  failure_reason text NOT NULL DEFAULT '',
  reason         text NOT NULL DEFAULT '',
  requested_by   uuid NOT NULL REFERENCES users (id),
  requested_at   timestamptz NOT NULL,
  created_at     timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX refunds_one_success_per_payment ON refunds (payment_id) WHERE status = 'succeeded';
CREATE INDEX refunds_order_idx ON refunds (order_id);

CREATE TRIGGER refunds_append_only
  BEFORE UPDATE OR DELETE ON refunds
  FOR EACH ROW EXECUTE FUNCTION forbid_mutation();
CREATE TRIGGER refunds_no_truncate
  BEFORE TRUNCATE ON refunds
  FOR EACH STATEMENT EXECUTE FUNCTION forbid_mutation();

-- +goose Down
DROP TABLE refunds;
DROP TABLE payment_events;
DROP TABLE payments;
