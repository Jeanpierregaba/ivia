package orders

import (
	"context"
	"crypto/subtle"
	"errors"
	"fmt"
	"time"
	"unicode/utf8"

	"github.com/google/uuid"

	"ivia/backend/internal/admin"
	"ivia/backend/internal/notifications"
	"ivia/backend/internal/orders/store"
	"ivia/backend/internal/platform/apperr"
	"ivia/backend/internal/platform/database"
	"ivia/backend/internal/stock"
)

// Actor est l'auteur d'une transition.
type Actor struct {
	Type ActorType
	ID   *uuid.UUID
}

// System est l'acteur des tâches de fond et du traitement des paiements.
var System = Actor{Type: ActorSystem}

// As construit un acteur identifié.
func As(t ActorType, id uuid.UUID) Actor { return Actor{Type: t, ID: &id} }

var statusLabels = map[Status]string{
	StatusPendingPayment: "en attente de paiement", StatusExpired: "expirée", StatusAwaitingSeller: "en attente du marchand",
	StatusAccepted: "acceptée", StatusPreparing: "en préparation", StatusReadyForPickup: "prête à retirer",
	StatusAwaitingDriver: "en attente d'un livreur", StatusDriverAssigned: "livreur en route vers la boutique",
	StatusPickedUp: "en cours de livraison", StatusDelivered: "livrée", StatusDeliveryFailed: "échec de livraison",
	StatusReturnedToShop: "revenue en boutique", StatusCompleted: "retirée", StatusCancelled: "annulée", StatusRefunded: "remboursée",
}

func invalidTransition(o Order) error {
	return apperr.Conflict("invalid_transition", "Action impossible : la commande est « "+statusLabels[o.Status]+" ».")
}

// apply fait passer une commande au statut to. C'est le seul chemin qui modifie le statut.
func (s *Service) apply(ctx context.Context, orderID uuid.UUID, to Status, actor Actor, reason string) (Order, error) {
	var out Order
	err := s.db.InTx(ctx, func(ctx context.Context) error {
		st := store.New(s.db.Conn(ctx))
		if _, err := st.LockOrder(ctx, orderID); err != nil {
			if database.IsNoRows(err) {
				return errNotFound
			}
			return fmt.Errorf("verrou de la commande : %w", err)
		}
		o, err := s.get(ctx, orderID)
		if err != nil {
			return err
		}
		if !CanTransition(o.Status, to, actor.Type) {
			return invalidTransition(o)
		}

		p := store.UpdateStatusParams{
			ID: orderID, FromStatus: string(o.Status), ToStatus: string(to), Reason: reason,
			RefundDueXof: o.RefundDueXOF, StockReleased: o.StockReleased,
		}
		switch to {
		case StatusAwaitingSeller:
			settings, err := s.admin.Settings(ctx)
			if err != nil {
				return err
			}
			p.MarkPaid = true
			deadline := time.Now().Add(settings.SellerResponseTimeout())
			p.SellerDeadlineAt = &deadline
			if o.StockReleased { // paiement tardif : le stock rendu à l'expiration est repris
				if err := s.stock.Reserve(ctx, orderID, o.trackedLines()); err != nil {
					return err
				}
				p.StockReleased = false
			}
		case StatusCancelled:
			if o.Status == StatusExpired {
				p.MarkPaid = true // paiement tardif arrivé alors que le stock est épuisé
			}
			if o.PaidAt != nil || p.MarkPaid {
				// Annulée après paiement : remboursement intégral.
				p.RefundDueXof = o.TotalXOF
			}
		case StatusReturnedToShop:
			// Échec de livraison : produits remboursés, frais de livraison conservés.
			p.RefundDueXof = o.SubtotalXOF
		case StatusRefunded:
			p.RefundDueXof = 0
		}
		if to.releasesStock() && !p.StockReleased {
			if err := s.stock.Release(ctx, orderID, o.trackedLines()); err != nil {
				return err
			}
			p.StockReleased = true
		}

		n, err := st.UpdateStatus(ctx, p)
		if err != nil {
			return fmt.Errorf("changement de statut : %w", err)
		}
		if n == 0 {
			return invalidTransition(o)
		}
		from := string(o.Status)
		if err := st.InsertEvent(ctx, store.InsertEventParams{
			OrderID: orderID, FromStatus: &from, ToStatus: string(to), ActorType: string(actor.Type), ActorID: actor.ID, Reason: reason,
		}); err != nil {
			return fmt.Errorf("historique de la commande : %w", err)
		}
		if out, err = s.get(ctx, orderID); err != nil {
			return err
		}
		return s.effects(ctx, o, out)
	})
	return out, err
}

