package pharmacy

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/riverqueue/river"

	"ivia/backend/internal/admin"
	"ivia/backend/internal/notifications"
	"ivia/backend/internal/payments"
	"ivia/backend/internal/pharmacy/store"
	"ivia/backend/internal/platform/apperr"
	"ivia/backend/internal/platform/database"
	"ivia/backend/internal/platform/validate"
)

// Statuts d'un paiement (mêmes valeurs que les paiements de commandes).
const (
	PayPending       = "pending"
	PaySucceeded     = "succeeded"
	PayFailed        = "failed"
	PayExpired       = "expired"
	PayRefundPending = "refund_pending"
	PayRefunded      = "refunded"
)

// PayInput : numéro Mobile Money du payeur.
type PayInput struct {
	Operator string `json:"operator"`
	Phone    string `json:"phone"`
}

// Payment est un paiement du module (déblocage ou livraison).
type Payment struct {
	ID            uuid.UUID  `json:"id"`
	Purpose       string     `json:"purpose"`
	AlertID       uuid.UUID  `json:"alert_id"`
	ReservationID *uuid.UUID `json:"reservation_id"`
	Status        string     `json:"status"`
	AmountXOF     int64      `json:"amount_xof"`
	Currency      string     `json:"currency"`
	Operator      string     `json:"operator"`
	PhoneMasked   string     `json:"phone_masked"`
	FailureReason string     `json:"failure_reason"`
	Instructions  string     `json:"instructions,omitempty"`
	CreatedAt     time.Time  `json:"created_at"`
	UpdatedAt     time.Time  `json:"updated_at"`
}

// UnlockResult : alerte après la demande de déblocage, et le paiement à valider (nul si gratuit).
type UnlockResult struct {
	Alert   Alert    `json:"alert"`
	Payment *Payment `json:"payment"`
}

var errPaymentNotFound = apperr.NotFound("payment_not_found", "Paiement introuvable.")

const cancelledByBuyer = "Annulé par le client."

func toPayment(r store.PharmacyPayment) Payment {
	return Payment{
		ID: r.ID, Purpose: r.Purpose, AlertID: r.AlertID, ReservationID: r.ReservationID, Status: r.Status,
		AmountXOF: r.AmountXof, Currency: r.Currency, Operator: r.Operator, PhoneMasked: validate.MaskPhone(r.PayerPhone),
		FailureReason: r.FailureReason, CreatedAt: r.CreatedAt, UpdatedAt: r.UpdatedAt,
	}
}

func validatePayInput(in PayInput) (string, error) {
	v := validate.New()
	v.Check(in.Operator == string(payments.OperatorFlooz) || in.Operator == string(payments.OperatorTMoney), "operator", "Opérateur attendu : flooz ou tmoney.")
	phone, ok := validate.NormalizeTogoPhone(in.Phone)
	v.Check(ok, "phone", "Numéro Mobile Money togolais invalide.")
	return phone, v.Err()
}

