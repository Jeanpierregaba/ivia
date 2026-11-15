package pharmacy

import (
	"context"
	"fmt"
	"time"

	"github.com/google/uuid"

	"ivia/backend/internal/admin"
	"ivia/backend/internal/geo"
	"ivia/backend/internal/pharmacy/store"
	"ivia/backend/internal/platform/apperr"
	"ivia/backend/internal/platform/database"
	"ivia/backend/internal/platform/validate"
)

// OnDutyPharmacy : pharmacie de garde, information publique (écran « De garde maintenant »,
// accueil « Pharmacies de garde »).
type OnDutyPharmacy struct {
	ID          uuid.UUID  `json:"id"`
	Name        string     `json:"name"`
	Phone       string     `json:"phone"`
	AddressText string     `json:"address_text"`
	Location    geo.Point  `json:"location"`
	DistanceM   int32      `json:"distance_m"`
	Open24h     bool       `json:"open_24h"`
	IsOpen      bool       `json:"is_open"`
	OnDuty      bool       `json:"on_duty"`
	DutyUntil   *time.Time `json:"duty_until"`
}

// DutyShift : créneau de garde du planning.
type DutyShift struct {
	ID         uuid.UUID `json:"id"`
	PharmacyID uuid.UUID `json:"pharmacy_id"`
	StartsAt   time.Time `json:"starts_at"`
	EndsAt     time.Time `json:"ends_at"`
	// Source : manual (ajoutée seule par la pharmacie), import (planning officiel, importé d'une
	// liste) ou admin (saisie par l'équipe ivia).
	Source     string     `json:"source"`
	ImportedAt *time.Time `json:"imported_at"`
	CreatedAt  time.Time  `json:"created_at"`
}

// DutyShiftInput : un créneau (8 jours au plus).
type DutyShiftInput struct {
	StartsAt time.Time `json:"starts_at"`
	EndsAt   time.Time `json:"ends_at"`
	Reason   string    `json:"reason"`
}

// Medicine : produit de la base des médicaments (suggestions de saisie).
type Medicine struct {
	ID               uuid.UUID `json:"id"`
	Name             string    `json:"name"`
	Dosage           string    `json:"dosage"`
	Form             string    `json:"form"`
	ActiveIngredient string    `json:"active_ingredient"`
	// Label : nom et dosage, tel que repris dans l'alerte.
	Label    string `json:"label"`
	IsActive bool   `json:"is_active"`
}

// MedicineInput crée ou modifie un médicament (back-office).
type MedicineInput struct {
	Name             string `json:"name"`
	Dosage           string `json:"dosage"`
	Form             string `json:"form"`
	ActiveIngredient string `json:"active_ingredient"`
	IsActive         *bool  `json:"is_active"`
}

// OnDuty liste les pharmacies de garde autour d'un point, les plus proches d'abord.
func (s *Service) OnDuty(ctx context.Context, p geo.Point, radiusM int32, limit int32) ([]OnDutyPharmacy, error) {
	v := validate.New()
	v.Coordinates("", p.Lat, p.Lng)
	v.Check(radiusM >= 500 && radiusM <= 50_000, "radius_m", "Entre 500 m et 50 km.")
	if err := v.Err(); err != nil {
		return nil, err
	}
	rows, err := s.q(ctx).OnDutyPharmacies(ctx, store.OnDutyPharmaciesParams{Lat: p.Lat, Lng: p.Lng, RadiusM: float64(radiusM), Lim: limit})
	if err != nil {
		return nil, fmt.Errorf("pharmacies de garde : %w", err)
	}
	out := make([]OnDutyPharmacy, len(rows))
	for i, r := range rows {
		out[i] = OnDutyPharmacy{
			ID: r.ID, Name: r.Name, Phone: r.Phone, AddressText: r.AddressText, Location: geo.Point{Lat: r.Lat, Lng: r.Lng},
			DistanceM: int32(r.DistanceM + 0.5), Open24h: r.Open24h, IsOpen: r.IsOpen, OnDuty: r.OnDuty, DutyUntil: dutyUntil(r.DutyUntil),
		}
	}
	return out, nil
}

func toShift(r store.PharmacyDutyShift) DutyShift {
	return DutyShift{ID: r.ID, PharmacyID: r.PharmacyID, StartsAt: r.StartsAt, EndsAt: r.EndsAt, Source: r.Source, ImportedAt: r.ImportedAt, CreatedAt: r.CreatedAt}
}

