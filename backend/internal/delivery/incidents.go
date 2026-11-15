package delivery

// Signalements des livreurs (colis endommagé, adresse introuvable, code refusé, accident) et date
// d'expiration des pièces, saisie par l'équipe ivia.

import (
	"context"
	"fmt"
	"net/http"
	"time"

	"github.com/google/uuid"

	"ivia/backend/internal/admin"
	"ivia/backend/internal/delivery/store"
	"ivia/backend/internal/geo"
	"ivia/backend/internal/platform/apperr"
	"ivia/backend/internal/platform/database"
	"ivia/backend/internal/platform/httpapi"
	"ivia/backend/internal/platform/identity"
	"ivia/backend/internal/platform/validate"
	"ivia/backend/internal/uploads"
)

var incidentLabels = map[string]string{
	"damaged_parcel": "Colis endommagé", "address_not_found": "Adresse introuvable",
	"code_refused": "Code refusé", "accident": "Accident ou urgence", "other": "Autre problème",
}

// IncidentInput est un signalement envoyé par le livreur.
type IncidentInput struct {
	Kind        string     `json:"kind"`
	MissionType *string    `json:"mission_type"`
	MissionID   *uuid.UUID `json:"mission_id"`
	Note        string     `json:"note"`
	PhotoKey    *string    `json:"photo_key"`
	Lat         *float64   `json:"lat"`
	Lng         *float64   `json:"lng"`
}

// Incident est un signalement ; PhotoURL n'est donnée qu'au back-office.
type Incident struct {
	ID             uuid.UUID  `json:"id"`
	DriverID       uuid.UUID  `json:"driver_id"`
	Kind           string     `json:"kind"`
	MissionType    *string    `json:"mission_type"`
	MissionID      *uuid.UUID `json:"mission_id"`
	Note           string     `json:"note"`
	HasPhoto       bool       `json:"has_photo"`
	PhotoURL       string     `json:"photo_url,omitempty"`
	Location       *geo.Point `json:"location"`
	Status         string     `json:"status"`
	ResolutionNote string     `json:"resolution_note"`
	ResolvedAt     *time.Time `json:"resolved_at"`
	CreatedAt      time.Time  `json:"created_at"`
}

func (s *Service) toIncident(ctx context.Context, r store.ListIncidentsRow, withURL bool) (Incident, error) {
	in := Incident{
		ID: r.ID, DriverID: r.DriverID, Kind: r.Kind, MissionType: r.MissionType, MissionID: r.MissionID, Note: r.Note,
		HasPhoto: r.PhotoKey != nil, Status: r.Status, ResolutionNote: r.ResolutionNote, ResolvedAt: r.ResolvedAt, CreatedAt: r.CreatedAt,
	}
	if r.HasLocation {
		in.Location = &geo.Point{Lat: r.Lat, Lng: r.Lng}
	}
	if withURL && r.PhotoKey != nil {
		u, err := s.uploads.PrivateURL(ctx, *r.PhotoKey)
		if err != nil {
			return Incident{}, err
		}
		in.PhotoURL = u
	}
	return in, nil
}

