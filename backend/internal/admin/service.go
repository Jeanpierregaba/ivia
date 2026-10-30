// Package admin gère les paramètres de la plateforme et le journal des actions admin.
//
// Le journal est en ajout seul (trigger en base). Chaque action admin des autres modules appelle
// Audit.Record dans la même transaction que l'action elle-même.
package admin

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/google/uuid"

	"ivia/backend/internal/admin/store"
	"ivia/backend/internal/platform/database"
	"ivia/backend/internal/platform/validate"
)

// Settings sont les paramètres réglables par l'admin.
type Settings struct {
	CommissionRateBP             int32     `json:"commission_rate_bp"`
	MotorbikeBaseFeeXOF          int64     `json:"motorbike_base_fee_xof"`
	MotorbikePerKmXOF            int64     `json:"motorbike_per_km_xof"`
	CarBaseFeeXOF                int64     `json:"car_base_fee_xof"`
	CarPerKmXOF                  int64     `json:"car_per_km_xof"`
	DistanceCoefficientPct       int32     `json:"distance_coefficient_pct"`
	PaymentTimeoutMinutes        int32     `json:"payment_timeout_minutes"`
	SellerResponseTimeoutMinutes int32     `json:"seller_response_timeout_minutes"`
	DriverOfferTimeoutSeconds    int32     `json:"driver_offer_timeout_seconds"`
	AssignmentMaxOffers          int32     `json:"assignment_max_offers"`
	AssignmentAlertMinutes       int32     `json:"assignment_alert_minutes"`
	UpdatedAt                    time.Time `json:"updated_at"`
}

// PaymentTimeout est le délai de paiement d'une commande.
func (s Settings) PaymentTimeout() time.Duration {
	return time.Duration(s.PaymentTimeoutMinutes) * time.Minute
}

// SellerResponseTimeout est le délai laissé au marchand pour accepter une commande.
func (s Settings) SellerResponseTimeout() time.Duration {
	return time.Duration(s.SellerResponseTimeoutMinutes) * time.Minute
}

// DriverOfferTimeout est le délai laissé au livreur pour répondre à une proposition.
func (s Settings) DriverOfferTimeout() time.Duration {
	return time.Duration(s.DriverOfferTimeoutSeconds) * time.Second
}

// AssignmentAlertAfter est la durée sans livreur au-delà de laquelle l'admin est alerté.
func (s Settings) AssignmentAlertAfter() time.Duration {
	return time.Duration(s.AssignmentAlertMinutes) * time.Minute
}

// SettingsPatch modifie une partie des paramètres (champs absents inchangés).
type SettingsPatch struct {
	CommissionRateBP             *int32 `json:"commission_rate_bp"`
	MotorbikeBaseFeeXOF          *int64 `json:"motorbike_base_fee_xof"`
	MotorbikePerKmXOF            *int64 `json:"motorbike_per_km_xof"`
	CarBaseFeeXOF                *int64 `json:"car_base_fee_xof"`
	CarPerKmXOF                  *int64 `json:"car_per_km_xof"`
	DistanceCoefficientPct       *int32 `json:"distance_coefficient_pct"`
	PaymentTimeoutMinutes        *int32 `json:"payment_timeout_minutes"`
	SellerResponseTimeoutMinutes *int32 `json:"seller_response_timeout_minutes"`
	DriverOfferTimeoutSeconds    *int32 `json:"driver_offer_timeout_seconds"`
	AssignmentMaxOffers          *int32 `json:"assignment_max_offers"`
	AssignmentAlertMinutes       *int32 `json:"assignment_alert_minutes"`
}

// AuditEntry décrit une action admin à journaliser.
type AuditEntry struct {
	// AdminID nil : action du système (tâche de fond, ligne de commande).
	AdminID    *uuid.UUID
	Action     string
	TargetType string
	TargetID   string
	Before     any
	After      any
	Reason     string
}

// AuditRecord est une ligne du journal.
type AuditRecord struct {
	ID         int64           `json:"id"`
	AdminID    *uuid.UUID      `json:"admin_id"`
	Action     string          `json:"action"`
	TargetType string          `json:"target_type"`
	TargetID   string          `json:"target_id"`
	Before     json.RawMessage `json:"before"`
	After      json.RawMessage `json:"after"`
	Reason     string          `json:"reason"`
	CreatedAt  time.Time       `json:"created_at"`
}

