// Package payments gère les paiements Mobile Money, les notifications du prestataire et les
// remboursements (ADR 0007).
//
// Règles :
//   - un paiement n'est réussi que sur un événement vérifié du prestataire (webhook signé ou
//     revérification par son API), jamais sur une information venant de l'app ;
//   - le montant et la devise reçus sont comparés au paiement attendu ;
//   - chaque événement est enregistré une seule fois (payment_events, unique par prestataire et
//     identifiant) et traité en tâche de fond : le webhook répond tout de suite ;
//   - un remboursement n'est écrit dans refunds qu'une fois son résultat connu (ajout seul).
package payments

import (
	"context"
	"crypto/rand"
	"encoding/base32"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"slices"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/riverqueue/river"

	"ivia/backend/internal/admin"
	"ivia/backend/internal/notifications"
	"ivia/backend/internal/orders"
	"ivia/backend/internal/payments/store"
	"ivia/backend/internal/platform/apperr"
	"ivia/backend/internal/platform/database"
	"ivia/backend/internal/platform/jobs"
	"ivia/backend/internal/platform/validate"
)

// Status d'un paiement.
type Status string

const (
	StatusPending       Status = "pending"
	StatusSucceeded     Status = "succeeded"
	StatusFailed        Status = "failed"
	StatusExpired       Status = "expired"
	StatusRefundPending Status = "refund_pending"
	StatusRefunded      Status = "refunded"
)

// pendingGiveUpAfter : un paiement encore en attente chez le prestataire après ce délai est expiré.
const pendingGiveUpAfter = time.Hour

// Nouvelles demandes de paiement, par acheteur et par numéro payeur : avec l'annulation, sans
// limite, on pourrait envoyer des demandes en boucle vers le numéro d'un tiers, depuis un ou
// plusieurs comptes. Comptées dans la table payments (checkRequestLimits) : la limite survit aux
// redémarrages et aux déploiements ; deux requêtes simultanées peuvent la dépasser d'une unité.
const (
	requestLimit       = 10
	requestLimitWindow = time.Hour
)

// Raisons d'échec posées par ivia sans que le prestataire le sache : il peut encore faire aboutir
// ces demandes, qui restent revérifiées pendant pendingGiveUpAfter.
const (
	cancelledByBuyer    = "Annulé par l'acheteur."
	providerUnreachable = "Prestataire injoignable."
)

var reopenableReasons = []string{cancelledByBuyer, providerUnreachable}

// Payment est la vue d'un paiement.
type Payment struct {
	ID            uuid.UUID `json:"id"`
	OrderID       uuid.UUID `json:"order_id"`
	Status        Status    `json:"status"`
	AmountXOF     int64     `json:"amount_xof"`
	Currency      string    `json:"currency"`
	Operator      Operator  `json:"operator"`
	PhoneMasked   string    `json:"phone_masked"`
	FailureReason string    `json:"failure_reason"`
	IsDuplicate   bool      `json:"is_duplicate"`
	Instructions  string    `json:"instructions,omitempty"`
	CreatedAt     time.Time `json:"created_at"`
	UpdatedAt     time.Time `json:"updated_at"`
}

// AdminPayment ajoute les références techniques (back-office).
type AdminPayment struct {
	Payment
	BuyerID     uuid.UUID     `json:"buyer_id"`
	Provider    string        `json:"provider"`
	Reference   string        `json:"reference"`
	ProviderRef *string       `json:"provider_ref"`
	SucceededAt *time.Time    `json:"succeeded_at"`
	Events      []EventRecord `json:"events,omitempty"`
}

// EventRecord est un événement reçu du prestataire (sans le contenu brut).
type EventRecord struct {
	ID         int64     `json:"id"`
	Source     string    `json:"source"`
	EventID    string    `json:"event_id"`
	Status     string    `json:"status"`
	AmountXOF  int64     `json:"amount_xof"`
	Currency   string    `json:"currency"`
	ReceivedAt time.Time `json:"received_at"`
}

