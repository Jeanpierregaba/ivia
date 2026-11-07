package delivery

import (
	"context"
	"encoding/csv"
	"net/http"
	"strconv"
	"time"

	"github.com/google/uuid"

	"ivia/backend/internal/platform/apperr"
	"ivia/backend/internal/platform/httpapi"
	"ivia/backend/internal/platform/identity"
)

// Lome est le fuseau des périodes d'export.
var Lome = mustLoadLocation("Africa/Lome")

func mustLoadLocation(name string) *time.Location {
	loc, err := time.LoadLocation(name)
	if err != nil {
		// Lomé est en UTC toute l'année (pas d'heure d'été) : repli sûr si la base tz manque.
		return time.FixedZone("Africa/Lome", 0)
	}
	return loc
}

// Handler expose les routes des livreurs et des livraisons.
type Handler struct {
	svc *Service
}

// NewHandler crée le handler.
func NewHandler(svc *Service) *Handler { return &Handler{svc: svc} }

// Register enregistre les routes.
func (h *Handler) Register(rt *httpapi.Router) {
	// Candidature : ouverte à tout utilisateur connecté (le rôle driver vient de la validation).
	rt.Auth("GET /v1/driver/me", h.me)
	h.registerPartner(rt)
	rt.Auth("PUT /v1/driver/application", h.apply)
	rt.Auth("POST /v1/driver/application/documents", h.addDocument)

	rt.Roles("PUT /v1/driver/availability", h.availability, identity.RoleDriver)
	rt.Roles("POST /v1/driver/location", h.location, identity.RoleDriver)
	rt.Roles("GET /v1/driver/offers/current", h.currentOffer, identity.RoleDriver)
	rt.Roles("POST /v1/driver/offers/{id}/accept", h.acceptOffer, identity.RoleDriver)
	rt.Roles("POST /v1/driver/offers/{id}/decline", h.declineOffer, identity.RoleDriver)
	rt.Roles("GET /v1/driver/missions/current", h.currentMission, identity.RoleDriver)
	rt.Roles("GET /v1/driver/missions", h.history, identity.RoleDriver)
	rt.Roles("POST /v1/driver/missions/{id}/arrived-at-shop", h.step(h.svc.ArrivedAtShop), identity.RoleDriver)
	rt.Roles("POST /v1/driver/missions/{id}/picked-up", h.step(h.svc.PickedUp), identity.RoleDriver)
	rt.Roles("POST /v1/driver/missions/{id}/arrived-at-customer", h.step(h.svc.ArrivedAtCustomer), identity.RoleDriver)
	rt.Roles("POST /v1/driver/missions/{id}/deliver", h.deliver, identity.RoleDriver)
	rt.Roles("POST /v1/driver/missions/{id}/fail", h.fail, identity.RoleDriver)
	rt.Roles("POST /v1/driver/missions/{id}/withdraw", h.withdraw, identity.RoleDriver)

	rt.Roles("GET /v1/orders/{id}/delivery", h.buyerInfo, identity.RoleBuyer)
	rt.Roles("GET /v1/seller/orders/{id}/delivery", h.sellerInfo, identity.RoleSeller)

	rt.Roles("GET /v1/admin/drivers", h.adminList, identity.RoleAdmin)
	rt.Roles("GET /v1/admin/drivers/{id}", h.adminGet, identity.RoleAdmin)
	for _, d := range []string{"approve", "reject", "suspend", "reinstate"} {
		rt.Roles("POST /v1/admin/drivers/{id}/"+d, h.review(d), identity.RoleAdmin)
	}
	rt.Roles("POST /v1/admin/orders/{id}/unassign-driver", h.adminUnassign, identity.RoleAdmin)
	rt.Roles("GET /v1/admin/delivery-alerts", h.alerts, identity.RoleAdmin)
	rt.Roles("GET /v1/admin/deliveries/export", h.export, identity.RoleAdmin)
}

func me(r *http.Request) identity.Principal { return identity.MustFromContext(r.Context()) }

func (h *Handler) me(w http.ResponseWriter, r *http.Request) error {
	d, err := h.svc.Me(r.Context(), me(r).UserID)
	if err != nil {
		return err
	}
	return httpapi.OK(w, d)
}

func (h *Handler) apply(w http.ResponseWriter, r *http.Request) error {
	var in ApplicationInput
	if err := httpapi.Decode(r, &in); err != nil {
		return err
	}
	d, err := h.svc.Apply(r.Context(), me(r).UserID, in)
	if err != nil {
		return err
	}
	return httpapi.OK(w, d)
}

func (h *Handler) addDocument(w http.ResponseWriter, r *http.Request) error {
	var in struct {
		Kind      string `json:"kind"`
		ObjectKey string `json:"object_key"`
	}
	if err := httpapi.Decode(r, &in); err != nil {
		return err
	}
	d, err := h.svc.AddDocument(r.Context(), me(r).UserID, in.Kind, in.ObjectKey)
	if err != nil {
		return err
	}
	return httpapi.Created(w, d)
}

