package pharmacy

import (
	"context"
	"fmt"
	"slices"
	"strings"
	"time"

	"github.com/google/uuid"

	"ivia/backend/internal/admin"
	"ivia/backend/internal/geo"
	"ivia/backend/internal/notifications"
	"ivia/backend/internal/pharmacy/store"
	"ivia/backend/internal/platform/apperr"
	"ivia/backend/internal/platform/database"
	"ivia/backend/internal/platform/identity"
	"ivia/backend/internal/platform/validate"
	"ivia/backend/internal/uploads"
)

// RequiredDocuments : pièces sans lesquelles une pharmacie ne peut pas être validée.
var RequiredDocuments = []string{"opening_authorization", "owner_id", "storefront_photo"}

var documentKinds = []string{"opening_authorization", "order_registration", "owner_id", "storefront_photo", "other"}

// Pharmacy est le dossier d'une pharmacie (vu par son titulaire et par l'admin).
type Pharmacy struct {
	ID uuid.UUID `json:"id"`
	// StorefrontURL : lien de courte durée vers la dernière photo de la devanture (photo de profil).
	StorefrontURL  *string    `json:"storefront_url"`
	Name           string     `json:"name"`
	LicenseNumber  string     `json:"license_number"`
	Phone          string     `json:"phone"`
	AddressText    string     `json:"address_text"`
	NeighborhoodID *uuid.UUID `json:"neighborhood_id"`
	Location       geo.Point  `json:"location"`
	OpeningHours   string     `json:"opening_hours"`
	IsOpen         bool       `json:"is_open"`
	OnDuty         bool       `json:"on_duty"`
	Open24h        bool       `json:"open_24h"`
	// DutyUntil : fin de la garde en cours selon le planning (nul hors garde planifiée).
	DutyUntil *time.Time `json:"duty_until"`
	// Status résume : pending_review, approved, rejected ou suspended.
	Status           string         `json:"status"`
	ReviewStatus     string         `json:"review_status"`
	ReviewNote       string         `json:"review_note"`
	ReviewedAt       *time.Time     `json:"reviewed_at"`
	SuspendedAt      *time.Time     `json:"suspended_at"`
	SuspensionReason string         `json:"suspension_reason"`
	Documents        []Document     `json:"documents"`
	MissingDocuments []string       `json:"missing_documents"`
	Payout           *PayoutAccount `json:"payout"`
	SubmittedAt      *time.Time     `json:"submitted_at"`
	Email            string         `json:"email"`
	NightFromHour    int32          `json:"night_from_hour"`
	NightToHour      int32          `json:"night_to_hour"`
	CreatedAt        time.Time      `json:"created_at"`
	UpdatedAt        time.Time      `json:"updated_at"`
}

// Document est une pièce du dossier. L'URL n'est fournie qu'aux admins.
type Document struct {
	ID        uuid.UUID `json:"id"`
	Kind      string    `json:"kind"`
	URL       string    `json:"url,omitempty"`
	CreatedAt time.Time `json:"created_at"`
}

// AdminPharmacy ajoute le titulaire pour le back-office.
type AdminPharmacy struct {
	Pharmacy
	OwnerID        uuid.UUID `json:"owner_id"`
	OwnerFirstName string    `json:"owner_first_name"`
	OwnerPhone     string    `json:"owner_phone"`
}

// ApplicationInput est l'inscription d'une pharmacie.
type ApplicationInput struct {
	Name           string     `json:"name"`
	LicenseNumber  string     `json:"license_number"`
	Phone          string     `json:"phone"`
	Email          string     `json:"email"`
	AddressText    string     `json:"address_text"`
	NeighborhoodID *uuid.UUID `json:"neighborhood_id"`
	Location       geo.Point  `json:"location"`
	OpeningHours   string     `json:"opening_hours"`
}

// ContactInput modifie ce qu'une pharmacie validée peut changer seule.
type ContactInput struct {
	Phone        string `json:"phone"`
	OpeningHours string `json:"opening_hours"`
}