// Refund est un remboursement exécuté (réussi ou échoué).
type Refund struct {
	ID            uuid.UUID `json:"id"`
	PaymentID     uuid.UUID `json:"payment_id"`
	OrderID       uuid.UUID `json:"order_id"`
	AmountXOF     int64     `json:"amount_xof"`
	Status        string    `json:"status"`
	FailureReason string    `json:"failure_reason"`
	Reason        string    `json:"reason"`
	RequestedBy   uuid.UUID `json:"requested_by"`
	RequestedAt   time.Time `json:"requested_at"`
	CreatedAt     time.Time `json:"created_at"`
	ProviderRef   *string   `json:"provider_ref"`
}

// Service gère les paiements.
type Service struct {
	db       *database.DB
	jobs     jobs.Enqueuer
	provider Provider
	orders   *orders.Service
	audit    *admin.Service
	notify   *notifications.Service
	logger   *slog.Logger
}

// NewService crée le service.
func NewService(db *database.DB, enq jobs.Enqueuer, provider Provider, ord *orders.Service, audit *admin.Service, notify *notifications.Service, logger *slog.Logger) *Service {
	return &Service{db: db, jobs: enq, provider: provider, orders: ord, audit: audit, notify: notify, logger: logger}
}

// Provider retourne le prestataire configuré.
func (s *Service) Provider() Provider { return s.provider }

var errNotFound = apperr.NotFound("payment_not_found", "Paiement introuvable.")

// Initiate lance le paiement d'une commande de l'acheteur. S'il y a déjà un paiement en attente,
// il est retourné (un seul paiement en cours par commande).
func (s *Service) Initiate(ctx context.Context, buyerID, orderID uuid.UUID, operator Operator, phone string) (Payment, error) {
	v := validate.New()
	v.Check(operator == OperatorFlooz || operator == OperatorTMoney, "operator", "Opérateur attendu : flooz ou tmoney.")
	normalized, ok := validate.NormalizeTogoPhone(phone)
	v.Check(ok, "phone", "Numéro Mobile Money togolais invalide.")
	if err := v.Err(); err != nil {
		return Payment{}, err
	}
	order, err := s.orders.RequirePayable(ctx, buyerID, orderID)
	if err != nil {
		return Payment{}, err
	}

	q := store.New(s.db.Pool)
	if cur, err := q.PendingPaymentForOrder(ctx, orderID); err == nil {
		return toPayment(cur), nil
	} else if !database.IsNoRows(err) {
		return Payment{}, fmt.Errorf("lecture du paiement en cours : %w", err)
	}
	// Seule une demande envoyée au payeur compte : rendre la demande en attente n'envoie rien, et
	// une demande qui n'a pas atteint le prestataire n'est pas comptée.
	if err := s.checkRequestLimits(ctx, q, buyerID, normalized); err != nil {
		return Payment{}, err
	}
	row, err := q.CreatePayment(ctx, store.CreatePaymentParams{
		OrderID: orderID, BuyerID: buyerID, Provider: s.provider.Name(), Reference: newReference("ivp"),
		AmountXof: order.TotalXOF, Operator: string(operator), PayerPhone: normalized,
	})
	if database.IsUniqueViolation(err, "payments_one_pending_per_order") {
		// Une autre requête a créé la demande en même temps.
		cur, err := q.PendingPaymentForOrder(ctx, orderID)
		if err != nil {
			return Payment{}, fmt.Errorf("lecture du paiement en cours : %w", err)
		}
		return toPayment(cur), nil
	}
	if err != nil {
		return Payment{}, fmt.Errorf("création du paiement : %w", err)
	}

	// Appel au prestataire hors transaction : on ne garde jamais un verrou pendant un appel réseau.
	res, err := s.provider.Initiate(ctx, InitiateRequest{
		Reference: row.Reference, AmountXOF: row.AmountXof, Operator: operator, Phone: normalized,
		Description: "Commande " + order.Reference,
	})
	if err != nil {
		s.logger.Error("lancement du paiement impossible", "payment_id", row.ID, "err", err)
		_, _ = q.SetPaymentStatus(ctx, store.SetPaymentStatusParams{
			ID: row.ID, NewStatus: string(StatusFailed), FailureReason: providerUnreachable, FromStatuses: []string{string(StatusPending)},
		})
		return Payment{}, apperr.Unavailable("payment_provider_unavailable", "Le paiement n'a pas pu être lancé. Réessayez dans un instant.")
	}
	if err := q.SetProviderRef(ctx, store.SetProviderRefParams{ID: row.ID, ProviderRef: &res.ProviderRef}); err != nil {
		return Payment{}, fmt.Errorf("enregistrement de la référence : %w", err)
	}
	p := toPayment(row)
	p.Instructions = res.Instructions
	return p, nil
}