func (h *Handler) availability(w http.ResponseWriter, r *http.Request) error {
	var in struct {
		Online   bool   `json:"online"`
		Activity string `json:"activity"`
	}
	if err := httpapi.Decode(r, &in); err != nil {
		return err
	}
	// En ligne sur une seule activité à la fois : seules les missions de livraison existent.
	if in.Online && in.Activity == ActivityVTC {
		return apperr.Conflict("vtc_not_open", "Les courses Taxi VTC ne sont pas encore ouvertes : passez en ligne en livraison.")
	}
	d, err := h.svc.SetAvailability(r.Context(), me(r).UserID, in.Online)
	if err != nil {
		return err
	}
	return httpapi.OK(w, d)
}

func (h *Handler) location(w http.ResponseWriter, r *http.Request) error {
	var in LocationInput
	if err := httpapi.Decode(r, &in); err != nil {
		return err
	}
	if err := h.svc.UpdateLocation(r.Context(), me(r).UserID, in); err != nil {
		return err
	}
	return httpapi.NoContent(w)
}

func (h *Handler) currentOffer(w http.ResponseWriter, r *http.Request) error {
	o, err := h.svc.CurrentOffer(r.Context(), me(r).UserID)
	if err != nil {
		return err
	}
	return httpapi.OK(w, map[string]any{"offer": o})
}

func (h *Handler) acceptOffer(w http.ResponseWriter, r *http.Request) error {
	id, err := httpapi.PathUUID(r, "id")
	if err != nil {
		return err
	}
	m, err := h.svc.AcceptOffer(r.Context(), me(r).UserID, id)
	if err != nil {
		return err
	}
	return httpapi.OK(w, m)
}

func (h *Handler) declineOffer(w http.ResponseWriter, r *http.Request) error {
	id, err := httpapi.PathUUID(r, "id")
	if err != nil {
		return err
	}
	if err := h.svc.DeclineOffer(r.Context(), me(r).UserID, id); err != nil {
		return err
	}
	return httpapi.NoContent(w)
}

func (h *Handler) currentMission(w http.ResponseWriter, r *http.Request) error {
	m, err := h.svc.CurrentMission(r.Context(), me(r).UserID)
	if err != nil {
		return err
	}
	return httpapi.OK(w, map[string]any{"mission": m})
}

func (h *Handler) history(w http.ResponseWriter, r *http.Request) error {
	q := httpapi.NewQuery(r)
	page := q.Page()
	if err := q.Err(); err != nil {
		return err
	}
	items, err := h.svc.History(r.Context(), me(r).UserID, page.FetchLimit(), int32(page.Offset))
	if err != nil {
		return err
	}
	return httpapi.OK(w, httpapi.NewList(items, page))
}

type stepFn = func(ctx context.Context, driverID, deliveryID uuid.UUID) (Mission, error)

func (h *Handler) step(fn stepFn) httpapi.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) error {
		id, err := httpapi.PathUUID(r, "id")
		if err != nil {
			return err
		}
		m, err := fn(r.Context(), me(r).UserID, id)
		if err != nil {
			return err
		}
		return httpapi.OK(w, m)
	}
}

func (h *Handler) deliver(w http.ResponseWriter, r *http.Request) error {
	id, err := httpapi.PathUUID(r, "id")
	if err != nil {
		return err
	}
	var in struct {
		Code string `json:"code"`
	}
	if err := httpapi.Decode(r, &in); err != nil {
		return err
	}
	m, err := h.svc.Deliver(r.Context(), me(r).UserID, id, in.Code)
	if err != nil {
		return err
	}
	return httpapi.OK(w, m)
}

func (h *Handler) fail(w http.ResponseWriter, r *http.Request) error {
	id, err := httpapi.PathUUID(r, "id")
	if err != nil {
		return err
	}
	var in struct {
		Reason       string `json:"reason"`
		CallAttempts int32  `json:"call_attempts"`
	}
	if err := httpapi.Decode(r, &in); err != nil {
		return err
	}
	m, err := h.svc.Fail(r.Context(), me(r).UserID, id, in.Reason, in.CallAttempts)
	if err != nil {
		return err
	}
	return httpapi.OK(w, m)
}

func (h *Handler) withdraw(w http.ResponseWriter, r *http.Request) error {
	id, err := httpapi.PathUUID(r, "id")
	if err != nil {
		return err
	}
	var in struct {
		Reason string `json:"reason"`
	}
	if err := httpapi.Decode(r, &in); err != nil {
		return err
	}
	if err := h.svc.Withdraw(r.Context(), me(r).UserID, id, in.Reason); err != nil {
		return err
	}
	return httpapi.NoContent(w)
}

