package pharmacy

import (
	"context"
	"fmt"
	"net/http"
	"regexp"
	"strings"
	"time"

	"github.com/google/uuid"

	"ivia/backend/internal/pharmacy/store"
	"ivia/backend/internal/platform/apperr"
	"ivia/backend/internal/platform/database"
	"ivia/backend/internal/platform/httpapi"
	"ivia/backend/internal/platform/validate"
)

// Workflow d'inscription : brouillon, planning de garde et compte de versement du titulaire, envoi
// au back-office.

const maxShiftsAtOnce = 60

var payoutPhone = regexp.MustCompile(`^\+228[0-9]{8}$`)

// PayoutAccount est le compte de versement ; le numéro complet n'est donné qu'au back-office.
type PayoutAccount struct {
	Operator    string `json:"operator"`
	PhoneMasked string `json:"phone_masked"`
	Phone       string `json:"phone,omitempty"`
	Holder      string `json:"holder"`
}

// PayoutInput est la saisie du compte de versement.
type PayoutInput struct {
	Operator string `json:"operator"`
	Phone    string `json:"phone"`
	Holder   string `json:"holder"`
}

// withDossier complète la vue : compte de versement et date d'envoi.
func (s *Service) withDossier(ctx context.Context, p *Pharmacy, full bool) error {
	r, err := s.q(ctx).PharmacyDossier(ctx, p.ID)
	if err != nil {
		return fmt.Errorf("dossier de la pharmacie : %w", err)
	}
	p.SubmittedAt = r.SubmittedAt
	if r.PayoutOperator != nil && r.PayoutPhone != nil {
		phone := *r.PayoutPhone
		p.Payout = &PayoutAccount{Operator: *r.PayoutOperator, PhoneMasked: "+228 •• •• •• " + phone[len(phone)-2:], Holder: r.PayoutHolder}
		if full {
			p.Payout.Phone = phone
		}
	}
	return nil
}

// editable indique si le titulaire peut encore modifier son dossier.
func editable(status string) bool {
	return status == ReviewDraft || status == ReviewChangesRequested || status == ReviewRejected
}

// SetPayout renseigne le compte de versement, avant la validation seulement : ensuite, le titulaire
// passe par l'équipe ivia, qui vérifie le nouveau titulaire du compte.
func (s *Service) SetPayout(ctx context.Context, ownerID uuid.UUID, in PayoutInput) (Pharmacy, error) {
	in.Holder = validate.Clean(in.Holder)
	v := validate.New()
	v.Check(in.Operator == "flooz" || in.Operator == "tmoney", "operator", "Choisissez Moov Money (Flooz) ou Yas (T-Money).")
	v.Check(payoutPhone.MatchString(in.Phone), "phone", "Numéro attendu : +228 suivi de 8 chiffres.")
	v.Text("holder", in.Holder, 3, 100)
	if err := v.Err(); err != nil {
		return Pharmacy{}, err
	}
	id, err := s.pharmacyIDOf(ctx, ownerID)
	if err != nil {
		return Pharmacy{}, err
	}
	n, err := s.q(ctx).SetPharmacyPayout(ctx, store.SetPharmacyPayoutParams{ID: id, PayoutOperator: &in.Operator, PayoutPhone: &in.Phone, PayoutHolder: in.Holder})
	if err != nil {
		return Pharmacy{}, fmt.Errorf("compte de versement : %w", err)
	}
	if n == 0 {
		return Pharmacy{}, apperr.Conflict("payout_locked", "Dossier envoyé ou validé : contactez l'équipe ivia pour changer de compte de versement.")
	}
	p, _, err := s.pharmacyView(ctx, id, false)
	return p, err
}

// Submit envoie le dossier au back-office ; aucune alerte n'est reçue avant la validation.
func (s *Service) Submit(ctx context.Context, ownerID uuid.UUID) (Pharmacy, error) {
	id, err := s.pharmacyIDOf(ctx, ownerID)
	if err != nil {
		return Pharmacy{}, err
	}
	var out Pharmacy
	err = s.db.InTx(ctx, func(ctx context.Context) error {
		q := s.q(ctx)
		cur, err := q.LockPharmacy(ctx, id)
		if err != nil {
			return fmt.Errorf("verrou de la pharmacie : %w", err)
		}
		if !editable(cur.ReviewStatus) {
			return apperr.Conflict("pharmacy_not_editable", "Ce dossier a déjà été envoyé.")
		}
		p, _, err := s.pharmacyView(ctx, id, false)
		if err != nil {
			return err
		}
		if len(p.MissingDocuments) > 0 {
			return apperr.Unprocessable("documents_missing", "Pièces manquantes : "+strings.Join(p.MissingDocuments, ", ")+".")
		}
		if p.Payout == nil {
			return apperr.Unprocessable("payout_missing", "Renseignez votre compte de versement.")
		}
		if err := q.MarkPharmacySubmitted(ctx, id); err != nil {
			return fmt.Errorf("envoi du dossier : %w", err)
		}
		if err := s.notify.NotifyAdmins(ctx, "pharmacy_application", "Nouvelle pharmacie à valider",
			p.Name+" demande à rejoindre ivia.", map[string]string{"pharmacy_id": id.String()}); err != nil {
			return err
		}
		out, _, err = s.pharmacyView(ctx, id, false)
		return err
	})
	return out, err
}

