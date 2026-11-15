-- Workflow d'inscription d'ivia Pharmacie : dossier en brouillon jusqu'à l'envoi, compléments
-- demandés par le back-office, photo de la devanture, compte de versement, heures de nuit où
-- seules les pharmacies de garde reçoivent les alertes. Migration additive.

-- +goose Up
ALTER TABLE pharmacies DROP CONSTRAINT pharmacies_review_status_check;
ALTER TABLE pharmacies ADD CONSTRAINT pharmacies_review_status_check
  CHECK (review_status IN ('draft', 'pending_review', 'changes_requested', 'approved', 'rejected'));
ALTER TABLE pharmacies ALTER COLUMN review_status SET DEFAULT 'draft';
ALTER TABLE pharmacies
  ADD COLUMN submitted_at    timestamptz,
  ADD COLUMN payout_operator text CHECK (payout_operator IN ('flooz', 'tmoney')),
  ADD COLUMN payout_phone    text CHECK (payout_phone ~ '^\+228[0-9]{8}$'),
  ADD COLUMN payout_holder   text NOT NULL DEFAULT '';

ALTER TABLE pharmacy_documents DROP CONSTRAINT pharmacy_documents_kind_check;
ALTER TABLE pharmacy_documents ADD CONSTRAINT pharmacy_documents_kind_check
  CHECK (kind IN ('opening_authorization', 'order_registration', 'owner_id', 'storefront_photo', 'other'));

-- Heure de Lomé. Début égal à fin : pas de restriction de nuit.
ALTER TABLE pharmacy_settings
  ADD COLUMN night_from_hour integer NOT NULL DEFAULT 20 CHECK (night_from_hour BETWEEN 0 AND 23),
  ADD COLUMN night_to_hour   integer NOT NULL DEFAULT 7 CHECK (night_to_hour BETWEEN 0 AND 23);

-- +goose Down
ALTER TABLE pharmacy_settings DROP COLUMN night_to_hour, DROP COLUMN night_from_hour;
ALTER TABLE pharmacy_documents DROP CONSTRAINT pharmacy_documents_kind_check;
UPDATE pharmacy_documents SET kind = 'other' WHERE kind = 'storefront_photo';
ALTER TABLE pharmacy_documents ADD CONSTRAINT pharmacy_documents_kind_check
  CHECK (kind IN ('opening_authorization', 'order_registration', 'owner_id', 'other'));
ALTER TABLE pharmacies DROP COLUMN payout_holder, DROP COLUMN payout_phone, DROP COLUMN payout_operator, DROP COLUMN submitted_at;
ALTER TABLE pharmacies DROP CONSTRAINT pharmacies_review_status_check;
UPDATE pharmacies SET review_status = 'pending_review' WHERE review_status IN ('draft', 'changes_requested');
ALTER TABLE pharmacies ALTER COLUMN review_status SET DEFAULT 'pending_review';
ALTER TABLE pharmacies ADD CONSTRAINT pharmacies_review_status_check
  CHECK (review_status IN ('pending_review', 'approved', 'rejected'));