func (s *Service) attachedDocuments(ctx context.Context, keys []string) (map[string]bool, error) {
	found, err := s.q(ctx).DocumentKeysIn(ctx, keys)
	if err != nil {
		return nil, fmt.Errorf("pièces rattachées : %w", err)
	}
	out := make(map[string]bool, len(found))
	for _, k := range found {
		out[k] = true
	}
	return out, nil
}

func pharmacyStatus(r store.GetPharmacyRow) string {
	if r.SuspendedAt != nil {
		return "suspended"
	}
	return r.ReviewStatus
}

func (s *Service) pharmacyView(ctx context.Context, id uuid.UUID, withURLs bool) (Pharmacy, store.GetPharmacyRow, error) {
	q := s.q(ctx)
	r, err := q.GetPharmacy(ctx, id)
	if database.IsNoRows(err) {
		return Pharmacy{}, r, errPharmacyNotFound
	}
	if err != nil {
		return Pharmacy{}, r, fmt.Errorf("lecture de la pharmacie : %w", err)
	}
	docs, err := q.ListDocuments(ctx, id)
	if err != nil {
		return Pharmacy{}, r, fmt.Errorf("pièces de la pharmacie : %w", err)
	}
	p := Pharmacy{
		ID: r.ID, Name: r.Name, LicenseNumber: r.LicenseNumber, Phone: r.Phone, AddressText: r.AddressText,
		NeighborhoodID: r.NeighborhoodID, Location: geo.Point{Lat: r.Lat, Lng: r.Lng}, OpeningHours: r.OpeningHours,
		IsOpen: r.IsOpen, OnDuty: r.OnDuty, Open24h: r.Open24h, DutyUntil: dutyUntil(r.DutyUntil), Status: pharmacyStatus(r), ReviewStatus: r.ReviewStatus, ReviewNote: r.ReviewNote,
		ReviewedAt: r.ReviewedAt, SuspendedAt: r.SuspendedAt, SuspensionReason: r.SuspensionReason,
		Documents: make([]Document, 0, len(docs)), MissingDocuments: []string{}, CreatedAt: r.CreatedAt, UpdatedAt: r.UpdatedAt,
	}
	have := map[string]bool{}
	var storefrontKey string
	for _, d := range docs {
		if d.Kind == "storefront_photo" {
			storefrontKey = d.ObjectKey // pièces par date : la dernière l'emporte
		}
		doc := Document{ID: d.ID, Kind: d.Kind, CreatedAt: d.CreatedAt}
		if withURLs {
			if doc.URL, err = s.uploads.PrivateURL(ctx, d.ObjectKey); err != nil {
				return Pharmacy{}, r, err
			}
		}
		have[d.Kind] = true
		p.Documents = append(p.Documents, doc)
	}
	if storefrontKey != "" {
		u, err := s.uploads.PrivateURL(ctx, storefrontKey)
		if err != nil {
			return Pharmacy{}, r, err
		}
		p.StorefrontURL = &u
	}
	for _, k := range RequiredDocuments {
		if !have[k] {
			p.MissingDocuments = append(p.MissingDocuments, k)
		}
	}
	if err := s.withDossier(ctx, &p, withURLs); err != nil {
		return Pharmacy{}, r, err
	}
	return p, r, nil
}

func (s *Service) pharmacyIDOf(ctx context.Context, ownerID uuid.UUID) (uuid.UUID, error) {
	id, err := s.q(ctx).PharmacyIDByOwner(ctx, ownerID)
	if database.IsNoRows(err) {
		return uuid.Nil, apperr.NotFound("pharmacy_not_found", "Aucune pharmacie inscrite avec ce compte.")
	}
	if err != nil {
		return uuid.Nil, fmt.Errorf("pharmacie du compte : %w", err)
	}
	return id, nil
}

