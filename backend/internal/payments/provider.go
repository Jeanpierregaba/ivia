package payments

import (
	"context"
	"errors"
	"net/http"
)

// Operator est l'opérateur Mobile Money du payeur.
type Operator string

const (
	OperatorFlooz  Operator = "flooz"  // Moov Africa
	OperatorTMoney Operator = "tmoney" // Yas
)

// ProviderStatus est l'état d'une transaction chez le prestataire.
type ProviderStatus string

const (
	ProviderPending   ProviderStatus = "pending"
	ProviderSucceeded ProviderStatus = "succeeded"
	ProviderFailed    ProviderStatus = "failed"
)

// InitiateRequest demande un paiement au prestataire.
type InitiateRequest struct {
	Reference   string
	AmountXOF   int64
	Operator    Operator
	Phone       string
	Description string
}

// InitiateResult est la réponse du prestataire à une demande de paiement.
type InitiateResult struct {
	ProviderRef string
	// Instructions à afficher à l'acheteur (ex. « validez sur votre téléphone »).
	Instructions string
}

// Event est une information de paiement reçue du prestataire (webhook signé ou revérification).
type Event struct {
	// EventID identifie l'événement chez le prestataire (idempotence).
	EventID     string
	Reference   string
	ProviderRef string
	Status      ProviderStatus
	AmountXOF   int64
	Currency    string
	Raw         []byte
}

// PayoutRequest demande un transfert vers un numéro Mobile Money (remboursement).
type PayoutRequest struct {
	Reference string
	AmountXOF int64
	Operator  Operator
	Phone     string
	Reason    string
}

// PayoutResult est l'état d'un transfert.
type PayoutResult struct {
	ProviderRef   string
	Status        ProviderStatus
	FailureReason string
}

// Erreurs des prestataires.
var (
	ErrInvalidSignature = errors.New("signature de webhook invalide")
	ErrPayoutNotFound   = errors.New("transfert inconnu du prestataire")
)

// Provider est l'interface d'un agrégateur Mobile Money (ADR 0007). Le choix de l'agrégateur réel
// est en attente : le développement se fait avec le faux prestataire (FakeProvider).
type Provider interface {
	Name() string
	// Initiate lance un paiement (l'acheteur valide ensuite sur son téléphone).
	Initiate(ctx context.Context, req InitiateRequest) (InitiateResult, error)
	// Status revérifie un paiement auprès du prestataire (webhook non reçu).
	Status(ctx context.Context, reference string) (Event, error)
	// ParseWebhook vérifie la signature d'une notification et la décode (ErrInvalidSignature sinon).
	ParseWebhook(header http.Header, body []byte) (Event, error)
	// Payout transfère de l'argent vers un numéro (remboursement). Idempotent par référence.
	Payout(ctx context.Context, req PayoutRequest) (PayoutResult, error)
	// PayoutStatus retourne l'état d'un transfert (ErrPayoutNotFound s'il n'a jamais été demandé).
	PayoutStatus(ctx context.Context, reference string) (PayoutResult, error)
}