// effects crée les notifications et tâches consécutives à une transition (même transaction).
func (s *Service) effects(ctx context.Context, before, o Order) error {
	shop, err := s.shops.Get(ctx, o.ShopID)
	if err != nil {
		return err
	}
	data := map[string]string{"order_id": o.ID.String()}
	buyer := func(kind, title, body string) error {
		return s.notify.Notify(ctx, notifications.Message{UserID: o.BuyerID, App: notifications.AppBuyer, Kind: kind, Title: title, Body: body, Data: data})
	}
	seller := func(kind, title, body string) error {
		return s.notify.Notify(ctx, notifications.Message{UserID: shop.OwnerID, App: notifications.AppSeller, Kind: kind, Title: title, Body: body, Data: data})
	}
	ref := o.Reference
	both := func(errs ...error) error { return errors.Join(errs...) }

	switch o.Status {
	case StatusAwaitingSeller:
		if err := s.jobs.Enqueue(ctx, SellerTimeoutArgs{OrderID: o.ID}, atTime(*o.SellerDeadlineAt)); err != nil {
			return err
		}
		return both(
			buyer("order_paid", "Paiement reçu", "Commande "+ref+" payée. "+shop.Name+" va la confirmer."),
			seller("order_new", "Nouvelle commande "+ref, "Acceptez-la ou refusez-la dans les 15 minutes."),
		)
	case StatusExpired:
		return buyer("order_expired", "Commande expirée", "Le paiement de la commande "+ref+" n'a pas été reçu à temps.")
	case StatusAccepted:
		return buyer("order_accepted", "Commande acceptée", shop.Name+" a accepté votre commande "+ref+".")
	case StatusPreparing:
		return buyer("order_preparing", "Commande en préparation", "Votre commande "+ref+" est en préparation.")
	case StatusReadyForPickup:
		return buyer("order_ready_for_pickup", "Commande prête", "Votre commande "+ref+" vous attend chez "+shop.Name+". Présentez votre code de remise.")
	case StatusAwaitingDriver:
		if err := s.jobs.Enqueue(ctx, StatusChangedArgs{OrderID: o.ID, Status: o.Status}, nil); err != nil {
			return err
		}
		if before.Status == StatusPreparing {
			return buyer("order_ready", "Commande prête", "Votre commande "+ref+" est prête : nous cherchons un livreur.")
		}
		return nil
	case StatusDriverAssigned:
		return both(
			buyer("driver_assigned", "Livreur trouvé", "Un livreur va récupérer votre commande "+ref+"."),
			seller("driver_assigned", "Livreur en route", "Un livreur arrive pour la commande "+ref+"."),
		)
	case StatusPickedUp:
		return buyer("order_picked_up", "Commande en route", "Votre commande "+ref+" est en cours de livraison. Préparez votre code de remise.")
	case StatusDelivered, StatusCompleted:
		return both(
			buyer("order_completed", "Commande remise", "Votre commande "+ref+" vous a été remise. Merci !"),
			seller("order_completed", "Commande remise", "La commande "+ref+" a été remise à l'acheteur."),
		)
	case StatusDeliveryFailed:
		return both(
			buyer("delivery_failed", "Livraison impossible", "Le livreur n'a pas pu vous remettre la commande "+ref+". Elle retourne en boutique et ses produits vous seront remboursés."),
			seller("delivery_failed", "Colis en retour", "La livraison de la commande "+ref+" a échoué : le livreur vous rapporte le colis."),
		)
	case StatusReturnedToShop:
		return s.jobs.Enqueue(ctx, StatusChangedArgs{OrderID: o.ID, Status: o.Status}, nil)
	case StatusCancelled:
		if o.Fulfillment == FulfillmentDelivery {
			if err := s.jobs.Enqueue(ctx, StatusChangedArgs{OrderID: o.ID, Status: o.Status}, nil); err != nil {
				return err
			}
		}
		body := "Votre commande " + ref + " est annulée."
		if o.RefundDueXOF > 0 {
			body += " Vous serez remboursé de " + formatXOF(o.RefundDueXOF) + "."
		}
		errs := []error{buyer("order_cancelled", "Commande annulée", body)}
		if before.Status != StatusPendingPayment && before.Status != StatusExpired {
			errs = append(errs, seller("order_cancelled", "Commande annulée", "La commande "+ref+" est annulée."))
		}
		return both(errs...)
	case StatusRefunded:
		return buyer("order_refunded", "Remboursement effectué", "Le remboursement de la commande "+ref+" a été envoyé sur votre compte Mobile Money.")
	}
	return nil
}

