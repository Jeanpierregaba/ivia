package pharmacy

import (
	"net/http"
	"time"

	"github.com/google/uuid"

	"ivia/backend/internal/payments"
	"ivia/backend/internal/platform/apperr"
	"ivia/backend/internal/platform/httpapi"
	"ivia/backend/internal/platform/identity"
	"ivia/backend/internal/platform/ratelimit"
)

// AlertsPerUserPerHour : alertes qu'un client peut lancer par heure (chaque alerte sollicite
// plusieurs pharmacies).
const AlertsPerUserPerHour = 10

// Handler expose les routes du module.
type Handler struct {
	svc    *Service
	alerts *ratelimit.Limiter
	// fake : faux prestataire, exposé en développement local seulement (nil sinon).
	fake *payments.FakeProvider
}

// NewHandler crée le handler. fake non nul ajoute la route de simulation des paiements (local).
func NewHandler(svc *Service, fake *payments.FakeProvider) *Handler {
	return &Handler{svc: svc, alerts: ratelimit.New(AlertsPerUserPerHour, time.Hour), fake: fake}
}

// Register enregistre les routes.
func (h *Handler) Register(rt *httpapi.Router) {
	// Client (app acheteur).
	rt.Auth("POST /v1/medicine-alerts", h.createAlert)
	rt.Auth("GET /v1/medicine-alerts", h.listAlerts)
	rt.Auth("GET /v1/medicine-alerts/{id}", h.getAlert)
	rt.Auth("POST /v1/medicine-alerts/{id}/cancel", h.cancelAlert)
	rt.Auth("POST /v1/medicine-alerts/{id}/unlock", h.unlock)
	rt.Auth("POST /v1/medicine-alerts/{id}/reservations", h.reserve)
	rt.Auth("GET /v1/medicine-reservations", h.listReservations)
	rt.Auth("GET /v1/medicine-reservations/{id}", h.getReservation)
	rt.Auth("POST /v1/medicine-reservations/{id}/pay", h.payReservation)
	rt.Auth("POST /v1/medicine-reservations/{id}/cancel", h.cancelReservation)
	rt.Auth("GET /v1/medicine-payments/{id}", h.getPayment)
	rt.Auth("POST /v1/medicine-payments/{id}/cancel", h.cancelPayment)
	if h.fake != nil {
		rt.Auth("POST /v1/dev/medicine-payments/{id}/simulate", h.simulate)
	}

	// Pharmacie (app pharmacie) : inscription ouverte à tout compte, le reste au rôle pharmacien.
	rt.Auth("POST /v1/pharmacy/application", h.apply)
	rt.Auth("GET /v1/pharmacy/me", h.me)
	rt.Auth("PATCH /v1/pharmacy/me", h.updateContact)
	rt.Auth("POST /v1/pharmacy/me/documents", h.addDocument)
	ph := identity.RolePharmacist
	rt.Roles("PUT /v1/pharmacy/me/status", h.setStatus, ph)
	rt.Roles("GET /v1/pharmacy/inbox", h.inbox, ph)
	rt.Roles("GET /v1/pharmacy/inbox/{id}", h.inboxGet, ph)
	rt.Roles("POST /v1/pharmacy/inbox/{id}/respond", h.respond, ph)
	rt.Roles("POST /v1/pharmacy/inbox/{id}/decline", h.decline, ph)
	rt.Roles("GET /v1/pharmacy/reservations", h.pharmacyReservations, ph)
	rt.Roles("GET /v1/pharmacy/reservations/{id}", h.pharmacyReservation, ph)
	rt.Roles("POST /v1/pharmacy/reservations/{id}/complete", h.completePickup, ph)
	rt.Roles("POST /v1/pharmacy/reservations/{id}/cancel", h.pharmacyCancel, ph)
	rt.Roles("GET /v1/pharmacy/earnings", h.earnings, ph)

	// Livreur ivia.
	dr := identity.RoleDriver
	rt.Roles("GET /v1/driver/pharmacy-offers/current", h.currentOffer, dr)
	rt.Roles("POST /v1/driver/pharmacy-offers/{id}/accept", h.acceptOffer, dr)
	rt.Roles("POST /v1/driver/pharmacy-offers/{id}/decline", h.declineOffer, dr)
	rt.Roles("GET /v1/driver/pharmacy-missions/current", h.currentMission, dr)
	rt.Roles("GET /v1/driver/pharmacy-missions", h.missionHistory, dr)
	rt.Roles("POST /v1/driver/pharmacy-missions/{id}/picked-up", h.pickedUp, dr)
	rt.Roles("POST /v1/driver/pharmacy-missions/{id}/delivered", h.delivered, dr)
	rt.Roles("POST /v1/driver/pharmacy-missions/{id}/withdraw", h.withdraw, dr)

	// Back-office.
	ad := identity.RoleAdmin
	rt.Roles("GET /v1/admin/pharmacies", h.adminList, ad)
	rt.Roles("GET /v1/admin/pharmacies/{id}", h.adminGet, ad)
	rt.Roles("POST /v1/admin/pharmacies/{id}/review", h.adminReview, ad)
	rt.Roles("GET /v1/admin/pharmacies/{id}/earnings", h.adminEarnings, ad)
	rt.Roles("POST /v1/admin/pharmacies/{id}/payouts", h.adminPayout, ad)
	rt.Roles("GET /v1/admin/medicine-alerts", h.adminAlerts, ad)
	rt.Roles("GET /v1/admin/medicine-alerts/{id}", h.adminAlert, ad)
	rt.Roles("GET /v1/admin/medicine-payments", h.adminPayments, ad)
	rt.Roles("POST /v1/admin/medicine-payments/{id}/refund", h.adminRefund, ad)
	rt.Roles("GET /v1/admin/pharmacy/settings", h.getSettings, ad)
	rt.Roles("PUT /v1/admin/pharmacy/settings", h.putSettings, ad)
	rt.Roles("GET /v1/admin/pharmacy/overview", h.overview, ad)
}

