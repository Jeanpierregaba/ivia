// Package business porte le workflow Ivia Business : dossier d'un espace (boutique, agence,
// artisan, restaurant), justificatifs, compte de versement, validation par le back-office et
// ouverture d'un espace par une session.
package business

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"regexp"
	"slices"
	"strings"
	"time"

	"github.com/google/uuid"
	"golang.org/x/crypto/bcrypt"

	"ivia/backend/internal/admin"
	"ivia/backend/internal/business/store"
	"ivia/backend/internal/geo"
	"ivia/backend/internal/notifications"
	"ivia/backend/internal/platform/apperr"
	"ivia/backend/internal/platform/database"
	"ivia/backend/internal/platform/validate"
	"ivia/backend/internal/shops"
	"ivia/backend/internal/uploads"
	"ivia/backend/internal/users"
)

// Secteurs d'activité. D'autres pourront s'ajouter : le secteur décide du formulaire, des
// justificatifs et des fonctionnalités.
const (
	SectorShop       = "shop"
	SectorRealEstate = "real_estate"
	SectorArtisan    = "artisan"
	SectorRestaurant = "restaurant"
)

// Statuts d'un espace.
const (
	StatusDraft        = "draft"
	StatusPending      = "pending_review"
	StatusNeedsChanges = "needs_changes"
	StatusRejected     = "rejected"
	StatusApproved     = "approved"
	StatusSuspended    = "suspended"
)

const (
	maxSpaces       = 5
	maxItems        = 200
	maxPhotos       = 8
	pinMaxAttempts  = 5
	pinLockMinutes  = 15
	restaurantLabel = "Restauration"
)

var (
	sectors    = []string{SectorShop, SectorRealEstate, SectorArtisan, SectorRestaurant}
	docKinds   = []string{"id_card", "selfie", "rccm", "business_registration", "trade_proof", "hygiene_certificate"}
	phoneRe    = regexp.MustCompile(`^\+228[0-9]{8}$`)
	pinRe      = regexp.MustCompile(`^[0-9]{4,6}$`)
	errSpace   = apperr.NotFound("business_space_not_found", "Espace introuvable.")
	errLocked  = apperr.TooManyRequests("pin_locked", "Trop d'essais : réessayez dans 15 minutes.", pinLockMinutes*60)
	errBadPIN  = apperr.Forbidden("pin_incorrect", "Code PIN incorrect.")
	errNoPIN   = apperr.Conflict("pin_required", "Créez d'abord votre code PIN.")
	errEditing = apperr.Conflict("business_space_not_editable", "Ce dossier ne peut plus être modifié pour le moment.")
)

// RequiredDocuments donne les justificatifs exigés pour un secteur : identité et selfie pour tous,
// plus les pièces propres au secteur.
func RequiredDocuments(sector string) []string {
	if sector == SectorRealEstate {
		return []string{"id_card", "selfie", "rccm"}
	}
	return []string{"id_card", "selfie"}
}

// Details regroupe les champs propres aux secteurs.
type Details struct {
	Description    string     `json:"description,omitempty"`
	Phone          string     `json:"phone,omitempty"`
	AddressText    string     `json:"address_text,omitempty"`
	NeighborhoodID *uuid.UUID `json:"neighborhood_id,omitempty"`
	CategoryID     *uuid.UUID `json:"category_id,omitempty"`
	Lat            *float64   `json:"lat,omitempty"`
	Lng            *float64   `json:"lng,omitempty"`
	LogoKey        *string    `json:"logo_key,omitempty"`
	PhotoKeys      []string   `json:"photo_keys,omitempty"`
	RCCM           string     `json:"rccm,omitempty"`
	Zone           string     `json:"zone,omitempty"`
	Trades         []string   `json:"trades,omitempty"`
	Cuisine        string     `json:"cuisine,omitempty"`
	OpeningHours   string     `json:"opening_hours,omitempty"`
}

// Document est un justificatif ; URL est renseignée pour le back-office seulement.
type Document struct {
	Kind string  `json:"kind"`
	URL  *string `json:"url,omitempty"`
}

// Payout est le compte de versement ; le numéro complet n'est donné qu'au back-office.
type Payout struct {
	Operator    string `json:"operator"`
	PhoneMasked string `json:"phone_masked"`
	Phone       string `json:"phone,omitempty"`
	Holder      string `json:"holder"`
}

// Owner est le titulaire vu par le back-office (identité à rapprocher du compte de versement).
type Owner struct {
	ID        uuid.UUID `json:"id"`
	FirstName string    `json:"first_name"`
	LastName  string    `json:"last_name"`
	Phone     string    `json:"phone"`
}

