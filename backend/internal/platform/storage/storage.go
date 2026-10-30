// Package storage donne accès au stockage des fichiers (photos, documents des livreurs) derrière
// l'interface ObjectStore : Cloudflare R2 en production, disque local en développement.
// Les fichiers sont envoyés directement par les apps grâce à des URL signées à durée courte.
package storage

import (
	"context"
	"time"
)

// Visibility désigne le compartiment : public (photos) ou privé (documents des livreurs).
type Visibility string

const (
	Public  Visibility = "public"
	Private Visibility = "private"
)

// PresignedRequest décrit la requête HTTP que l'app doit faire pour envoyer le fichier.
type PresignedRequest struct {
	Method    string            `json:"method"`
	URL       string            `json:"url"`
	Headers   map[string]string `json:"headers"`
	ExpiresAt time.Time         `json:"expires_at"`
}

// ObjectStore est implémenté par R2 et par le stockage local.
type ObjectStore interface {
	// PresignPut signe un envoi : le type et la taille exacte du fichier font partie de la signature.
	PresignPut(ctx context.Context, vis Visibility, key, contentType string, size int64, ttl time.Duration) (PresignedRequest, error)
	// PresignGet signe une lecture d'un fichier privé.
	PresignGet(ctx context.Context, key string, ttl time.Duration) (string, error)
	// PublicURL retourne l'URL publique d'un fichier du compartiment public.
	PublicURL(key string) string
	// Exists vérifie qu'un fichier a bien été envoyé.
	Exists(ctx context.Context, vis Visibility, key string) (bool, error)
	// Delete supprime un fichier (sans erreur s'il n'existe pas).
	Delete(ctx context.Context, vis Visibility, key string) error
}