func me(r *http.Request) uuid.UUID { return identity.MustFromContext(r.Context()).UserID }

// withID lit {id} puis appelle fn.
func withID(r *http.Request, fn func(id uuid.UUID) (any, error)) (any, error) {
	id, err := httpapi.PathUUID(r, "id")
	if err != nil {
		return nil, err
	}
	return fn(id)
}

func ok(w http.ResponseWriter, v any, err error) error {
	if err != nil {
		return err
	}
	return httpapi.OK(w, v)
}

func page(r *http.Request) (httpapi.Page, *httpapi.Query, error) {
	q := httpapi.NewQuery(r)
	p := q.Page()
	return p, q, q.Err()
}

func boolParam(q *httpapi.Query, name string, def bool) bool {
	d := "false"
	if def {
		d = "true"
	}
	return q.Enum(name, d, "true", "false") == "true"
}

type reasonInput struct {
	Reason string `json:"reason"`
}

type codeInput struct {
	Code string `json:"code"`
}

// --- Client -----------------------------------------------------------------------------------

func (h *Handler) createAlert(w http.ResponseWriter, r *http.Request) error {
	if allowed, retry := h.alerts.Allow(me(r).String()); !allowed {
		return apperr.TooManyRequests("rate_limited", "Trop d'alertes lancées. Réessayez plus tard.", retry)
	}
	var in AlertInput
	if err := httpapi.Decode(r, &in); err != nil {
		return err
	}
	a, err := h.svc.CreateAlert(r.Context(), me(r), in)
	if err != nil {
		return err
	}
	return httpapi.Created(w, a)
}

func (h *Handler) listAlerts(w http.ResponseWriter, r *http.Request) error {
	p, _, err := page(r)
	if err != nil {
		return err
	}
	items, err := h.svc.ListAlerts(r.Context(), me(r), p.FetchLimit(), int32(p.Offset))
	return ok(w, httpapi.NewList(items, p), err)
}