// Space est un espace Ivia Business.
type Space struct {
	ID               uuid.UUID  `json:"id"`
	Sector           string     `json:"sector"`
	Name             string     `json:"name"`
	Details          Details    `json:"details"`
	LogoURL          *string    `json:"logo_url"`
	PhotoURLs        []string   `json:"photo_urls"`
	ShopID           *uuid.UUID `json:"shop_id"`
	Status           string     `json:"status"`
	StatusReason     string     `json:"status_reason"`
	Access           string     `json:"access"`
	Payout           *Payout    `json:"payout"`
	Documents        []Document `json:"documents"`
	MissingDocuments []string   `json:"missing_documents"`
	Owner            *Owner     `json:"owner,omitempty"`
	SubmittedAt      *time.Time `json:"submitted_at"`
	ReviewedAt       *time.Time `json:"reviewed_at"`
	CreatedAt        time.Time  `json:"created_at"`
	UpdatedAt        time.Time  `json:"updated_at"`
}

// Item est un bien ou un service préparé par une agence ou un artisan.
type Item struct {
	ID          uuid.UUID `json:"id"`
	Title       string    `json:"title"`
	Description string    `json:"description"`
	PriceXOF    int64     `json:"price_xof"`
	CreatedAt   time.Time `json:"created_at"`
}

// Input est le formulaire d'un espace.
type Input struct {
	Sector  string  `json:"sector"`
	Name    string  `json:"name"`
	Details Details `json:"details"`
}

// PayoutInput est la saisie du compte de versement.
type PayoutInput struct {
	Operator string `json:"operator"`
	Phone    string `json:"phone"`
	Holder   string `json:"holder"`
	PIN      string `json:"pin"`
}

// Service porte le workflow.
type Service struct {
	db      *database.DB
	shops   *shops.Service
	users   *users.Service
	uploads *uploads.Service
	audit   *admin.Service
	notify  *notifications.Service
}

// NewService crée le service et se branche sur la validation des boutiques : une décision prise
// depuis la fiche boutique met l'espace à jour.
func NewService(db *database.DB, sh *shops.Service, us *users.Service, up *uploads.Service, audit *admin.Service, notify *notifications.Service) *Service {
	s := &Service{db: db, shops: sh, users: us, uploads: up, audit: audit, notify: notify}
	sh.SetReviewHook(s.syncFromShop)
	up.RegisterOwner(uploads.BusinessDocument, s.attachedDocuments)
	return s
}

func (s *Service) q(ctx context.Context) *store.Queries { return store.New(s.db.Conn(ctx)) }

func accessOf(status string) string {
	switch status {
	case StatusApproved:
		return "full"
	case StatusPending:
		return "restricted"
	case StatusSuspended:
		return "blocked"
	}
	return "correction"
}

func mask(phone string) string {
	if len(phone) < 2 {
		return ""
	}
	return "+228 •• •• •• " + phone[len(phone)-2:]
}

func editable(status string) bool {
	return status == StatusDraft || status == StatusNeedsChanges || status == StatusRejected
}

// view construit l'espace ; forAdmin ajoute les liens des pièces, le numéro complet et le titulaire.
func (s *Service) view(ctx context.Context, r store.BusinessSpace, forAdmin bool) (Space, error) {
	var d Details
	if err := json.Unmarshal(r.Details, &d); err != nil {
		return Space{}, fmt.Errorf("détails de l'espace : %w", err)
	}
	out := Space{
		ID: r.ID, Sector: r.Sector, Name: r.Name, Details: d, ShopID: r.ShopID, Status: r.Status, StatusReason: r.StatusReason,
		Access: accessOf(r.Status), SubmittedAt: r.SubmittedAt, ReviewedAt: r.ReviewedAt, CreatedAt: r.CreatedAt, UpdatedAt: r.UpdatedAt,
		PhotoURLs: make([]string, len(d.PhotoKeys)), Documents: []Document{}, MissingDocuments: []string{},
	}
	for i, k := range d.PhotoKeys {
		out.PhotoURLs[i] = s.uploads.PublicURL(k)
	}
	if d.LogoKey != nil {
		u := s.uploads.PublicURL(*d.LogoKey)
		out.LogoURL = &u
	}
	if r.PayoutOperator != nil && r.PayoutPhone != nil {
		out.Payout = &Payout{Operator: *r.PayoutOperator, PhoneMasked: mask(*r.PayoutPhone), Holder: r.PayoutHolder}
		if forAdmin {
			out.Payout.Phone = *r.PayoutPhone
		}
	}
	docs, err := s.q(ctx).ListDocuments(ctx, r.ID)
	if err != nil {
		return Space{}, fmt.Errorf("justificatifs : %w", err)
	}
	have := make([]string, 0, len(docs))
	for _, doc := range docs {
		have = append(have, doc.Kind)
		v := Document{Kind: doc.Kind}
		if forAdmin {
			u, err := s.uploads.PrivateURL(ctx, doc.ObjectKey)
			if err != nil {
				return Space{}, fmt.Errorf("lien du justificatif : %w", err)
			}
			v.URL = &u
		}
		out.Documents = append(out.Documents, v)
	}
	for _, k := range RequiredDocuments(r.Sector) {
		if !slices.Contains(have, k) {
			out.MissingDocuments = append(out.MissingDocuments, k)
		}
	}
	if forAdmin {
		u, err := s.users.Get(ctx, r.OwnerID)
		if err != nil {
			return Space{}, err
		}
		o := Owner{ID: u.ID, FirstName: u.FirstName, LastName: u.LastName}
		if u.Phone != nil {
			o.Phone = *u.Phone
		}
		out.Owner = &o
	}
	return out, nil
}