// --- Actions de l'acheteur ------------------------------------------------------------------

// CancelByBuyer annule une commande non payée ou pas encore acceptée par le marchand.
func (s *Service) CancelByBuyer(ctx context.Context, buyerID, orderID uuid.UUID) (BuyerOrder, error) {
	o, err := s.get(ctx, orderID)
	if err != nil {
		return BuyerOrder{}, err
	}
	if o.BuyerID != buyerID {
		return BuyerOrder{}, errNotFound
	}
	if !CanTransition(o.Status, StatusCancelled, ActorBuyer) {
		return BuyerOrder{}, apperr.Conflict("cannot_cancel", "La boutique a déjà accepté cette commande : contactez le support pour l'annuler.")
	}
	if o, err = s.apply(ctx, orderID, StatusCancelled, As(ActorBuyer, buyerID), "Annulée par l'acheteur."); err != nil {
		return BuyerOrder{}, err
	}
	return s.buyerView(ctx, o)
}

// --- Actions du marchand --------------------------------------------------------------------

func (s *Service) sellerAction(ctx context.Context, sellerID, orderID uuid.UUID, to Status, reason string) (SellerOrder, error) {
	if _, err := s.requireSellerOrder(ctx, sellerID, orderID); err != nil {
		return SellerOrder{}, err
	}
	o, err := s.apply(ctx, orderID, to, As(ActorSeller, sellerID), reason)
	if err != nil {
		return SellerOrder{}, err
	}
	return s.sellerView(ctx, o)
}

// MaxRejectReason : longueur maximale du motif de refus (caractères), comme dans l'app marchand.
const MaxRejectReason = 200

var errSellerDeadline = apperr.Conflict("seller_deadline_passed",
	"Le délai de réponse est dépassé : la commande est annulée et l'acheteur remboursé.")

// requireBeforeDeadline refuse une réponse du marchand arrivée après le délai, sans attendre la
// tâche de fond SellerTimeout : la commande est annulée tout de suite, comme elle l'aurait fait.
func (s *Service) requireBeforeDeadline(ctx context.Context, sellerID, orderID uuid.UUID) error {
	o, err := s.requireSellerOrder(ctx, sellerID, orderID)
	if err != nil {
		return err
	}
	if o.Status != StatusAwaitingSeller || o.SellerDeadlineAt == nil || time.Now().Before(*o.SellerDeadlineAt) {
		return nil
	}
	if err := s.SellerTimeout(ctx, orderID); err != nil {
		return err
	}
	return errSellerDeadline
}

// Accept : le marchand accepte (et confirme la disponibilité des produits à stock non suivi),
// avant la fin du délai de réponse.
func (s *Service) Accept(ctx context.Context, sellerID, orderID uuid.UUID) (SellerOrder, error) {
	if err := s.requireBeforeDeadline(ctx, sellerID, orderID); err != nil {
		return SellerOrder{}, err
	}
	return s.sellerAction(ctx, sellerID, orderID, StatusAccepted, "")
}

