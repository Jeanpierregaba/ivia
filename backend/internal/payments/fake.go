package payments

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"sync"

	"github.com/google/uuid"
)

// FakeProvider simule un agrégateur Mobile Money pour le développement local et les tests :
// paiements en attente, réussis ou échoués à la demande, webhooks signés (HMAC-SHA256),
// transferts. Jamais utilisable en production (config.Load le refuse).
//
// Convention de test : un transfert vers un numéro se terminant par 0000 échoue.
type FakeProvider struct {
	secret []byte

	mu       sync.Mutex
	payments map[string]*fakePayment // par référence
	payouts  map[string]PayoutResult // par référence
}

type fakePayment struct {
	providerRef string
	amount      int64
	status      ProviderStatus
}

// FakeSignatureHeader porte la signature des webhooks simulés.
const FakeSignatureHeader = "X-Fake-Signature"

// NewFakeProvider crée le faux prestataire ; secret signe les webhooks.
func NewFakeProvider(secret []byte) *FakeProvider {
	return &FakeProvider{secret: secret, payments: map[string]*fakePayment{}, payouts: map[string]PayoutResult{}}
}

// Name implémente Provider.
func (f *FakeProvider) Name() string { return "fake" }

// Initiate implémente Provider : le paiement reste en attente jusqu'à une simulation.
func (f *FakeProvider) Initiate(_ context.Context, req InitiateRequest) (InitiateResult, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	ref := "fake_" + uuid.NewString()
	f.payments[req.Reference] = &fakePayment{providerRef: ref, amount: req.AmountXOF, status: ProviderPending}
	return InitiateResult{
		ProviderRef:  ref,
		Instructions: "Paiement simulé : validez-le avec POST /v1/dev/payments/{id}/simulate.",
	}, nil
}

// Status implémente Provider.
func (f *FakeProvider) Status(_ context.Context, reference string) (Event, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	p, ok := f.payments[reference]
	if !ok {
		return Event{Reference: reference, Status: ProviderPending, Currency: "XOF"}, nil
	}
	return f.event(reference, p), nil
}

type fakeWebhook struct {
	EventID     string `json:"event_id"`
	Reference   string `json:"reference"`
	ProviderRef string `json:"provider_ref"`
	Status      string `json:"status"`
	AmountXOF   int64  `json:"amount_xof"`
	Currency    string `json:"currency"`
}

// ParseWebhook implémente Provider : vérifie la signature HMAC du corps brut.
func (f *FakeProvider) ParseWebhook(header http.Header, body []byte) (Event, error) {
	sig, err := hex.DecodeString(header.Get(FakeSignatureHeader))
	if err != nil || !hmac.Equal(sig, f.sign(body)) {
		return Event{}, ErrInvalidSignature
	}
	var w fakeWebhook
	if err := json.Unmarshal(body, &w); err != nil {
		return Event{}, fmt.Errorf("webhook illisible : %w", err)
	}
	return Event{
		EventID: w.EventID, Reference: w.Reference, ProviderRef: w.ProviderRef,
		Status: ProviderStatus(w.Status), AmountXOF: w.AmountXOF, Currency: w.Currency, Raw: body,
	}, nil
}

// Simulate fait aboutir (ou échouer) un paiement et retourne le webhook signé correspondant,
// tel que le prestataire l'enverrait. amountXOF < 0 : montant du paiement.
func (f *FakeProvider) Simulate(reference string, status ProviderStatus, amountXOF int64) (http.Header, []byte, error) {
	f.mu.Lock()
	p, ok := f.payments[reference]
	if !ok {
		f.mu.Unlock()
		return nil, nil, fmt.Errorf("paiement simulé inconnu : %s", reference)
	}
	p.status = status
	if amountXOF < 0 {
		amountXOF = p.amount
	}
	ev := fakeWebhook{
		EventID: "evt_" + uuid.NewString(), Reference: reference, ProviderRef: p.providerRef,
		Status: string(status), AmountXOF: amountXOF, Currency: "XOF",
	}
	f.mu.Unlock()
	return f.SignedWebhook(ev)
}

// SignedWebhook signe un corps de webhook (tests : rejouer, falsifier un montant...).
func (f *FakeProvider) SignedWebhook(ev any) (http.Header, []byte, error) {
	body, err := json.Marshal(ev)
	if err != nil {
		return nil, nil, err
	}
	h := http.Header{}
	h.Set("Content-Type", "application/json")
	h.Set(FakeSignatureHeader, hex.EncodeToString(f.sign(body)))
	return h, body, nil
}

// Payout implémente Provider.
func (f *FakeProvider) Payout(_ context.Context, req PayoutRequest) (PayoutResult, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if r, ok := f.payouts[req.Reference]; ok {
		return r, nil
	}
	r := PayoutResult{ProviderRef: "fakepo_" + uuid.NewString(), Status: ProviderSucceeded}
	if strings.HasSuffix(req.Phone, "0000") {
		r.Status, r.FailureReason = ProviderFailed, "Numéro refusé par l'opérateur (simulation)."
	}
	f.payouts[req.Reference] = r
	return r, nil
}

// PayoutStatus implémente Provider.
func (f *FakeProvider) PayoutStatus(_ context.Context, reference string) (PayoutResult, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	r, ok := f.payouts[reference]
	if !ok {
		return PayoutResult{}, ErrPayoutNotFound
	}
	return r, nil
}

func (f *FakeProvider) event(reference string, p *fakePayment) Event {
	return Event{
		EventID: "status_" + reference + "_" + string(p.status), Reference: reference, ProviderRef: p.providerRef,
		Status: p.status, AmountXOF: p.amount, Currency: "XOF",
	}
}

func (f *FakeProvider) sign(body []byte) []byte {
	h := hmac.New(sha256.New, f.secret)
	h.Write(body)
	return h.Sum(nil)
}

var _ Provider = (*FakeProvider)(nil)