func validateInput(in *Input) error {
	in.Name = validate.Clean(in.Name)
	d := &in.Details
	d.Description = validate.Clean(d.Description)
	d.AddressText = validate.Clean(d.AddressText)
	d.RCCM = validate.Clean(d.RCCM)
	d.Zone = validate.Clean(d.Zone)
	d.Cuisine = validate.Clean(d.Cuisine)
	d.OpeningHours = validate.Clean(d.OpeningHours)
	v := validate.New()
	v.Check(slices.Contains(sectors, in.Sector), "sector", "Secteur inconnu.")
	v.Text("name", in.Name, 2, 100)
	v.Text("description", d.Description, 0, 1000)
	v.Text("address_text", d.AddressText, 0, 300)
	v.Check(len(d.PhotoKeys) <= maxPhotos, "photo_keys", "8 photos au plus.")
	located := func() {
		v.Check(d.Lat != nil && d.Lng != nil && *d.Lat >= 6 && *d.Lat <= 11.2 && *d.Lng >= -0.2 && *d.Lng <= 1.9,
			"location", "Indiquez la position de l'établissement, au Togo.")
		v.Check(phoneRe.MatchString(d.Phone), "phone", "Numéro attendu : +228 suivi de 8 chiffres.")
		v.Text("address_text", d.AddressText, 3, 300)
	}
	switch in.Sector {
	case SectorShop:
		v.Check(d.CategoryID != nil, "category_id", "Choisissez une catégorie.")
		located()
		v.Check(len(d.PhotoKeys) >= 1, "photo_keys", "Ajoutez au moins une photo de la boutique.")
	case SectorRealEstate:
		v.Text("rccm", d.RCCM, 3, 60)
		v.Text("zone", d.Zone, 2, 200)
		v.Check(d.LogoKey != nil, "logo_key", "Ajoutez le logo de l'agence.")
	case SectorArtisan:
		d.Trades = cleanList(d.Trades)
		v.Check(len(d.Trades) >= 1 && len(d.Trades) <= 10, "trades", "Indiquez entre 1 et 10 métiers.")
		v.Text("zone", d.Zone, 2, 200)
		v.Check(len(d.PhotoKeys) >= 1, "photo_keys", "Ajoutez au moins une photo de vos réalisations.")
	case SectorRestaurant:
		v.Text("cuisine", d.Cuisine, 2, 80)
		v.Text("opening_hours", d.OpeningHours, 2, 200)
		located()
	}
	return v.Err()
}

func cleanList(in []string) []string {
	out := make([]string, 0, len(in))
	for _, t := range in {
		if t = validate.Clean(t); t != "" && len(t) <= 80 {
			out = append(out, t)
		}
	}
	return out
}

// checkFiles vérifie les nouveaux fichiers ; ceux déjà sur l'espace restent permis. Le logo d'une
// boutique ou d'un restaurant est vérifié à la création de la boutique.
func (s *Service) checkFiles(ctx context.Context, owner uuid.UUID, sector string, d Details, before Details) error {
	establishment := sector == SectorShop || sector == SectorRestaurant
	if d.LogoKey != nil && !establishment && (before.LogoKey == nil || *before.LogoKey != *d.LogoKey) {
		if err := s.uploads.Check(ctx, uploads.BusinessPhoto, owner, *d.LogoKey, "logo_key"); err != nil {
			return err
		}
	}
	for _, k := range d.PhotoKeys {
		if slices.Contains(before.PhotoKeys, k) {
			continue
		}
		if err := s.uploads.Check(ctx, uploads.BusinessPhoto, owner, k, "photo_keys"); err != nil {
			return err
		}
	}
	return nil
}

// Spaces retourne les espaces du compte (tableau vide : pas encore de compte Ivia Business).
func (s *Service) Spaces(ctx context.Context, owner uuid.UUID) ([]Space, error) {
	rows, err := s.q(ctx).ListSpacesOfOwner(ctx, owner)
	if err != nil {
		return nil, fmt.Errorf("espaces : %w", err)
	}
	out := make([]Space, len(rows))
	for i, r := range rows {
		if out[i], err = s.view(ctx, r, false); err != nil {
			return nil, err
		}
	}
	return out, nil
}

func (s *Service) owned(ctx context.Context, owner, id uuid.UUID) (store.BusinessSpace, error) {
	r, err := s.q(ctx).GetSpace(ctx, id)
	if database.IsNoRows(err) || (err == nil && r.OwnerID != owner) {
		return r, errSpace
	}
	if err != nil {
		return r, fmt.Errorf("espace : %w", err)
	}
	return r, nil
}