// ReportIncident enregistre un signalement et prévient l'équipe ivia. La photo est envoyée d'abord
// dans le dossier privé du livreur (même usage que ses pièces).
func (s *Service) ReportIncident(ctx context.Context, driverID uuid.UUID, in IncidentInput) (Incident, error) {
	if _, err := s.requireActiveDriver(ctx, driverID); err != nil {
		return Incident{}, err
	}
	in.Note = validate.Clean(in.Note)
	v := validate.New()
	_, known := incidentLabels[in.Kind]
	v.Check(known, "kind", "Type attendu : damaged_parcel, address_not_found, code_refused, accident ou other.")
	v.Text("note", in.Note, 0, 500)
	v.Check((in.MissionType == nil) == (in.MissionID == nil), "mission_id", "Indiquez la mission et son type ensemble.")
	if in.MissionType != nil {
		v.Check(*in.MissionType == "shop" || *in.MissionType == "pharmacy", "mission_type", "Type attendu : shop ou pharmacy.")
	}
	v.Check((in.Lat == nil) == (in.Lng == nil), "lat", "Indiquez la latitude et la longitude ensemble.")
	if in.Lat != nil && in.Lng != nil {
		v.Coordinates("", *in.Lat, *in.Lng)
	}
	if err := v.Err(); err != nil {
		return Incident{}, err
	}
	q := store.New(s.db.Conn(ctx))
	if in.MissionID != nil {
		var owned bool
		var err error
		if *in.MissionType == "shop" {
			owned, err = q.DeliveryOwnedBy(ctx, store.DeliveryOwnedByParams{ID: *in.MissionID, DriverID: driverID})
		} else if s.pharmacy != nil {
			owned, err = s.pharmacy.OwnsCourierMission(ctx, driverID, *in.MissionID)
		}
		if err != nil {
			return Incident{}, fmt.Errorf("mission du signalement : %w", err)
		}
		if !owned {
			return Incident{}, apperr.NotFound("mission_not_found", "Mission introuvable.")
		}
	}
	if in.PhotoKey != nil {
		if err := s.uploads.Check(ctx, uploads.DriverDocument, driverID, *in.PhotoKey, "photo_key"); err != nil {
			return Incident{}, err
		}
	}
	var id uuid.UUID
	err := s.db.InTx(ctx, func(ctx context.Context) error {
		var err error
		id, err = store.New(s.db.Conn(ctx)).InsertIncident(ctx, store.InsertIncidentParams{
			DriverID: driverID, Kind: in.Kind, MissionType: in.MissionType, MissionID: in.MissionID, Note: in.Note,
			PhotoKey: in.PhotoKey, Lat: in.Lat, Lng: in.Lng,
		})
		if err != nil {
			return fmt.Errorf("signalement : %w", err)
		}
		title := "Signalement d'un livreur : " + incidentLabels[in.Kind]
		if in.Kind == "accident" {
			title = "URGENT : accident ou urgence signalé par un livreur"
		}
		return s.notify.NotifyAdmins(ctx, "driver_incident", title, "Un livreur a envoyé un signalement à traiter.",
			map[string]string{"incident_id": id.String(), "driver_id": driverID.String()})
	})
	if err != nil {
		return Incident{}, err
	}
	return s.incident(ctx, id, false)
}

func (s *Service) incident(ctx context.Context, id uuid.UUID, withURL bool) (Incident, error) {
	r, err := store.New(s.db.Conn(ctx)).GetIncident(ctx, id)
	if database.IsNoRows(err) {
		return Incident{}, apperr.NotFound("incident_not_found", "Signalement introuvable.")
	}
	if err != nil {
		return Incident{}, fmt.Errorf("lecture du signalement : %w", err)
	}
	return s.toIncident(ctx, store.ListIncidentsRow(r), withURL)
}

// Incidents liste des signalements : ceux d'un livreur (driverID) ou tous (back-office).
func (s *Service) Incidents(ctx context.Context, driverID *uuid.UUID, status string, withURL bool, limit, offset int32) ([]Incident, error) {
	var st *string
	if status != "" {
		st = &status
	}
	rows, err := store.New(s.db.Conn(ctx)).ListIncidents(ctx, store.ListIncidentsParams{Status: st, DriverID: driverID, Lim: limit, Off: offset})
	if err != nil {
		return nil, fmt.Errorf("liste des signalements : %w", err)
	}
	out := make([]Incident, 0, len(rows))
	for _, r := range rows {
		in, err := s.toIncident(ctx, r, withURL)
		if err != nil {
			return nil, err
		}
		out = append(out, in)
	}
	return out, nil
}

// ResolveIncident clôt un signalement (journalisé).
func (s *Service) ResolveIncident(ctx context.Context, adminID, id uuid.UUID, note string) (Incident, error) {
	note = validate.Clean(note)
	v := validate.New()
	v.Text("note", note, 3, 500)
	if err := v.Err(); err != nil {
		return Incident{}, err
	}
	err := s.db.InTx(ctx, func(ctx context.Context) error {
		n, err := store.New(s.db.Conn(ctx)).ResolveIncident(ctx, store.ResolveIncidentParams{ID: id, Note: note, AdminID: &adminID})
		if err != nil {
			return fmt.Errorf("clôture du signalement : %w", err)
		}
		if n == 0 {
			return apperr.Conflict("incident_not_open", "Ce signalement est introuvable ou déjà traité.")
		}
		return s.admin.Record(ctx, admin.AuditEntry{
			AdminID: &adminID, Action: "driver.incident_resolved", TargetType: "driver_incident", TargetID: id.String(), Reason: note,
		})
	})
	if err != nil {
		return Incident{}, err
	}
	return s.incident(ctx, id, true)
}

