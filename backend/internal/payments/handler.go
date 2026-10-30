package payments

import (
	"errors"
	"io"
	"log/slog"
	"net/http"

	"ivia/backend/internal/platform/apperr"
	"ivia/backend/internal/platform/httpapi"
	"ivia/backend/internal/platform/identity"
)

// maxWebhookBytes borne le corps d'un webhook.
const maxWebhookBytes = 64 << 10

// Handler expose les routes des paiements.
type Handler struct {
	svc    *Service
	logger *slog.Logger
	// devTools : routes de simulation (local et tests uniquement).
	devTools bool
}

// NewHandler crée le handler.
func NewHandler(svc *Service, logger *slog.Logger, devTools bool) *Handler {
	return &Handler{svc: svc, logger: logger, devTools: devTools}
}

// Register enregistre les routes.
func (h *Handler) Register(rt *httpapi.Router) {
	rt.Roles("POST /v1/orders/{id}/payments", h.initiate, identity.RoleBuyer)
	rt.Roles("GET /v1/orders/{id}/payments", h.listForOrder, identity.RoleBuyer)
	rt.Roles("GET /v1/payments/{id}", h.get, identity.RoleBuyer)

	rt.Raw("POST /v1/webhooks/payments/{provider}", http.HandlerFunc(h.webhook))

	rt.Roles("GET /v1/admin/payments", h.adminList, identity.RoleAdmin)
	rt.Roles("GET /v1/admin/payments/{id}", h.adminGet, identity.RoleAdmin)
	rt.Roles("POST /v1/admin/payments/{id}/verify", h.adminVerify, identity.RoleAdmin)
	rt.Roles("POST /v1/admin/payments/{id}/refund", h.adminRefundDuplicate, identity.RoleAdmin)
	rt.Roles("POST /v1/admin/orders/{id}/refund", h.adminRefundOrder, identity.RoleAdmin)
	rt.Roles("GET /v1/admin/refunds", h.adminRefunds, identity.RoleAdmin)

	if fake, ok := h.svc.Provider().(*FakeProvider); ok && h.devTools {
		rt.Auth("POST /v1/dev/payments/{id}/simulate", h.simulate(fake))
	}
}

func (h *Handler) initiate(w http.ResponseWriter, r *http.Request) error {
	id, err := httpapi.PathUUID(r, "id")
	if err != nil {
		return err
	}
	var in struct {
		Operator Operator `json:"operator"`
		Phone    string   `json:"phone"`
	}
	if err := httpapi.Decode(r, &in); err != nil {
		return err
	}
	p, err := h.svc.Initiate(r.Context(), identity.MustFromContext(r.Context()).UserID, id, in.Operator, in.Phone)
	if err != nil {
		return err
	}
	return httpapi.Created(w, p)
}

func (h *Handler) listForOrder(w http.ResponseWriter, r *http.Request) error {
	id, err := httpapi.PathUUID(r, "id")
	if err != nil {
		return err
	}
	items, err := h.svc.ListForOrder(r.Context(), identity.MustFromContext(r.Context()).UserID, id)
	if err != nil {
		return err
	}
	return httpapi.OK(w, map[string]any{"items": items})
}

func (h *Handler) get(w http.ResponseWriter, r *http.Request) error {
	id, err := httpapi.PathUUID(r, "id")
	if err != nil {
		return err
	}
	p, err := h.svc.GetForBuyer(r.Context(), identity.MustFromContext(r.Context()).UserID, id)
	if err != nil {
		return err
	}
	return httpapi.OK(w, p)
}

// webhook reçoit une notification du prestataire : signature vérifiée sur le corps brut, puis
// enregistrement et réponse immédiate ; le traitement se fait en tâche de fond.
func (h *Handler) webhook(w http.ResponseWriter, r *http.Request) {
	body, err := io.ReadAll(io.LimitReader(r.Body, maxWebhookBytes+1))
	if err != nil || len(body) > maxWebhookBytes {
		http.Error(w, "corps invalide", http.StatusBadRequest)
		return
	}
	provider := r.PathValue("provider")
	if provider != h.svc.Provider().Name() {
		http.NotFound(w, r)
		return
	}
	ev, err := h.svc.Provider().ParseWebhook(r.Header, body)
	if errors.Is(err, ErrInvalidSignature) {
		h.logger.Warn("webhook de paiement à la signature invalide", "provider", provider, "request_id", httpapi.RequestID(r.Context()))
		http.Error(w, "signature invalide", http.StatusUnauthorized)
		return
	}
	if err != nil {
		http.Error(w, "webhook illisible", http.StatusBadRequest)
		return
	}
	if err := h.svc.HandleWebhook(r.Context(), ev); err != nil {
		httpapi.WriteError(w, r, h.logger, err)
		return
	}
	w.WriteHeader(http.StatusOK)
}