func (s *Service) lockOwned(ctx context.Context, owner, id uuid.UUID) (store.BusinessSpace, error) {
	r, err := s.q(ctx).LockSpace(ctx, id)
	if database.IsNoRows(err) || (err == nil && r.OwnerID != owner) {
		return r, errSpace
	}
	if err != nil {
		return r, fmt.Errorf("verrou de l'espace : %w", err)
	}
	return r, nil
}

// Get retourne un espace du compte.
func (s *Service) Get(ctx context.Context, owner, id uuid.UUID) (Space, error) {
	r, err := s.owned(ctx, owner, id)
	if err != nil {
		return Space{}, err
	}
	return s.view(ctx, r, false)
}

// Create enregistre le brouillon d'un espace.
func (s *Service) Create(ctx context.Context, owner uuid.UUID, in Input) (Space, error) {
	if err := validateInput(&in); err != nil {
		return Space{}, err
	}
	if err := s.checkFiles(ctx, owner, in.Sector, in.Details, Details{}); err != nil {
		return Space{}, err
	}
	raw, err := json.Marshal(in.Details)
	if err != nil {
		return Space{}, fmt.Errorf("détails de l'espace : %w", err)
	}
	var out Space
	err = s.db.InTx(ctx, func(ctx context.Context) error {
		q := s.q(ctx)
		n, err := q.CountSpacesOfOwner(ctx, owner)
		if err != nil {
			return fmt.Errorf("décompte des espaces : %w", err)
		}
		if n >= maxSpaces {
			return apperr.Conflict("too_many_spaces", "Vous avez atteint le nombre maximal d'espaces.")
		}
		r, err := q.CreateSpace(ctx, store.CreateSpaceParams{OwnerID: owner, Sector: in.Sector, Name: in.Name, Details: raw})
		if err != nil {
			return fmt.Errorf("création de l'espace : %w", err)
		}
		out, err = s.view(ctx, r, false)
		return err
	})
	return out, err
}

// Update corrige le dossier tant qu'il n'est pas en cours d'examen. Le secteur ne change pas.
func (s *Service) Update(ctx context.Context, owner, id uuid.UUID, in Input) (Space, error) {
	var out Space
	err := s.db.InTx(ctx, func(ctx context.Context) error {
		r, err := s.lockOwned(ctx, owner, id)
		if err != nil {
			return err
		}
		if !editable(r.Status) {
			return errEditing
		}
		in.Sector = r.Sector
		if err := validateInput(&in); err != nil {
			return err
		}
		var before Details
		if err := json.Unmarshal(r.Details, &before); err != nil {
			return fmt.Errorf("détails de l'espace : %w", err)
		}
		if err := s.checkFiles(ctx, owner, in.Sector, in.Details, before); err != nil {
			return err
		}
		raw, err := json.Marshal(in.Details)
		if err != nil {
			return fmt.Errorf("détails de l'espace : %w", err)
		}
		q := s.q(ctx)
		if err := q.UpdateSpaceDetails(ctx, store.UpdateSpaceDetailsParams{ID: id, Name: in.Name, Details: raw}); err != nil {
			return fmt.Errorf("modification de l'espace : %w", err)
		}
		if r, err = q.GetSpace(ctx, id); err != nil {
			return fmt.Errorf("espace : %w", err)
		}
		out, err = s.view(ctx, r, false)
		return err
	})
	return out, err
}

// AddDocument dépose ou remplace un justificatif.
func (s *Service) AddDocument(ctx context.Context, owner, id uuid.UUID, kind, key string) (Space, error) {
	v := validate.New()
	v.Check(slices.Contains(docKinds, kind), "kind", "Justificatif inconnu.")
	if err := v.Err(); err != nil {
		return Space{}, err
	}
	if err := s.uploads.Check(ctx, uploads.BusinessDocument, owner, key, "object_key"); err != nil {
		return Space{}, err
	}
	var out Space
	var replaced string
	err := s.db.InTx(ctx, func(ctx context.Context) error {
		r, err := s.lockOwned(ctx, owner, id)
		if err != nil {
			return err
		}
		if !editable(r.Status) {
			return errEditing
		}
		q := s.q(ctx)
		old, err := q.GetDocumentKey(ctx, store.GetDocumentKeyParams{SpaceID: id, Kind: kind})
		if err == nil && old != key {
			replaced = old
		} else if err != nil && !database.IsNoRows(err) {
			return fmt.Errorf("justificatif : %w", err)
		}
		if err := q.UpsertDocument(ctx, store.UpsertDocumentParams{SpaceID: id, Kind: kind, ObjectKey: key}); err != nil {
			return fmt.Errorf("dépôt du justificatif : %w", err)
		}
		out, err = s.view(ctx, r, false)
		return err
	})
	if err == nil && replaced != "" {
		// Sans effet sur le dossier si l'effacement échoue : le nettoyage périodique s'en charge.
		_ = s.uploads.Delete(ctx, uploads.BusinessDocument, replaced)
	}
	return out, err
}

