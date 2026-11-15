// Package pharmacy gère l'alerte médicament (spec 029) : inscription et validation des
// pharmacies, alertes des clients, réponses des pharmacies, déblocage payant, réservation en
// retrait ou en livraison par un livreur ivia, reversements aux pharmacies.
//
// Règles :
//   - une alerte combine des produits saisis (base des médicaments ou texte libre) et des photos
//     (pages d'ordonnance, boîtes) ; son lancement est gratuit ;
//   - elle part aux pharmacies validées, non suspendues et de garde (planning en vigueur,
//     24 h/24, ou déclarées ouvertes / de garde) dans le rayon choisi par le client ;
//   - les pharmacies répondent ligne par ligne (disponible ou non, prix) pendant la fenêtre de
//     réponse ; le client voit les réponses anonymes, classées par distance ;
//   - le forfait débloque UNE pharmacie (nom, adresse, téléphone, position) et met ses produits
//     de côté avec un code de retrait ; en débloquer une autre se paie à nouveau ; le forfait est
//     remboursé si la pharmacie annule ;
//   - le client va chercher ses produits (paiement sur place) ou se fait livrer par un livreur
//     ivia (produits et livraison payés dans l'app) ; sur ordonnance, le livreur vérifie l'original ;
//   - un paiement n'est réussi que sur un événement vérifié du prestataire (même circuit que les
//     commandes : payments.ExternalPayments) ;
//   - le client, la pharmacie et le livreur ne voient chacun que ce dont ils ont besoin : la
//     pharmacie ne connaît jamais l'identité du client avant la réservation (prénom seulement) ;
//   - les photos d'ordonnance (données de santé) sont privées, lues par URL signée de 10 minutes
//     par les seules pharmacies sollicitées, et supprimées après la durée de conservation (24 h).
package pharmacy

import (
	"context"
	"crypto/rand"
	"fmt"
	"log/slog"
	"math/big"
	"slices"
	"time"

	"github.com/google/uuid"

	"ivia/backend/internal/admin"
	"ivia/backend/internal/delivery"
	"ivia/backend/internal/geo"
	"ivia/backend/internal/mapping"
	"ivia/backend/internal/notifications"
	"ivia/backend/internal/payments"
	"ivia/backend/internal/pharmacy/store"
	"ivia/backend/internal/platform/apperr"
	"ivia/backend/internal/platform/database"
	"ivia/backend/internal/platform/jobs"
	"ivia/backend/internal/platform/validate"
	"ivia/backend/internal/uploads"
	"ivia/backend/internal/users"
)

// ReferencePrefix : préfixe des références de paiement du module (« ivh_… »).
const ReferencePrefix = "ivh"

// Statuts de validation d'une pharmacie.
const (
	ReviewPending          = "pending_review"
	ReviewDraft            = "draft"
	ReviewChangesRequested = "changes_requested"
	ReviewApproved         = "approved"
	ReviewRejected         = "rejected"
)

// Types d'alerte.
const (
	KindPrescription = "prescription"
	KindBoxPhoto     = "box_photo"
	KindName         = "name"
	KindMixed        = "mixed"
)

// Types de photo d'une alerte.
const (
	PhotoPrescription = "prescription"
	PhotoBox          = "box"
)

// Statuts d'une alerte.
const (
	AlertSearching  = "searching"
	AlertAnswered   = "answered"
	AlertNoResponse = "no_response"
	AlertUnlocked   = "unlocked"
	AlertFulfilled  = "fulfilled"
	AlertCancelled  = "cancelled"
)

// Modes de remise et statuts d'une réservation.
const (
	Pickup   = "pickup"
	Delivery = "delivery"

	ResReserved = "reserved"
	// ResCourierSearch : « Livreur ivia » choisi, recherche du livreur (avant le paiement).
	ResCourierSearch = "courier_search"
	// ResAwaitingPayment : un livreur a accepté ; le client paie produits et livraison.
	ResAwaitingPayment = "awaiting_payment"
	ResPaid            = "paid"
	ResCourierAssigned = "courier_assigned"
	ResPickedUp        = "picked_up"
	ResCompleted       = "completed"
	ResExpired         = "expired"
	ResCancelled       = "cancelled"
)

// activeReservation : statuts d'une réservation en cours.
var activeReservation = []string{ResReserved, ResCourierSearch, ResAwaitingPayment, ResPaid, ResCourierAssigned, ResPickedUp}

