-- Pharmacie : manques côté serveur de l'app (spec 032) et paiement en espèces par le livreur
-- (docs/decisions/0014). Migration additive : rien n'est supprimé ; les comptes de versement et
-- l'historique des versements restent pour mémoire.

-- +goose Up

-- Numéro court d'alerte (« A-12 »), qui ne repasse jamais par zéro. Les alertes existantes sont
-- numérotées dans l'ordre de leur création.
CREATE SEQUENCE pharmacy_alert_number_seq;
ALTER TABLE pharmacy_alerts ADD COLUMN number bigint;
UPDATE pharmacy_alerts a SET number = n.rn
FROM (SELECT id, row_number() OVER (ORDER BY created_at, id) AS rn FROM pharmacy_alerts) n
WHERE a.id = n.id;
SELECT setval('pharmacy_alert_number_seq', COALESCE((SELECT max(number) FROM pharmacy_alerts), 0) + 1, false);
ALTER TABLE pharmacy_alerts
  ALTER COLUMN number SET DEFAULT nextval('pharmacy_alert_number_seq'),
  ALTER COLUMN number SET NOT NULL,
  ADD CONSTRAINT pharmacy_alerts_number_key UNIQUE (number);
ALTER SEQUENCE pharmacy_alert_number_seq OWNED BY pharmacy_alerts.number;

-- Origine d'une garde : ajoutée à la main par la pharmacie, importée d'une liste (planning
-- officiel), ou saisie par l'équipe ivia.
ALTER TABLE pharmacy_duty_shifts
  ADD COLUMN source      text NOT NULL DEFAULT 'manual' CHECK (source IN ('manual', 'import', 'admin')),
  ADD COLUMN imported_at timestamptz,
  ADD CONSTRAINT pharmacy_duty_shifts_import_check CHECK ((source = 'import') = (imported_at IS NOT NULL));
UPDATE pharmacy_duty_shifts s SET source = 'admin'
FROM pharmacies p
WHERE p.id = s.pharmacy_id AND s.created_by <> p.owner_id;

-- Remise au livreur à la pharmacie : code de retrait du livreur (4 chiffres, tiré à l'acceptation
-- de la course) et espèces payées par le livreur, que ivia lui rembourse.
ALTER TABLE pharmacy_deliveries
  ADD COLUMN pickup_code   text CHECK (pickup_code ~ '^[0-9]{4}$'),
  ADD COLUMN cash_paid_xof bigint CHECK (cash_paid_xof >= 0),
  ADD COLUMN cash_paid_at  timestamptz,
  ADD CONSTRAINT pharmacy_deliveries_cash_check CHECK ((cash_paid_xof IS NULL) = (cash_paid_at IS NULL));

-- Sonnerie des alertes choisie sur chaque téléphone : faux, le push part sans son (iOS).
ALTER TABLE device_tokens ADD COLUMN alert_sound boolean NOT NULL DEFAULT true;

-- +goose Down
ALTER TABLE device_tokens DROP COLUMN alert_sound;
ALTER TABLE pharmacy_deliveries
  DROP CONSTRAINT pharmacy_deliveries_cash_check,
  DROP COLUMN cash_paid_at,
  DROP COLUMN cash_paid_xof,
  DROP COLUMN pickup_code;
ALTER TABLE pharmacy_duty_shifts
  DROP CONSTRAINT pharmacy_duty_shifts_import_check,
  DROP COLUMN imported_at,
  DROP COLUMN source;
ALTER TABLE pharmacy_alerts DROP COLUMN number;
DROP SEQUENCE IF EXISTS pharmacy_alert_number_seq;
