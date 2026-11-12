// Package delivery gère les livreurs, l'attribution automatique des missions et leur déroulé.
//
// Garanties (règle 6 d'AGENTS.md), portées par la base :
//   - une seule mission active par commande et par livreur (index uniques partiels) ;
//   - une seule proposition en attente par commande et par livreur (index uniques partiels) ;
//   - deux attributions simultanées ne choisissent pas le même livreur (FOR UPDATE SKIP LOCKED).
package delivery

import (
	"context"
	"fmt"
	"log/slog"
	"strings"
	"time"

	"github.com/google/uuid"

	"ivia/backend/internal/admin"
	"ivia/backend/internal/delivery/store"
	"ivia/backend/internal/geo"
	"ivia/backend/internal/notifications"
	"ivia/backend/internal/orders"
	"ivia/backend/internal/platform/apperr"
	"ivia/backend/internal/platform/database"
	"ivia/backend/internal/platform/identity"
	"ivia/backend/internal/platform/jobs"
	"ivia/backend/internal/platform/ratelimit"
	"ivia/backend/internal/platform/validate"
	"ivia/backend/internal/shops"
	"ivia/backend/internal/uploads"
	"ivia/backend/internal/users"
)

// Statuts de validation, de disponibilité et des missions.
const (
	ReviewPending  = "pending_review"
	ReviewApproved = "approved"
	ReviewRejected = "rejected"

	Offline   = "offline"
	Available = "available"
	Busy      = "busy"
)

// Règles de l'attribution et de la livraison.
const (
	// LocationMaxAge : une position plus ancienne exclut le livreur de l'attribution.
	LocationMaxAge = 2 * time.Minute
	// MaxDriverDistanceM : rayon de recherche autour de la boutique.
	MaxDriverDistanceM = 15_000
	// RetryAssignmentAfter : délai avant de chercher à nouveau quand aucun livreur n'est libre.
	RetryAssignmentAfter = 30 * time.Second
	// MinWaitBeforeFailure : attente minimale chez le client avant de déclarer un échec.
	MinWaitBeforeFailure = 10 * time.Minute
	// MinCallsBeforeFailure : appels minimum au client avant de déclarer un échec.
	MinCallsBeforeFailure = 2
)

// Driver est le profil d'un livreur.
type Driver struct {
	UserID             uuid.UUID  `json:"user_id"`
	Status             string     `json:"status"`
	ReviewStatus       string     `json:"review_status"`
	ReviewNote         string     `json:"review_note"`
	ReviewedAt         *time.Time `json:"reviewed_at"`
	SuspendedAt        *time.Time `json:"suspended_at"`
	SuspensionReason   string     `json:"suspension_reason"`
	Availability       string     `json:"availability"`
	VehicleType        string     `json:"vehicle_type"`
	VehiclePlate       string     `json:"vehicle_plate"`
	VehicleDescription string     `json:"vehicle_description"`
	LastLocationAt     *time.Time `json:"last_location_at"`
	Documents          []Document `json:"documents"`
	// Activités déclarées (livraison, taxi VTC) et état de leur dossier ; Status et ReviewStatus
	// ci-dessus suivent l'activité livraison.
	Activities []Activity     `json:"activities"`
	Payout     *PayoutAccount `json:"payout"`
	CreatedAt  time.Time      `json:"created_at"`
}

// Document est une pièce du dossier d'un livreur. L'URL n'est fournie qu'aux admins.
type Document struct {
	ID   uuid.UUID `json:"id"`
	Kind string    `json:"kind"`
	URL  string    `json:"url,omitempty"`
	// ExpiresOn : date d'expiration (AAAA-MM-JJ), saisie par l'équipe ivia ; nulle si inconnue.
	ExpiresOn *string   `json:"expires_on"`
	CreatedAt time.Time `json:"created_at"`
}

// AdminDriver ajoute l'identité du livreur pour le back-office.
type AdminDriver struct {
	Driver
	FirstName string `json:"first_name"`
	Phone     string `json:"phone"`
}