// checkRequestLimits refuse une nouvelle demande au-delà de requestLimit par heure, par acheteur
// puis par numéro payeur ; Retry-After indique quand la plus ancienne sort de la fenêtre.
func (s *Service) checkRequestLimits(ctx context.Context, q *store.Queries, buyerID uuid.UUID, phone string) error {
	now := time.Now()
	since := now.Add(-requestLimitWindow)
	retry := func(oldest time.Time) int {
		return max(1, int(oldest.Add(requestLimitWindow).Sub(now).Seconds())+1)
	}
	byBuyer, err := q.RecentRequestsByBuyer(ctx, store.RecentRequestsByBuyerParams{BuyerID: buyerID, Since: since, NotSent: providerUnreachable})
	if err != nil {
		return fmt.Errorf("décompte des demandes de paiement : %w", err)
	}
	if byBuyer.N >= requestLimit {
		return apperr.TooManyRequests("rate_limited", "Trop de demandes de paiement. Réessayez plus tard.", retry(byBuyer.Oldest))
	}
	toPhone, err := q.RecentRequestsToPhone(ctx, store.RecentRequestsToPhoneParams{PayerPhone: phone, Since: since, NotSent: providerUnreachable})
	if err != nil {
		return fmt.Errorf("décompte des demandes de paiement : %w", err)
	}
	if toPhone.N >= requestLimit {
		return apperr.TooManyRequests("rate_limited", "Trop de demandes de paiement vers ce numéro. Réessayez plus tard.", retry(toPhone.Oldest))
	}
	return nil
}

// GetForBuyer retourne un paiement de l'acheteur.
func (s *Service) GetForBuyer(ctx context.Context, buyerID, id uuid.UUID) (Payment, error) {
	row, err := store.New(s.db.Conn(ctx)).GetPayment(ctx, id)
	if database.IsNoRows(err) || (err == nil && row.BuyerID != buyerID) {
		return Payment{}, errNotFound
	}
	if err != nil {
		return Payment{}, fmt.Errorf("lecture du paiement : %w", err)
	}
	return toPayment(row), nil
}

// Cancel abandonne une demande de paiement en attente de l'acheteur : elle passe en échec, ce qui
// permet d'en lancer une autre (autre numéro, autre opérateur). Le prestataire n'est pas prévenu :
// une validation tardive arrive par webhook et reste appliquée (applySuccess part aussi de
// failed) ; deux demandes réussies font un doublon à rembourser. Idempotent.
func (s *Service) Cancel(ctx context.Context, buyerID, paymentID uuid.UUID) (Payment, error) {
	q := store.New(s.db.Conn(ctx))
	if _, err := s.GetForBuyer(ctx, buyerID, paymentID); err != nil {
		return Payment{}, err
	}
	if _, err := q.SetPaymentStatus(ctx, store.SetPaymentStatusParams{
		ID: paymentID, NewStatus: string(StatusFailed), FailureReason: cancelledByBuyer,
		FromStatuses: []string{string(StatusPending)},
	}); err != nil {
		return Payment{}, fmt.Errorf("annulation du paiement : %w", err)
	}
	// Relu après la transition conditionnelle : un webhook a pu la croiser.
	p, err := s.GetForBuyer(ctx, buyerID, paymentID)
	if err != nil {
		return Payment{}, err
	}
	switch p.Status {
	case StatusFailed, StatusExpired:
		return p, nil
	default:
		return Payment{}, apperr.Conflict("payment_not_cancellable", "Ce paiement est déjà confirmé : il ne peut plus être annulé.")
	}
}