// Unlock débloque l'identité des pharmacies qui ont répondu : paiement forfaitaire, une fois par
// alerte. Gratuit si le forfait est réglé à 0.
func (s *Service) Unlock(ctx context.Context, buyerID, alertID uuid.UUID, in PayInput) (UnlockResult, error) {
	q := s.q(ctx)
	a, err := q.GetAlert(ctx, alertID)
	if database.IsNoRows(err) || (err == nil && a.BuyerID != buyerID) {
		return UnlockResult{}, errAlertNotFound
	}
	if err != nil {
		return UnlockResult{}, fmt.Errorf("lecture de l'alerte : %w", err)
	}
	if a.UnlockedAt != nil {
		return UnlockResult{}, apperr.Conflict("already_unlocked", "Les pharmacies de cette alerte sont déjà débloquées.")
	}
	if a.Status == AlertCancelled || a.Status == AlertFulfilled || a.Status == AlertNoResponse {
		return UnlockResult{}, apperr.Conflict("alert_closed", "Cette alerte est terminée.")
	}
	n, err := q.CountActiveResponses(ctx, alertID)
	if err != nil {
		return UnlockResult{}, fmt.Errorf("décompte des réponses : %w", err)
	}
	if n == 0 {
		return UnlockResult{}, apperr.Conflict("no_response_yet", "Aucune pharmacie n'a encore répondu : le déblocage n'est pas encore utile.")
	}
	settings, err := s.Settings(ctx)
	if err != nil {
		return UnlockResult{}, err
	}
	var pay *Payment
	if settings.UnlockFeeXOF == 0 {
		if _, err := q.MarkUnlocked(ctx, alertID); err != nil {
			return UnlockResult{}, fmt.Errorf("déblocage : %w", err)
		}
	} else {
		if cur, err := q.PendingUnlockPayment(ctx, alertID); err == nil {
			p := toPayment(cur)
			pay = &p
		} else if !database.IsNoRows(err) {
			return UnlockResult{}, fmt.Errorf("paiement en cours : %w", err)
		} else {
			phone, err := validatePayInput(in)
			if err != nil {
				return UnlockResult{}, err
			}
			p, err := s.initiate(ctx, store.CreatePaymentParams{
				Purpose: "unlock", AlertID: alertID, BuyerID: buyerID, AmountXof: settings.UnlockFeeXOF,
				Operator: in.Operator, PayerPhone: phone,
			}, "Déblocage alerte médicament", "pharmacy_payments_one_pending_unlock", func(ctx context.Context) (store.PharmacyPayment, error) {
				return s.q(ctx).PendingUnlockPayment(ctx, alertID)
			})
			if err != nil {
				return UnlockResult{}, err
			}
			pay = &p
		}
	}
	al, err := s.GetAlert(ctx, buyerID, alertID)
	if err != nil {
		return UnlockResult{}, err
	}
	return UnlockResult{Alert: al, Payment: pay}, nil
}

// PayReservation lance le paiement d'une livraison (médicament + frais de livraison).
func (s *Service) PayReservation(ctx context.Context, buyerID, reservationID uuid.UUID, in PayInput) (Payment, error) {
	phone, err := validatePayInput(in)
	if err != nil {
		return Payment{}, err
	}
	r, err := s.reservationRow(ctx, reservationID)
	if err != nil {
		return Payment{}, err
	}
	if r.BuyerID != buyerID {
		return Payment{}, errReservationNotFound
	}
	if r.Status != ResAwaitingPayment || (r.ExpiresAt != nil && time.Now().After(*r.ExpiresAt)) {
		return Payment{}, apperr.Conflict("not_payable", "Cette réservation n'attend pas de paiement.")
	}
	if cur, err := s.q(ctx).PendingOrderPayment(ctx, &reservationID); err == nil {
		return toPayment(cur), nil
	} else if !database.IsNoRows(err) {
		return Payment{}, fmt.Errorf("paiement en cours : %w", err)
	}
	return s.initiate(ctx, store.CreatePaymentParams{
		Purpose: "order", AlertID: r.AlertID, ReservationID: &reservationID, BuyerID: buyerID, AmountXof: r.TotalXof,
		Operator: in.Operator, PayerPhone: phone,
	}, "Livraison de médicament", "pharmacy_payments_one_pending_order", func(ctx context.Context) (store.PharmacyPayment, error) {
		return s.q(ctx).PendingOrderPayment(ctx, &reservationID)
	})
}