// AuditFilter filtre la consultation du journal.
type AuditFilter struct {
	AdminID    *uuid.UUID
	TargetType string
	TargetID   string
	Limit      int32
	Offset     int32
}

// Service gère paramètres et journal.
type Service struct {
	db *database.DB
}

// NewService crée le service.
func NewService(db *database.DB) *Service { return &Service{db: db} }

// Settings retourne les paramètres en vigueur.
func (s *Service) Settings(ctx context.Context) (Settings, error) {
	row, err := store.New(s.db.Conn(ctx)).GetSettings(ctx)
	if err != nil {
		return Settings{}, fmt.Errorf("lecture des paramètres : %w", err)
	}
	return toSettings(row), nil
}

// UpdateSettings applique patch, journalise l'avant/après et retourne les nouveaux paramètres.
func (s *Service) UpdateSettings(ctx context.Context, adminID uuid.UUID, patch SettingsPatch, reason string) (Settings, error) {
	var out Settings
	err := s.db.InTx(ctx, func(ctx context.Context) error {
		q := store.New(s.db.Conn(ctx))
		cur, err := q.GetSettings(ctx)
		if err != nil {
			return fmt.Errorf("lecture des paramètres : %w", err)
		}
		before := toSettings(cur)
		p := store.UpdateSettingsParams{
			CommissionRateBp:             pick(patch.CommissionRateBP, cur.CommissionRateBp),
			MotorbikeBaseFeeXof:          pick(patch.MotorbikeBaseFeeXOF, cur.MotorbikeBaseFeeXof),
			MotorbikePerKmXof:            pick(patch.MotorbikePerKmXOF, cur.MotorbikePerKmXof),
			CarBaseFeeXof:                pick(patch.CarBaseFeeXOF, cur.CarBaseFeeXof),
			CarPerKmXof:                  pick(patch.CarPerKmXOF, cur.CarPerKmXof),
			DistanceCoefficientPct:       pick(patch.DistanceCoefficientPct, cur.DistanceCoefficientPct),
			PaymentTimeoutMinutes:        pick(patch.PaymentTimeoutMinutes, cur.PaymentTimeoutMinutes),
			SellerResponseTimeoutMinutes: pick(patch.SellerResponseTimeoutMinutes, cur.SellerResponseTimeoutMinutes),
			DriverOfferTimeoutSeconds:    pick(patch.DriverOfferTimeoutSeconds, cur.DriverOfferTimeoutSeconds),
			AssignmentMaxOffers:          pick(patch.AssignmentMaxOffers, cur.AssignmentMaxOffers),
			AssignmentAlertMinutes:       pick(patch.AssignmentAlertMinutes, cur.AssignmentAlertMinutes),
			UpdatedBy:                    &adminID,
		}
		if err := validateSettings(p); err != nil {
			return err
		}
		row, err := q.UpdateSettings(ctx, p)
		if err != nil {
			return fmt.Errorf("mise à jour des paramètres : %w", err)
		}
		out = toSettings(row)
		return s.Record(ctx, AuditEntry{
			AdminID: &adminID, Action: "settings.update", TargetType: "settings", TargetID: "global",
			Before: before, After: out, Reason: reason,
		})
	})
	return out, err
}