// ListForOrder retourne les paiements d'une commande de l'acheteur.
func (s *Service) ListForOrder(ctx context.Context, buyerID, orderID uuid.UUID) ([]Payment, error) {
	isBuyer, err := s.orders.IsBuyerOf(ctx, buyerID, orderID)
	if err != nil {
		return nil, err
	}
	if !isBuyer {
		return nil, apperr.NotFound("order_not_found", "Commande introuvable.")
	}
	rows, err := store.New(s.db.Conn(ctx)).ListOrderPayments(ctx, orderID)
	if err != nil {
		return nil, fmt.Errorf("liste des paiements : %w", err)
	}
	out := make([]Payment, len(rows))
	for i, r := range rows {
		out[i] = toPayment(r)
	}
	return out, nil
}

// --- Événements du prestataire --------------------------------------------------------------

// HandleWebhook enregistre une notification dont la signature a été vérifiée
// (Provider.ParseWebhook), puis planifie son traitement. Un événement déjà reçu est ignoré.
func (s *Service) HandleWebhook(ctx context.Context, ev Event) error {
	return s.record(ctx, "webhook", ev)
}

func (s *Service) record(ctx context.Context, source string, ev Event) error {
	if ev.EventID == "" || ev.Reference == "" {
		return apperr.BadRequest("invalid_event", "Événement incomplet.")
	}
	payload := ev.Raw
	if len(payload) == 0 || !json.Valid(payload) {
		payload, _ = json.Marshal(map[string]any{"status": ev.Status, "amount_xof": ev.AmountXOF, "currency": ev.Currency})
	}
	return s.db.InTx(ctx, func(ctx context.Context) error {
		id, err := store.New(s.db.Conn(ctx)).InsertEvent(ctx, store.InsertEventParams{
			Provider: s.provider.Name(), Source: source, EventID: ev.EventID, Reference: ev.Reference,
			Status: string(ev.Status), AmountXof: ev.AmountXOF, Currency: ev.Currency, Payload: payload,
		})
		if database.IsNoRows(err) {
			return nil // déjà reçu : déjà traité ou en cours de traitement
		}
		if err != nil {
			return fmt.Errorf("enregistrement de l'événement : %w", err)
		}
		return s.jobs.Enqueue(ctx, ProcessEventArgs{EventID: id}, nil)
	})
}

// processEvent applique un événement enregistré. Rejouable sans effet en double.
func (s *Service) processEvent(ctx context.Context, eventID int64) error {
	q := store.New(s.db.Conn(ctx))
	ev, err := q.GetEvent(ctx, eventID)
	if err != nil {
		return fmt.Errorf("lecture de l'événement : %w", err)
	}
	pay, err := q.GetPaymentByReference(ctx, ev.Reference)
	if database.IsNoRows(err) {
		s.logger.Warn("événement de paiement pour une référence inconnue", "event_id", eventID)
		return nil
	}
	if err != nil {
		return fmt.Errorf("lecture du paiement : %w", err)
	}

	switch ProviderStatus(ev.Status) {
	case ProviderSucceeded:
		if ev.AmountXof != pay.AmountXof || ev.Currency != pay.Currency {
			// Montant différent du montant attendu : la commande n'est pas validée, le paiement passe en
			// échec (il ne reste pas en attente indéfiniment) et l'admin vérifie auprès du prestataire.
			s.logger.Error("montant de paiement incohérent", "payment_id", pay.ID, "expected", pay.AmountXof, "received", ev.AmountXof)
			if _, err := q.SetPaymentStatus(ctx, store.SetPaymentStatusParams{
				ID: pay.ID, NewStatus: string(StatusFailed), FailureReason: "Montant reçu différent du montant attendu : vérification en cours.",
				FromStatuses: []string{string(StatusPending)},
			}); err != nil {
				return fmt.Errorf("paiement incohérent : %w", err)
			}
			return s.notify.NotifyAdmins(ctx, "payment_amount_mismatch", "Paiement incohérent",
				"Montant reçu différent du montant attendu pour un paiement : vérification manuelle nécessaire.",
				map[string]string{"payment_id": pay.ID.String(), "order_id": pay.OrderID.String()})
		}
		return s.applySuccess(ctx, pay.ID)
	case ProviderFailed:
		_, err := q.SetPaymentStatus(ctx, store.SetPaymentStatusParams{
			ID: pay.ID, NewStatus: string(StatusFailed), FailureReason: "Paiement refusé ou annulé.",
			FromStatuses: []string{string(StatusPending)},
		})
		return err
	}
	return nil
}