// ApplicationInput est la candidature d'un livreur.
type ApplicationInput struct {
	VehicleType        string `json:"vehicle_type"`
	VehiclePlate       string `json:"vehicle_plate"`
	VehicleDescription string `json:"vehicle_description"`
}

// Service gère livreurs, propositions et missions.
type Service struct {
	db       *database.DB
	jobs     jobs.Enqueuer
	admin    *admin.Service
	users    *users.Service
	geo      *geo.Service
	shops    *shops.Service
	orders   *orders.Service
	uploads  *uploads.Service
	notify   *notifications.Service
	logger   *slog.Logger
	locLimit *ratelimit.Limiter
	// zones : zones de travail proposées au dossier (module carte, voir SetZones).
	zones ZoneLister
	// pharmacy : courses pharmacie du livreur (tableau de bord, voir SetPharmacyEarnings).
	pharmacy PharmacyEarnings
}

// WorkZone : zone de travail que le livreur choisit dans son dossier.
type WorkZone struct {
	ID   uuid.UUID `json:"id"`
	Name string    `json:"name"`
}

// ZoneLister lit les zones de travail (zones desservies actives) dans le module qui les possède.
type ZoneLister interface {
	WorkZones(ctx context.Context) ([]WorkZone, error)
}

// SetZones branche la lecture des zones (le module carte dépend de ce module : pas d'import).
func (s *Service) SetZones(z ZoneLister) { s.zones = z }

// Deps regroupe les dépendances du service.
type Deps struct {
	DB      *database.DB
	Jobs    jobs.Enqueuer
	Admin   *admin.Service
	Users   *users.Service
	Geo     *geo.Service
	Shops   *shops.Service
	Orders  *orders.Service
	Uploads *uploads.Service
	Notify  *notifications.Service
	Logger  *slog.Logger
}

// NewService crée le service.
func NewService(d Deps) *Service {
	s := &Service{
		db: d.DB, jobs: d.Jobs, admin: d.Admin, users: d.Users, geo: d.Geo, shops: d.Shops, orders: d.Orders,
		uploads: d.Uploads, notify: d.Notify, logger: d.Logger,
		// Position : l'app en envoie une toutes les 30 s ; marge pour les reprises réseau.
		locLimit: ratelimit.New(12, time.Minute),
	}
	d.Uploads.RegisterOwner(uploads.DriverDocument, s.attachedDocuments)
	return s
}

// attachedDocuments dit lesquelles de ces clés sont rattachées à un dossier (uploads.AttachedFunc).
func (s *Service) attachedDocuments(ctx context.Context, keys []string) (map[string]bool, error) {
	found, err := store.New(s.db.Conn(ctx)).DriverDocumentKeysIn(ctx, keys)
	if err != nil {
		return nil, fmt.Errorf("lecture des documents rattachés : %w", err)
	}
	out := make(map[string]bool, len(found))
	for _, k := range found {
		out[k] = true
	}
	return out, nil
}

var errDriverNotFound = apperr.NotFound("driver_not_found", "Livreur introuvable.")

// statusOf résume l'état d'un livreur : en attente, refusé, suspendu, hors ligne, disponible, occupé.
func statusOf(d store.GetDriverRow) string {
	switch {
	case d.SuspendedAt != nil:
		return "suspended"
	case d.ReviewStatus != ReviewApproved:
		return d.ReviewStatus
	default:
		return d.Availability
	}
}