// simulate fait aboutir un paiement du faux prestataire en passant par le même chemin qu'un vrai
// webhook (signature comprise). Réservé au développement local.
func (h *Handler) simulate(fake *FakeProvider) httpapi.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) error {
		id, err := httpapi.PathUUID(r, "id")
		if err != nil {
			return err
		}
		var in struct {
			Outcome   ProviderStatus `json:"outcome"`
			AmountXOF *int64         `json:"amount_xof"`
		}
		if err := httpapi.Decode(r, &in); err != nil {
			return err
		}
		if in.Outcome != ProviderSucceeded && in.Outcome != ProviderFailed {
			return apperr.Validation(map[string]string{"outcome": "Valeur attendue : succeeded ou failed."})
		}
		p, err := h.svc.AdminGet(r.Context(), id)
		if err != nil {
			return err
		}
		if p.BuyerID != identity.MustFromContext(r.Context()).UserID {
			return errNotFound
		}
		amount := int64(-1)
		if in.AmountXOF != nil {
			amount = *in.AmountXOF
		}
		header, body, err := fake.Simulate(p.Reference, in.Outcome, amount)
		if err != nil {
			return apperr.Conflict("simulation_failed", err.Error())
		}
		ev, err := fake.ParseWebhook(header, body)
		if err != nil {
			return err
		}
		if err := h.svc.HandleWebhook(r.Context(), ev); err != nil {
			return err
		}
		return httpapi.OK(w, map[string]string{"status": "webhook_sent"})
	}
}

func (h *Handler) adminList(w http.ResponseWriter, r *http.Request) error {
	q := httpapi.NewQuery(r)
	page := q.Page()
	f := AdminFilter{
		Status:         Status(q.Enum("status", "", "pending", "succeeded", "failed", "expired", "refund_pending", "refunded")),
		OrderID:        q.UUID("order_id"),
		DuplicatesOnly: q.Enum("duplicates", "false", "true", "false") == "true",
	}
	if err := q.Err(); err != nil {
		return err
	}
	items, err := h.svc.AdminList(r.Context(), f, page.FetchLimit(), int32(page.Offset))
	if err != nil {
		return err
	}
	return httpapi.OK(w, httpapi.NewList(items, page))
}

func (h *Handler) adminGet(w http.ResponseWriter, r *http.Request) error {
	id, err := httpapi.PathUUID(r, "id")
	if err != nil {
		return err
	}
	p, err := h.svc.AdminGet(r.Context(), id)
	if err != nil {
		return err
	}
	return httpapi.OK(w, p)
}

func (h *Handler) adminVerify(w http.ResponseWriter, r *http.Request) error {
	id, err := httpapi.PathUUID(r, "id")
	if err != nil {
		return err
	}
	p, err := h.svc.VerifyNow(r.Context(), id)
	if err != nil {
		return err
	}
	return httpapi.OK(w, p)
}

type reasonInput struct {
	Reason string `json:"reason"`
}

func (h *Handler) adminRefundOrder(w http.ResponseWriter, r *http.Request) error {
	id, err := httpapi.PathUUID(r, "id")
	if err != nil {
		return err
	}
	var in reasonInput
	if err := httpapi.Decode(r, &in); err != nil {
		return err
	}
	p, err := h.svc.RefundOrder(r.Context(), identity.MustFromContext(r.Context()).UserID, id, in.Reason)
	if err != nil {
		return err
	}
	httpapi.WriteJSON(w, http.StatusAccepted, p)
	return nil
}

func (h *Handler) adminRefundDuplicate(w http.ResponseWriter, r *http.Request) error {
	id, err := httpapi.PathUUID(r, "id")
	if err != nil {
		return err
	}
	var in reasonInput
	if err := httpapi.Decode(r, &in); err != nil {
		return err
	}
	p, err := h.svc.RefundDuplicate(r.Context(), identity.MustFromContext(r.Context()).UserID, id, in.Reason)
	if err != nil {
		return err
	}
	httpapi.WriteJSON(w, http.StatusAccepted, p)
	return nil
}

func (h *Handler) adminRefunds(w http.ResponseWriter, r *http.Request) error {
	q := httpapi.NewQuery(r)
	page := q.Page()
	orderID := q.UUID("order_id")
	if err := q.Err(); err != nil {
		return err
	}
	items, err := h.svc.ListRefunds(r.Context(), orderID, page.FetchLimit(), int32(page.Offset))
	if err != nil {
		return err
	}
	return httpapi.OK(w, httpapi.NewList(items, page))
}