func (h *Handler) getAlert(w http.ResponseWriter, r *http.Request) error {
	v, err := withID(r, func(id uuid.UUID) (any, error) { return h.svc.GetAlert(r.Context(), me(r), id) })
	return ok(w, v, err)
}

func (h *Handler) cancelAlert(w http.ResponseWriter, r *http.Request) error {
	v, err := withID(r, func(id uuid.UUID) (any, error) { return h.svc.CancelAlert(r.Context(), me(r), id) })
	return ok(w, v, err)
}

func (h *Handler) unlock(w http.ResponseWriter, r *http.Request) error {
	var in PayInput
	if err := httpapi.Decode(r, &in); err != nil {
		return err
	}
	v, err := withID(r, func(id uuid.UUID) (any, error) { return h.svc.Unlock(r.Context(), me(r), id, in) })
	return ok(w, v, err)
}

func (h *Handler) reserve(w http.ResponseWriter, r *http.Request) error {
	var in ReserveInput
	if err := httpapi.Decode(r, &in); err != nil {
		return err
	}
	v, err := withID(r, func(id uuid.UUID) (any, error) { return h.svc.Reserve(r.Context(), me(r), id, in) })
	if err != nil {
		return err
	}
	return httpapi.Created(w, v)
}

func (h *Handler) listReservations(w http.ResponseWriter, r *http.Request) error {
	p, _, err := page(r)
	if err != nil {
		return err
	}
	items, err := h.svc.ListReservations(r.Context(), me(r), p.FetchLimit(), int32(p.Offset))
	return ok(w, httpapi.NewList(items, p), err)
}

func (h *Handler) getReservation(w http.ResponseWriter, r *http.Request) error {
	v, err := withID(r, func(id uuid.UUID) (any, error) { return h.svc.GetReservation(r.Context(), me(r), id) })
	return ok(w, v, err)
}

func (h *Handler) payReservation(w http.ResponseWriter, r *http.Request) error {
	var in PayInput
	if err := httpapi.Decode(r, &in); err != nil {
		return err
	}
	v, err := withID(r, func(id uuid.UUID) (any, error) { return h.svc.PayReservation(r.Context(), me(r), id, in) })
	return ok(w, v, err)
}

func (h *Handler) cancelReservation(w http.ResponseWriter, r *http.Request) error {
	var in reasonInput
	if err := httpapi.Decode(r, &in); err != nil {
		return err
	}
	v, err := withID(r, func(id uuid.UUID) (any, error) { return h.svc.CancelReservation(r.Context(), me(r), id, in.Reason) })
	return ok(w, v, err)
}

func (h *Handler) getPayment(w http.ResponseWriter, r *http.Request) error {
	v, err := withID(r, func(id uuid.UUID) (any, error) { return h.svc.GetPayment(r.Context(), me(r), id) })
	return ok(w, v, err)
}

func (h *Handler) simulate(w http.ResponseWriter, r *http.Request) error {
	var in struct {
		Outcome payments.ProviderStatus `json:"outcome"`
	}
	if err := httpapi.Decode(r, &in); err != nil {
		return err
	}
	_, err := withID(r, func(id uuid.UUID) (any, error) {
		return nil, h.svc.DevSimulate(r.Context(), h.fake, me(r), id, in.Outcome)
	})
	return ok(w, map[string]string{"status": "webhook_sent"}, err)
}

func (h *Handler) cancelPayment(w http.ResponseWriter, r *http.Request) error {
	v, err := withID(r, func(id uuid.UUID) (any, error) { return h.svc.CancelPayment(r.Context(), me(r), id) })
	return ok(w, v, err)
}

// --- Pharmacie --------------------------------------------------------------------------------

func (h *Handler) apply(w http.ResponseWriter, r *http.Request) error {
	var in ApplicationInput
	if err := httpapi.Decode(r, &in); err != nil {
		return err
	}
	p, err := h.svc.Apply(r.Context(), me(r), in)
	if err != nil {
		return err
	}
	return httpapi.Created(w, p)
}