// applySuccess marque le paiement réussi et transmet l'information à la commande, atomiquement.
func (s *Service) applySuccess(ctx context.Context, paymentID uuid.UUID) error {
	return s.db.InTx(ctx, func(ctx context.Context) error {
		q := store.New(s.db.Conn(ctx))
		pay, err := q.LockPayment(ctx, paymentID)
		if err != nil {
			return fmt.Errorf("verrou du paiement : %w", err)
		}
		switch Status(pay.Status) {
		case StatusPending, StatusFailed, StatusExpired:
		default:
			return nil // déjà réussi : événement rejoué
		}
		if _, err := q.SetPaymentStatus(ctx, store.SetPaymentStatusParams{
			ID: pay.ID, NewStatus: string(StatusSucceeded), FromStatuses: []string{pay.Status},
		}); err != nil {
			return fmt.Errorf("paiement réussi : %w", err)
		}
		outcome, err := s.orders.OnPaymentSucceeded(ctx, pay.OrderID)
		if err != nil {
			return err
		}
		if outcome == orders.PaymentDuplicate {
			if _, err := q.SetPaymentStatus(ctx, store.SetPaymentStatusParams{
				ID: pay.ID, NewStatus: string(StatusSucceeded), IsDuplicate: true, FromStatuses: []string{string(StatusSucceeded)},
			}); err != nil {
				return fmt.Errorf("paiement en double : %w", err)
			}
			return s.notify.NotifyAdmins(ctx, "payment_duplicate", "Paiement en double",
				"Une commande a été payée deux fois : le second paiement est à rembourser.",
				map[string]string{"payment_id": pay.ID.String(), "order_id": pay.OrderID.String()})
		}
		return nil
	})
}

// Recheck revérifie auprès du prestataire les paiements restés en attente, et ceux abandonnés
// côté ivia depuis moins de pendingGiveUpAfter (un webhook perdu n'est ainsi jamais ignoré).
// Tâche périodique.
func (s *Service) Recheck(ctx context.Context) error {
	rows, err := store.New(s.db.Conn(ctx)).PaymentsToRecheck(ctx, store.PaymentsToRecheckParams{
		ReopenableReasons: reopenableReasons, Since: time.Now().Add(-pendingGiveUpAfter),
	})
	if err != nil {
		return fmt.Errorf("paiements à revérifier : %w", err)
	}
	for _, p := range rows {
		if err := s.recheckOne(ctx, p, false); err != nil {
			s.logger.Error("revérification impossible", "payment_id", p.ID, "err", err)
		}
	}
	return nil
}

// VerifyNow revérifie un paiement à la demande d'un admin.
func (s *Service) VerifyNow(ctx context.Context, paymentID uuid.UUID) (AdminPayment, error) {
	p, err := store.New(s.db.Conn(ctx)).GetPayment(ctx, paymentID)
	if database.IsNoRows(err) {
		return AdminPayment{}, errNotFound
	}
	if err != nil {
		return AdminPayment{}, fmt.Errorf("lecture du paiement : %w", err)
	}
	// L'admin peut revérifier toute demande non aboutie : un paiement débité après une annulation
	// ou une expiration est alors appliqué.
	if err := s.recheckOne(ctx, p, true); err != nil {
		return AdminPayment{}, err
	}
	return s.AdminGet(ctx, paymentID)
}