func (s *Service) getDriver(ctx context.Context, userID uuid.UUID, withURLs bool) (Driver, error) {
	q := store.New(s.db.Conn(ctx))
	r, err := q.GetDriver(ctx, userID)
	if database.IsNoRows(err) {
		return Driver{}, errDriverNotFound
	}
	if err != nil {
		return Driver{}, fmt.Errorf("lecture du livreur : %w", err)
	}
	docs, err := q.ListDocuments(ctx, userID)
	if err != nil {
		return Driver{}, fmt.Errorf("lecture des documents : %w", err)
	}
	d := Driver{
		UserID: r.UserID, Status: statusOf(r), ReviewStatus: r.ReviewStatus, ReviewNote: r.ReviewNote,
		ReviewedAt: r.ReviewedAt, SuspendedAt: r.SuspendedAt, SuspensionReason: r.SuspensionReason,
		Availability: r.Availability, VehicleType: r.VehicleType, VehiclePlate: r.VehiclePlate,
		VehicleDescription: r.VehicleDescription, LastLocationAt: r.LastLocationAt, CreatedAt: r.CreatedAt,
		Documents: make([]Document, len(docs)),
	}
	for i, doc := range docs {
		d.Documents[i] = Document{ID: doc.ID, Kind: doc.Kind, CreatedAt: doc.CreatedAt}
		if doc.ExpiresOn != nil {
			e := doc.ExpiresOn.Format(time.DateOnly)
			d.Documents[i].ExpiresOn = &e
		}
		if withURLs {
			if d.Documents[i].URL, err = s.uploads.PrivateURL(ctx, doc.ObjectKey); err != nil {
				return Driver{}, err
			}
		}
	}
	if err := s.loadActivities(ctx, &d, withURLs); err != nil {
		return Driver{}, err
	}
	return d, nil
}

// requireActiveDriver vérifie, à chaque action, que le livreur est validé et non suspendu.
func (s *Service) requireActiveDriver(ctx context.Context, userID uuid.UUID) (store.GetDriverRow, error) {
	r, err := store.New(s.db.Conn(ctx)).GetDriver(ctx, userID)
	if database.IsNoRows(err) {
		return store.GetDriverRow{}, errDriverNotFound
	}
	if err != nil {
		return store.GetDriverRow{}, fmt.Errorf("lecture du livreur : %w", err)
	}
	if r.SuspendedAt != nil {
		return store.GetDriverRow{}, apperr.Forbidden("driver_suspended", "Votre compte livreur est suspendu. Contactez l'équipe ivia.")
	}
	if r.ReviewStatus != ReviewApproved {
		return store.GetDriverRow{}, apperr.Forbidden("driver_not_approved", "Votre compte livreur n'est pas encore validé.")
	}
	return r, nil
}

// Me retourne le profil livreur de l'utilisateur.
func (s *Service) Me(ctx context.Context, userID uuid.UUID) (Driver, error) {
	return s.getDriver(ctx, userID, false)
}

// Apply dépose ou corrige une candidature de livreur. Le rôle driver n'est donné qu'à la validation.
func (s *Service) Apply(ctx context.Context, userID uuid.UUID, in ApplicationInput) (Driver, error) {
	in.VehiclePlate = validate.Clean(in.VehiclePlate)
	in.VehicleDescription = validate.Clean(in.VehicleDescription)
	v := validate.New()
	v.Check(in.VehicleType == string(orders.VehicleMotorbike) || in.VehicleType == string(orders.VehicleCar), "vehicle_type", "Véhicule attendu : motorbike ou car.")
	v.Text("vehicle_plate", in.VehiclePlate, 2, 20)
	v.Text("vehicle_description", in.VehicleDescription, 0, 200)
	if err := v.Err(); err != nil {
		return Driver{}, err
	}
	u, err := s.users.Get(ctx, userID)
	if err != nil {
		return Driver{}, err
	}
	if !u.ProfileComplete {
		return Driver{}, apperr.Conflict("profile_incomplete", "Complétez votre profil (prénom, téléphone, consentement) avant de postuler.")
	}
	err = s.db.InTx(ctx, func(ctx context.Context) error {
		q := store.New(s.db.Conn(ctx))
		// Lecture d'abord : un INSERT en échec invaliderait la transaction (correction d'un dossier refusé).
		cur, err := q.GetDriver(ctx, userID)
		switch {
		case database.IsNoRows(err):
			if err := q.CreateDriver(ctx, store.CreateDriverParams{UserID: userID, VehicleType: in.VehicleType, VehiclePlate: in.VehiclePlate, VehicleDescription: in.VehicleDescription}); err != nil {
				return fmt.Errorf("création de la candidature : %w", err)
			}
			if err := q.UpsertLegacyDelivery(ctx, userID); err != nil {
				return fmt.Errorf("activité livraison : %w", err)
			}
		case err != nil:
			return fmt.Errorf("lecture de la candidature : %w", err)
		default:
			n, err := q.UpdateApplication(ctx, store.UpdateApplicationParams{UserID: userID, VehicleType: in.VehicleType, VehiclePlate: in.VehiclePlate, VehicleDescription: in.VehicleDescription})
			if err != nil {
				return fmt.Errorf("mise à jour de la candidature : %w", err)
			}
			if n == 0 {
				return apperr.Conflict("application_locked", "Votre candidature a déjà été validée : contactez l'équipe ivia pour la modifier.")
			}
			if err := q.UpsertLegacyDelivery(ctx, userID); err != nil {
				return fmt.Errorf("activité livraison : %w", err)
			}
			if cur.ReviewStatus == ReviewPending {
				return nil // simple correction d'un dossier déjà en attente : pas de nouvelle alerte
			}
		}
		// Nouvelle candidature, ou dossier refusé soumis de nouveau : à revoir par un admin.
		return s.notify.NotifyAdmins(ctx, "driver_application", "Candidature de livreur à valider",
			"Un livreur attend la validation de son dossier.", map[string]string{"driver_id": userID.String()})
	})
	if err != nil {
		return Driver{}, err
	}
	return s.getDriver(ctx, userID, false)
}