// initiate crée la demande et l'envoie au prestataire (hors transaction : aucun verrou pendant
// l'appel réseau). Une demande créée en parallèle (index unique) est retournée telle quelle.
func (s *Service) initiate(ctx context.Context, p store.CreatePaymentParams, description, uniqueIdx string, pending func(context.Context) (store.PharmacyPayment, error)) (Payment, error) {
	q := s.q(ctx)
	recent, err := q.RecentRequestsByBuyer(ctx, store.RecentRequestsByBuyerParams{BuyerID: p.BuyerID, Since: time.Now().Add(-time.Hour)})
	if err != nil {
		return Payment{}, fmt.Errorf("décompte des demandes : %w", err)
	}
	if recent >= paymentRequestLimit {
		return Payment{}, apperr.TooManyRequests("rate_limited", "Trop de demandes de paiement. Réessayez plus tard.", 600)
	}
	p.Provider = s.provider.Name()
	p.Reference = payments.NewReference(ReferencePrefix)
	row, err := q.CreatePayment(ctx, p)
	if database.IsUniqueViolation(err, uniqueIdx) {
		cur, err := pending(ctx)
		if err != nil {
			return Payment{}, fmt.Errorf("lecture du paiement en cours : %w", err)
		}
		return toPayment(cur), nil
	}
	if err != nil {
		return Payment{}, fmt.Errorf("création du paiement : %w", err)
	}
	res, err := s.provider.Initiate(ctx, payments.InitiateRequest{
		Reference: row.Reference, AmountXOF: row.AmountXof, Operator: payments.Operator(row.Operator), Phone: row.PayerPhone,
		Description: description,
	})
	if err != nil {
		s.logger.Error("lancement du paiement pharmacie impossible", "payment_id", row.ID, "err", err)
		_, _ = q.SetPaymentStatus(ctx, store.SetPaymentStatusParams{
			ID: row.ID, NewStatus: PayFailed, FailureReason: "Prestataire injoignable.", FromStatuses: []string{PayPending},
		})
		return Payment{}, apperr.Unavailable("payment_provider_unavailable", "Le paiement n'a pas pu être lancé. Réessayez dans un instant.")
	}
	if err := q.SetProviderRef(ctx, store.SetProviderRefParams{ID: row.ID, ProviderRef: &res.ProviderRef}); err != nil {
		return Payment{}, fmt.Errorf("enregistrement de la référence : %w", err)
	}
	out := toPayment(row)
	out.Instructions = res.Instructions
	return out, nil
}

// GetPayment retourne un paiement du client.
func (s *Service) GetPayment(ctx context.Context, buyerID, id uuid.UUID) (Payment, error) {
	r, err := s.q(ctx).GetPayment(ctx, id)
	if database.IsNoRows(err) || (err == nil && r.BuyerID != buyerID) {
		return Payment{}, errPaymentNotFound
	}
	if err != nil {
		return Payment{}, fmt.Errorf("lecture du paiement : %w", err)
	}
	return toPayment(r), nil
}

// CancelPayment abandonne une demande en attente (autre numéro, autre opérateur). Une validation
// tardive reste appliquée (le prestataire fait foi).
func (s *Service) CancelPayment(ctx context.Context, buyerID, id uuid.UUID) (Payment, error) {
	if _, err := s.GetPayment(ctx, buyerID, id); err != nil {
		return Payment{}, err
	}
	if _, err := s.q(ctx).SetPaymentStatus(ctx, store.SetPaymentStatusParams{
		ID: id, NewStatus: PayFailed, FailureReason: cancelledByBuyer, FromStatuses: []string{PayPending},
	}); err != nil {
		return Payment{}, fmt.Errorf("annulation du paiement : %w", err)
	}
	p, err := s.GetPayment(ctx, buyerID, id)
	if err != nil {
		return Payment{}, err
	}
	if p.Status != PayFailed && p.Status != PayExpired {
		return Payment{}, apperr.Conflict("payment_not_cancellable", "Ce paiement est déjà confirmé : il ne peut plus être annulé.")
	}
	return p, nil
}

// ApplyProviderEvent applique un événement vérifié du prestataire (payments.ExternalPayments).
func (s *Service) ApplyProviderEvent(ctx context.Context, ev payments.Event) error {
	q := s.q(ctx)
	pay, err := q.GetPaymentByReference(ctx, ev.Reference)
	if database.IsNoRows(err) {
		s.logger.Warn("événement pharmacie pour une référence inconnue")
		return nil
	}
	if err != nil {
		return fmt.Errorf("lecture du paiement : %w", err)
	}
	switch ev.Status {
	case payments.ProviderSucceeded:
		if ev.AmountXOF != pay.AmountXof || ev.Currency != pay.Currency {
			s.logger.Error("montant de paiement pharmacie incohérent", "payment_id", pay.ID, "expected", pay.AmountXof, "received", ev.AmountXOF)
			if _, err := q.SetPaymentStatus(ctx, store.SetPaymentStatusParams{
				ID: pay.ID, NewStatus: PayFailed, FailureReason: "Montant reçu différent du montant attendu : vérification en cours.",
				FromStatuses: []string{PayPending},
			}); err != nil {
				return err
			}
			return s.notify.NotifyAdmins(ctx, "payment_amount_mismatch", "Paiement pharmacie incohérent",
				"Montant reçu différent du montant attendu : vérification manuelle nécessaire.",
				map[string]string{"pharmacy_payment_id": pay.ID.String()})
		}
		return s.applySuccess(ctx, pay.ID)
	case payments.ProviderFailed:
		_, err := q.SetPaymentStatus(ctx, store.SetPaymentStatusParams{
			ID: pay.ID, NewStatus: PayFailed, FailureReason: "Paiement refusé ou annulé.", FromStatuses: []string{PayPending},
		})
		return err
	}
	return nil
}

