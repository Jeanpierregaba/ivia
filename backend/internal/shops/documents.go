package shops

import (
	"context"
	"fmt"
	"strings"
	"time"

	"github.com/google/uuid"

	"ivia/backend/internal/platform/apperr"
	"ivia/backend/internal/shops/store"
	"ivia/backend/internal/uploads"
)

// Pièces du marchand : elles concernent la personne (un marchand à plusieurs boutiques ne les dépose
// qu'une fois) et sont vérifiées par l'admin avant la publication d'une boutique.

// Document est une pièce du marchand. L'URL, temporaire, n'est fournie qu'aux admins.
type Document struct {
	ID        uuid.UUID `json:"id"`
	Kind      string    `json:"kind"`
	URL       *string   `json:"url,omitempty"`
	CreatedAt time.Time `json:"created_at"`
}

// RequiredDocuments : pièces sans lesquelles aucune boutique du marchand ne peut être publiée.
var RequiredDocuments = []string{"id_card"}

var documentKinds = map[string]string{
	"id_card":               "pièce d'identité",
	"business_registration": "registre du commerce",
	"other":                 "autre document",
}

// maxDocuments borne le nombre de pièces d'un marchand.
const maxDocuments = 10

// AddDocument ajoute une pièce au dossier du marchand (fichier déjà envoyé dans le compartiment privé).
func (s *Service) AddDocument(ctx context.Context, ownerID uuid.UUID, kind, objectKey string) ([]Document, error) {
	if _, ok := documentKinds[kind]; !ok {
		return nil, apperr.Validation(map[string]string{"kind": "Type de document inconnu : id_card, business_registration ou other."})
	}
	q := store.New(s.db.Conn(ctx))
	n, err := q.CountMerchantDocuments(ctx, ownerID)
	if err != nil {
		return nil, fmt.Errorf("décompte des documents : %w", err)
	}
	if n >= maxDocuments {
		return nil, apperr.Conflict("too_many_documents", "Nombre maximal de documents atteint.")
	}
	if err := s.uploads.Check(ctx, uploads.MerchantDocument, ownerID, objectKey, "object_key"); err != nil {
		return nil, err
	}
	if _, err := q.InsertMerchantDocument(ctx, store.InsertMerchantDocumentParams{OwnerID: ownerID, Kind: kind, ObjectKey: objectKey}); err != nil {
		return nil, fmt.Errorf("ajout du document : %w", err)
	}
	return s.Documents(ctx, ownerID, false)
}

// Documents retourne les pièces d'un marchand ; withURLs ajoute des liens de lecture temporaires
// (back-office uniquement).
func (s *Service) Documents(ctx context.Context, ownerID uuid.UUID, withURLs bool) ([]Document, error) {
	rows, err := store.New(s.db.Conn(ctx)).ListMerchantDocuments(ctx, ownerID)
	if err != nil {
		return nil, fmt.Errorf("lecture des documents : %w", err)
	}
	out := make([]Document, len(rows))
	for i, r := range rows {
		out[i] = Document{ID: r.ID, Kind: r.Kind, CreatedAt: r.CreatedAt}
		if withURLs {
			u, err := s.uploads.PrivateURL(ctx, r.ObjectKey)
			if err != nil {
				return nil, err
			}
			out[i].URL = &u
		}
	}
	return out, nil
}

// requireDocuments refuse la publication tant que le marchand n'a pas déposé les pièces obligatoires.
func requireDocuments(docs []Document) error {
	have := make(map[string]bool, len(docs))
	for _, d := range docs {
		have[d.Kind] = true
	}
	var missing []string
	for _, k := range RequiredDocuments {
		if !have[k] {
			missing = append(missing, documentKinds[k])
		}
	}
	if len(missing) > 0 {
		return apperr.Conflict("merchant_documents_missing", "Dossier du marchand incomplet : "+strings.Join(missing, ", ")+" manquant(s).")
	}
	return nil
}

// deleteDocuments efface les pièces d'un marchand à la suppression du compte : tout son dossier
// de fichiers (même ceux jamais rattachés), puis les lignes.
func (s *Service) deleteDocuments(ctx context.Context, ownerID uuid.UUID) error {
	if _, err := s.uploads.DeleteAllOf(ctx, uploads.MerchantDocument, ownerID); err != nil {
		return err
	}
	if err := store.New(s.db.Conn(ctx)).DeleteMerchantDocumentsOf(ctx, ownerID); err != nil {
		return fmt.Errorf("suppression des documents : %w", err)
	}
	return nil
}

// attachedDocuments dit lesquelles de ces clés sont rattachées à un marchand (uploads.AttachedFunc).
func (s *Service) attachedDocuments(ctx context.Context, keys []string) (map[string]bool, error) {
	found, err := store.New(s.db.Conn(ctx)).MerchantDocumentKeysIn(ctx, keys)
	if err != nil {
		return nil, fmt.Errorf("lecture des pièces rattachées : %w", err)
	}
	out := make(map[string]bool, len(found))
	for _, k := range found {
		out[k] = true
	}
	return out, nil
}
