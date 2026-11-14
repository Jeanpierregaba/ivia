-- Notifications push dans le navigateur (Firebase Cloud Messaging, Web Push) : un appareil peut
-- être un navigateur.

-- +goose Up
ALTER TABLE device_tokens DROP CONSTRAINT device_tokens_platform_check;
ALTER TABLE device_tokens ADD CONSTRAINT device_tokens_platform_check
  CHECK (platform IN ('android', 'ios', 'web'));

-- +goose Down
DELETE FROM device_tokens WHERE platform = 'web';
ALTER TABLE device_tokens DROP CONSTRAINT device_tokens_platform_check;
ALTER TABLE device_tokens ADD CONSTRAINT device_tokens_platform_check
  CHECK (platform IN ('android', 'ios'));