// Reject : le marchand refuse avant la fin du délai ; la commande payée part dans la file de
// remboursement. Motif facultatif, 200 caractères au plus.
func (s *Service) Reject(ctx context.Context, sellerID, orderID uuid.UUID, reason string) (SellerOrder, error) {
	if utf8.RuneCountInString(reason) > MaxRejectReason {
		return SellerOrder{}, apperr.Validation(map[string]string{
			"reason": fmt.Sprintf("Le motif fait %d caractères au plus.", MaxRejectReason),
		})
	}
	if err := s.requireBeforeDeadline(ctx, sellerID, orderID); err != nil {
		return SellerOrder{}, err
	}
	if reason == "" {
		reason = "Refusée par le marchand."
	}
	return s.sellerAction(ctx, sellerID, orderID, StatusCancelled, reason)
}

// StartPreparing passe la commande en préparation.
func (s *Service) StartPreparing(ctx context.Context, sellerID, orderID uuid.UUID) (SellerOrder, error) {
	return s.sellerAction(ctx, sellerID, orderID, StatusPreparing, "")
}

// MarkReady : prête à retirer (retrait) ou en attente d'un livreur (livraison).
func (s *Service) MarkReady(ctx context.Context, sellerID, orderID uuid.UUID) (SellerOrder, error) {
	o, err := s.requireSellerOrder(ctx, sellerID, orderID)
	if err != nil {
		return SellerOrder{}, err
	}
	to := StatusReadyForPickup
	if o.Fulfillment == FulfillmentDelivery {
		to = StatusAwaitingDriver
	}
	return s.sellerAction(ctx, sellerID, orderID, to, "")
}

// CompletePickup : le marchand saisit le code de l'acheteur venu retirer sa commande.
func (s *Service) CompletePickup(ctx context.Context, sellerID, orderID uuid.UUID, code string) (SellerOrder, error) {
	o, err := s.requireSellerOrder(ctx, sellerID, orderID)
	if err != nil {
		return SellerOrder{}, err
	}
	if o.Status != StatusReadyForPickup {
		return SellerOrder{}, invalidTransition(o)
	}
	if err := s.checkHandoverCode(ctx, o, code); err != nil {
		return SellerOrder{}, err
	}
	return s.sellerAction(ctx, sellerID, orderID, StatusCompleted, "")
}

// ConfirmReturn : le marchand confirme que le colis d'une livraison échouée est revenu.
func (s *Service) ConfirmReturn(ctx context.Context, sellerID, orderID uuid.UUID) (SellerOrder, error) {
	return s.sellerAction(ctx, sellerID, orderID, StatusReturnedToShop, "Colis revenu en boutique.")
}

// checkHandoverCode vérifie le code de remise. L'essai est compté AVANT la comparaison, par une
// mise à jour conditionnelle (essais < 5) validée dans sa propre transaction : même des centaines
// de requêtes simultanées ne comparent jamais plus de 5 codes, et un mauvais essai reste compté si
// l'action échoue ensuite. Au 5e essai, le code est bloqué jusqu'au déblocage par un admin.
func (s *Service) checkHandoverCode(ctx context.Context, o Order, code string) error {
	locked := apperr.Conflict("handover_locked", "Trop d'essais : le code est bloqué. Contactez l'équipe ivia.")
	n, err := store.New(s.db.Pool).IncrementHandoverAttempts(ctx, store.IncrementHandoverAttemptsParams{ID: o.ID, MaxAttempts: MaxHandoverAttempts})
	if database.IsNoRows(err) {
		return locked
	}
	if err != nil {
		return fmt.Errorf("comptage des essais de code : %w", err)
	}
	if len(code) == 4 && subtle.ConstantTimeCompare([]byte(code), []byte(o.HandoverCode)) == 1 {
		return nil
	}
	if n >= MaxHandoverAttempts {
		if err := s.notify.NotifyAdmins(context.WithoutCancel(ctx), "handover_locked", "Code de remise bloqué",
			"La commande "+o.Reference+" a atteint 5 essais de code.", map[string]string{"order_id": o.ID.String()}); err != nil {
			s.logger.Error("alerte admin impossible", "err", err)
		}
		return locked
	}
	return apperr.Unprocessable("handover_code_invalid", fmt.Sprintf("Code incorrect. Il reste %d essai(s).", MaxHandoverAttempts-n))
}

// --- Actions du livreur (appelées par le module delivery, qui vérifie la mission) -----------

