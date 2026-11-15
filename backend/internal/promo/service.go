// Package promo diffuse la publicité dans les apps (IVI et AWU-IVI d'abord) : visuels publiés
// par l'admin (affiches, bannières, visuels de bienvenue ou du mois, fenêtres, pages
// d'interstitiel), réglages de diffusion et statistiques.
//
// Les apps lisent un fil (visuels en cours, produits mis en avant, réglages) et appliquent
// elles-mêmes délai, intervalle, plafond par session et rotation : une seule fenêtre à la fois,
// toujours fermable, jamais pendant un paiement. Les événements (affichage, fermeture, clics)
// sont anonymes : un identifiant de session tiré au hasard par l'app, sans lien avec le compte.
// La commande passe par le panier et le paiement habituels : pas de circuit parallèle.
package promo

import (
	"context"
	"fmt"
	"net/url"
	"slices"
	"strings"
	"time"

	"github.com/google/uuid"

	"ivia/backend/internal/admin"
	"ivia/backend/internal/catalog"
	"ivia/backend/internal/orders"
	"ivia/backend/internal/platform/apperr"
	"ivia/backend/internal/platform/database"
	"ivia/backend/internal/platform/validate"
	"ivia/backend/internal/promo/store"
	"ivia/backend/internal/uploads"
)

// Kinds : types de visuels.
var Kinds = []string{"banner", "modal", "interstitial", "welcome", "monthly", "poster"}

// Placements : emplacements dans les apps.
var Placements = []string{"home_hero", "home_feed", "catalog_feed", "modal", "interstitial", "splash"}

// Apps : apps qui affichent la publicité.
var Apps = []string{"buyer", "seller", "driver"}

// EventKinds : événements remontés par les apps.
var EventKinds = []string{"impression", "dismiss", "click_order", "click_product", "click_site", "order"}

