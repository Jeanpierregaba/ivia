// Package uploads délivre les URL signées d'envoi direct des fichiers vers le stockage
// (photos de produits, logos de boutiques, documents des livreurs) et vérifie les clés renvoyées
// par les apps. Il n'a pas de table : la clé du fichier est choisie par le serveur et contient
// l'identifiant de l'utilisateur, ce qui permet de vérifier qu'il en est l'auteur.
package uploads

import (
	"context"
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/google/uuid"

	"ivia/backend/internal/platform/apperr"
	"ivia/backend/internal/platform/httpapi"
	"ivia/backend/internal/platform/identity"
	"ivia/backend/internal/platform/storage"
	"ivia/backend/internal/platform/validate"
)

// Purpose est l'usage d'un fichier ; il fixe le compartiment, les types permis et le préfixe de clé.
type Purpose string

const (
	ProductImage   Purpose = "product_image"
	ShopLogo       Purpose = "shop_logo"
	DriverDocument Purpose = "driver_document"
	// MerchantDocument : pièce d'identité ou registre du commerce, vérifiés avant publication.
	MerchantDocument Purpose = "merchant_document"
)

// Limites imposées à la signature (SECURITY.md).
const (
	MaxBytes = 5 << 20
	URLTTL   = 5 * time.Minute
)

type rule struct {
	prefix string
	vis    storage.Visibility
	types  map[string]string // type MIME → extension
	role   identity.Role     // rôle requis ("" : tout utilisateur connecté)
}

var images = map[string]string{"image/jpeg": "jpg", "image/png": "png", "image/webp": "webp"}

var documents = map[string]string{"image/jpeg": "jpg", "image/png": "png", "image/webp": "webp", "application/pdf": "pdf"}

var rules = map[Purpose]rule{
	ProductImage: {prefix: "products", vis: storage.Public, types: images, role: identity.RoleSeller},
	// Le logo est envoyé à la création de la boutique, avant que l'utilisateur soit marchand.
	ShopLogo:       {prefix: "shops", vis: storage.Public, types: images},
	DriverDocument: {prefix: "drivers", vis: storage.Private, types: documents},
	// Déposées après la création de la boutique, qui donne le rôle marchand.
	MerchantDocument: {prefix: "merchants", vis: storage.Private, types: documents, role: identity.RoleSeller},
}

// Service signe les envois et vérifie les clés.
type Service struct {
	store storage.ObjectStore
}

// NewService crée le service.
func NewService(store storage.ObjectStore) *Service { return &Service{store: store} }

// Upload est la réponse à une demande d'envoi.
type Upload struct {
	ObjectKey string                   `json:"object_key"`
	Request   storage.PresignedRequest `json:"upload"`
}

// Sign prépare l'envoi d'un fichier.
func (s *Service) Sign(ctx context.Context, p identity.Principal, purpose Purpose, contentType string, size int64) (Upload, error) {
	r, ok := rules[purpose]
	v := validate.New()
	v.Check(ok, "purpose", "Usage inconnu : product_image, shop_logo, driver_document ou merchant_document.")
	if ok {
		_, typeOK := r.types[contentType]
		v.Check(typeOK, "content_type", "Type de fichier non accepté.")
	}
	v.Check(size > 0 && size <= MaxBytes, "size_bytes", "Le fichier doit faire au plus 5 Mo.")
	if err := v.Err(); err != nil {
		return Upload{}, err
	}
	if r.role != "" && !p.HasRole(r.role) {
		return Upload{}, apperr.Forbidden("forbidden", "Votre compte n'a pas accès à cette fonctionnalité.")
	}
	key := fmt.Sprintf("%s/%s/%s.%s", r.prefix, p.UserID, uuid.New(), r.types[contentType])
	req, err := s.store.PresignPut(ctx, r.vis, key, contentType, size, URLTTL)
	if err != nil {
		return Upload{}, fmt.Errorf("signature de l'envoi : %w", err)
	}
	return Upload{ObjectKey: key, Request: req}, nil
}

// Check vérifie qu'une clé fournie par une app a été délivrée à cet utilisateur pour cet usage et
// que le fichier a bien été envoyé.
func (s *Service) Check(ctx context.Context, purpose Purpose, userID uuid.UUID, key string, field string) error {
	r := rules[purpose]
	prefix := r.prefix + "/" + userID.String() + "/"
	rest, ok := strings.CutPrefix(key, prefix)
	if !ok || strings.ContainsAny(rest, "/\\") || len(rest) > 64 {
		return apperr.Validation(map[string]string{field: "Fichier invalide."})
	}
	exists, err := s.store.Exists(ctx, r.vis, key)
	if err != nil {
		return fmt.Errorf("vérification du fichier : %w", err)
	}
	if !exists {
		return apperr.Validation(map[string]string{field: "Le fichier n'a pas été reçu. Renvoyez-le."})
	}
	return nil
}

// DeletePrivate supprime un document privé (fin de collaboration d'un livreur ou d'un marchand).
func (s *Service) DeletePrivate(ctx context.Context, key string) error {
	return s.store.Delete(ctx, storage.Private, key)
}

// PublicURL retourne l'URL d'un fichier public (photo, logo).
func (s *Service) PublicURL(key string) string { return s.store.PublicURL(key) }

// PrivateURL retourne une URL de lecture temporaire d'un document privé (admins uniquement).
func (s *Service) PrivateURL(ctx context.Context, key string) (string, error) {
	return s.store.PresignGet(ctx, key, 10*time.Minute)
}

// Register enregistre la route de demande d'envoi.
func (s *Service) Register(rt *httpapi.Router) {
	rt.Auth("POST /v1/uploads", func(w http.ResponseWriter, r *http.Request) error {
		var in struct {
			Purpose     Purpose `json:"purpose"`
			ContentType string  `json:"content_type"`
			SizeBytes   int64   `json:"size_bytes"`
		}
		if err := httpapi.Decode(r, &in); err != nil {
			return err
		}
		up, err := s.Sign(r.Context(), identity.MustFromContext(r.Context()), in.Purpose, in.ContentType, in.SizeBytes)
		if err != nil {
			return err
		}
		return httpapi.Created(w, up)
	})
}