// requireActivePharmacy retourne la pharmacie validée et non suspendue du titulaire.
func (s *Service) requireActivePharmacy(ctx context.Context, ownerID uuid.UUID) (store.GetPharmacyRow, error) {
	id, err := s.pharmacyIDOf(ctx, ownerID)
	if err != nil {
		return store.GetPharmacyRow{}, err
	}
	r, err := s.q(ctx).GetPharmacy(ctx, id)
	if err != nil {
		return store.GetPharmacyRow{}, fmt.Errorf("lecture de la pharmacie : %w", err)
	}
	if r.ReviewStatus != ReviewApproved {
		return r, apperr.Forbidden("pharmacy_not_approved", "Votre pharmacie n'est pas encore validée.")
	}
	if r.SuspendedAt != nil {
		return r, apperr.Forbidden("pharmacy_suspended", "Votre pharmacie est suspendue. Contactez ivia.")
	}
	return r, nil
}

func (s *Service) validateApplication(ctx context.Context, in *ApplicationInput) error {
	in.Name = validate.Clean(in.Name)
	in.LicenseNumber = validate.Clean(in.LicenseNumber)
	in.AddressText = validate.Clean(in.AddressText)
	in.OpeningHours = validate.Clean(in.OpeningHours)
	v := validate.New()
	v.Text("name", in.Name, 2, 120)
	v.Text("license_number", in.LicenseNumber, 2, 60)
	v.Text("address_text", in.AddressText, 3, 300)
	v.Check(len(in.OpeningHours) <= 300, "opening_hours", "300 caractères au plus.")
	phone, ok := validate.NormalizeTogoPhone(in.Phone)
	v.Check(ok, "phone", "Numéro togolais invalide.")
	in.Phone = phone
	email, ok := validate.NormalizeEmail(in.Email)
	v.Check(ok, "email", "Adresse e-mail invalide.")
	in.Email = email
	v.Coordinates("location.", in.Location.Lat, in.Location.Lng)
	if err := v.Err(); err != nil {
		return err
	}
	if in.NeighborhoodID != nil {
		if _, err := s.geo.RequireActive(ctx, *in.NeighborhoodID); err != nil {
			return err
		}
	}
	return nil
}

// Apply inscrit la pharmacie du compte, ou corrige un dossier pas encore validé (un dossier
// refusé repart en vérification). Le rôle pharmacien n'est donné qu'à la validation.
func (s *Service) Apply(ctx context.Context, ownerID uuid.UUID, in ApplicationInput) (Pharmacy, error) {
	if err := s.validateApplication(ctx, &in); err != nil {
		return Pharmacy{}, err
	}
	var id uuid.UUID
	err := s.db.InTx(ctx, func(ctx context.Context) error {
		q := s.q(ctx)
		existing, err := q.PharmacyIDByOwner(ctx, ownerID)
		if err != nil && !database.IsNoRows(err) {
			return fmt.Errorf("pharmacie du compte : %w", err)
		}
		if err == nil {
			id = existing
			n, err := q.UpdateApplication(ctx, store.UpdateApplicationParams{
				ID: id, Name: in.Name, LicenseNumber: in.LicenseNumber, Phone: in.Phone, AddressText: in.AddressText,
				NeighborhoodID: in.NeighborhoodID, Lat: in.Location.Lat, Lng: in.Location.Lng, OpeningHours: in.OpeningHours,
			})
			if err != nil {
				return fmt.Errorf("mise à jour du dossier : %w", err)
			}
			if n == 0 {
				return apperr.Conflict("pharmacy_not_editable", "Dossier envoyé ou validé : il ne se modifie plus pour le moment.")
			}
			if err := q.SetPharmacyEmail(ctx, store.SetPharmacyEmailParams{ID: id, Email: in.Email}); err != nil {
				return fmt.Errorf("e-mail de la pharmacie : %w", err)
			}
			return nil
		}
		id, err = q.CreatePharmacy(ctx, store.CreatePharmacyParams{
			OwnerID: ownerID, Name: in.Name, LicenseNumber: in.LicenseNumber, Phone: in.Phone, AddressText: in.AddressText,
			NeighborhoodID: in.NeighborhoodID, Lat: in.Location.Lat, Lng: in.Location.Lng, OpeningHours: in.OpeningHours,
		})
		if database.IsUniqueViolation(err, "") {
			return apperr.Conflict("pharmacy_exists", "Une pharmacie est déjà inscrite avec ce compte.")
		}
		if err != nil {
			return fmt.Errorf("inscription de la pharmacie : %w", err)
		}
		if err := q.SetPharmacyEmail(ctx, store.SetPharmacyEmailParams{ID: id, Email: in.Email}); err != nil {
			return fmt.Errorf("e-mail de la pharmacie : %w", err)
		}
		return nil
	})
	if err != nil {
		return Pharmacy{}, err
	}
	p, _, err := s.pharmacyView(ctx, id, false)
	return p, err
}