func (s *Service) shifts(ctx context.Context, pharmacyID uuid.UUID) ([]DutyShift, error) {
	rows, err := s.q(ctx).ListDutyShifts(ctx, store.ListDutyShiftsParams{PharmacyID: pharmacyID, Since: time.Now().Add(-24 * time.Hour)})
	if err != nil {
		return nil, fmt.Errorf("planning de garde : %w", err)
	}
	out := make([]DutyShift, len(rows))
	for i, r := range rows {
		out[i] = toShift(r)
	}
	return out, nil
}

// MyDutyShifts : planning de garde de la pharmacie du titulaire.
func (s *Service) MyDutyShifts(ctx context.Context, ownerID uuid.UUID) ([]DutyShift, error) {
	id, err := s.pharmacyIDOf(ctx, ownerID)
	if err != nil {
		return nil, err
	}
	return s.shifts(ctx, id)
}

// AdminDutyShifts : planning de garde d'une pharmacie.
func (s *Service) AdminDutyShifts(ctx context.Context, pharmacyID uuid.UUID) ([]DutyShift, error) {
	if _, err := s.q(ctx).GetPharmacy(ctx, pharmacyID); database.IsNoRows(err) {
		return nil, errPharmacyNotFound
	} else if err != nil {
		return nil, fmt.Errorf("lecture de la pharmacie : %w", err)
	}
	return s.shifts(ctx, pharmacyID)
}

// AddDutyShift ajoute un créneau de garde (admin, journalisé).
func (s *Service) AddDutyShift(ctx context.Context, adminID, pharmacyID uuid.UUID, in DutyShiftInput) (DutyShift, error) {
	v := validate.New()
	v.Check(!in.StartsAt.IsZero() && !in.EndsAt.IsZero(), "starts_at", "Début et fin attendus (RFC 3339).")
	v.Check(in.EndsAt.After(in.StartsAt), "ends_at", "La fin doit suivre le début.")
	v.Check(in.EndsAt.Sub(in.StartsAt) <= 8*24*time.Hour, "ends_at", "8 jours au plus.")
	v.Check(in.EndsAt.After(time.Now()), "ends_at", "Créneau déjà passé.")
	if err := v.Err(); err != nil {
		return DutyShift{}, err
	}
	var out DutyShift
	err := s.db.InTx(ctx, func(ctx context.Context) error {
		q := s.q(ctx)
		if _, err := q.LockPharmacy(ctx, pharmacyID); database.IsNoRows(err) {
			return errPharmacyNotFound
		} else if err != nil {
			return fmt.Errorf("verrou de la pharmacie : %w", err)
		}
		r, err := q.InsertDutyShift(ctx, store.InsertDutyShiftParams{PharmacyID: pharmacyID, StartsAt: in.StartsAt, EndsAt: in.EndsAt, CreatedBy: adminID, Source: "admin"})
		if err != nil {
			return fmt.Errorf("créneau de garde : %w", err)
		}
		out = toShift(r)
		return s.admin.Record(ctx, admin.AuditEntry{
			AdminID: &adminID, Action: "pharmacy.duty_shift_added", TargetType: "pharmacy", TargetID: pharmacyID.String(),
			After: out, Reason: validate.Clean(in.Reason),
		})
	})
	return out, err
}

// DeleteDutyShift retire un créneau de garde (admin, journalisé).
func (s *Service) DeleteDutyShift(ctx context.Context, adminID, shiftID uuid.UUID, reason string) error {
	return s.db.InTx(ctx, func(ctx context.Context) error {
		r, err := s.q(ctx).DeleteDutyShift(ctx, shiftID)
		if database.IsNoRows(err) {
			return apperr.NotFound("duty_shift_not_found", "Créneau introuvable.")
		}
		if err != nil {
			return fmt.Errorf("suppression du créneau : %w", err)
		}
		return s.admin.Record(ctx, admin.AuditEntry{
			AdminID: &adminID, Action: "pharmacy.duty_shift_deleted", TargetType: "pharmacy", TargetID: r.PharmacyID.String(),
			Before: toShift(r), Reason: validate.Clean(reason),
		})
	})
}

// --- Base des médicaments ---------------------------------------------------------------------

func toMedicine(r store.Medicine) Medicine {
	label := r.Name
	if r.Dosage != "" {
		label += " " + r.Dosage
	}
	return Medicine{
		ID: r.ID, Name: r.Name, Dosage: r.Dosage, Form: r.Form, ActiveIngredient: r.ActiveIngredient, Label: label, IsActive: r.IsActive,
	}
}