func (s *Service) applySuccess(ctx context.Context, paymentID uuid.UUID) error {
	return s.db.InTx(ctx, func(ctx context.Context) error {
		q := s.q(ctx)
		pay, err := q.LockPayment(ctx, paymentID)
		if err != nil {
			return fmt.Errorf("verrou du paiement : %w", err)
		}
		if pay.Status != PayPending && pay.Status != PayFailed && pay.Status != PayExpired {
			return nil // déjà appliqué
		}
		if _, err := q.SetPaymentStatus(ctx, store.SetPaymentStatusParams{
			ID: pay.ID, NewStatus: PaySucceeded, FromStatuses: []string{pay.Status},
		}); err != nil {
			return fmt.Errorf("paiement réussi : %w", err)
		}
		pay.Status = PaySucceeded
		if pay.Purpose == "unlock" {
			n, err := q.MarkUnlocked(ctx, pay.AlertID)
			if err != nil {
				return fmt.Errorf("déblocage : %w", err)
			}
			if n == 0 {
				// Déjà débloquée (deux paiements) : le second est remboursé.
				return s.startRefund(ctx, nil, pay, "Déblocage payé deux fois.")
			}
			return s.notify.Notify(ctx, notifications.Message{
				UserID: pay.BuyerID, App: notifications.AppBuyer, Kind: "pharmacy_unlocked",
				Title: "Pharmacies débloquées", Body: "Noms, adresses et téléphones des pharmacies sont visibles. Réservez votre médicament.",
				Data: map[string]string{"alert_id": pay.AlertID.String()},
			})
		}
		// Livraison : la réservation doit encore attendre son paiement, sinon remboursement.
		rid := *pay.ReservationID
		cur, err := q.LockReservation(ctx, rid)
		if err != nil {
			return fmt.Errorf("verrou de la réservation : %w", err)
		}
		if cur != ResAwaitingPayment {
			return s.startRefund(ctx, nil, pay, "Paiement reçu pour une réservation annulée ou expirée.")
		}
		if _, err := q.SetReservationStatus(ctx, store.SetReservationStatusParams{ID: rid, NewStatus: ResPaid, FromStatuses: []string{ResAwaitingPayment}}); err != nil {
			return fmt.Errorf("réservation payée : %w", err)
		}
		r, err := q.GetReservation(ctx, rid)
		if err != nil {
			return fmt.Errorf("lecture de la réservation : %w", err)
		}
		ph, err := q.GetPharmacy(ctx, r.PharmacyID)
		if err != nil {
			return fmt.Errorf("lecture de la pharmacie : %w", err)
		}
		if err := s.notify.Notify(ctx, notifications.Message{
			UserID: ph.OwnerID, App: notifications.AppPharmacy, Kind: "pharmacy_delivery_paid",
			Title: "Livraison payée", Body: fmt.Sprintf("Préparez %d article(s) : un livreur ivia arrive.", r.Quantity),
			Data: map[string]string{"reservation_id": rid.String()},
		}); err != nil {
			return err
		}
		if err := s.notify.Notify(ctx, notifications.Message{
			UserID: r.BuyerID, App: notifications.AppBuyer, Kind: "pharmacy_delivery_paid",
			Title: "Paiement reçu", Body: "Nous cherchons un livreur pour vous apporter votre médicament.",
			Data: map[string]string{"reservation_id": rid.String()},
		}); err != nil {
			return err
		}
		return s.jobs.Enqueue(ctx, AssignCourierArgs{ReservationID: rid}, nil)
	})
}