// SetPayout renseigne le compte de versement. Une fois l'espace validé, le changement exige le code
// PIN, et prévient le titulaire et le back-office (le nouveau titulaire n'a pas été vérifié).
func (s *Service) SetPayout(ctx context.Context, owner, id uuid.UUID, in PayoutInput) (Space, error) {
	in.Holder = validate.Clean(in.Holder)
	v := validate.New()
	v.Check(in.Operator == "flooz" || in.Operator == "tmoney", "operator", "Choisissez Flooz (Moov) ou T-Money (Yas).")
	v.Check(phoneRe.MatchString(in.Phone), "phone", "Numéro attendu : +228 suivi de 8 chiffres.")
	v.Text("holder", in.Holder, 3, 100)
	if err := v.Err(); err != nil {
		return Space{}, err
	}
	r, err := s.owned(ctx, owner, id)
	if err != nil {
		return Space{}, err
	}
	sensitive := r.Status == StatusApproved || r.Status == StatusSuspended
	if sensitive {
		if err := s.VerifyPIN(ctx, owner, in.PIN); err != nil {
			return Space{}, err
		}
	}
	var out Space
	err = s.db.InTx(ctx, func(ctx context.Context) error {
		r, err := s.lockOwned(ctx, owner, id)
		if err != nil {
			return err
		}
		q := s.q(ctx)
		if err := q.SetSpacePayout(ctx, store.SetSpacePayoutParams{ID: id, PayoutOperator: &in.Operator, PayoutPhone: &in.Phone, PayoutHolder: in.Holder}); err != nil {
			return fmt.Errorf("compte de versement : %w", err)
		}
		if r, err = q.GetSpace(ctx, id); err != nil {
			return fmt.Errorf("espace : %w", err)
		}
		if out, err = s.view(ctx, r, false); err != nil {
			return err
		}
		if !sensitive {
			return nil
		}
		if err := s.notify.NotifyAdmins(ctx, "business_payout_changed", "Compte de versement modifié",
			r.Name+" a changé de compte de versement : titulaire à vérifier.", map[string]string{"business_space_id": id.String()}); err != nil {
			return err
		}
		return s.notify.Notify(ctx, notifications.Message{
			UserID: owner, App: notifications.AppSeller, Kind: "business_payout_changed", Title: r.Name,
			Body: "Votre compte de versement vient d'être modifié. Si ce n'est pas vous, contactez le support.",
			Data: map[string]string{"business_space_id": id.String()},
		})
	})
	return out, err
}

func shopInput(in store.BusinessSpace, d Details, category *uuid.UUID) shops.Input {
	return shops.Input{
		Name: in.Name, Description: d.Description, Phone: d.Phone, AddressText: d.AddressText, NeighborhoodID: d.NeighborhoodID,
		CategoryID: category, Location: geo.Point{Lat: *d.Lat, Lng: *d.Lng}, LogoKey: d.LogoKey,
	}
}

func (s *Service) restaurantCategory(ctx context.Context) (*uuid.UUID, error) {
	cats, err := s.shops.ListCategories(ctx)
	if err != nil {
		return nil, err
	}
	for _, c := range cats {
		if c.Name == restaurantLabel {
			return &c.ID, nil
		}
	}
	return nil, apperr.Unprocessable("restaurant_category_missing", "La catégorie « Restauration » n'existe pas encore : contactez le support.")
}

// Submit envoie le dossier au back-office. Boutique et restaurant obtiennent leur boutique, en
// attente et invisible des clients : le catalogue se prépare dès maintenant.
func (s *Service) Submit(ctx context.Context, owner, id uuid.UUID) (Space, error) {
	var out Space
	err := s.db.InTx(ctx, func(ctx context.Context) error {
		r, err := s.lockOwned(ctx, owner, id)
		if err != nil {
			return err
		}
		if !editable(r.Status) {
			return errEditing
		}
		v, err := s.view(ctx, r, false)
		if err != nil {
			return err
		}
		if len(v.MissingDocuments) > 0 {
			return apperr.Conflict("business_documents_missing", "Il manque des justificatifs à votre dossier.")
		}
		if v.Payout == nil {
			return apperr.Conflict("business_payout_missing", "Renseignez votre compte de versement.")
		}
		q := s.q(ctx)
		hasPIN, err := q.PinExists(ctx, owner)
		if err != nil {
			return fmt.Errorf("code PIN : %w", err)
		}
		if !hasPIN {
			return errNoPIN
		}
		if r.Sector == SectorShop || r.Sector == SectorRestaurant {
			if err := s.syncShop(ctx, q, r, v.Details); err != nil {
				return err
			}
		}
		if err := q.MarkSpaceSubmitted(ctx, id); err != nil {
			return fmt.Errorf("envoi du dossier : %w", err)
		}
		if err := s.notify.NotifyAdmins(ctx, "business_pending_review", "Nouveau dossier Ivia Business",
			r.Name+" attend votre validation.", map[string]string{"business_space_id": id.String()}); err != nil {
			return err
		}
		if r, err = q.GetSpace(ctx, id); err != nil {
			return fmt.Errorf("espace : %w", err)
		}
		out, err = s.view(ctx, r, false)
		return err
	})
	return out, err
}

