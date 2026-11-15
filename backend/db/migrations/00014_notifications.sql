-- Module notifications : liste consultable dans chaque app, envoyée aussi en push.

-- +goose Up
CREATE TABLE notifications (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      uuid NOT NULL REFERENCES users (id),
  app          text NOT NULL CHECK (app IN ('buyer', 'seller', 'driver', 'admin')),
  kind         text NOT NULL,
  title        text NOT NULL,
  body         text NOT NULL,
  data         jsonb NOT NULL DEFAULT '{}',
  read_at      timestamptz,
  push_sent_at timestamptz,
  created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX notifications_user_app_idx ON notifications (user_id, app, created_at DESC);
CREATE INDEX notifications_unread_idx ON notifications (user_id, app) WHERE read_at IS NULL;

-- +goose Down
DROP TABLE notifications;