// Recheck revérifie auprès du prestataire les paiements en attente (webhook perdu). Tâche périodique.
func (s *Service) Recheck(ctx context.Context) error {
	rows, err := s.q(ctx).PaymentsToRecheck(ctx)
	if err != nil {
		return fmt.Errorf("paiements à revérifier : %w", err)
	}
	for _, p := range rows {
		if err := s.recheckOne(ctx, p); err != nil {
			s.logger.Error("revérification pharmacie impossible", "payment_id", p.ID, "err", err)
		}
	}
	return nil
}

func (s *Service) recheckOne(ctx context.Context, p store.PharmacyPayment) error {
	ev, err := s.provider.Status(ctx, p.Reference)
	if err != nil {
		return fmt.Errorf("statut chez le prestataire : %w", err)
	}
	if ev.Status == payments.ProviderPending {
		if time.Since(p.CreatedAt) > pendingGiveUpAfter {
			_, err := s.q(ctx).SetPaymentStatus(ctx, store.SetPaymentStatusParams{
				ID: p.ID, NewStatus: PayExpired, FailureReason: "Aucune confirmation du prestataire.", FromStatuses: []string{PayPending},
			})
			return err
		}
		return nil
	}
	return s.payments.RecordVerified(ctx, ev)
}

// --- Remboursements ---------------------------------------------------------------------------

// startRefund lance le remboursement d'un paiement réussi (transfert vers le numéro payeur).
// adminID nil : remboursement automatique (annulation, doublon). Dans une transaction.
func (s *Service) startRefund(ctx context.Context, adminID *uuid.UUID, pay store.PharmacyPayment, reason string) error {
	q := s.q(ctx)
	n, err := q.SetPaymentStatus(ctx, store.SetPaymentStatusParams{
		ID: pay.ID, NewStatus: PayRefundPending, FailureReason: pay.FailureReason, FromStatuses: []string{PaySucceeded},
	})
	if err != nil {
		return fmt.Errorf("remboursement : %w", err)
	}
	if n == 0 {
		return apperr.Conflict("refund_in_progress", "Ce paiement est déjà remboursé ou en cours de remboursement.")
	}
	ref := payments.NewReference(ReferencePrefix + "r")
	if err := q.SetRefundReference(ctx, store.SetRefundReferenceParams{ID: pay.ID, RefundReference: &ref}); err != nil {
		return fmt.Errorf("référence du remboursement : %w", err)
	}
	if err := s.admin.Record(ctx, admin.AuditEntry{
		AdminID: adminID, Action: "pharmacy.refund_requested", TargetType: "pharmacy_payment", TargetID: pay.ID.String(),
		After: map[string]any{"amount_xof": pay.AmountXof, "purpose": pay.Purpose}, Reason: reason,
	}); err != nil {
		return err
	}
	return s.jobs.Enqueue(ctx, RefundArgs{PaymentID: pay.ID}, nil)
}

// AdminRefund rembourse un paiement réussi (ex. déblocage alors qu'aucune pharmacie n'a pu
// servir le client). Journalisé.
func (s *Service) AdminRefund(ctx context.Context, adminID, paymentID uuid.UUID, reason string) (Payment, error) {
	reason = validate.Clean(reason)
	v := validate.New()
	v.Text("reason", reason, 3, 300)
	if err := v.Err(); err != nil {
		return Payment{}, err
	}
	err := s.db.InTx(ctx, func(ctx context.Context) error {
		pay, err := s.q(ctx).LockPayment(ctx, paymentID)
		if database.IsNoRows(err) {
			return errPaymentNotFound
		}
		if err != nil {
			return fmt.Errorf("verrou du paiement : %w", err)
		}
		if pay.Status != PaySucceeded {
			return apperr.Conflict("not_refundable", "Seul un paiement réussi peut être remboursé.")
		}
		return s.startRefund(ctx, &adminID, pay, reason)
	})
	if err != nil {
		return Payment{}, err
	}
	r, err := s.q(ctx).GetPayment(ctx, paymentID)
	if err != nil {
		return Payment{}, fmt.Errorf("lecture du paiement : %w", err)
	}
	return toPayment(r), nil
}