// syncShop crée la boutique de l'espace, ou y reporte les corrections du dossier.
func (s *Service) syncShop(ctx context.Context, q *store.Queries, r store.BusinessSpace, d Details) error {
	category := d.CategoryID
	if r.Sector == SectorRestaurant {
		c, err := s.restaurantCategory(ctx)
		if err != nil {
			return err
		}
		category = c
	}
	if r.ShopID == nil {
		shop, err := s.shops.Create(ctx, r.OwnerID, shopInput(r, d, category))
		if err != nil {
			return err
		}
		if err := q.SetSpaceShop(ctx, store.SetSpaceShopParams{ID: r.ID, ShopID: &shop.ID}); err != nil {
			return fmt.Errorf("boutique de l'espace : %w", err)
		}
		return nil
	}
	if _, err := s.shops.Update(ctx, r.OwnerID, *r.ShopID, shopInput(r, d, category)); err != nil {
		return err
	}
	return s.shops.ResubmitLinked(ctx, *r.ShopID)
}

// Décisions du back-office : statuts de départ, statut d'arrivée, message au titulaire.
var decisions = map[string]struct {
	from   []string
	to     string
	title  string
	body   string
	reason bool
}{
	"approve":       {[]string{StatusPending}, StatusApproved, "Espace activé", "Votre espace est actif et visible des clients.", false},
	"needs_changes": {[]string{StatusPending}, StatusNeedsChanges, "Compléments demandés", "Votre dossier est à compléter.", true},
	"reject":        {[]string{StatusPending}, StatusRejected, "Dossier refusé", "Votre dossier n'a pas été validé.", true},
	"suspend":       {[]string{StatusApproved}, StatusSuspended, "Espace suspendu", "Votre espace est suspendu.", true},
	"reinstate":     {[]string{StatusSuspended}, StatusApproved, "Espace rétabli", "Votre espace est de nouveau actif.", false},
}

// AdminList retourne les dossiers.
func (s *Service) AdminList(ctx context.Context, status, sector *string, limit, offset int32) ([]Space, error) {
	rows, err := s.q(ctx).AdminListSpaces(ctx, store.AdminListSpacesParams{Status: status, Sector: sector, Lim: limit, Off: offset})
	if err != nil {
		return nil, fmt.Errorf("dossiers : %w", err)
	}
	out := make([]Space, len(rows))
	for i, r := range rows {
		if out[i], err = s.view(ctx, r, true); err != nil {
			return nil, err
		}
	}
	return out, nil
}

// AdminGet retourne un dossier.
func (s *Service) AdminGet(ctx context.Context, id uuid.UUID) (Space, error) {
	r, err := s.q(ctx).GetSpace(ctx, id)
	if database.IsNoRows(err) {
		return Space{}, errSpace
	}
	if err != nil {
		return Space{}, fmt.Errorf("dossier : %w", err)
	}
	return s.view(ctx, r, true)
}

// Review applique la décision du back-office (journalisée) et prévient le titulaire.
func (s *Service) Review(ctx context.Context, adminID, id uuid.UUID, decision, reason string) (Space, error) {
	t, ok := decisions[decision]
	reason = validate.Clean(reason)
	v := validate.New()
	v.Check(ok, "decision", "Décision inconnue.")
	v.Check(!t.reason || len(reason) >= 3, "reason", "Motif obligatoire (il sera communiqué au marchand).")
	if err := v.Err(); err != nil {
		return Space{}, err
	}
	var out Space
	err := s.db.InTx(ctx, func(ctx context.Context) error {
		q := s.q(ctx)
		r, err := q.LockSpace(ctx, id)
		if database.IsNoRows(err) {
			return errSpace
		}
		if err != nil {
			return fmt.Errorf("verrou du dossier : %w", err)
		}
		if !slices.Contains(t.from, r.Status) {
			return apperr.Conflict("invalid_business_transition", "Action impossible pour un dossier dans cet état.")
		}
		if decision == "approve" {
			view, err := s.view(ctx, r, false)
			if err != nil {
				return err
			}
			if len(view.MissingDocuments) > 0 || view.Payout == nil {
				return apperr.Conflict("business_file_incomplete", "Dossier incomplet : justificatifs ou compte de versement manquants.")
			}
		}
		// Les compléments demandés laissent la boutique en attente.
		if r.ShopID != nil && decision != "needs_changes" {
			if _, err := s.shops.ReviewLinked(ctx, adminID, *r.ShopID, decision, reason); err != nil {
				return err
			}
		}
		if err := q.SetSpaceReview(ctx, store.SetSpaceReviewParams{ID: id, Status: t.to, StatusReason: reason, ReviewedBy: &adminID}); err != nil {
			return fmt.Errorf("décision sur le dossier : %w", err)
		}
		if err := s.audit.Record(ctx, admin.AuditEntry{
			AdminID: &adminID, Action: "business." + decision, TargetType: "business_space", TargetID: id.String(),
			Before: map[string]any{"status": r.Status}, After: map[string]any{"status": t.to}, Reason: reason,
		}); err != nil {
			return err
		}
		body := t.body
		if reason != "" {
			body += " Motif : " + reason
		}
		if err := s.notify.Notify(ctx, notifications.Message{
			UserID: r.OwnerID, App: notifications.AppSeller, Kind: "business_" + decision, Title: t.title, Body: body,
			Data: map[string]string{"business_space_id": id.String()},
		}); err != nil {
			return err
		}
		if r, err = q.GetSpace(ctx, id); err != nil {
			return fmt.Errorf("dossier : %w", err)
		}
		out, err = s.view(ctx, r, true)
		return err
	})
	return out, err
}