// recheckOne demande au prestataire l'état d'une demande en attente ou, si reopened l'autorise,
// d'une demande close côté ivia (failed, expired) : une réussite y est appliquée (applySuccess
// part aussi de failed et expired). force : toute demande failed ou expired (admin) ; sinon
// seulement celles abandonnées sans que le prestataire le sache.
func (s *Service) recheckOne(ctx context.Context, p store.Payment, force bool) error {
	switch Status(p.Status) {
	case StatusPending:
	case StatusFailed, StatusExpired:
		if !force && !slices.Contains(reopenableReasons, p.FailureReason) {
			return nil
		}
	default:
		return nil
	}
	ev, err := s.provider.Status(ctx, p.Reference)
	if err != nil {
		return fmt.Errorf("statut chez le prestataire : %w", err)
	}
	if ev.Status == ProviderPending {
		if Status(p.Status) == StatusPending && time.Since(p.CreatedAt) > pendingGiveUpAfter {
			_, err := store.New(s.db.Conn(ctx)).SetPaymentStatus(ctx, store.SetPaymentStatusParams{
				ID: p.ID, NewStatus: string(StatusExpired), FailureReason: "Aucune confirmation du prestataire.",
				FromStatuses: []string{string(StatusPending)},
			})
			return err
		}
		return nil
	}
	if ev.EventID == "" {
		ev.EventID = "verify:" + p.Reference + ":" + string(ev.Status)
	}
	return s.record(ctx, "verify", ev)
}

// --- Remboursements -------------------------------------------------------------------------

// RefundOrder déclenche le remboursement d'une commande de la file (admin, journalisé).
func (s *Service) RefundOrder(ctx context.Context, adminID, orderID uuid.UUID, reason string) (AdminPayment, error) {
	o, err := s.orders.RequireRefundable(ctx, orderID)
	if err != nil {
		return AdminPayment{}, err
	}
	pay, err := store.New(s.db.Conn(ctx)).RefundablePaymentForOrder(ctx, orderID)
	if database.IsNoRows(err) {
		return AdminPayment{}, apperr.Conflict("refund_in_progress", "Un remboursement est déjà en cours pour cette commande.")
	}
	if err != nil {
		return AdminPayment{}, fmt.Errorf("lecture du paiement : %w", err)
	}
	if o.RefundDueXOF > pay.AmountXof {
		return AdminPayment{}, fmt.Errorf("montant à rembourser supérieur au paiement (%d > %d)", o.RefundDueXOF, pay.AmountXof)
	}
	return s.startRefund(ctx, adminID, pay, o.RefundDueXOF, false, reason)
}

// RefundDuplicate rembourse un paiement reçu en double (admin, journalisé).
func (s *Service) RefundDuplicate(ctx context.Context, adminID, paymentID uuid.UUID, reason string) (AdminPayment, error) {
	pay, err := store.New(s.db.Conn(ctx)).GetPayment(ctx, paymentID)
	if database.IsNoRows(err) {
		return AdminPayment{}, errNotFound
	}
	if err != nil {
		return AdminPayment{}, fmt.Errorf("lecture du paiement : %w", err)
	}
	if !pay.IsDuplicate || Status(pay.Status) != StatusSucceeded {
		return AdminPayment{}, apperr.Conflict("not_refundable", "Ce paiement n'est pas un paiement en double à rembourser.")
	}
	return s.startRefund(ctx, adminID, pay, pay.AmountXof, true, reason)
}

func (s *Service) startRefund(ctx context.Context, adminID uuid.UUID, pay store.Payment, amount int64, duplicate bool, reason string) (AdminPayment, error) {
	reason = validate.Clean(reason)
	err := s.db.InTx(ctx, func(ctx context.Context) error {
		n, err := store.New(s.db.Conn(ctx)).SetPaymentStatus(ctx, store.SetPaymentStatusParams{
			ID: pay.ID, NewStatus: string(StatusRefundPending), FromStatuses: []string{string(StatusSucceeded)},
		})
		if err != nil {
			return fmt.Errorf("remboursement : %w", err)
		}
		if n == 0 {
			return apperr.Conflict("refund_in_progress", "Un remboursement est déjà en cours pour ce paiement.")
		}
		if err := s.audit.Record(ctx, admin.AuditEntry{
			AdminID: &adminID, Action: "payment.refund_requested", TargetType: "payment", TargetID: pay.ID.String(),
			After: map[string]any{"order_id": pay.OrderID, "amount_xof": amount, "duplicate": duplicate}, Reason: reason,
		}); err != nil {
			return err
		}
		return s.jobs.Enqueue(ctx, ExecuteRefundArgs{
			PaymentID: pay.ID, OrderID: pay.OrderID, AmountXOF: amount, Duplicate: duplicate,
			Reference: newReference("ivr"), Reason: reason, RequestedBy: adminID, RequestedAt: time.Now(),
		}, nil)
	})
	if err != nil {
		return AdminPayment{}, err
	}
	return s.AdminGet(ctx, pay.ID)
}

