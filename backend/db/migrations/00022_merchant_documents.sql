-- Pièces du marchand (la personne, pas la boutique) : vérifiées par l'admin avant de publier une
-- de ses boutiques. Pièce d'identité obligatoire, registre du commerce (RCCM) facultatif.
-- Fichiers dans le compartiment privé, lus par URL signée réservée aux admins (SECURITY.md) ;
-- effacés à la suppression du compte.

-- +goose Up
CREATE TABLE merchant_documents (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id   uuid NOT NULL REFERENCES users (id),
  kind       text NOT NULL CHECK (kind IN ('id_card', 'business_registration', 'other')),
  object_key text NOT NULL UNIQUE,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX merchant_documents_owner_idx ON merchant_documents (owner_id, created_at);

-- +goose Down
DROP TABLE merchant_documents;