// Me retourne la pharmacie du compte.
func (s *Service) Me(ctx context.Context, ownerID uuid.UUID) (Pharmacy, error) {
	id, err := s.pharmacyIDOf(ctx, ownerID)
	if err != nil {
		return Pharmacy{}, err
	}
	p, _, err := s.pharmacyView(ctx, id, false)
	return p, err
}

// UpdateContact modifie le téléphone et les horaires d'une pharmacie.
func (s *Service) UpdateContact(ctx context.Context, ownerID uuid.UUID, in ContactInput) (Pharmacy, error) {
	id, err := s.pharmacyIDOf(ctx, ownerID)
	if err != nil {
		return Pharmacy{}, err
	}
	v := validate.New()
	phone, ok := validate.NormalizeTogoPhone(in.Phone)
	v.Check(ok, "phone", "Numéro togolais invalide.")
	hours := validate.Clean(in.OpeningHours)
	v.Check(len(hours) <= 300, "opening_hours", "300 caractères au plus.")
	if err := v.Err(); err != nil {
		return Pharmacy{}, err
	}
	if err := s.q(ctx).UpdateContact(ctx, store.UpdateContactParams{ID: id, Phone: phone, OpeningHours: hours}); err != nil {
		return Pharmacy{}, fmt.Errorf("mise à jour de la pharmacie : %w", err)
	}
	p, _, err := s.pharmacyView(ctx, id, false)
	return p, err
}

// OpenStatusInput : ouverture, garde déclarée et ouverture 24 h/24.
type OpenStatusInput struct {
	IsOpen  bool `json:"is_open"`
	OnDuty  bool `json:"on_duty"`
	Open24h bool `json:"open_24h"`
}

// SetOpenStatus ouvre ou ferme la pharmacie, la déclare de garde ou ouverte 24 h/24. Reçoivent
// les alertes : les pharmacies ouvertes, de garde (déclarée ou planifiée) ou ouvertes 24 h/24.
func (s *Service) SetOpenStatus(ctx context.Context, ownerID uuid.UUID, in OpenStatusInput) (Pharmacy, error) {
	r, err := s.requireActivePharmacy(ctx, ownerID)
	if err != nil {
		return Pharmacy{}, err
	}
	if err := s.q(ctx).SetOpenStatus(ctx, store.SetOpenStatusParams{ID: r.ID, IsOpen: in.IsOpen, OnDuty: in.OnDuty, Open24h: in.Open24h}); err != nil {
		return Pharmacy{}, fmt.Errorf("ouverture de la pharmacie : %w", err)
	}
	p, _, err := s.pharmacyView(ctx, r.ID, false)
	return p, err
}