// Règles fixes (les autres sont dans pharmacy_settings, réglables par l'admin).
const (
	// paymentRequestLimit : demandes de paiement par client et par heure.
	paymentRequestLimit = 10
	// pendingGiveUpAfter : un paiement sans confirmation du prestataire après ce délai est expiré.
	pendingGiveUpAfter = time.Hour
	// retryCourierAfter : délai avant de chercher à nouveau un livreur quand aucun n'est libre.
	retryCourierAfter = 30 * time.Second
)

// Settings : réglages du module.
type Settings struct {
	Enabled               bool  `json:"enabled"`
	UnlockFeeXOF          int64 `json:"unlock_fee_xof"`
	SearchRadiusM         int32 `json:"search_radius_m"`
	MaxRadiusM            int32 `json:"max_radius_m"`
	TargetResponses       int32 `json:"target_responses"`
	WidenAfterMinutes     int32 `json:"widen_after_minutes"`
	ResponseWindowMinutes int32 `json:"response_window_minutes"`
	PickupHoldMinutes     int32 `json:"pickup_hold_minutes"`
	PhotoRetentionHours   int32 `json:"photo_retention_hours"`
	// RadiusOptionsM : rayons proposés au client ; SearchRadiusM est celui par défaut.
	RadiusOptionsM []int32 `json:"radius_options_m"`
	// AutoWiden : élargit seul la recherche au rayon maximal si les réponses manquent.
	AutoWiden bool `json:"auto_widen"`
	// ProductCommissionBP : commission ivia sur les médicaments livrés (points de base). 0 par
	// défaut : ivia est rémunéré par le forfait de déblocage ; jamais de commission sur un retrait.
	ProductCommissionBP int32 `json:"product_commission_bp"`
	// Heures de nuit par défaut (Lomé), tant que la pharmacie n'a pas choisi les siennes. Début égal à
	// fin : aucune restriction.
	NightFromHour int32     `json:"night_from_hour"`
	NightToHour   int32     `json:"night_to_hour"`
	UpdatedAt     time.Time `json:"updated_at"`
	// photoRetentionDays : ancienne colonne (00027), conservée telle quelle.
	photoRetentionDays int32
}

// SettingsPatch modifie les réglages (champs absents : inchangés).
type SettingsPatch struct {
	Enabled               *bool    `json:"enabled"`
	UnlockFeeXOF          *int64   `json:"unlock_fee_xof"`
	SearchRadiusM         *int32   `json:"search_radius_m"`
	MaxRadiusM            *int32   `json:"max_radius_m"`
	TargetResponses       *int32   `json:"target_responses"`
	WidenAfterMinutes     *int32   `json:"widen_after_minutes"`
	ResponseWindowMinutes *int32   `json:"response_window_minutes"`
	PickupHoldMinutes     *int32   `json:"pickup_hold_minutes"`
	PhotoRetentionHours   *int32   `json:"photo_retention_hours"`
	RadiusOptionsM        *[]int32 `json:"radius_options_m"`
	AutoWiden             *bool    `json:"auto_widen"`
	ProductCommissionBP   *int32   `json:"product_commission_bp"`
	NightFromHour         *int32   `json:"night_from_hour"`
	NightToHour           *int32   `json:"night_to_hour"`
}

// Router calcule un itinéraire (module carte) ; branché après l'assemblage (SetRouter).
type Router interface {
	Route(ctx context.Context, profile string, points []mapping.LatLng) (mapping.Route, error)
}

// SetRouter branche le calcul d'itinéraire (arrivée estimée du livreur chez la pharmacie).
func (s *Service) SetRouter(r Router) { s.router = r }

// Service gère le module.
type Service struct {
	router   Router
	mail     notifications.EmailSender
	db       *database.DB
	jobs     jobs.Enqueuer
	admin    *admin.Service
	users    *users.Service
	geo      *geo.Service
	uploads  *uploads.Service
	notify   *notifications.Service
	payments *payments.Service
	provider payments.Provider
	drivers  *delivery.Service
	logger   *slog.Logger
}

// Deps regroupe les dépendances du service.
type Deps struct {
	DB       *database.DB
	Jobs     jobs.Enqueuer
	Admin    *admin.Service
	Users    *users.Service
	Geo      *geo.Service
	Uploads  *uploads.Service
	Notify   *notifications.Service
	Payments *payments.Service
	Delivery *delivery.Service
	Logger   *slog.Logger
	Mail     notifications.EmailSender
}