func (h *Handler) me(w http.ResponseWriter, r *http.Request) error {
	p, err := h.svc.Me(r.Context(), me(r))
	return ok(w, p, err)
}

func (h *Handler) updateContact(w http.ResponseWriter, r *http.Request) error {
	var in ContactInput
	if err := httpapi.Decode(r, &in); err != nil {
		return err
	}
	p, err := h.svc.UpdateContact(r.Context(), me(r), in)
	return ok(w, p, err)
}

func (h *Handler) addDocument(w http.ResponseWriter, r *http.Request) error {
	var in struct {
		Kind      string `json:"kind"`
		ObjectKey string `json:"object_key"`
	}
	if err := httpapi.Decode(r, &in); err != nil {
		return err
	}
	p, err := h.svc.AddDocument(r.Context(), me(r), in.Kind, in.ObjectKey)
	if err != nil {
		return err
	}
	return httpapi.Created(w, p)
}

func (h *Handler) setStatus(w http.ResponseWriter, r *http.Request) error {
	var in struct {
		IsOpen bool `json:"is_open"`
		OnDuty bool `json:"on_duty"`
	}
	if err := httpapi.Decode(r, &in); err != nil {
		return err
	}
	p, err := h.svc.SetOpenStatus(r.Context(), me(r), in.IsOpen, in.OnDuty)
	return ok(w, p, err)
}

func (h *Handler) inbox(w http.ResponseWriter, r *http.Request) error {
	p, q, err := page(r)
	if err != nil {
		return err
	}
	openOnly := boolParam(q, "open_only", true)
	if err := q.Err(); err != nil {
		return err
	}
	items, err := h.svc.Inbox(r.Context(), me(r), openOnly, p.FetchLimit(), int32(p.Offset))
	return ok(w, httpapi.NewList(items, p), err)
}

func (h *Handler) inboxGet(w http.ResponseWriter, r *http.Request) error {
	v, err := withID(r, func(id uuid.UUID) (any, error) { return h.svc.InboxGet(r.Context(), me(r), id) })
	return ok(w, v, err)
}

func (h *Handler) respond(w http.ResponseWriter, r *http.Request) error {
	var in ResponseInput
	if err := httpapi.Decode(r, &in); err != nil {
		return err
	}
	v, err := withID(r, func(id uuid.UUID) (any, error) { return h.svc.Respond(r.Context(), me(r), id, in) })
	return ok(w, v, err)
}

func (h *Handler) decline(w http.ResponseWriter, r *http.Request) error {
	v, err := withID(r, func(id uuid.UUID) (any, error) { return h.svc.Decline(r.Context(), me(r), id) })
	return ok(w, v, err)
}

func (h *Handler) pharmacyReservations(w http.ResponseWriter, r *http.Request) error {
	p, q, err := page(r)
	if err != nil {
		return err
	}
	activeOnly := boolParam(q, "active_only", false)
	if err := q.Err(); err != nil {
		return err
	}
	items, err := h.svc.PharmacyReservations(r.Context(), me(r), activeOnly, p.FetchLimit(), int32(p.Offset))
	return ok(w, httpapi.NewList(items, p), err)
}

func (h *Handler) pharmacyReservation(w http.ResponseWriter, r *http.Request) error {
	v, err := withID(r, func(id uuid.UUID) (any, error) { return h.svc.PharmacyGetReservation(r.Context(), me(r), id) })
	return ok(w, v, err)
}

func (h *Handler) completePickup(w http.ResponseWriter, r *http.Request) error {
	var in codeInput
	if err := httpapi.Decode(r, &in); err != nil {
		return err
	}
	v, err := withID(r, func(id uuid.UUID) (any, error) { return h.svc.CompletePickup(r.Context(), me(r), id, in.Code) })
	return ok(w, v, err)
}