// syncFromShop reporte sur l'espace une décision prise depuis la fiche boutique.
func (s *Service) syncFromShop(ctx context.Context, shopID uuid.UUID, decision, reason string) error {
	t, ok := decisions[decision]
	if !ok {
		return nil
	}
	if err := s.q(ctx).SyncSpaceFromShop(ctx, store.SyncSpaceFromShopParams{ShopID: &shopID, Status: t.to, StatusReason: reason}); err != nil {
		return fmt.Errorf("espace de la boutique : %w", err)
	}
	return nil
}

// --- Session -------------------------------------------------------------------------------

// Open lie la session à l'espace choisi ; les droits découlent du statut de l'espace.
func (s *Service) Open(ctx context.Context, owner, sessionID, id uuid.UUID) (Space, error) {
	r, err := s.owned(ctx, owner, id)
	if err != nil {
		return Space{}, err
	}
	if err := s.q(ctx).OpenSession(ctx, store.OpenSessionParams{SessionID: sessionID, SpaceID: id}); err != nil {
		return Space{}, fmt.Errorf("ouverture de l'espace : %w", err)
	}
	return s.view(ctx, r, false)
}

// Opened retourne l'espace ouvert par la session ; nil s'il n'y en a pas.
func (s *Service) Opened(ctx context.Context, owner, sessionID uuid.UUID) (*Space, error) {
	id, err := s.q(ctx).OpenedSpace(ctx, sessionID)
	if database.IsNoRows(err) {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("espace ouvert : %w", err)
	}
	v, err := s.Get(ctx, owner, id)
	if errors.Is(err, errSpace) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return &v, nil
}

// Close délie la session (changement d'espace).
func (s *Service) Close(ctx context.Context, sessionID uuid.UUID) error {
	if err := s.q(ctx).CloseSession(ctx, sessionID); err != nil {
		return fmt.Errorf("fermeture de l'espace : %w", err)
	}
	return nil
}

// --- Brouillon : biens et services ---------------------------------------------------------

// Items retourne les biens ou services d'un espace.
func (s *Service) Items(ctx context.Context, owner, id uuid.UUID) ([]Item, error) {
	if _, err := s.owned(ctx, owner, id); err != nil {
		return nil, err
	}
	rows, err := s.q(ctx).ListItems(ctx, id)
	if err != nil {
		return nil, fmt.Errorf("brouillon : %w", err)
	}
	out := make([]Item, len(rows))
	for i, r := range rows {
		out[i] = Item{ID: r.ID, Title: r.Title, Description: r.Description, PriceXOF: r.PriceXof, CreatedAt: r.CreatedAt}
	}
	return out, nil
}

// AddItem ajoute un bien ou un service.
func (s *Service) AddItem(ctx context.Context, owner, id uuid.UUID, title, description string, price int64) (Item, error) {
	title, description = validate.Clean(title), validate.Clean(description)
	v := validate.New()
	v.Text("title", title, 2, 120)
	v.Text("description", description, 0, 2000)
	v.Check(price >= 0, "price_xof", "Prix en FCFA.")
	if err := v.Err(); err != nil {
		return Item{}, err
	}
	r, err := s.owned(ctx, owner, id)
	if err != nil {
		return Item{}, err
	}
	if r.Status == StatusSuspended {
		return Item{}, errEditing
	}
	q := s.q(ctx)
	n, err := q.CountItems(ctx, id)
	if err != nil {
		return Item{}, fmt.Errorf("décompte du brouillon : %w", err)
	}
	if n >= maxItems {
		return Item{}, apperr.Conflict("too_many_items", "Vous avez atteint le nombre maximal d'éléments.")
	}
	row, err := q.CreateItem(ctx, store.CreateItemParams{SpaceID: id, Title: title, Description: description, PriceXof: price})
	if err != nil {
		return Item{}, fmt.Errorf("ajout au brouillon : %w", err)
	}
	return Item{ID: row.ID, Title: row.Title, Description: row.Description, PriceXOF: row.PriceXof, CreatedAt: row.CreatedAt}, nil
}