// NewService crée le service et le déclare propriétaire de ses paiements et de ses fichiers privés.
func NewService(d Deps) *Service {
	s := &Service{
		mail: d.Mail, db: d.DB, jobs: d.Jobs, admin: d.Admin, users: d.Users, geo: d.Geo, uploads: d.Uploads, notify: d.Notify,
		payments: d.Payments, provider: d.Payments.Provider(), drivers: d.Delivery, logger: d.Logger,
	}
	d.Payments.AddExternal(ReferencePrefix, s)
	d.Uploads.RegisterOwner(uploads.PharmacyDocument, s.attachedDocuments)
	d.Uploads.RegisterOwner(uploads.PharmacyAlertPhoto, s.attachedPhotos)
	return s
}

func (s *Service) q(ctx context.Context) *store.Queries { return store.New(s.db.Conn(ctx)) }

// Settings retourne les réglages du module.
func (s *Service) Settings(ctx context.Context) (Settings, error) {
	r, err := s.q(ctx).GetSettings(ctx)
	if err != nil {
		return Settings{}, fmt.Errorf("réglages pharmacie : %w", err)
	}
	return toSettings(r), nil
}

// UpdateSettings modifie les réglages (admin, journalisé).
func (s *Service) UpdateSettings(ctx context.Context, adminID uuid.UUID, p SettingsPatch, reason string) (Settings, error) {
	var out Settings
	err := s.db.InTx(ctx, func(ctx context.Context) error {
		cur, err := s.Settings(ctx)
		if err != nil {
			return err
		}
		next := store.UpdateSettingsParams{
			Enabled: pick(p.Enabled, cur.Enabled), UnlockFeeXof: pick(p.UnlockFeeXOF, cur.UnlockFeeXOF),
			SearchRadiusM: pick(p.SearchRadiusM, cur.SearchRadiusM), MaxRadiusM: pick(p.MaxRadiusM, cur.MaxRadiusM),
			TargetResponses: pick(p.TargetResponses, cur.TargetResponses), WidenAfterMinutes: pick(p.WidenAfterMinutes, cur.WidenAfterMinutes),
			ResponseWindowMinutes: pick(p.ResponseWindowMinutes, cur.ResponseWindowMinutes),
			PickupHoldMinutes:     pick(p.PickupHoldMinutes, cur.PickupHoldMinutes),
			PhotoRetentionDays:    cur.photoRetentionDays,
			PhotoRetentionHours:   pick(p.PhotoRetentionHours, cur.PhotoRetentionHours),
			RadiusOptionsM:        pick(p.RadiusOptionsM, cur.RadiusOptionsM),
			AutoWiden:             pick(p.AutoWiden, cur.AutoWiden),
			ProductCommissionBp:   pick(p.ProductCommissionBP, cur.ProductCommissionBP),
			NightFromHour:         pick(p.NightFromHour, cur.NightFromHour),
			NightToHour:           pick(p.NightToHour, cur.NightToHour),
		}
		v := validate.New()
		v.Check(next.UnlockFeeXof >= 0 && next.UnlockFeeXof <= 100_000, "unlock_fee_xof", "Entre 0 et 100 000 FCFA.")
		v.Check(next.SearchRadiusM >= 500 && next.SearchRadiusM <= 50_000, "search_radius_m", "Entre 500 m et 50 km.")
		v.Check(next.MaxRadiusM >= next.SearchRadiusM && next.MaxRadiusM <= 50_000, "max_radius_m", "Au moins le rayon de recherche, 50 km au plus.")
		v.Check(next.TargetResponses >= 1 && next.TargetResponses <= 20, "target_responses", "Entre 1 et 20.")
		v.Check(next.WidenAfterMinutes >= 1 && next.WidenAfterMinutes <= 60, "widen_after_minutes", "Entre 1 et 60 minutes.")
		v.Check(next.ResponseWindowMinutes >= 2 && next.ResponseWindowMinutes <= 120, "response_window_minutes", "Entre 2 et 120 minutes.")
		v.Check(next.PickupHoldMinutes >= 15 && next.PickupHoldMinutes <= 1440, "pickup_hold_minutes", "Entre 15 minutes et 24 heures.")
		v.Check(next.NightFromHour >= 0 && next.NightFromHour <= 23 && next.NightToHour >= 0 && next.NightToHour <= 23, "night_from_hour", "Heure entre 0 et 23.")
		v.Check(next.ProductCommissionBp >= 0 && next.ProductCommissionBp <= 5000, "product_commission_bp",
			"Entre 0 et 5 000 points de base (50 %).")
		v.Check(next.PhotoRetentionHours >= 1 && next.PhotoRetentionHours <= 8760, "photo_retention_hours", "Entre 1 heure et 1 an.")
		v.Check(validRadiusOptions(next.RadiusOptionsM, next.MaxRadiusM), "radius_options_m",
			"1 à 5 rayons croissants, entre 500 m et le rayon maximal.")
		v.Check(slices.Contains(next.RadiusOptionsM, next.SearchRadiusM), "search_radius_m",
			"Le rayon par défaut doit faire partie des rayons proposés.")
		if err := v.Err(); err != nil {
			return err
		}
		r, err := s.q(ctx).UpdateSettings(ctx, next)
		if err != nil {
			return fmt.Errorf("enregistrement des réglages : %w", err)
		}
		out = toSettings(r)
		return s.admin.Record(ctx, admin.AuditEntry{
			AdminID: &adminID, Action: "pharmacy.settings_updated", TargetType: "pharmacy_settings", TargetID: "1",
			Before: cur, After: out, Reason: validate.Clean(reason),
		})
	})
	return out, err
}