// AssignDriver : un livreur a accepté la mission.
func (s *Service) AssignDriver(ctx context.Context, orderID, driverID uuid.UUID) error {
	_, err := s.apply(ctx, orderID, StatusDriverAssigned, As(ActorDriver, driverID), "")
	return err
}

// UnassignDriver : le livreur se désiste (ou l'admin le retire) avant la récupération.
func (s *Service) UnassignDriver(ctx context.Context, orderID uuid.UUID, actor Actor, reason string) error {
	_, err := s.apply(ctx, orderID, StatusAwaitingDriver, actor, reason)
	return err
}

// MarkPickedUp : le livreur a récupéré le colis.
func (s *Service) MarkPickedUp(ctx context.Context, orderID, driverID uuid.UUID) error {
	_, err := s.apply(ctx, orderID, StatusPickedUp, As(ActorDriver, driverID), "")
	return err
}

// CompleteDelivery : le livreur saisit le code de l'acheteur.
func (s *Service) CompleteDelivery(ctx context.Context, orderID, driverID uuid.UUID, code string) error {
	o, err := s.get(ctx, orderID)
	if err != nil {
		return err
	}
	if o.Status != StatusPickedUp {
		return invalidTransition(o)
	}
	if err := s.checkHandoverCode(ctx, o, code); err != nil {
		return err
	}
	_, err = s.apply(ctx, orderID, StatusDelivered, As(ActorDriver, driverID), "")
	return err
}

// MarkDeliveryFailed : client absent ou injoignable.
func (s *Service) MarkDeliveryFailed(ctx context.Context, orderID, driverID uuid.UUID, reason string) error {
	_, err := s.apply(ctx, orderID, StatusDeliveryFailed, As(ActorDriver, driverID), reason)
	return err
}

// --- Paiement (appelé par le module payments sur un paiement vérifié) -----------------------

// PaymentOutcome est l'effet d'un paiement réussi sur la commande.
type PaymentOutcome int

const (
	// PaymentApplied : la commande est payée et transmise au marchand.
	PaymentApplied PaymentOutcome = iota
	// PaymentCancelledNoStock : paiement tardif, stock épuisé : commande annulée, à rembourser.
	PaymentCancelledNoStock
	// PaymentOnCancelledOrder : la commande avait été annulée avant le paiement : à rembourser.
	PaymentOnCancelledOrder
	// PaymentDuplicate : la commande était déjà payée : ce paiement est à rembourser.
	PaymentDuplicate
)

// PayableOrder est ce dont le module payments a besoin pour lancer un paiement.
type PayableOrder struct {
	ID        uuid.UUID
	Reference string
	TotalXOF  int64
	Deadline  time.Time
}

// RequirePayable vérifie qu'une commande de l'acheteur attend son paiement.
func (s *Service) RequirePayable(ctx context.Context, buyerID, orderID uuid.UUID) (PayableOrder, error) {
	o, err := s.get(ctx, orderID)
	if err != nil {
		return PayableOrder{}, err
	}
	if o.BuyerID != buyerID {
		return PayableOrder{}, errNotFound
	}
	if o.Status != StatusPendingPayment {
		return PayableOrder{}, apperr.Conflict("order_not_payable", "Cette commande n'attend pas de paiement.")
	}
	if time.Now().After(o.PaymentDeadlineAt) {
		return PayableOrder{}, apperr.Conflict("order_expired", "Le délai de paiement est dépassé.")
	}
	return PayableOrder{ID: o.ID, Reference: o.Reference, TotalXOF: o.TotalXOF, Deadline: o.PaymentDeadlineAt}, nil
}

