-- Workflow partenaire livreur / chauffeur (BPMN « ivia Livreur », 2026-11-07) : une ligne par
-- activité (livraison, taxi VTC), justificatifs selon le véhicule, compte de versement, envoi du
-- dossier, contrôle du véhicule sur place et décision du back-office (valider, compléments, refus).
-- `drivers` garde l'état de l'activité livraison, lu par l'attribution des missions.

-- +goose Up
ALTER TABLE drivers DROP CONSTRAINT drivers_review_status_check;
ALTER TABLE drivers ADD CONSTRAINT drivers_review_status_check
  CHECK (review_status IN ('draft', 'pending_review', 'changes_requested', 'approved', 'rejected'));
ALTER TABLE drivers DROP CONSTRAINT drivers_vehicle_type_check;
ALTER TABLE drivers ADD CONSTRAINT drivers_vehicle_type_check
  CHECK (vehicle_type IN ('bicycle', 'motorbike', 'car'));

-- Compte de versement Mobile Money, commun à toutes les activités du partenaire.
ALTER TABLE drivers
  ADD COLUMN payout_operator text CHECK (payout_operator IN ('flooz', 'tmoney')),
  ADD COLUMN payout_phone    text CHECK (payout_phone ~ '^\+228[0-9]{8}$'),
  ADD COLUMN payout_holder   text NOT NULL DEFAULT '' CHECK (length(payout_holder) <= 100);

ALTER TABLE driver_documents DROP CONSTRAINT driver_documents_kind_check;
ALTER TABLE driver_documents ADD CONSTRAINT driver_documents_kind_check
  CHECK (kind IN ('id_card', 'driving_license', 'vehicle_registration', 'vehicle_insurance',
                  'vehicle_photo', 'criminal_record', 'photo', 'other'));

CREATE TABLE driver_activities (
  user_id              uuid NOT NULL REFERENCES drivers (user_id),
  activity             text NOT NULL CHECK (activity IN ('delivery', 'vtc')),
  status               text NOT NULL DEFAULT 'draft'
                       CHECK (status IN ('draft', 'pending_review', 'changes_requested', 'approved', 'rejected')),
  review_note          text NOT NULL DEFAULT '',
  reviewed_at          timestamptz,
  reviewed_by          uuid REFERENCES users (id),
  vehicle_type         text NOT NULL CHECK (vehicle_type IN ('bicycle', 'motorbike', 'car')),
  vehicle_brand        text NOT NULL DEFAULT '' CHECK (length(vehicle_brand) <= 60),
  vehicle_model        text NOT NULL DEFAULT '' CHECK (length(vehicle_model) <= 60),
  vehicle_color        text NOT NULL DEFAULT '' CHECK (length(vehicle_color) <= 40),
  vehicle_plate        text NOT NULL DEFAULT '' CHECK (length(vehicle_plate) <= 20),
  vehicle_seats        smallint CHECK (vehicle_seats BETWEEN 1 AND 8),
  work_zone_id         uuid REFERENCES zones (id),
  vehicle_checked_at   timestamptz,
  vehicle_checked_by   uuid REFERENCES users (id),
  vehicle_check_passed boolean,
  vehicle_check_note   text NOT NULL DEFAULT '' CHECK (length(vehicle_check_note) <= 500),
  submitted_at         timestamptz,
  -- Dossier déposé par l'ancien parcours (PUT /v1/driver/application) : anciennes exigences.
  legacy               boolean NOT NULL DEFAULT false,
  created_at           timestamptz NOT NULL DEFAULT now(),
  updated_at           timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, activity),
  CHECK (activity <> 'vtc' OR vehicle_type = 'car')
);
CREATE INDEX driver_activities_status_idx ON driver_activities (status, submitted_at);

INSERT INTO driver_activities (user_id, activity, status, review_note, reviewed_at, reviewed_by,
                               vehicle_type, vehicle_plate, submitted_at, legacy, created_at, updated_at)
SELECT user_id, 'delivery', review_status, review_note, reviewed_at, reviewed_by,
       vehicle_type, vehicle_plate, created_at, true, created_at, updated_at
FROM drivers;

-- Réglages du back-office : taxi VTC masqué, en pré-inscription ou ouvert ; contrôle du véhicule
-- exigé ou non pour la livraison (toujours exigé pour le VTC) ; guide du partenaire.
CREATE TABLE driver_settings (
  id                     boolean PRIMARY KEY DEFAULT true CHECK (id),
  vtc_mode               text NOT NULL DEFAULT 'hidden' CHECK (vtc_mode IN ('hidden', 'preregistration', 'open')),
  delivery_vehicle_check boolean NOT NULL DEFAULT false,
  partner_guide          text NOT NULL DEFAULT '' CHECK (length(partner_guide) <= 20000),
  updated_at             timestamptz NOT NULL DEFAULT now(),
  updated_by             uuid REFERENCES users (id)
);
INSERT INTO driver_settings DEFAULT VALUES;

-- +goose Down
DROP TABLE driver_settings;
DROP TABLE driver_activities;
UPDATE driver_documents SET kind = 'other' WHERE kind IN ('vehicle_insurance', 'vehicle_photo', 'criminal_record');
ALTER TABLE driver_documents DROP CONSTRAINT driver_documents_kind_check;
ALTER TABLE driver_documents ADD CONSTRAINT driver_documents_kind_check
  CHECK (kind IN ('id_card', 'driving_license', 'vehicle_registration', 'photo', 'other'));
ALTER TABLE drivers DROP COLUMN payout_holder, DROP COLUMN payout_phone, DROP COLUMN payout_operator;
UPDATE drivers SET review_status = 'pending_review' WHERE review_status IN ('draft', 'changes_requested');
UPDATE drivers SET vehicle_type = 'motorbike' WHERE vehicle_type = 'bicycle';
ALTER TABLE drivers DROP CONSTRAINT drivers_vehicle_type_check;
ALTER TABLE drivers ADD CONSTRAINT drivers_vehicle_type_check CHECK (vehicle_type IN ('motorbike', 'car'));
ALTER TABLE drivers DROP CONSTRAINT drivers_review_status_check;
ALTER TABLE drivers ADD CONSTRAINT drivers_review_status_check
  CHECK (review_status IN ('pending_review', 'approved', 'rejected'));
