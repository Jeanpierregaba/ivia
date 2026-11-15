-- Comptes admin à rôles (spec 039) : super admin et rôles par domaine. Les admins existants
-- deviennent super admins (aucun accès retiré).

-- +goose Up
CREATE TABLE admin_profiles (
  user_id    uuid PRIMARY KEY REFERENCES users (id),
  role       text NOT NULL CHECK (role IN ('super_admin', 'operations', 'network', 'health', 'marketing',
                                           'finance', 'map', 'support')),
  created_by uuid REFERENCES users (id),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO admin_profiles (user_id, role)
SELECT user_id, 'super_admin' FROM user_roles WHERE role = 'admin'
ON CONFLICT DO NOTHING;

-- +goose Down
DROP TABLE admin_profiles;