// AddDocument rattache une pièce envoyée dans le compartiment privé (POST /v1/uploads,
// usage pharmacy_document).
func (s *Service) AddDocument(ctx context.Context, ownerID uuid.UUID, kind, objectKey string) (Pharmacy, error) {
	id, err := s.pharmacyIDOf(ctx, ownerID)
	if err != nil {
		return Pharmacy{}, err
	}
	cur, err := s.q(ctx).GetPharmacy(ctx, id)
	if err != nil {
		return Pharmacy{}, fmt.Errorf("lecture de la pharmacie : %w", err)
	}
	if cur.ReviewStatus == ReviewPending {
		return Pharmacy{}, apperr.Conflict("pharmacy_not_editable", "Votre dossier est en cours d'examen.")
	}
	v := validate.New()
	v.Check(slices.Contains(documentKinds, kind), "kind", "Valeur attendue : "+strings.Join(documentKinds, ", ")+".")
	if err := v.Err(); err != nil {
		return Pharmacy{}, err
	}
	if err := s.uploads.Check(ctx, uploads.PharmacyDocument, ownerID, objectKey, "object_key"); err != nil {
		return Pharmacy{}, err
	}
	_, err = s.q(ctx).InsertDocument(ctx, store.InsertDocumentParams{PharmacyID: id, Kind: kind, ObjectKey: objectKey})
	if database.IsUniqueViolation(err, "") {
		return Pharmacy{}, apperr.Conflict("document_exists", "Ce fichier est déjà joint au dossier.")
	}
	if err != nil {
		return Pharmacy{}, fmt.Errorf("ajout de la pièce : %w", err)
	}
	p, _, err := s.pharmacyView(ctx, id, false)
	return p, err
}

// --- Back-office ----------------------------------------------------------------------------

// AdminList liste les pharmacies (filtre de validation, suspendues seulement, recherche par nom).
func (s *Service) AdminList(ctx context.Context, reviewStatus string, suspendedOnly bool, search string, limit, offset int32) ([]AdminPharmacy, error) {
	var st *string
	if reviewStatus != "" {
		st = &reviewStatus
	}
	ids, err := s.q(ctx).ListPharmacyIDs(ctx, store.ListPharmacyIDsParams{
		ReviewStatus: st, SuspendedOnly: suspendedOnly, Q: validate.Clean(search), Lim: limit, Off: offset,
	})
	if err != nil {
		return nil, fmt.Errorf("liste des pharmacies : %w", err)
	}
	out := make([]AdminPharmacy, 0, len(ids))
	for _, id := range ids {
		p, err := s.AdminGet(ctx, id, false)
		if err != nil {
			return nil, err
		}
		out = append(out, p)
	}
	return out, nil
}

// AdminGet retourne le dossier d'une pharmacie ; withURLs ajoute des liens temporaires vers les pièces.
func (s *Service) AdminGet(ctx context.Context, id uuid.UUID, withURLs bool) (AdminPharmacy, error) {
	p, r, err := s.pharmacyView(ctx, id, withURLs)
	if err != nil {
		return AdminPharmacy{}, err
	}
	c, err := s.users.Contact(ctx, r.OwnerID)
	if err != nil {
		return AdminPharmacy{}, err
	}
	return AdminPharmacy{Pharmacy: p, OwnerID: r.OwnerID, OwnerFirstName: c.FirstName, OwnerPhone: c.Phone}, nil
}

