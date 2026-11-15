-- Messagerie de la course (spec 037) : client ↔ livreur et livreur ↔ boutique, ouverte dès qu'un
-- livreur a accepté la course, en lecture seule une fois la course terminée.

-- +goose Up
CREATE TABLE chat_messages (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id    uuid NOT NULL REFERENCES orders (id),
  thread      text NOT NULL CHECK (thread IN ('buyer_driver', 'driver_shop')),
  sender_id   uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  sender_role text NOT NULL CHECK (sender_role IN ('buyer', 'driver', 'seller')),
  body        text NOT NULL CHECK (length(body) BETWEEN 1 AND 1000),
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX chat_messages_thread_idx ON chat_messages (order_id, thread, created_at);

-- Dernière lecture d'un fil par chaque participant (accusés de lecture, messages non lus).
CREATE TABLE chat_reads (
  order_id     uuid NOT NULL REFERENCES orders (id),
  thread       text NOT NULL,
  user_id      uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  last_read_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (order_id, thread, user_id)
);

-- +goose Down
DROP TABLE chat_reads;
DROP TABLE chat_messages;