// SearchMedicines suggère des médicaments (nom, dosage ou principe actif ; 2 lettres au moins).
func (s *Service) SearchMedicines(ctx context.Context, query string, limit int32) ([]Medicine, error) {
	query = validate.Clean(query)
	if len([]rune(query)) < 2 {
		return []Medicine{}, nil
	}
	rows, err := s.q(ctx).SearchMedicines(ctx, store.SearchMedicinesParams{Q: query, Lim: limit})
	if err != nil {
		return nil, fmt.Errorf("recherche de médicaments : %w", err)
	}
	out := make([]Medicine, len(rows))
	for i, r := range rows {
		out[i] = toMedicine(r)
	}
	return out, nil
}

// AdminListMedicines liste la base (recherche facultative).
func (s *Service) AdminListMedicines(ctx context.Context, query string, limit, offset int32) ([]Medicine, error) {
	rows, err := s.q(ctx).AdminListMedicines(ctx, store.AdminListMedicinesParams{Q: validate.Clean(query), Lim: limit, Off: offset})
	if err != nil {
		return nil, fmt.Errorf("base des médicaments : %w", err)
	}
	out := make([]Medicine, len(rows))
	for i, r := range rows {
		out[i] = toMedicine(r)
	}
	return out, nil
}

func cleanMedicine(in MedicineInput) (MedicineInput, error) {
	in.Name, in.Dosage = validate.Clean(in.Name), validate.Clean(in.Dosage)
	in.Form, in.ActiveIngredient = validate.Clean(in.Form), validate.Clean(in.ActiveIngredient)
	v := validate.New()
	v.Text("name", in.Name, 2, 120)
	v.Check(len(in.Dosage) <= 60, "dosage", "60 caractères au plus.")
	v.Check(len(in.Form) <= 60, "form", "60 caractères au plus.")
	v.Check(len(in.ActiveIngredient) <= 120, "active_ingredient", "120 caractères au plus.")
	return in, v.Err()
}

var errMedicineExists = apperr.Conflict("medicine_exists", "Ce médicament (nom, dosage, forme) existe déjà.")

// CreateMedicine ajoute un médicament à la base (admin, journalisé).
func (s *Service) CreateMedicine(ctx context.Context, adminID uuid.UUID, in MedicineInput) (Medicine, error) {
	in, err := cleanMedicine(in)
	if err != nil {
		return Medicine{}, err
	}
	var out Medicine
	err = s.db.InTx(ctx, func(ctx context.Context) error {
		r, err := s.q(ctx).InsertMedicine(ctx, store.InsertMedicineParams{Name: in.Name, Dosage: in.Dosage, Form: in.Form, ActiveIngredient: in.ActiveIngredient})
		if database.IsUniqueViolation(err, "") {
			return errMedicineExists
		}
		if err != nil {
			return fmt.Errorf("ajout du médicament : %w", err)
		}
		out = toMedicine(r)
		return s.admin.Record(ctx, admin.AuditEntry{
			AdminID: &adminID, Action: "medicine.created", TargetType: "medicine", TargetID: r.ID.String(), After: out,
		})
	})
	return out, err
}

// UpdateMedicine modifie ou désactive un médicament (admin, journalisé).
func (s *Service) UpdateMedicine(ctx context.Context, adminID, id uuid.UUID, in MedicineInput) (Medicine, error) {
	in, err := cleanMedicine(in)
	if err != nil {
		return Medicine{}, err
	}
	var out Medicine
	err = s.db.InTx(ctx, func(ctx context.Context) error {
		q := s.q(ctx)
		cur, err := q.GetMedicine(ctx, id)
		if database.IsNoRows(err) {
			return apperr.NotFound("medicine_not_found", "Médicament introuvable.")
		}
		if err != nil {
			return fmt.Errorf("lecture du médicament : %w", err)
		}
		r, err := q.UpdateMedicine(ctx, store.UpdateMedicineParams{
			ID: id, Name: in.Name, Dosage: in.Dosage, Form: in.Form, ActiveIngredient: in.ActiveIngredient,
			IsActive: pick(in.IsActive, cur.IsActive),
		})
		if database.IsUniqueViolation(err, "") {
			return errMedicineExists
		}
		if err != nil {
			return fmt.Errorf("modification du médicament : %w", err)
		}
		out = toMedicine(r)
		return s.admin.Record(ctx, admin.AuditEntry{
			AdminID: &adminID, Action: "medicine.updated", TargetType: "medicine", TargetID: id.String(),
			Before: toMedicine(cur), After: out,
		})
	})
	return out, err
}