// executeRefund demande le transfert puis enregistre son résultat. Rejouable : l'état du
// transfert est d'abord demandé au prestataire par sa référence.
func (s *Service) executeRefund(ctx context.Context, a ExecuteRefundArgs) error {
	pay, err := store.New(s.db.Conn(ctx)).GetPayment(ctx, a.PaymentID)
	if err != nil {
		return fmt.Errorf("lecture du paiement : %w", err)
	}
	if Status(pay.Status) != StatusRefundPending {
		return nil // déjà conclu
	}
	res, err := s.provider.PayoutStatus(ctx, a.Reference)
	if errors.Is(err, ErrPayoutNotFound) {
		res, err = s.provider.Payout(ctx, PayoutRequest{
			Reference: a.Reference, AmountXOF: a.AmountXOF, Operator: Operator(pay.Operator), Phone: pay.PayerPhone, Reason: a.Reason,
		})
	}
	if err != nil {
		return fmt.Errorf("transfert de remboursement : %w", err) // River réessaiera
	}
	if res.Status == ProviderPending {
		return river.JobSnooze(time.Minute)
	}

	return s.db.InTx(ctx, func(ctx context.Context) error {
		q := store.New(s.db.Conn(ctx))
		var providerRef *string
		if res.ProviderRef != "" {
			providerRef = &res.ProviderRef
		}
		if _, err := q.InsertRefund(ctx, store.InsertRefundParams{
			PaymentID: pay.ID, OrderID: pay.OrderID, Reference: a.Reference, AmountXof: a.AmountXOF,
			Status: string(res.Status), ProviderRef: providerRef, FailureReason: res.FailureReason,
			Reason: a.Reason, RequestedBy: a.RequestedBy, RequestedAt: a.RequestedAt,
		}); err != nil {
			return fmt.Errorf("enregistrement du remboursement : %w", err)
		}
		if res.Status == ProviderFailed {
			if _, err := q.SetPaymentStatus(ctx, store.SetPaymentStatusParams{
				ID: pay.ID, NewStatus: string(StatusSucceeded), FromStatuses: []string{string(StatusRefundPending)},
			}); err != nil {
				return err
			}
			return s.notify.NotifyAdmins(ctx, "refund_failed", "Remboursement échoué",
				"Le transfert de remboursement a échoué : "+res.FailureReason,
				map[string]string{"payment_id": pay.ID.String(), "order_id": pay.OrderID.String()})
		}
		if _, err := q.SetPaymentStatus(ctx, store.SetPaymentStatusParams{
			ID: pay.ID, NewStatus: string(StatusRefunded), FromStatuses: []string{string(StatusRefundPending)},
		}); err != nil {
			return err
		}
		if a.Duplicate {
			return s.notify.Notify(ctx, notifications.Message{
				UserID: pay.BuyerID, App: notifications.AppBuyer, Kind: "payment_refunded", Title: "Remboursement effectué",
				Body: "Votre paiement en double a été remboursé sur votre compte Mobile Money.", Data: map[string]string{"order_id": pay.OrderID.String()},
			})
		}
		return s.orders.MarkRefunded(ctx, pay.OrderID, a.RequestedBy)
	})
}

// --- Back-office ----------------------------------------------------------------------------

// AdminFilter filtre la liste des paiements.
type AdminFilter struct {
	Status         Status
	OrderID        *uuid.UUID
	DuplicatesOnly bool
}