// SetDocumentExpiry enregistre (ou retire) la date d'expiration d'une pièce, lue par l'équipe ivia
// à la vérification (journalisé).
func (s *Service) SetDocumentExpiry(ctx context.Context, adminID, driverID, documentID uuid.UUID, expiresOn *string) (AdminDriver, error) {
	var date *time.Time
	if expiresOn != nil && *expiresOn != "" {
		d, err := time.Parse(time.DateOnly, *expiresOn)
		if err != nil {
			return AdminDriver{}, apperr.Validation(map[string]string{"expires_on": "Date attendue au format AAAA-MM-JJ."})
		}
		date = &d
	}
	err := s.db.InTx(ctx, func(ctx context.Context) error {
		n, err := store.New(s.db.Conn(ctx)).SetDocumentExpiry(ctx, store.SetDocumentExpiryParams{ID: documentID, DriverID: driverID, ExpiresOn: date})
		if err != nil {
			return fmt.Errorf("expiration de la pièce : %w", err)
		}
		if n == 0 {
			return apperr.NotFound("document_not_found", "Pièce introuvable.")
		}
		after := map[string]any{"expires_on": nil}
		if date != nil {
			after["expires_on"] = date.Format(time.DateOnly)
		}
		return s.admin.Record(ctx, admin.AuditEntry{
			AdminID: &adminID, Action: "driver.document_expiry", TargetType: "driver_document", TargetID: documentID.String(), After: after,
		})
	})
	if err != nil {
		return AdminDriver{}, err
	}
	return s.AdminGet(ctx, driverID, true)
}

// --- Routes -----------------------------------------------------------------------------------

func (h *Handler) registerIncidents(rt *httpapi.Router) {
	rt.Roles("POST /v1/driver/incidents", h.reportIncident, identity.RoleDriver)
	rt.Roles("GET /v1/driver/incidents", h.myIncidents, identity.RoleDriver)
	rt.Roles("GET /v1/admin/driver-incidents", h.adminIncidents, identity.RoleAdmin)
	rt.Roles("POST /v1/admin/driver-incidents/{id}/resolve", h.resolveIncident, identity.RoleAdmin)
	rt.Roles("PUT /v1/admin/drivers/{id}/documents/{document_id}/expiry", h.documentExpiry, identity.RoleAdmin)
}

func (h *Handler) reportIncident(w http.ResponseWriter, r *http.Request) error {
	var in IncidentInput
	if err := httpapi.Decode(r, &in); err != nil {
		return err
	}
	v, err := h.svc.ReportIncident(r.Context(), me(r).UserID, in)
	if err != nil {
		return err
	}
	return httpapi.Created(w, v)
}

func (h *Handler) myIncidents(w http.ResponseWriter, r *http.Request) error {
	q := httpapi.NewQuery(r)
	page := q.Page()
	if err := q.Err(); err != nil {
		return err
	}
	id := me(r).UserID
	items, err := h.svc.Incidents(r.Context(), &id, "", false, page.FetchLimit(), int32(page.Offset))
	if err != nil {
		return err
	}
	return httpapi.OK(w, httpapi.NewList(items, page))
}

func (h *Handler) adminIncidents(w http.ResponseWriter, r *http.Request) error {
	q := httpapi.NewQuery(r)
	page := q.Page()
	status := q.Enum("status", "", "open", "resolved")
	if err := q.Err(); err != nil {
		return err
	}
	items, err := h.svc.Incidents(r.Context(), nil, status, true, page.FetchLimit(), int32(page.Offset))
	if err != nil {
		return err
	}
	return httpapi.OK(w, httpapi.NewList(items, page))
}

func (h *Handler) resolveIncident(w http.ResponseWriter, r *http.Request) error {
	id, err := httpapi.PathUUID(r, "id")
	if err != nil {
		return err
	}
	var in struct {
		Note string `json:"note"`
	}
	if err := httpapi.Decode(r, &in); err != nil {
		return err
	}
	v, err := h.svc.ResolveIncident(r.Context(), me(r).UserID, id, in.Note)
	if err != nil {
		return err
	}
	return httpapi.OK(w, v)
}

func (h *Handler) documentExpiry(w http.ResponseWriter, r *http.Request) error {
	id, err := httpapi.PathUUID(r, "id")
	if err != nil {
		return err
	}
	docID, err := httpapi.PathUUID(r, "document_id")
	if err != nil {
		return err
	}
	var in struct {
		ExpiresOn *string `json:"expires_on"`
	}
	if err := httpapi.Decode(r, &in); err != nil {
		return err
	}
	v, err := h.svc.SetDocumentExpiry(r.Context(), me(r).UserID, id, docID, in.ExpiresOn)
	if err != nil {
		return err
	}
	return httpapi.OK(w, v)
}