func (h *Handler) buyerInfo(w http.ResponseWriter, r *http.Request) error {
	id, err := httpapi.PathUUID(r, "id")
	if err != nil {
		return err
	}
	info, err := h.svc.InfoForBuyer(r.Context(), me(r).UserID, id)
	if err != nil {
		return err
	}
	return httpapi.OK(w, map[string]any{"delivery": info})
}

func (h *Handler) sellerInfo(w http.ResponseWriter, r *http.Request) error {
	id, err := httpapi.PathUUID(r, "id")
	if err != nil {
		return err
	}
	info, err := h.svc.InfoForSeller(r.Context(), me(r).UserID, id)
	if err != nil {
		return err
	}
	return httpapi.OK(w, map[string]any{"delivery": info})
}

func (h *Handler) adminList(w http.ResponseWriter, r *http.Request) error {
	q := httpapi.NewQuery(r)
	page := q.Page()
	review := q.Enum("review_status", "", StatusDraft, ReviewPending, StatusChangesRequested, ReviewApproved, ReviewRejected)
	suspended := q.Enum("suspended", "false", "true", "false") == "true"
	if err := q.Err(); err != nil {
		return err
	}
	items, err := h.svc.AdminList(r.Context(), review, suspended, page.FetchLimit(), int32(page.Offset))
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
	d, err := h.svc.AdminGet(r.Context(), id, true)
	if err != nil {
		return err
	}
	return httpapi.OK(w, d)
}

func (h *Handler) review(decision string) httpapi.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) error {
		id, err := httpapi.PathUUID(r, "id")
		if err != nil {
			return err
		}
		var in struct {
			Reason string `json:"reason"`
		}
		if err := httpapi.Decode(r, &in); err != nil {
			return err
		}
		d, err := h.svc.Review(r.Context(), me(r).UserID, id, decision, in.Reason)
		if err != nil {
			return err
		}
		return httpapi.OK(w, d)
	}
}

func (h *Handler) adminUnassign(w http.ResponseWriter, r *http.Request) error {
	id, err := httpapi.PathUUID(r, "id")
	if err != nil {
		return err
	}
	var in struct {
		Reason string `json:"reason"`
	}
	if err := httpapi.Decode(r, &in); err != nil {
		return err
	}
	if err := h.svc.AdminUnassign(r.Context(), me(r).UserID, id, in.Reason); err != nil {
		return err
	}
	return httpapi.NoContent(w)
}

func (h *Handler) alerts(w http.ResponseWriter, r *http.Request) error {
	items, err := h.svc.Alerts(r.Context())
	if err != nil {
		return err
	}
	return httpapi.OK(w, map[string]any{"items": items})
}

// export retourne le bilan par livreur, en JSON ou en CSV (format=csv), sur une période en dates
// de Lomé (bornes incluses).
func (h *Handler) export(w http.ResponseWriter, r *http.Request) error {
	q := httpapi.NewQuery(r)
	q.Require("from")
	q.Require("to")
	from, to := q.Date("from"), q.Date("to")
	format := q.Enum("format", "json", "json", "csv")
	if err := q.Err(); err != nil {
		return err
	}
	if to.Before(*from) || to.Sub(*from) > 366*24*time.Hour {
		return apperr.Validation(map[string]string{"to": "Période invalide (un an au plus)."})
	}
	start := time.Date(from.Year(), from.Month(), from.Day(), 0, 0, 0, 0, Lome)
	end := time.Date(to.Year(), to.Month(), to.Day(), 0, 0, 0, 0, Lome).AddDate(0, 0, 1)
	rows, err := h.svc.Export(r.Context(), start, end)
	if err != nil {
		return err
	}
	if format == "json" {
		return httpapi.OK(w, map[string]any{"from": from.Format(time.DateOnly), "to": to.Format(time.DateOnly), "items": rows})
	}
	w.Header().Set("Content-Type", "text/csv; charset=utf-8")
	w.Header().Set("Content-Disposition", `attachment; filename="livraisons_`+from.Format("20060102")+`_`+to.Format("20060102")+`.csv"`)
	cw := csv.NewWriter(w)
	cw.Comma = ';' // lisible directement par Excel en français
	_ = cw.Write([]string{"livreur_id", "prenom", "vehicule", "livrees", "echecs", "desistements", "frais_livres_xof"})
	for _, row := range rows {
		_ = cw.Write([]string{
			row.DriverID.String(), row.FirstName, row.VehicleType, strconv.FormatInt(row.Delivered, 10),
			strconv.FormatInt(row.Failed, 10), strconv.FormatInt(row.Withdrawn, 10), strconv.FormatInt(row.DeliveredFeesXOF, 10),
		})
	}
	cw.Flush()
	return cw.Error()
}