// AddDocument ajoute une pièce au dossier (le fichier a été envoyé dans le compartiment privé).
func (s *Service) AddDocument(ctx context.Context, userID uuid.UUID, kind, objectKey string) (Driver, error) {
	switch kind {
	case "id_card", "driving_license", "vehicle_registration", "vehicle_insurance", "vehicle_photo", "criminal_record", "photo", "other":
	default:
		return Driver{}, apperr.Validation(map[string]string{"kind": "Type de document inconnu."})
	}
	q := store.New(s.db.Conn(ctx))
	if _, err := q.GetDriver(ctx, userID); err != nil {
		if database.IsNoRows(err) {
			return Driver{}, apperr.Conflict("no_application", "Déposez d'abord votre candidature.")
		}
		return Driver{}, fmt.Errorf("lecture du livreur : %w", err)
	}
	n, err := q.CountDocuments(ctx, userID)
	if err != nil {
		return Driver{}, fmt.Errorf("décompte des documents : %w", err)
	}
	if n >= 20 {
		return Driver{}, apperr.Conflict("too_many_documents", "Nombre maximal de documents atteint.")
	}
	if err := s.uploads.Check(ctx, uploads.DriverDocument, userID, objectKey, "object_key"); err != nil {
		return Driver{}, err
	}
	if _, err := q.InsertDocument(ctx, store.InsertDocumentParams{DriverID: userID, Kind: kind, ObjectKey: objectKey}); err != nil {
		return Driver{}, fmt.Errorf("ajout du document : %w", err)
	}
	return s.getDriver(ctx, userID, false)
}

// SetAvailability passe le livreur en ligne ou hors ligne.
func (s *Service) SetAvailability(ctx context.Context, userID uuid.UUID, online bool) (Driver, error) {
	err := s.db.InTx(ctx, func(ctx context.Context) error {
		if _, err := s.requireActiveDriver(ctx, userID); err != nil {
			return err
		}
		q := store.New(s.db.Conn(ctx))
		cur, err := q.LockDriver(ctx, userID)
		if err != nil {
			return fmt.Errorf("verrou du livreur : %w", err)
		}
		if cur == Busy {
			return apperr.Conflict("mission_in_progress", "Terminez votre mission en cours avant de changer de disponibilité.")
		}
		next := Offline
		if online {
			next = Available
		} else if err := q.CancelPendingOffersForDriver(ctx, userID); err != nil {
			return fmt.Errorf("annulation des propositions : %w", err)
		}
		return q.SetAvailability(ctx, store.SetAvailabilityParams{UserID: userID, Availability: next})
	})
	if err != nil {
		return Driver{}, err
	}
	return s.getDriver(ctx, userID, false)
}

// LocationInput est une position envoyée par l'app livreur.
type LocationInput struct {
	Lat        float64    `json:"lat"`
	Lng        float64    `json:"lng"`
	AccuracyM  *int32     `json:"accuracy_m"`
	RecordedAt *time.Time `json:"recorded_at"`
}