// AdminList liste les paiements.
func (s *Service) AdminList(ctx context.Context, f AdminFilter, limit, offset int32) ([]AdminPayment, error) {
	var st *string
	if f.Status != "" {
		v := string(f.Status)
		st = &v
	}
	rows, err := store.New(s.db.Conn(ctx)).ListPayments(ctx, store.ListPaymentsParams{
		Status: st, OrderID: f.OrderID, DuplicatesOnly: f.DuplicatesOnly, Lim: limit, Off: offset,
	})
	if err != nil {
		return nil, fmt.Errorf("liste des paiements : %w", err)
	}
	out := make([]AdminPayment, len(rows))
	for i, r := range rows {
		out[i] = toAdminPayment(r)
	}
	return out, nil
}

// AdminGet retourne un paiement avec ses événements.
func (s *Service) AdminGet(ctx context.Context, id uuid.UUID) (AdminPayment, error) {
	q := store.New(s.db.Conn(ctx))
	r, err := q.GetPayment(ctx, id)
	if database.IsNoRows(err) {
		return AdminPayment{}, errNotFound
	}
	if err != nil {
		return AdminPayment{}, fmt.Errorf("lecture du paiement : %w", err)
	}
	p := toAdminPayment(r)
	evs, err := q.ListEventsByReference(ctx, r.Reference)
	if err != nil {
		return AdminPayment{}, fmt.Errorf("événements du paiement : %w", err)
	}
	p.Events = make([]EventRecord, len(evs))
	for i, e := range evs {
		p.Events[i] = EventRecord{ID: e.ID, Source: e.Source, EventID: e.EventID, Status: e.Status, AmountXOF: e.AmountXof, Currency: e.Currency, ReceivedAt: e.ReceivedAt}
	}
	return p, nil
}

// ListRefunds liste les remboursements exécutés.
func (s *Service) ListRefunds(ctx context.Context, orderID *uuid.UUID, limit, offset int32) ([]Refund, error) {
	rows, err := store.New(s.db.Conn(ctx)).ListRefunds(ctx, store.ListRefundsParams{OrderID: orderID, Lim: limit, Off: offset})
	if err != nil {
		return nil, fmt.Errorf("liste des remboursements : %w", err)
	}
	out := make([]Refund, len(rows))
	for i, r := range rows {
		out[i] = Refund{
			ID: r.ID, PaymentID: r.PaymentID, OrderID: r.OrderID, AmountXOF: r.AmountXof, Status: r.Status,
			FailureReason: r.FailureReason, Reason: r.Reason, RequestedBy: r.RequestedBy, RequestedAt: r.RequestedAt,
			CreatedAt: r.CreatedAt, ProviderRef: r.ProviderRef,
		}
	}
	return out, nil
}

// PendingOlderThan compte les paiements en attente depuis plus de d (indicateur back-office).
func (s *Service) PendingOlderThan(ctx context.Context, d time.Duration) (int64, error) {
	n, err := store.New(s.db.Conn(ctx)).PendingPaymentsOlderThan(ctx, time.Now().Add(-d))
	if err != nil {
		return 0, fmt.Errorf("paiements en attente : %w", err)
	}
	return n, nil
}

func toPayment(r store.Payment) Payment {
	return Payment{
		ID: r.ID, OrderID: r.OrderID, Status: Status(r.Status), AmountXOF: r.AmountXof, Currency: r.Currency,
		Operator: Operator(r.Operator), PhoneMasked: validate.MaskPhone(r.PayerPhone), FailureReason: r.FailureReason,
		IsDuplicate: r.IsDuplicate, CreatedAt: r.CreatedAt, UpdatedAt: r.UpdatedAt,
	}
}

func toAdminPayment(r store.Payment) AdminPayment {
	return AdminPayment{
		Payment: toPayment(r), BuyerID: r.BuyerID, Provider: r.Provider, Reference: r.Reference,
		ProviderRef: r.ProviderRef, SucceededAt: r.SucceededAt,
	}
}

// newReference génère une référence unique transmise au prestataire (ex. ivp_K3J9...).
func newReference(prefix string) string {
	b := make([]byte, 15)
	_, _ = rand.Read(b)
	return prefix + "_" + strings.ToLower(base32.StdEncoding.WithPadding(base32.NoPadding).EncodeToString(b))
}