// OnPaymentSucceeded applique un paiement réussi et vérifié. Seul le module payments l'appelle,
// depuis le traitement d'un webhook vérifié ou d'une revérification auprès du prestataire.
func (s *Service) OnPaymentSucceeded(ctx context.Context, orderID uuid.UUID) (PaymentOutcome, error) {
	var outcome PaymentOutcome
	err := s.db.InTx(ctx, func(ctx context.Context) error {
		st := store.New(s.db.Conn(ctx))
		status, err := st.LockOrder(ctx, orderID)
		if err != nil {
			return fmt.Errorf("verrou de la commande : %w", err)
		}
		switch Status(status) {
		case StatusPendingPayment:
			outcome = PaymentApplied
			_, err := s.apply(ctx, orderID, StatusAwaitingSeller, System, "Paiement confirmé par le prestataire.")
			return err
		case StatusExpired:
			err := s.db.Savepoint(ctx, func(ctx context.Context) error {
				_, err := s.apply(ctx, orderID, StatusAwaitingSeller, System, "Paiement reçu après expiration, stock disponible.")
				return err
			})
			var insufficient *stock.InsufficientStockError
			if errors.As(err, &insufficient) {
				outcome = PaymentCancelledNoStock
				_, err = s.apply(ctx, orderID, StatusCancelled, System, "Paiement reçu après expiration, stock épuisé.")
				return err
			}
			outcome = PaymentApplied
			return err
		case StatusCancelled:
			n, err := st.RecordLatePayment(ctx, orderID)
			if err != nil {
				return fmt.Errorf("enregistrement du paiement tardif : %w", err)
			}
			if n == 0 {
				outcome = PaymentDuplicate // déjà payée puis annulée : ce second paiement est en double
				return nil
			}
			outcome = PaymentOnCancelledOrder
			from := status
			return st.InsertEvent(ctx, store.InsertEventParams{
				OrderID: orderID, FromStatus: &from, ToStatus: status, ActorType: string(ActorSystem),
				Reason: "Paiement reçu après l'annulation : à rembourser.",
			})
		default:
			outcome = PaymentDuplicate
			return nil
		}
	})
	return outcome, err
}

// RefundableOrder décrit le remboursement attendu d'une commande de la file.
type RefundableOrder struct {
	ID           uuid.UUID
	Reference    string
	BuyerID      uuid.UUID
	RefundDueXOF int64
}

// RequireRefundable vérifie qu'une commande est dans la file de remboursement.
func (s *Service) RequireRefundable(ctx context.Context, orderID uuid.UUID) (RefundableOrder, error) {
	o, err := s.get(ctx, orderID)
	if err != nil {
		return RefundableOrder{}, err
	}
	if (o.Status != StatusCancelled && o.Status != StatusReturnedToShop) || o.RefundDueXOF <= 0 {
		return RefundableOrder{}, apperr.Conflict("not_refundable", "Cette commande n'est pas dans la file de remboursement.")
	}
	return RefundableOrder{ID: o.ID, Reference: o.Reference, BuyerID: o.BuyerID, RefundDueXOF: o.RefundDueXOF}, nil
}

// MarkRefunded passe la commande à « remboursée » une fois le transfert confirmé.
func (s *Service) MarkRefunded(ctx context.Context, orderID uuid.UUID, adminID uuid.UUID) error {
	_, err := s.apply(ctx, orderID, StatusRefunded, As(ActorAdmin, adminID), "Remboursement confirmé par le prestataire.")
	return err
}

// --- Actions admin --------------------------------------------------------------------------

// CancelByAdmin annule une commande (après acceptation, seul l'admin le peut). Journalisé.
func (s *Service) CancelByAdmin(ctx context.Context, adminID, orderID uuid.UUID, reason string) (AdminOrder, error) {
	if reason == "" {
		return AdminOrder{}, apperr.Validation(map[string]string{"reason": "Indiquez le motif de l'annulation."})
	}
	var out Order
	err := s.db.InTx(ctx, func(ctx context.Context) error {
		before, err := s.get(ctx, orderID)
		if err != nil {
			return err
		}
		if out, err = s.apply(ctx, orderID, StatusCancelled, As(ActorAdmin, adminID), reason); err != nil {
			return err
		}
		return s.admin.Record(ctx, admin.AuditEntry{
			AdminID: &adminID, Action: "order.cancel", TargetType: "order", TargetID: orderID.String(),
			Before: map[string]any{"status": before.Status}, After: map[string]any{"status": out.Status, "refund_due_xof": out.RefundDueXOF},
			Reason: reason,
		})
	})
	return adminView(out), err
}