// UpdateLocation enregistre la position du livreur. Refusée hors service : aucune position n'est
// collectée quand le livreur est hors ligne.
func (s *Service) UpdateLocation(ctx context.Context, userID uuid.UUID, in LocationInput) error {
	v := validate.New()
	v.Coordinates("", in.Lat, in.Lng)
	if in.AccuracyM != nil {
		v.Check(*in.AccuracyM >= 0 && *in.AccuracyM <= 100_000, "accuracy_m", "Précision invalide.")
	}
	if err := v.Err(); err != nil {
		return err
	}
	if ok, retry := s.locLimit.Allow(userID.String()); !ok {
		return apperr.TooManyRequests("rate_limited", "Positions envoyées trop souvent.", retry)
	}
	d, err := s.requireActiveDriver(ctx, userID)
	if err != nil {
		return err
	}
	if d.Availability == Offline {
		return apperr.Conflict("driver_offline", "Passez en ligne pour partager votre position.")
	}
	now := time.Now()
	recorded := now
	// Une position horodatée par l'app est acceptée si elle est récente (envoi différé en 3G).
	if in.RecordedAt != nil && in.RecordedAt.Before(now) && now.Sub(*in.RecordedAt) < 5*time.Minute {
		recorded = *in.RecordedAt
	}
	return s.db.InTx(ctx, func(ctx context.Context) error {
		q := store.New(s.db.Conn(ctx))
		if err := q.UpdateLocation(ctx, store.UpdateLocationParams{UserID: userID, Lat: in.Lat, Lng: in.Lng, RecordedAt: recorded}); err != nil {
			return fmt.Errorf("mise à jour de la position : %w", err)
		}
		return q.InsertPosition(ctx, store.InsertPositionParams{DriverID: userID, Lat: in.Lat, Lng: in.Lng, AccuracyM: in.AccuracyM, RecordedAt: recorded})
	})
}

// DriverLocation est la dernière position connue d'un livreur.
type DriverLocation struct {
	Point       geo.Point
	RecordedAt  time.Time
	VehicleType string
}

// LastLocation retourne la dernière position du livreur ; nil s'il n'en a pas.
func (s *Service) LastLocation(ctx context.Context, userID uuid.UUID) (*DriverLocation, error) {
	r, err := store.New(s.db.Conn(ctx)).DriverLastLocation(ctx, userID)
	if database.IsNoRows(err) {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("position du livreur : %w", err)
	}
	return &DriverLocation{Point: geo.Point{Lat: r.Lat, Lng: r.Lng}, RecordedAt: r.RecordedAt, VehicleType: r.VehicleType}, nil
}

// --- Back-office ----------------------------------------------------------------------------

// AdminList liste les livreurs.
func (s *Service) AdminList(ctx context.Context, reviewStatus string, suspendedOnly bool, limit, offset int32) ([]AdminDriver, error) {
	var rs *string
	if reviewStatus != "" {
		rs = &reviewStatus
	}
	rows, err := store.New(s.db.Conn(ctx)).ListDrivers(ctx, store.ListDriversParams{ReviewStatus: rs, SuspendedOnly: suspendedOnly, Lim: limit, Off: offset})
	if err != nil {
		return nil, fmt.Errorf("liste des livreurs : %w", err)
	}
	out := make([]AdminDriver, 0, len(rows))
	for _, r := range rows {
		d, err := s.AdminGet(ctx, r.UserID, false)
		if err != nil {
			return nil, err
		}
		out = append(out, d)
	}
	return out, nil
}

// AdminGet retourne le dossier complet d'un livreur ; withURLs ajoute des liens temporaires vers les documents.
func (s *Service) AdminGet(ctx context.Context, userID uuid.UUID, withURLs bool) (AdminDriver, error) {
	d, err := s.getDriver(ctx, userID, withURLs)
	if err != nil {
		return AdminDriver{}, err
	}
	c, err := s.users.Contact(ctx, userID)
	if err != nil {
		return AdminDriver{}, err
	}
	return AdminDriver{Driver: d, FirstName: c.FirstName, Phone: c.Phone}, nil
}

