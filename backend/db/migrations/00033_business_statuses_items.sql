-- Ivia Business : statuts du brief (active, changes_requested), contenu des modules agence et
-- artisan (annonces, services). Aucune donnée perdue : les statuts sont renommés.

-- +goose Up
ALTER TABLE business_spaces DROP CONSTRAINT business_spaces_status_check;
UPDATE business_spaces SET status = 'active' WHERE status = 'approved';
UPDATE business_spaces SET status = 'changes_requested' WHERE status = 'needs_changes';
ALTER TABLE business_spaces ADD CONSTRAINT business_spaces_status_check
  CHECK (status IN ('draft', 'pending_review', 'changes_requested', 'rejected', 'active', 'suspended'));

ALTER TABLE business_items
  ADD COLUMN status     text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'active', 'archived')),
  ADD COLUMN attributes jsonb NOT NULL DEFAULT '{}',
  ADD COLUMN photo_keys text[] NOT NULL DEFAULT '{}',
  ADD COLUMN updated_at timestamptz NOT NULL DEFAULT now();

-- +goose Down
ALTER TABLE business_items DROP COLUMN updated_at, DROP COLUMN photo_keys, DROP COLUMN attributes, DROP COLUMN status;
ALTER TABLE business_spaces DROP CONSTRAINT business_spaces_status_check;
UPDATE business_spaces SET status = 'approved' WHERE status = 'active';
UPDATE business_spaces SET status = 'needs_changes' WHERE status = 'changes_requested';
ALTER TABLE business_spaces ADD CONSTRAINT business_spaces_status_check
  CHECK (status IN ('draft', 'pending_review', 'needs_changes', 'rejected', 'approved', 'suspended'));