func validateSettings(p store.UpdateSettingsParams) error {
	v := validate.New()
	v.Check(p.CommissionRateBp >= 0 && p.CommissionRateBp <= 10000, "commission_rate_bp", "Entre 0 et 10000 (points de base).")
	for field, val := range map[string]int64{
		"motorbike_base_fee_xof": p.MotorbikeBaseFeeXof, "motorbike_per_km_xof": p.MotorbikePerKmXof,
		"car_base_fee_xof": p.CarBaseFeeXof, "car_per_km_xof": p.CarPerKmXof,
	} {
		v.Check(val >= 0 && val <= 1_000_000, field, "Montant entre 0 et 1 000 000 FCFA.")
	}
	v.Check(p.DistanceCoefficientPct >= 100 && p.DistanceCoefficientPct <= 300, "distance_coefficient_pct", "Entre 100 et 300.")
	v.Check(p.PaymentTimeoutMinutes >= 5 && p.PaymentTimeoutMinutes <= 120, "payment_timeout_minutes", "Entre 5 et 120 minutes.")
	v.Check(p.SellerResponseTimeoutMinutes >= 5 && p.SellerResponseTimeoutMinutes <= 120, "seller_response_timeout_minutes", "Entre 5 et 120 minutes.")
	v.Check(p.DriverOfferTimeoutSeconds >= 15 && p.DriverOfferTimeoutSeconds <= 300, "driver_offer_timeout_seconds", "Entre 15 et 300 secondes.")
	v.Check(p.AssignmentMaxOffers >= 1 && p.AssignmentMaxOffers <= 50, "assignment_max_offers", "Entre 1 et 50.")
	v.Check(p.AssignmentAlertMinutes >= 1 && p.AssignmentAlertMinutes <= 240, "assignment_alert_minutes", "Entre 1 et 240 minutes.")
	return v.Err()
}

// Record écrit une ligne dans le journal des actions admin (dans la transaction en cours).
func (s *Service) Record(ctx context.Context, e AuditEntry) error {
	before, err := marshalOptional(e.Before)
	if err != nil {
		return err
	}
	after, err := marshalOptional(e.After)
	if err != nil {
		return err
	}
	err = store.New(s.db.Conn(ctx)).InsertAudit(ctx, store.InsertAuditParams{
		AdminID: e.AdminID, Action: e.Action, TargetType: e.TargetType, TargetID: e.TargetID,
		Before: before, After: after, Reason: e.Reason,
	})
	if err != nil {
		return fmt.Errorf("journal admin (%s) : %w", e.Action, err)
	}
	return nil
}

// ListAudit retourne les lignes du journal, les plus récentes d'abord.
func (s *Service) ListAudit(ctx context.Context, f AuditFilter) ([]AuditRecord, error) {
	rows, err := store.New(s.db.Conn(ctx)).ListAudit(ctx, store.ListAuditParams{
		AdminID: f.AdminID, TargetType: nilIfEmpty(f.TargetType), TargetID: nilIfEmpty(f.TargetID),
		Lim: f.Limit, Off: f.Offset,
	})
	if err != nil {
		return nil, fmt.Errorf("lecture du journal admin : %w", err)
	}
	out := make([]AuditRecord, len(rows))
	for i, r := range rows {
		out[i] = AuditRecord{
			ID: r.ID, AdminID: r.AdminID, Action: r.Action, TargetType: r.TargetType, TargetID: r.TargetID,
			Before: r.Before, After: r.After, Reason: r.Reason, CreatedAt: r.CreatedAt,
		}
	}
	return out, nil
}

func toSettings(r store.Setting) Settings {
	return Settings{
		CommissionRateBP:             r.CommissionRateBp,
		MotorbikeBaseFeeXOF:          r.MotorbikeBaseFeeXof,
		MotorbikePerKmXOF:            r.MotorbikePerKmXof,
		CarBaseFeeXOF:                r.CarBaseFeeXof,
		CarPerKmXOF:                  r.CarPerKmXof,
		DistanceCoefficientPct:       r.DistanceCoefficientPct,
		PaymentTimeoutMinutes:        r.PaymentTimeoutMinutes,
		SellerResponseTimeoutMinutes: r.SellerResponseTimeoutMinutes,
		DriverOfferTimeoutSeconds:    r.DriverOfferTimeoutSeconds,
		AssignmentMaxOffers:          r.AssignmentMaxOffers,
		AssignmentAlertMinutes:       r.AssignmentAlertMinutes,
		UpdatedAt:                    r.UpdatedAt,
	}
}

func marshalOptional(v any) ([]byte, error) {
	if v == nil {
		return nil, nil
	}
	b, err := json.Marshal(v)
	if err != nil {
		return nil, fmt.Errorf("journal admin : sérialisation : %w", err)
	}
	return b, nil
}

func pick[T any](p *T, def T) T {
	if p != nil {
		return *p
	}
	return def
}

func nilIfEmpty(s string) *string {
	if s == "" {
		return nil
	}
	return &s
}