func (h *Handler) pharmacyCancel(w http.ResponseWriter, r *http.Request) error {
	var in reasonInput
	if err := httpapi.Decode(r, &in); err != nil {
		return err
	}
	v, err := withID(r, func(id uuid.UUID) (any, error) {
		return h.svc.PharmacyCancelReservation(r.Context(), me(r), id, in.Reason)
	})
	return ok(w, v, err)
}

func (h *Handler) earnings(w http.ResponseWriter, r *http.Request) error {
	e, err := h.svc.Earnings(r.Context(), me(r))
	return ok(w, e, err)
}

// --- Livreur ----------------------------------------------------------------------------------

func (h *Handler) currentOffer(w http.ResponseWriter, r *http.Request) error {
	o, err := h.svc.CurrentCourierOffer(r.Context(), me(r))
	return ok(w, map[string]any{"offer": o}, err)
}

func (h *Handler) acceptOffer(w http.ResponseWriter, r *http.Request) error {
	v, err := withID(r, func(id uuid.UUID) (any, error) { return h.svc.AcceptCourierOffer(r.Context(), me(r), id) })
	return ok(w, v, err)
}

func (h *Handler) declineOffer(w http.ResponseWriter, r *http.Request) error {
	id, err := httpapi.PathUUID(r, "id")
	if err != nil {
		return err
	}
	if err := h.svc.DeclineCourierOffer(r.Context(), me(r), id); err != nil {
		return err
	}
	return httpapi.NoContent(w)
}

func (h *Handler) currentMission(w http.ResponseWriter, r *http.Request) error {
	m, err := h.svc.CurrentCourierMission(r.Context(), me(r))
	return ok(w, map[string]any{"mission": m}, err)
}

func (h *Handler) missionHistory(w http.ResponseWriter, r *http.Request) error {
	p, _, err := page(r)
	if err != nil {
		return err
	}
	items, err := h.svc.CourierHistory(r.Context(), me(r), p.FetchLimit(), int32(p.Offset))
	return ok(w, httpapi.NewList(items, p), err)
}

func (h *Handler) pickedUp(w http.ResponseWriter, r *http.Request) error {
	v, err := withID(r, func(id uuid.UUID) (any, error) { return h.svc.CourierPickedUp(r.Context(), me(r), id) })
	return ok(w, v, err)
}

func (h *Handler) delivered(w http.ResponseWriter, r *http.Request) error {
	var in codeInput
	if err := httpapi.Decode(r, &in); err != nil {
		return err
	}
	v, err := withID(r, func(id uuid.UUID) (any, error) { return h.svc.CourierDeliver(r.Context(), me(r), id, in.Code) })
	return ok(w, v, err)
}

func (h *Handler) withdraw(w http.ResponseWriter, r *http.Request) error {
	var in reasonInput
	if err := httpapi.Decode(r, &in); err != nil {
		return err
	}
	id, err := httpapi.PathUUID(r, "id")
	if err != nil {
		return err
	}
	if err := h.svc.CourierWithdraw(r.Context(), me(r), id, in.Reason); err != nil {
		return err
	}
	return httpapi.NoContent(w)
}

// --- Back-office ------------------------------------------------------------------------------

func (h *Handler) adminList(w http.ResponseWriter, r *http.Request) error {
	p, q, err := page(r)
	if err != nil {
		return err
	}
	status := q.Enum("review_status", "", ReviewPending, ReviewApproved, ReviewRejected)
	suspended := boolParam(q, "suspended_only", false)
	search := q.String("q", 100)
	if err := q.Err(); err != nil {
		return err
	}
	items, err := h.svc.AdminList(r.Context(), status, suspended, search, p.FetchLimit(), int32(p.Offset))
	return ok(w, httpapi.NewList(items, p), err)
}

func (h *Handler) adminGet(w http.ResponseWriter, r *http.Request) error {
	v, err := withID(r, func(id uuid.UUID) (any, error) { return h.svc.AdminGet(r.Context(), id, true) })
	return ok(w, v, err)
}