// Review applique une décision admin : approve, reject, suspend ou reinstate (journalisée).
func (s *Service) Review(ctx context.Context, adminID, id uuid.UUID, decision, reason string) (AdminPharmacy, error) {
	reason = validate.Clean(reason)
	v := validate.New()
	v.Check(slices.Contains([]string{"approve", "request_changes", "reject", "suspend", "reinstate"}, decision), "decision",
		"Valeur attendue : approve, request_changes, reject, suspend ou reinstate.")
	v.Check(decision == "approve" || decision == "reinstate" || len(reason) >= 3, "reason", "Motif obligatoire (3 caractères au moins).")
	if err := v.Err(); err != nil {
		return AdminPharmacy{}, err
	}
	err := s.db.InTx(ctx, func(ctx context.Context) error {
		q := s.q(ctx)
		cur, err := q.LockPharmacy(ctx, id)
		if database.IsNoRows(err) {
			return errPharmacyNotFound
		}
		if err != nil {
			return fmt.Errorf("verrou de la pharmacie : %w", err)
		}
		before, r, err := s.pharmacyView(ctx, id, false)
		if err != nil {
			return err
		}
		var kind, title, body string
		switch decision {
		case "approve":
			if len(before.MissingDocuments) > 0 {
				return apperr.Unprocessable("documents_missing", "Pièces manquantes : "+strings.Join(before.MissingDocuments, ", ")+".")
			}
			if cur.ReviewStatus != ReviewPending {
				return apperr.Conflict("invalid_transition", "Ce dossier n'est pas en attente de validation.")
			}
			if _, err := q.SetReview(ctx, store.SetReviewParams{ID: id, ReviewStatus: ReviewApproved, ReviewNote: reason, ReviewedBy: &adminID}); err != nil {
				return fmt.Errorf("validation : %w", err)
			}
			if err := s.users.GrantRole(ctx, r.OwnerID, identity.RolePharmacist, &adminID); err != nil {
				return err
			}
			if err := s.jobs.Enqueue(ctx, ApprovalEmailArgs{PharmacyID: id}, nil); err != nil {
				return fmt.Errorf("e-mail de validation : %w", err)
			}
			kind, title, body = "pharmacy_approved", "Pharmacie validée", "Bienvenue sur ivia ! Ouvrez votre pharmacie pour recevoir les alertes."
		case "request_changes":
			if cur.ReviewStatus != ReviewPending {
				return apperr.Conflict("invalid_transition", "Ce dossier n'est pas en attente de validation.")
			}
			if _, err := q.SetReview(ctx, store.SetReviewParams{ID: id, ReviewStatus: ReviewChangesRequested, ReviewNote: reason, ReviewedBy: &adminID}); err != nil {
				return fmt.Errorf("demande de compléments : %w", err)
			}
			kind, title, body = "pharmacy_changes_requested", "Dossier à compléter", "Complétez votre dossier : "+reason
		case "reject":
			if cur.ReviewStatus == ReviewApproved {
				return apperr.Conflict("invalid_transition", "Une pharmacie validée se suspend, elle ne se refuse pas.")
			}
			if _, err := q.SetReview(ctx, store.SetReviewParams{ID: id, ReviewStatus: ReviewRejected, ReviewNote: reason, ReviewedBy: &adminID}); err != nil {
				return fmt.Errorf("refus : %w", err)
			}
			kind, title, body = "pharmacy_rejected", "Dossier refusé", "Votre dossier n'a pas été validé : "+reason
		case "suspend":
			n, err := q.Suspend(ctx, store.SuspendParams{ID: id, Reason: reason})
			if err != nil {
				return fmt.Errorf("suspension : %w", err)
			}
			if n == 0 {
				return apperr.Conflict("invalid_transition", "Cette pharmacie est déjà suspendue.")
			}
			kind, title, body = "pharmacy_suspended", "Pharmacie suspendue", "Votre pharmacie ne reçoit plus d'alertes : "+reason
		case "reinstate":
			n, err := q.Reinstate(ctx, id)
			if err != nil {
				return fmt.Errorf("réactivation : %w", err)
			}
			if n == 0 {
				return apperr.Conflict("invalid_transition", "Cette pharmacie n'est pas suspendue.")
			}
			kind, title, body = "pharmacy_reinstated", "Pharmacie réactivée", "Vous pouvez de nouveau recevoir les alertes."
		}
		after, _, err := s.pharmacyView(ctx, id, false)
		if err != nil {
			return err
		}
		if err := s.admin.Record(ctx, admin.AuditEntry{
			AdminID: &adminID, Action: "pharmacy." + decision, TargetType: "pharmacy", TargetID: id.String(),
			Before: map[string]any{"status": before.Status}, After: map[string]any{"status": after.Status}, Reason: reason,
		}); err != nil {
			return err
		}
		return s.notify.Notify(ctx, notifications.Message{
			UserID: r.OwnerID, App: notifications.AppPharmacy, Kind: kind, Title: title, Body: body,
			Data: map[string]string{"pharmacy_id": id.String()},
		})
	})
	if err != nil {
		return AdminPharmacy{}, err
	}
	return s.AdminGet(ctx, id, false)
}