// Review applique une décision admin : approve, request_changes, reject, suspend, reinstate
// (journalisée). Les trois premières portent sur l'activité livraison (ReviewActivity).
func (s *Service) Review(ctx context.Context, adminID, userID uuid.UUID, decision, reason string) (AdminDriver, error) {
	if decision == "approve" || decision == "reject" || decision == "request_changes" {
		return s.ReviewActivity(ctx, adminID, userID, ActivityDelivery, decision, reason)
	}
	reason = validate.Clean(reason)
	if (decision == "reject" || decision == "suspend") && reason == "" {
		return AdminDriver{}, apperr.Validation(map[string]string{"reason": "Indiquez le motif (il sera communiqué au livreur)."})
	}
	err := s.db.InTx(ctx, func(ctx context.Context) error {
		before, err := s.getDriver(ctx, userID, false)
		if err != nil {
			return err
		}
		q := store.New(s.db.Conn(ctx))
		var n int64
		title, body := "", ""
		switch decision {
		case "approve":
			if err := requireDocuments(before.Documents); err != nil {
				return err
			}
			n, err = q.SetReview(ctx, store.SetReviewParams{UserID: userID, ReviewStatus: ReviewApproved, Note: reason, ReviewedBy: &adminID, FromStatuses: []string{ReviewPending, ReviewRejected}})
			if err == nil && n > 0 {
				err = s.users.GrantRole(ctx, userID, identity.RoleDriver, &adminID)
			}
			title, body = "Compte livreur validé", "Vous pouvez maintenant passer en ligne et recevoir des missions."
		case "reject":
			n, err = q.SetReview(ctx, store.SetReviewParams{UserID: userID, ReviewStatus: ReviewRejected, Note: reason, ReviewedBy: &adminID, FromStatuses: []string{ReviewPending}})
			title, body = "Candidature refusée", "Motif : "+reason
		case "suspend":
			n, err = q.Suspend(ctx, store.SuspendParams{UserID: userID, Reason: reason})
			if err == nil && n > 0 {
				err = s.onSuspended(ctx, adminID, userID)
			}
			title, body = "Compte livreur suspendu", "Motif : "+reason
		case "reinstate":
			n, err = q.Reinstate(ctx, userID)
			title, body = "Compte livreur rétabli", "Vous pouvez de nouveau passer en ligne."
		default:
			return fmt.Errorf("décision inconnue : %s", decision)
		}
		if err != nil {
			return fmt.Errorf("décision sur le livreur : %w", err)
		}
		if n == 0 {
			return apperr.Conflict("invalid_driver_transition", "Action impossible pour ce livreur dans son état actuel.")
		}
		after, err := s.getDriver(ctx, userID, false)
		if err != nil {
			return err
		}
		if err := s.admin.Record(ctx, admin.AuditEntry{
			AdminID: &adminID, Action: "driver." + decision, TargetType: "driver", TargetID: userID.String(),
			Before: map[string]any{"status": before.Status}, After: map[string]any{"status": after.Status}, Reason: reason,
		}); err != nil {
			return err
		}
		return s.notify.Notify(ctx, notifications.Message{
			UserID: userID, App: notifications.AppDriver, Kind: "driver_" + decision, Title: title, Body: body,
		})
	})
	if err != nil {
		return AdminDriver{}, err
	}
	return s.AdminGet(ctx, userID, false)
}

// RequiredDocuments : pièces sans lesquelles un dossier de livreur ne peut pas être validé.
var RequiredDocuments = []string{"id_card", "driving_license"}

var documentLabels = map[string]string{
	"id_card": "pièce d'identité", "driving_license": "permis de conduire", "vehicle_registration": "carte grise",
	"vehicle_insurance": "assurance du véhicule", "vehicle_photo": "photo du véhicule",
	"criminal_record": "extrait de casier judiciaire", "photo": "photo", "other": "autre pièce",
}