// Visual est un visuel publicitaire.
type Visual struct {
	ID          uuid.UUID  `json:"id"`
	Kind        string     `json:"kind"`
	Title       string     `json:"title"`
	Subtitle    string     `json:"subtitle"`
	Body        string     `json:"body"`
	ImageKey    string     `json:"image_key"`
	ImageURL    string     `json:"image_url"`
	ProductID   *uuid.UUID `json:"product_id"`
	CTALabel    string     `json:"cta_label"`
	ExternalURL string     `json:"external_url"`
	Placements  []string   `json:"placements"`
	Apps        []string   `json:"apps"`
	Priority    int32      `json:"priority"`
	Weight      int32      `json:"weight"`
	StartsAt    *time.Time `json:"starts_at"`
	EndsAt      *time.Time `json:"ends_at"`
	IsActive    bool       `json:"is_active"`
	// Live : actif et dans sa période de diffusion.
	Live      bool      `json:"live"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

// VisualInput : création ou modification d'un visuel.
type VisualInput struct {
	Kind        string     `json:"kind"`
	Title       string     `json:"title"`
	Subtitle    string     `json:"subtitle"`
	Body        string     `json:"body"`
	ImageKey    string     `json:"image_key"`
	ProductID   *uuid.UUID `json:"product_id"`
	CTALabel    string     `json:"cta_label"`
	ExternalURL string     `json:"external_url"`
	Placements  []string   `json:"placements"`
	Apps        []string   `json:"apps"`
	Priority    int32      `json:"priority"`
	Weight      int32      `json:"weight"`
	StartsAt    *time.Time `json:"starts_at"`
	EndsAt      *time.Time `json:"ends_at"`
	IsActive    *bool      `json:"is_active"`
}

// Settings : réglages de diffusion.
type Settings struct {
	Enabled             bool      `json:"enabled"`
	BannersEnabled      bool      `json:"banners_enabled"`
	ModalEnabled        bool      `json:"modal_enabled"`
	InterstitialEnabled bool      `json:"interstitial_enabled"`
	FirstDelaySeconds   int32     `json:"first_delay_seconds"`
	MinIntervalSeconds  int32     `json:"min_interval_seconds"`
	MaxPerSession       int32     `json:"max_per_session"`
	FeedEvery           int32     `json:"feed_every"`
	Rotation            string    `json:"rotation"`
	OfficialURL         string    `json:"official_url"`
	UpdatedAt           time.Time `json:"updated_at"`
}

// Service gère la publicité.
type Service struct {
	db      *database.DB
	uploads *uploads.Service
	catalog *catalog.Service
	orders  *orders.Service
	audit   *admin.Service
}

// NewService crée le service.
func NewService(db *database.DB, up *uploads.Service, cat *catalog.Service, ord *orders.Service, audit *admin.Service) *Service {
	return &Service{db: db, uploads: up, catalog: cat, orders: ord, audit: audit}
}

func (s *Service) toVisual(v store.PromoVisual, now time.Time) Visual {
	return Visual{
		ID: v.ID, Kind: v.Kind, Title: v.Title, Subtitle: v.Subtitle, Body: v.Body,
		ImageKey: v.ImageKey, ImageURL: s.uploads.PublicURL(v.ImageKey), ProductID: v.ProductID,
		CTALabel: v.CtaLabel, ExternalURL: v.ExternalUrl, Placements: nonNil(v.Placements), Apps: nonNil(v.Apps),
		Priority: v.Priority, Weight: v.Weight, StartsAt: v.StartsAt, EndsAt: v.EndsAt, IsActive: v.IsActive,
		Live:      v.IsActive && (v.StartsAt == nil || !now.Before(*v.StartsAt)) && (v.EndsAt == nil || now.Before(*v.EndsAt)),
		CreatedAt: v.CreatedAt, UpdatedAt: v.UpdatedAt,
	}
}

func toSettings(r store.PromoSetting) Settings {
	return Settings{
		Enabled: r.Enabled, BannersEnabled: r.BannersEnabled, ModalEnabled: r.ModalEnabled,
		InterstitialEnabled: r.InterstitialEnabled, FirstDelaySeconds: r.FirstDelaySeconds,
		MinIntervalSeconds: r.MinIntervalSeconds, MaxPerSession: r.MaxPerSession, FeedEvery: r.FeedEvery,
		Rotation: r.Rotation, OfficialURL: r.OfficialUrl, UpdatedAt: r.UpdatedAt,
	}
}

// --- Visuels ---------------------------------------------------------------------------------

// ListVisuals liste les visuels (tous pour l'admin).
func (s *Service) ListVisuals(ctx context.Context) ([]Visual, error) {
	rows, err := store.New(s.db.Conn(ctx)).ListVisuals(ctx, false)
	if err != nil {
		return nil, fmt.Errorf("liste des visuels : %w", err)
	}
	now := time.Now()
	out := make([]Visual, len(rows))
	for i, r := range rows {
		out[i] = s.toVisual(r, now)
	}
	return out, nil
}

// GetVisual retourne un visuel.
func (s *Service) GetVisual(ctx context.Context, id uuid.UUID) (Visual, error) {
	r, err := store.New(s.db.Conn(ctx)).GetVisual(ctx, id)
	if database.IsNoRows(err) {
		return Visual{}, apperr.NotFound("visual_not_found", "Visuel introuvable.")
	}
	if err != nil {
		return Visual{}, fmt.Errorf("lecture du visuel : %w", err)
	}
	return s.toVisual(r, time.Now()), nil
}

func (s *Service) validateVisual(ctx context.Context, adminID uuid.UUID, in *VisualInput, currentKey string) error {
	v := validate.New()
	in.Title, in.Subtitle, in.Body = validate.Clean(in.Title), validate.Clean(in.Subtitle), strings.TrimSpace(in.Body)
	in.CTALabel, in.ExternalURL = validate.Clean(in.CTALabel), strings.TrimSpace(in.ExternalURL)
	v.Check(slices.Contains(Kinds, in.Kind), "kind", "Type inconnu : "+strings.Join(Kinds, ", ")+".")
	v.Text("title", in.Title, 2, 80)
	v.Text("subtitle", in.Subtitle, 0, 140)
	v.Text("body", in.Body, 0, 600)
	v.Text("cta_label", in.CTALabel, 0, 30)
	if in.ExternalURL != "" {
		v.Check(validHTTPS(in.ExternalURL), "external_url", "Adresse https:// valide attendue.")
	}
	in.Placements = dedupe(in.Placements)
	for _, p := range in.Placements {
		v.Check(slices.Contains(Placements, p), "placements", "Emplacement inconnu : "+strings.Join(Placements, ", ")+".")
	}
	v.Check(len(in.Placements) > 0, "placements", "Choisissez au moins un emplacement.")
	if in.Apps = dedupe(in.Apps); len(in.Apps) == 0 {
		in.Apps = []string{"buyer"}
	}
	for _, a := range in.Apps {
		v.Check(slices.Contains(Apps, a), "apps", "App inconnue : buyer, seller ou driver.")
	}
	if in.Weight == 0 {
		in.Weight = 1
	}
	v.Check(in.Priority >= 0 && in.Priority <= 100, "priority", "Priorité entre 0 et 100.")
	v.Check(in.Weight >= 1 && in.Weight <= 100, "weight", "Poids entre 1 et 100.")
	if in.StartsAt != nil && in.EndsAt != nil {
		v.Check(in.EndsAt.After(*in.StartsAt), "ends_at", "La fin doit suivre le début.")
	}
	v.Check(in.ImageKey != "", "image_key", "Ajoutez l'image du visuel.")
	if err := v.Err(); err != nil {
		return err
	}
	if in.ImageKey != currentKey {
		if err := s.uploads.Check(ctx, uploads.PromoVisual, adminID, in.ImageKey, "image_key"); err != nil {
			return err
		}
	}
	if in.ProductID != nil {
		if _, err := s.catalog.AdminGet(ctx, *in.ProductID); err != nil {
			return apperr.Validation(map[string]string{"product_id": "Produit inconnu."})
		}
	}
	return nil
}

// CreateVisual publie un visuel (journalisé).
func (s *Service) CreateVisual(ctx context.Context, adminID uuid.UUID, in VisualInput) (Visual, error) {
	if err := s.validateVisual(ctx, adminID, &in, ""); err != nil {
		return Visual{}, err
	}
	var out Visual
	err := s.db.InTx(ctx, func(ctx context.Context) error {
		r, err := store.New(s.db.Conn(ctx)).CreateVisual(ctx, store.CreateVisualParams{
			Kind: in.Kind, Title: in.Title, Subtitle: in.Subtitle, Body: in.Body, ImageKey: in.ImageKey,
			ProductID: in.ProductID, CtaLabel: in.CTALabel, ExternalUrl: in.ExternalURL, Placements: in.Placements,
			Apps: in.Apps, Priority: in.Priority, Weight: in.Weight, StartsAt: in.StartsAt, EndsAt: in.EndsAt,
			IsActive: in.IsActive == nil || *in.IsActive, CreatedBy: &adminID,
		})
		if err != nil {
			return fmt.Errorf("création du visuel : %w", err)
		}
		out = s.toVisual(r, time.Now())
		return s.audit.Record(ctx, admin.AuditEntry{
			AdminID: &adminID, Action: "promo.visual_create", TargetType: "promo_visual", TargetID: r.ID.String(),
			After: map[string]any{"kind": r.Kind, "title": r.Title, "placements": r.Placements},
		})
	})
	return out, err
}

// UpdateVisual modifie un visuel (journalisé).
func (s *Service) UpdateVisual(ctx context.Context, adminID, id uuid.UUID, in VisualInput) (Visual, error) {
	cur, err := s.GetVisual(ctx, id)
	if err != nil {
		return Visual{}, err
	}
	if err := s.validateVisual(ctx, adminID, &in, cur.ImageKey); err != nil {
		return Visual{}, err
	}
	active := cur.IsActive
	if in.IsActive != nil {
		active = *in.IsActive
	}
	var out Visual
	err = s.db.InTx(ctx, func(ctx context.Context) error {
		r, err := store.New(s.db.Conn(ctx)).UpdateVisual(ctx, store.UpdateVisualParams{
			ID: id, Kind: in.Kind, Title: in.Title, Subtitle: in.Subtitle, Body: in.Body, ImageKey: in.ImageKey,
			ProductID: in.ProductID, CtaLabel: in.CTALabel, ExternalUrl: in.ExternalURL, Placements: in.Placements,
			Apps: in.Apps, Priority: in.Priority, Weight: in.Weight, StartsAt: in.StartsAt, EndsAt: in.EndsAt,
			IsActive: active,
		})
		if err != nil {
			return fmt.Errorf("modification du visuel : %w", err)
		}
		out = s.toVisual(r, time.Now())
		return s.audit.Record(ctx, admin.AuditEntry{
			AdminID: &adminID, Action: "promo.visual_update", TargetType: "promo_visual", TargetID: id.String(),
			Before: map[string]any{"title": cur.Title, "is_active": cur.IsActive},
			After:  map[string]any{"title": r.Title, "is_active": r.IsActive},
		})
	})
	return out, err
}

// DeleteVisual supprime un visuel ; ses statistiques restent, sans lien (journalisé).
func (s *Service) DeleteVisual(ctx context.Context, adminID, id uuid.UUID) error {
	cur, err := s.GetVisual(ctx, id)
	if err != nil {
		return err
	}
	return s.db.InTx(ctx, func(ctx context.Context) error {
		if err := store.New(s.db.Conn(ctx)).DeleteVisual(ctx, id); err != nil {
			return fmt.Errorf("suppression du visuel : %w", err)
		}
		return s.audit.Record(ctx, admin.AuditEntry{
			AdminID: &adminID, Action: "promo.visual_delete", TargetType: "promo_visual", TargetID: id.String(),
			Before: map[string]any{"title": cur.Title, "kind": cur.Kind},
		})
	})
}

// --- Réglages --------------------------------------------------------------------------------

// GetSettings retourne les réglages de diffusion.
func (s *Service) GetSettings(ctx context.Context) (Settings, error) {
	r, err := store.New(s.db.Conn(ctx)).GetSettings(ctx)
	if err != nil {
		return Settings{}, fmt.Errorf("réglages de la publicité : %w", err)
	}
	return toSettings(r), nil
}

// UpdateSettings enregistre les réglages (journalisé).
func (s *Service) UpdateSettings(ctx context.Context, adminID uuid.UUID, in Settings) (Settings, error) {
	v := validate.New()
	in.OfficialURL = strings.TrimSpace(in.OfficialURL)
	v.Check(in.FirstDelaySeconds >= 0 && in.FirstDelaySeconds <= 600, "first_delay_seconds", "Entre 0 et 600 secondes.")
	v.Check(in.MinIntervalSeconds >= 15 && in.MinIntervalSeconds <= 3600, "min_interval_seconds", "Entre 15 et 3600 secondes.")
	v.Check(in.MaxPerSession >= 0 && in.MaxPerSession <= 50, "max_per_session", "Entre 0 et 50.")
	v.Check(in.FeedEvery >= 3 && in.FeedEvery <= 50, "feed_every", "Entre 3 et 50.")
	v.Check(slices.Contains([]string{"weighted", "random", "priority"}, in.Rotation), "rotation", "Rotation : weighted, random ou priority.")
	if in.OfficialURL != "" {
		v.Check(validHTTPS(in.OfficialURL), "official_url", "Adresse https:// valide attendue.")
	}
	if err := v.Err(); err != nil {
		return Settings{}, err
	}
	cur, err := s.GetSettings(ctx)
	if err != nil {
		return Settings{}, err
	}
	var out Settings
	err = s.db.InTx(ctx, func(ctx context.Context) error {
		r, err := store.New(s.db.Conn(ctx)).UpdateSettings(ctx, store.UpdateSettingsParams{
			Enabled: in.Enabled, BannersEnabled: in.BannersEnabled, ModalEnabled: in.ModalEnabled,
			InterstitialEnabled: in.InterstitialEnabled, FirstDelaySeconds: in.FirstDelaySeconds,
			MinIntervalSeconds: in.MinIntervalSeconds, MaxPerSession: in.MaxPerSession, FeedEvery: in.FeedEvery,
			Rotation: in.Rotation, OfficialUrl: in.OfficialURL, UpdatedBy: &adminID,
		})
		if err != nil {
			return fmt.Errorf("enregistrement des réglages : %w", err)
		}
		out = toSettings(r)
		return s.audit.Record(ctx, admin.AuditEntry{
			AdminID: &adminID, Action: "promo.settings", TargetType: "promo_settings", TargetID: "promo",
			Before: cur, After: out,
		})
	})
	return out, err
}

// --- Fil des apps ----------------------------------------------------------------------------

// FeedVisual : visuel du fil, avec le produit commandable s'il est en vente.
type FeedVisual struct {
	Visual
	Product *catalog.Product `json:"product"`
}

// Feed est ce que les apps affichent.
type Feed struct {
	Settings Settings          `json:"settings"`
	Visuals  []FeedVisual      `json:"visuals"`
	Featured []catalog.Product `json:"featured"`
}

// Feed retourne le fil d'une app : visuels en cours (par priorité) et produits mis en avant.
// Publicité coupée : fil vide, réglages compris (l'app n'affiche rien).
func (s *Service) Feed(ctx context.Context, app string) (Feed, error) {
	settings, err := s.GetSettings(ctx)
	if err != nil {
		return Feed{}, err
	}
	out := Feed{Settings: settings, Visuals: []FeedVisual{}, Featured: []catalog.Product{}}
	if !settings.Enabled {
		return out, nil
	}
	rows, err := store.New(s.db.Conn(ctx)).ListVisuals(ctx, true)
	if err != nil {
		return Feed{}, fmt.Errorf("visuels en cours : %w", err)
	}
	now := time.Now()
	products := map[uuid.UUID]*catalog.Product{}
	for _, r := range rows {
		if !slices.Contains(r.Apps, app) {
			continue
		}
		fv := FeedVisual{Visual: s.toVisual(r, now)}
		if r.ProductID != nil {
			p, ok := products[*r.ProductID]
			if !ok {
				if prod, _, err := s.catalog.GetPublic(ctx, *r.ProductID); err == nil {
					p = &prod
				}
				products[*r.ProductID] = p
			}
			if p == nil {
				fv.ProductID = nil // produit retiré de la vente : le visuel reste, sans « Commander »
			}
			fv.Product = p
		}
		out.Visuals = append(out.Visuals, fv)
	}
	if out.Featured, err = s.catalog.Featured(ctx, 20); err != nil {
		return Feed{}, err
	}
	return out, nil
}

// Event : événement remonté par une app.
type Event struct {
	Kind      string     `json:"kind"`
	VisualID  *uuid.UUID `json:"visual_id"`
	ProductID *uuid.UUID `json:"product_id"`
	Placement string     `json:"placement"`
}

// MaxEventsPerBatch : événements au plus par envoi.
const MaxEventsPerBatch = 50

// RecordEvents enregistre un lot d'événements ; les événements invalides sont ignorés (les
// statistiques ne doivent jamais bloquer l'app). Retourne le nombre retenu.
func (s *Service) RecordEvents(ctx context.Context, app, sessionID string, events []Event) (int, error) {
	v := validate.New()
	v.Check(slices.Contains(Apps, app), "app", "App inconnue : buyer, seller ou driver.")
	v.Check(validSession(sessionID), "session_id", "Identifiant de session invalide.")
	v.Check(len(events) <= MaxEventsPerBatch, "events", fmt.Sprintf("%d événements au plus par envoi.", MaxEventsPerBatch))
	if err := v.Err(); err != nil {
		return 0, err
	}
	kept := 0
	err := s.db.InTx(ctx, func(ctx context.Context) error {
		for _, e := range events {
			if !slices.Contains(EventKinds, e.Kind) || (e.VisualID == nil && e.ProductID == nil) || len(e.Placement) > 30 {
				continue
			}
			if e.Placement != "" && !slices.Contains(Placements, e.Placement) {
				e.Placement = ""
			}
			// Visuel ou produit supprimé entre-temps : l'événement est gardé sans le lien.
			err := s.db.Savepoint(ctx, func(ctx context.Context) error {
				return store.New(s.db.Conn(ctx)).InsertEvent(ctx, store.InsertEventParams{
					Kind: e.Kind, VisualID: e.VisualID, ProductID: e.ProductID, Placement: e.Placement, App: app, SessionID: sessionID,
				})
			})
			if database.IsForeignKeyViolation(err) {
				continue
			}
			if err != nil {
				return fmt.Errorf("événement publicitaire : %w", err)
			}
			kept++
		}
		return nil
	})
	return kept, err
}

// --- Aides -----------------------------------------------------------------------------------

func validHTTPS(raw string) bool {
	u, err := url.Parse(raw)
	return err == nil && u.Scheme == "https" && u.Host != "" && u.User == nil && len(raw) <= 300
}

// validSession : 8 à 64 caractères [A-Za-z0-9_-] (identifiant aléatoire de l'app).
func validSession(id string) bool {
	if len(id) < 8 || len(id) > 64 {
		return false
	}
	for _, c := range id {
		if !(c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' || c >= '0' && c <= '9' || c == '-' || c == '_') {
			return false
		}
	}
	return true
}

func dedupe(v []string) []string {
	out := []string{}
	for _, s := range v {
		if s = strings.TrimSpace(s); s != "" && !slices.Contains(out, s) {
			out = append(out, s)
		}
	}
	return out
}

func nonNil(v []string) []string {
	if v == nil {
		return []string{}
	}
	return v
}