// AddOwnShifts ajoute des créneaux au planning de garde (un seul, ou un import).
func (s *Service) AddOwnShifts(ctx context.Context, ownerID uuid.UUID, shifts []DutyShiftInput) ([]DutyShift, error) {
	v := validate.New()
	v.Check(len(shifts) >= 1 && len(shifts) <= maxShiftsAtOnce, "shifts", "Entre 1 et 60 créneaux à la fois.")
	now := time.Now()
	for _, in := range shifts {
		v.Check(!in.StartsAt.IsZero() && !in.EndsAt.IsZero(), "shifts", "Début et fin attendus.")
		v.Check(in.EndsAt.After(in.StartsAt), "shifts", "La fin d'une garde doit suivre son début.")
		v.Check(in.EndsAt.Sub(in.StartsAt) <= 8*24*time.Hour, "shifts", "Une garde dure 8 jours au plus.")
		v.Check(in.EndsAt.After(now), "shifts", "Une garde est déjà passée.")
	}
	if err := v.Err(); err != nil {
		return nil, err
	}
	id, err := s.pharmacyIDOf(ctx, ownerID)
	if err != nil {
		return nil, err
	}
	err = s.db.InTx(ctx, func(ctx context.Context) error {
		q := s.q(ctx)
		cur, err := q.LockPharmacy(ctx, id)
		if err != nil {
			return fmt.Errorf("verrou de la pharmacie : %w", err)
		}
		if cur.SuspendedAt != nil {
			return apperr.Forbidden("pharmacy_suspended", "Votre pharmacie est suspendue.")
		}
		for _, in := range shifts {
			if _, err := q.InsertDutyShift(ctx, store.InsertDutyShiftParams{PharmacyID: id, StartsAt: in.StartsAt, EndsAt: in.EndsAt, CreatedBy: ownerID}); err != nil {
				return fmt.Errorf("créneau de garde : %w", err)
			}
		}
		return nil
	})
	if err != nil {
		return nil, err
	}
	return s.shifts(ctx, id)
}

// DeleteOwnShift retire un créneau du planning de la pharmacie du compte.
func (s *Service) DeleteOwnShift(ctx context.Context, ownerID, shiftID uuid.UUID) error {
	id, err := s.pharmacyIDOf(ctx, ownerID)
	if err != nil {
		return err
	}
	_, err = s.q(ctx).DeleteOwnDutyShift(ctx, store.DeleteOwnDutyShiftParams{ID: shiftID, PharmacyID: id})
	if database.IsNoRows(err) {
		return apperr.NotFound("duty_shift_not_found", "Créneau introuvable.")
	}
	if err != nil {
		return fmt.Errorf("suppression du créneau : %w", err)
	}
	return nil
}

// nightAt indique si l'heure (Lomé, UTC toute l'année) tombe dans la plage de nuit.
func nightAt(t time.Time, from, to int32) bool {
	if from == to {
		return false
	}
	h := int32(t.UTC().Hour())
	if from < to {
		return h >= from && h < to
	}
	return h >= from || h < to
}

// isNight : la nuit, seules les pharmacies de garde reçoivent les alertes.
func (s *Service) isNight(ctx context.Context) (bool, error) {
	st, err := s.q(ctx).GetSettings(ctx)
	if err != nil {
		return false, fmt.Errorf("réglages de nuit : %w", err)
	}
	return nightAt(time.Now(), st.NightFromHour, st.NightToHour), nil
}

func (h *Handler) setPayout(w http.ResponseWriter, r *http.Request) error {
	var in PayoutInput
	if err := httpapi.Decode(r, &in); err != nil {
		return err
	}
	p, err := h.svc.SetPayout(r.Context(), me(r), in)
	return ok(w, p, err)
}

func (h *Handler) submit(w http.ResponseWriter, r *http.Request) error {
	p, err := h.svc.Submit(r.Context(), me(r))
	return ok(w, p, err)
}

func (h *Handler) addOwnShifts(w http.ResponseWriter, r *http.Request) error {
	var in struct {
		Shifts []DutyShiftInput `json:"shifts"`
	}
	if err := httpapi.Decode(r, &in); err != nil {
		return err
	}
	items, err := h.svc.AddOwnShifts(r.Context(), me(r), in.Shifts)
	if err != nil {
		return err
	}
	return httpapi.Created(w, map[string]any{"items": items})
}

func (h *Handler) deleteOwnShift(w http.ResponseWriter, r *http.Request) error {
	id, err := httpapi.PathUUID(r, "id")
	if err != nil {
		return err
	}
	if err := h.svc.DeleteOwnShift(r.Context(), me(r), id); err != nil {
		return err
	}
	return httpapi.NoContent(w)
}