// requireDocuments refuse la validation d'un dossier incomplet : un compte livreur n'est activé
// qu'après vérification par un admin de l'identité et du permis du candidat.
func requireDocuments(docs []Document) error {
	have := map[string]bool{}
	for _, d := range docs {
		have[d.Kind] = true
	}
	var missing []string
	for _, k := range RequiredDocuments {
		if !have[k] {
			missing = append(missing, documentLabels[k])
		}
	}
	if len(missing) > 0 {
		return apperr.Conflict("driver_documents_missing", "Dossier incomplet : "+strings.Join(missing, ", ")+" manquant(s).")
	}
	return nil
}

// onSuspended coupe l'accès immédiatement : propositions annulées et mission non commencée
// rendue à l'attribution. Une mission dont le colis est déjà récupéré reste à traiter par l'admin.
func (s *Service) onSuspended(ctx context.Context, adminID, userID uuid.UUID) error {
	q := store.New(s.db.Conn(ctx))
	if err := q.CancelPendingOffersForDriver(ctx, userID); err != nil {
		return fmt.Errorf("annulation des propositions : %w", err)
	}
	m, err := q.ActiveDeliveryForDriver(ctx, userID)
	if database.IsNoRows(err) {
		return nil
	}
	if err != nil {
		return fmt.Errorf("mission en cours : %w", err)
	}
	if m.Status == "assigned" || m.Status == "at_shop" {
		return s.withdraw(ctx, m, orders.As(orders.ActorAdmin, adminID), "Livreur suspendu.")
	}
	return s.notify.NotifyAdmins(ctx, "suspended_driver_mission", "Mission d'un livreur suspendu",
		"Le livreur suspendu transporte un colis : reprenez contact avec lui.", map[string]string{"order_id": m.OrderID.String()})
}

// CheckAccountDeletable refuse la suppression d'un compte avec une mission en cours (users.DeletionGuard).
func (s *Service) CheckAccountDeletable(ctx context.Context, userID uuid.UUID) error {
	_, err := store.New(s.db.Conn(ctx)).ActiveDeliveryForDriver(ctx, userID)
	if database.IsNoRows(err) {
		return nil
	}
	if err != nil {
		return fmt.Errorf("mission en cours : %w", err)
	}
	return apperr.Conflict("active_mission", "Terminez votre mission en cours avant de supprimer votre compte.")
}

// OnAccountDeleted met fin à la collaboration : livreur hors ligne et suspendu, positions et
// documents effacés (users.DeletionHook).
func (s *Service) OnAccountDeleted(ctx context.Context, userID uuid.UUID) error {
	// Tout le dossier de fichiers, même sans candidature : un document peut avoir été envoyé avant.
	if _, err := s.uploads.DeleteAllOf(ctx, uploads.DriverDocument, userID); err != nil {
		return err
	}
	q := store.New(s.db.Conn(ctx))
	if _, err := q.GetDriver(ctx, userID); database.IsNoRows(err) {
		return nil
	} else if err != nil {
		return fmt.Errorf("lecture du livreur : %w", err)
	}
	if _, err := q.Suspend(ctx, store.SuspendParams{UserID: userID, Reason: "Compte supprimé."}); err != nil {
		return fmt.Errorf("suspension du livreur : %w", err)
	}
	if err := q.CancelPendingOffersForDriver(ctx, userID); err != nil {
		return err
	}
	if err := q.DeleteIncidentsOf(ctx, userID); err != nil {
		return fmt.Errorf("suppression des signalements : %w", err)
	}
	if err := q.DeleteDocumentsOf(ctx, userID); err != nil {
		return fmt.Errorf("suppression des documents : %w", err)
	}
	if err := q.DeletePositionsOf(ctx, userID); err != nil {
		return fmt.Errorf("suppression des positions : %w", err)
	}
	return q.ForgetLocation(ctx, userID)
}

// PurgePositions supprime les positions de plus de 30 jours (tâche quotidienne).
func (s *Service) PurgePositions(ctx context.Context) error {
	if _, err := store.New(s.db.Conn(ctx)).PurgePositions(ctx); err != nil {
		return fmt.Errorf("purge des positions : %w", err)
	}
	return nil
}