// executeRefund demande le transfert puis applique son résultat. Rejouable : l'état du transfert
// est d'abord demandé au prestataire par sa référence.
func (s *Service) executeRefund(ctx context.Context, paymentID uuid.UUID) error {
	pay, err := s.q(ctx).GetPayment(ctx, paymentID)
	if err != nil {
		return fmt.Errorf("lecture du paiement : %w", err)
	}
	if pay.Status != PayRefundPending || pay.RefundReference == nil {
		return nil
	}
	res, err := s.provider.PayoutStatus(ctx, *pay.RefundReference)
	if errors.Is(err, payments.ErrPayoutNotFound) {
		res, err = s.provider.Payout(ctx, payments.PayoutRequest{
			Reference: *pay.RefundReference, AmountXOF: pay.AmountXof, Operator: payments.Operator(pay.Operator),
			Phone: pay.PayerPhone, Reason: "Remboursement alerte médicament",
		})
	}
	if err != nil {
		return fmt.Errorf("transfert de remboursement : %w", err)
	}
	if res.Status == payments.ProviderPending {
		return river.JobSnooze(time.Minute)
	}
	return s.db.InTx(ctx, func(ctx context.Context) error {
		q := s.q(ctx)
		if res.Status == payments.ProviderFailed {
			if _, err := q.SetPaymentStatus(ctx, store.SetPaymentStatusParams{
				ID: pay.ID, NewStatus: PaySucceeded, FailureReason: "Remboursement échoué : " + res.FailureReason,
				FromStatuses: []string{PayRefundPending},
			}); err != nil {
				return err
			}
			return s.notify.NotifyAdmins(ctx, "refund_failed", "Remboursement pharmacie échoué",
				"Le transfert de remboursement a échoué : "+res.FailureReason, map[string]string{"pharmacy_payment_id": pay.ID.String()})
		}
		if _, err := q.SetPaymentStatus(ctx, store.SetPaymentStatusParams{
			ID: pay.ID, NewStatus: PayRefunded, FailureReason: pay.FailureReason, FromStatuses: []string{PayRefundPending},
		}); err != nil {
			return err
		}
		return s.notify.Notify(ctx, notifications.Message{
			UserID: pay.BuyerID, App: notifications.AppBuyer, Kind: "payment_refunded", Title: "Remboursement effectué",
			Body: fmt.Sprintf("%d FCFA vous ont été remboursés sur votre compte Mobile Money.", pay.AmountXof),
			Data: map[string]string{"alert_id": pay.AlertID.String()},
		})
	})
}

// AdminListPayments liste les paiements du module.
func (s *Service) AdminListPayments(ctx context.Context, status string, alertID *uuid.UUID, limit, offset int32) ([]Payment, error) {
	var st *string
	if status != "" {
		st = &status
	}
	rows, err := s.q(ctx).ListPayments(ctx, store.ListPaymentsParams{Status: st, AlertID: alertID, Lim: limit, Off: offset})
	if err != nil {
		return nil, fmt.Errorf("liste des paiements : %w", err)
	}
	out := make([]Payment, len(rows))
	for i, r := range rows {
		out[i] = toPayment(r)
	}
	return out, nil
}

// DevSimulate fait aboutir (ou échouer) un paiement du faux prestataire en passant par le même
// chemin qu'un vrai webhook signé. Développement local et tests uniquement.
func (s *Service) DevSimulate(ctx context.Context, fake *payments.FakeProvider, buyerID, paymentID uuid.UUID, outcome payments.ProviderStatus) error {
	if outcome != payments.ProviderSucceeded && outcome != payments.ProviderFailed {
		return apperr.Validation(map[string]string{"outcome": "Valeur attendue : succeeded ou failed."})
	}
	pay, err := s.q(ctx).GetPayment(ctx, paymentID)
	if database.IsNoRows(err) || (err == nil && pay.BuyerID != buyerID) {
		return errPaymentNotFound
	}
	if err != nil {
		return fmt.Errorf("lecture du paiement : %w", err)
	}
	header, body, err := fake.Simulate(pay.Reference, outcome, -1)
	if err != nil {
		return apperr.Conflict("simulation_failed", err.Error())
	}
	ev, err := fake.ParseWebhook(header, body)
	if err != nil {
		return err
	}
	return s.payments.HandleWebhook(ctx, ev)
}