func (h *Handler) adminReview(w http.ResponseWriter, r *http.Request) error {
	var in struct {
		Decision string `json:"decision"`
		Reason   string `json:"reason"`
	}
	if err := httpapi.Decode(r, &in); err != nil {
		return err
	}
	v, err := withID(r, func(id uuid.UUID) (any, error) { return h.svc.Review(r.Context(), me(r), id, in.Decision, in.Reason) })
	return ok(w, v, err)
}

func (h *Handler) adminEarnings(w http.ResponseWriter, r *http.Request) error {
	v, err := withID(r, func(id uuid.UUID) (any, error) { return h.svc.AdminEarnings(r.Context(), id) })
	return ok(w, v, err)
}

func (h *Handler) adminPayout(w http.ResponseWriter, r *http.Request) error {
	var in struct {
		AmountXOF int64  `json:"amount_xof"`
		Reference string `json:"reference"`
		Note      string `json:"note"`
	}
	if err := httpapi.Decode(r, &in); err != nil {
		return err
	}
	v, err := withID(r, func(id uuid.UUID) (any, error) {
		return h.svc.RecordPayout(r.Context(), me(r), id, in.AmountXOF, in.Reference, in.Note)
	})
	if err != nil {
		return err
	}
	return httpapi.Created(w, v)
}

func (h *Handler) adminAlerts(w http.ResponseWriter, r *http.Request) error {
	p, q, err := page(r)
	if err != nil {
		return err
	}
	status := q.Enum("status", "", AlertSearching, AlertAnswered, AlertNoResponse, AlertUnlocked, AlertFulfilled, AlertCancelled)
	if err := q.Err(); err != nil {
		return err
	}
	items, err := h.svc.AdminListAlerts(r.Context(), status, p.FetchLimit(), int32(p.Offset))
	return ok(w, httpapi.NewList(items, p), err)
}

func (h *Handler) adminAlert(w http.ResponseWriter, r *http.Request) error {
	v, err := withID(r, func(id uuid.UUID) (any, error) { return h.svc.AdminGetAlert(r.Context(), id) })
	return ok(w, v, err)
}

func (h *Handler) adminPayments(w http.ResponseWriter, r *http.Request) error {
	p, q, err := page(r)
	if err != nil {
		return err
	}
	status := q.Enum("status", "", PayPending, PaySucceeded, PayFailed, PayExpired, PayRefundPending, PayRefunded)
	alertID := q.UUID("alert_id")
	if err := q.Err(); err != nil {
		return err
	}
	items, err := h.svc.AdminListPayments(r.Context(), status, alertID, p.FetchLimit(), int32(p.Offset))
	return ok(w, httpapi.NewList(items, p), err)
}

func (h *Handler) adminRefund(w http.ResponseWriter, r *http.Request) error {
	var in reasonInput
	if err := httpapi.Decode(r, &in); err != nil {
		return err
	}
	v, err := withID(r, func(id uuid.UUID) (any, error) { return h.svc.AdminRefund(r.Context(), me(r), id, in.Reason) })
	return ok(w, v, err)
}

func (h *Handler) getSettings(w http.ResponseWriter, r *http.Request) error {
	s, err := h.svc.Settings(r.Context())
	return ok(w, s, err)
}

func (h *Handler) putSettings(w http.ResponseWriter, r *http.Request) error {
	var in struct {
		SettingsPatch
		Reason string `json:"reason"`
	}
	if err := httpapi.Decode(r, &in); err != nil {
		return err
	}
	s, err := h.svc.UpdateSettings(r.Context(), me(r), in.SettingsPatch, in.Reason)
	return ok(w, s, err)
}

func (h *Handler) overview(w http.ResponseWriter, r *http.Request) error {
	q := httpapi.NewQuery(r)
	from := q.Date("from")
	to := q.Date("to")
	if err := q.Err(); err != nil {
		return err
	}
	end := time.Now()
	if to != nil {
		end = to.AddDate(0, 0, 1)
	}
	start := end.AddDate(0, 0, -30)
	if from != nil {
		start = *from
	}
	o, err := h.svc.Overview(r.Context(), start, end)
	return ok(w, o, err)
}