func toSettings(r store.PharmacySetting) Settings {
	return Settings{
		Enabled: r.Enabled, UnlockFeeXOF: r.UnlockFeeXof, SearchRadiusM: r.SearchRadiusM, MaxRadiusM: r.MaxRadiusM,
		TargetResponses: r.TargetResponses, WidenAfterMinutes: r.WidenAfterMinutes, ResponseWindowMinutes: r.ResponseWindowMinutes,
		PickupHoldMinutes: r.PickupHoldMinutes, PhotoRetentionHours: r.PhotoRetentionHours, RadiusOptionsM: r.RadiusOptionsM,
		AutoWiden: r.AutoWiden, ProductCommissionBP: r.ProductCommissionBp, NightFromHour: r.NightFromHour, NightToHour: r.NightToHour, UpdatedAt: r.UpdatedAt, photoRetentionDays: r.PhotoRetentionDays,
	}
}

func validRadiusOptions(opts []int32, maxRadius int32) bool {
	if len(opts) == 0 || len(opts) > 5 {
		return false
	}
	for i, o := range opts {
		if o < 500 || o > maxRadius || (i > 0 && o <= opts[i-1]) {
			return false
		}
	}
	return true
}

// dutyUntil convertit la fin de garde lue en base (« epoch » quand aucune garde n'est en cours).
func dutyUntil(t time.Time) *time.Time {
	if t.Year() < 2000 {
		return nil
	}
	return &t
}

func pick[T any](p *T, def T) T {
	if p != nil {
		return *p
	}
	return def
}

// newCode tire un code de remise à 4 chiffres (essais limités par le handler).
func newCode() (string, error) {
	n, err := rand.Int(rand.Reader, big.NewInt(10_000))
	if err != nil {
		return "", fmt.Errorf("tirage du code : %w", err)
	}
	return fmt.Sprintf("%04d", n.Int64()), nil
}

var errPharmacyNotFound = apperr.NotFound("pharmacy_not_found", "Pharmacie introuvable.")

// Overview : indicateurs du module sur une période (tableau de bord admin).
type Overview struct {
	PendingReview         int64 `json:"pending_review"`
	Approved              int64 `json:"approved"`
	Reachable             int64 `json:"reachable"`
	Alerts                int64 `json:"alerts"`
	AlertsWithoutResponse int64 `json:"alerts_without_response"`
	Unlocked              int64 `json:"unlocked"`
	UnlockRevenueXOF      int64 `json:"unlock_revenue_xof"`
	CommissionXOF         int64 `json:"commission_xof"`
	Completed             int64 `json:"completed"`
}

// Overview retourne les indicateurs entre from et to.
func (s *Service) Overview(ctx context.Context, from, to time.Time) (Overview, error) {
	r, err := s.q(ctx).Overview(ctx, store.OverviewParams{FromTime: from, ToTime: to})
	if err != nil {
		return Overview{}, fmt.Errorf("indicateurs pharmacie : %w", err)
	}
	return Overview{
		PendingReview: r.PendingReview, Approved: r.Approved, Reachable: r.Reachable, Alerts: r.Alerts,
		AlertsWithoutResponse: r.AlertsWithoutResponse, Unlocked: r.Unlocked, UnlockRevenueXOF: r.UnlockRevenueXof,
		CommissionXOF: r.CommissionXof, Completed: r.Completed,
	}, nil
}