// ConfirmReturnByAdmin confirme le retour en boutique d'un colis non livré quand le marchand ne le
// fait pas : la mission du livreur se termine et la commande entre dans la file de remboursement.
// Journalisé.
func (s *Service) ConfirmReturnByAdmin(ctx context.Context, adminID, orderID uuid.UUID, reason string) (AdminOrder, error) {
	if reason == "" {
		return AdminOrder{}, apperr.Validation(map[string]string{"reason": "Indiquez comment le retour a été vérifié."})
	}
	var out Order
	err := s.db.InTx(ctx, func(ctx context.Context) error {
		before, err := s.get(ctx, orderID)
		if err != nil {
			return err
		}
		if out, err = s.apply(ctx, orderID, StatusReturnedToShop, As(ActorAdmin, adminID), reason); err != nil {
			return err
		}
		return s.admin.Record(ctx, admin.AuditEntry{
			AdminID: &adminID, Action: "order.confirm_return", TargetType: "order", TargetID: orderID.String(),
			Before: map[string]any{"status": before.Status}, After: map[string]any{"status": out.Status, "refund_due_xof": out.RefundDueXOF},
			Reason: reason,
		})
	})
	return adminView(out), err
}

// UnlockHandover remet à zéro les essais de code de remise après vérification par l'admin. Journalisé.
func (s *Service) UnlockHandover(ctx context.Context, adminID, orderID uuid.UUID, reason string) (AdminOrder, error) {
	var out Order
	err := s.db.InTx(ctx, func(ctx context.Context) error {
		before, err := s.get(ctx, orderID)
		if err != nil {
			return err
		}
		if err := store.New(s.db.Conn(ctx)).ResetHandoverAttempts(ctx, orderID); err != nil {
			return fmt.Errorf("déblocage du code : %w", err)
		}
		if out, err = s.get(ctx, orderID); err != nil {
			return err
		}
		return s.admin.Record(ctx, admin.AuditEntry{
			AdminID: &adminID, Action: "order.unlock_handover", TargetType: "order", TargetID: orderID.String(),
			Before: map[string]any{"handover_attempts": before.HandoverAttempts}, After: map[string]any{"handover_attempts": 0},
			Reason: reason,
		})
	})
	return adminView(out), err
}

// --- Tâches de fond -------------------------------------------------------------------------

// ExpirePayment expire une commande dont le délai de paiement est dépassé (idempotent).
func (s *Service) ExpirePayment(ctx context.Context, orderID uuid.UUID) error {
	o, err := s.get(ctx, orderID)
	if err != nil {
		return err
	}
	if o.Status != StatusPendingPayment {
		return nil
	}
	if time.Now().Before(o.PaymentDeadlineAt) {
		return errRetryLater{at: o.PaymentDeadlineAt}
	}
	_, err = s.apply(ctx, orderID, StatusExpired, System, "Délai de paiement dépassé.")
	if apperr.IsCode(err, "invalid_transition") {
		return nil // payée entre-temps
	}
	return err
}

// SellerTimeout annule une commande que le marchand n'a pas acceptée à temps (idempotent).
func (s *Service) SellerTimeout(ctx context.Context, orderID uuid.UUID) error {
	o, err := s.get(ctx, orderID)
	if err != nil {
		return err
	}
	if o.Status != StatusAwaitingSeller || o.SellerDeadlineAt == nil {
		return nil
	}
	if time.Now().Before(*o.SellerDeadlineAt) {
		return errRetryLater{at: *o.SellerDeadlineAt}
	}
	_, err = s.apply(ctx, orderID, StatusCancelled, System, "Le marchand n'a pas répondu à temps.")
	if apperr.IsCode(err, "invalid_transition") {
		return nil
	}
	return err
}

type errRetryLater struct{ at time.Time }

func (e errRetryLater) Error() string { return "trop tôt, à reprendre à " + e.at.String() }

func formatXOF(v int64) string {
	s := fmt.Sprintf("%d", v)
	out := make([]byte, 0, len(s)+len(s)/3)
	for i, c := range []byte(s) {
		if i > 0 && (len(s)-i)%3 == 0 {
			out = append(out, ' ')
		}
		out = append(out, c)
	}
	return string(out) + " FCFA"
}