// DeleteItem retire un bien ou un service du compte.
func (s *Service) DeleteItem(ctx context.Context, owner, id uuid.UUID) error {
	n, err := s.q(ctx).DeleteItem(ctx, store.DeleteItemParams{ID: id, OwnerID: owner})
	if err != nil {
		return fmt.Errorf("retrait du brouillon : %w", err)
	}
	if n == 0 {
		return apperr.NotFound("business_item_not_found", "Élément introuvable.")
	}
	return nil
}

// --- Code PIN ------------------------------------------------------------------------------

// HasPIN indique si le compte a un code PIN.
func (s *Service) HasPIN(ctx context.Context, owner uuid.UUID) (bool, error) {
	v, err := s.q(ctx).PinExists(ctx, owner)
	if err != nil {
		return false, fmt.Errorf("code PIN : %w", err)
	}
	return v, nil
}

// SetPIN crée le code PIN ; le changer exige le code actuel.
func (s *Service) SetPIN(ctx context.Context, owner uuid.UUID, pin, current string) error {
	v := validate.New()
	v.Check(pinRe.MatchString(pin) && strings.Trim(pin, pin[:1]) != "", "pin", "De 4 à 6 chiffres, pas tous identiques.")
	if err := v.Err(); err != nil {
		return err
	}
	has, err := s.HasPIN(ctx, owner)
	if err != nil {
		return err
	}
	if has {
		if err := s.VerifyPIN(ctx, owner, current); err != nil {
			return err
		}
	}
	hash, err := bcrypt.GenerateFromPassword([]byte(pin), bcrypt.DefaultCost)
	if err != nil {
		return fmt.Errorf("empreinte du code PIN : %w", err)
	}
	if err := s.q(ctx).UpsertPin(ctx, store.UpsertPinParams{UserID: owner, PinHash: string(hash)}); err != nil {
		return fmt.Errorf("code PIN : %w", err)
	}
	return nil
}

// VerifyPIN contrôle le code : 5 erreurs verrouillent le compte 15 minutes.
func (s *Service) VerifyPIN(ctx context.Context, owner uuid.UUID, pin string) error {
	q := s.q(ctx)
	hash, err := q.GetPinHash(ctx, owner)
	if database.IsNoRows(err) {
		return errNoPIN
	}
	if err != nil {
		return fmt.Errorf("code PIN : %w", err)
	}
	n, err := q.ReservePinAttempt(ctx, store.ReservePinAttemptParams{UserID: owner, MaxAttempts: pinMaxAttempts, LockMinutes: pinLockMinutes})
	if err != nil {
		return fmt.Errorf("essai du code PIN : %w", err)
	}
	if n == 0 {
		return errLocked
	}
	if bcrypt.CompareHashAndPassword([]byte(hash), []byte(pin)) != nil {
		return errBadPIN
	}
	if err := q.ResetPinAttempts(ctx, owner); err != nil {
		return fmt.Errorf("essai du code PIN : %w", err)
	}
	return nil
}

// --- Fichiers et suppression du compte ------------------------------------------------------

func (s *Service) attachedDocuments(ctx context.Context, keys []string) (map[string]bool, error) {
	found, err := s.q(ctx).DocumentKeysIn(ctx, keys)
	if err != nil {
		return nil, fmt.Errorf("lecture des justificatifs rattachés : %w", err)
	}
	out := make(map[string]bool, len(found))
	for _, k := range found {
		out[k] = true
	}
	return out, nil
}

// OnAccountDeleted suspend les espaces et efface justificatifs, compte de versement et code PIN
// (users.DeletionHook).
func (s *Service) OnAccountDeleted(ctx context.Context, userID uuid.UUID) error {
	q := s.q(ctx)
	if err := q.SuspendSpacesOfOwner(ctx, store.SuspendSpacesOfOwnerParams{OwnerID: userID, StatusReason: "Compte supprimé."}); err != nil {
		return fmt.Errorf("suspension des espaces : %w", err)
	}
	if err := q.DeleteDocumentsOfOwner(ctx, userID); err != nil {
		return fmt.Errorf("effacement des justificatifs : %w", err)
	}
	if err := q.DeletePin(ctx, userID); err != nil {
		return fmt.Errorf("effacement du code PIN : %w", err)
	}
	if _, err := s.uploads.DeleteAllOf(ctx, uploads.BusinessDocument, userID); err != nil {
		return fmt.Errorf("effacement des fichiers : %w", err)
	}
	return nil
}
