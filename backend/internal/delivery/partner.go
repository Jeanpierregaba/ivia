package delivery

// Workflow partenaire (BPMN « ivia Livreur : entrée et inscription » et « connexion »,
// 2026-11-07) : une activité par ligne (livraison, taxi VTC), justificatifs selon le véhicule,
// compte de versement, envoi du dossier, contrôle du véhicule sur place, puis décision du
// back-office (valider, demander des compléments, refuser). L'authentification, la création du
// compte et l'alerte de connexion depuis un nouvel appareil restent communes (module auth).

import (
	"context"
	"fmt"
	"regexp"
	"slices"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/google/uuid"

	"ivia/backend/internal/admin"
	"ivia/backend/internal/delivery/store"
	"ivia/backend/internal/notifications"
	"ivia/backend/internal/platform/apperr"
	"ivia/backend/internal/platform/database"
	"ivia/backend/internal/platform/identity"
	"ivia/backend/internal/platform/validate"
)

// Activités, statuts du dossier et ouverture du taxi VTC.
const (
	ActivityDelivery = "delivery"
	ActivityVTC      = "vtc"

	StatusDraft            = "draft"
	StatusChangesRequested = "changes_requested"

	// VTC masqué, en pré-inscription (dossier possible, courses fermées) ou ouvert.
	VTCHidden          = "hidden"
	VTCPreregistration = "preregistration"
	VTCOpen            = "open"
)

var payoutPhone = regexp.MustCompile(`^\+228[0-9]{8}$`)

var activityLabels = map[string]string{ActivityDelivery: "Livraison", ActivityVTC: "Taxi VTC"}

// DocumentsFor : pièces exigées selon l'activité et le véhicule. Vélo : sans permis ; moto et
// voiture : permis, carte grise, assurance ; taxi VTC : exigences renforcées.
func DocumentsFor(activity, vehicle string) []string {
	switch {
	case activity == ActivityVTC:
		return []string{"id_card", "driving_license", "vehicle_registration", "vehicle_insurance", "vehicle_photo", "criminal_record"}
	case vehicle == "bicycle":
		return []string{"id_card"}
	default:
		return []string{"id_card", "driving_license", "vehicle_registration", "vehicle_insurance"}
	}
}

// Vehicle décrit le véhicule déclaré pour une activité.
type Vehicle struct {
	Type  string `json:"type"`
	Brand string `json:"brand"`
	Model string `json:"model"`
	Color string `json:"color"`
	Plate string `json:"plate"`
	Seats *int16 `json:"seats"`
}

// VehicleCheck est le résultat du contrôle du véhicule sur place.
type VehicleCheck struct {
	Passed    bool       `json:"passed"`
	Note      string     `json:"note"`
	CheckedAt *time.Time `json:"checked_at"`
}

// Activity est une activité partenaire et l'état de son dossier.
type Activity struct {
	Activity          string        `json:"activity"`
	Status            string        `json:"status"`
	ReviewNote        string        `json:"review_note"`
	ReviewedAt        *time.Time    `json:"reviewed_at"`
	SubmittedAt       *time.Time    `json:"submitted_at"`
	Vehicle           Vehicle       `json:"vehicle"`
	WorkZoneID        *uuid.UUID    `json:"work_zone_id"`
	VehicleCheck      *VehicleCheck `json:"vehicle_check"`
	RequiredDocuments []string      `json:"required_documents"`
	MissingDocuments  []string      `json:"missing_documents"`
	legacy            bool
}

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

// ActivityInput est la déclaration d'une activité et de son véhicule.
type ActivityInput struct {
	VehicleType string     `json:"vehicle_type"`
	Brand       string     `json:"brand"`
	Model       string     `json:"model"`
	Color       string     `json:"color"`
	Plate       string     `json:"plate"`
	Seats       *int16     `json:"seats"`
	WorkZoneID  *uuid.UUID `json:"work_zone_id"`
}

// DriverSettings sont les réglages du back-office pour les partenaires.
type DriverSettings struct {
	VTCMode              string    `json:"vtc_mode"`
	DeliveryVehicleCheck bool      `json:"delivery_vehicle_check"`
	PartnerGuide         string    `json:"partner_guide"`
	UpdatedAt            time.Time `json:"updated_at"`
}

// VehicleOption est un véhicule possible et ses pièces exigées.
type VehicleOption struct {
	Type              string   `json:"type"`
	RequiredDocuments []string `json:"required_documents"`
}

// ActivityOption est une activité proposée à l'inscription ; mode vaut open ou preregistration.
type ActivityOption struct {
	Activity string          `json:"activity"`
	Label    string          `json:"label"`
	Mode     string          `json:"mode"`
	Vehicles []VehicleOption `json:"vehicles"`
}

// loadActivities complète le profil : activités, pièces manquantes et compte de versement.
func (s *Service) loadActivities(ctx context.Context, d *Driver, full bool) error {
	q := store.New(s.db.Conn(ctx))
	rows, err := q.ListActivities(ctx, d.UserID)
	if err != nil {
		return fmt.Errorf("lecture des activités : %w", err)
	}
	d.Activities = make([]Activity, len(rows))
	for i, r := range rows {
		a := Activity{
			Activity: r.Activity, Status: r.Status, ReviewNote: r.ReviewNote, ReviewedAt: r.ReviewedAt,
			SubmittedAt: r.SubmittedAt, WorkZoneID: r.WorkZoneID, legacy: r.Legacy,
			Vehicle: Vehicle{Type: r.VehicleType, Brand: r.VehicleBrand, Model: r.VehicleModel, Color: r.VehicleColor, Plate: r.VehiclePlate, Seats: r.VehicleSeats},
		}
		if r.VehicleCheckPassed != nil {
			a.VehicleCheck = &VehicleCheck{Passed: *r.VehicleCheckPassed, Note: r.VehicleCheckNote, CheckedAt: r.VehicleCheckedAt}
		}
		a.RequiredDocuments = DocumentsFor(r.Activity, r.VehicleType)
		if r.Legacy {
			a.RequiredDocuments = RequiredDocuments
		}
		a.MissingDocuments = missingKinds(d.Documents, a.RequiredDocuments)
		d.Activities[i] = a
	}
	p, err := q.DriverPayout(ctx, d.UserID)
	if err != nil {
		return fmt.Errorf("compte de versement : %w", err)
	}
	if p.PayoutOperator != nil && p.PayoutPhone != nil {
		phone := *p.PayoutPhone
		d.Payout = &PayoutAccount{Operator: *p.PayoutOperator, PhoneMasked: "+228 •• •• •• " + phone[len(phone)-2:], Holder: p.PayoutHolder}
		if full {
			d.Payout.Phone = phone
		}
	}
	return nil
}

func missingKinds(docs []Document, required []string) []string {
	missing := []string{}
	for _, k := range required {
		if !slices.ContainsFunc(docs, func(d Document) bool { return d.Kind == k }) {
			missing = append(missing, k)
		}
	}
	return missing
}

func labels(kinds []string) string {
	out := make([]string, len(kinds))
	for i, k := range kinds {
		out[i] = documentLabels[k]
	}
	return strings.Join(out, ", ")
}

func checkActivity(activity string) error {
	if _, ok := activityLabels[activity]; !ok {
		return apperr.NotFound("activity_not_found", "Activité inconnue.")
	}
	return nil
}

// --- Réglages -------------------------------------------------------------------------------

// Settings retourne les réglages partenaires.
func (s *Service) Settings(ctx context.Context) (DriverSettings, error) {
	r, err := store.New(s.db.Conn(ctx)).GetDriverSettings(ctx)
	if err != nil {
		return DriverSettings{}, fmt.Errorf("réglages partenaires : %w", err)
	}
	return DriverSettings{VTCMode: r.VtcMode, DeliveryVehicleCheck: r.DeliveryVehicleCheck, PartnerGuide: r.PartnerGuide, UpdatedAt: r.UpdatedAt}, nil
}

// UpdateSettings modifie les réglages partenaires (journalisé).
func (s *Service) UpdateSettings(ctx context.Context, adminID uuid.UUID, in DriverSettings) (DriverSettings, error) {
	in.PartnerGuide = strings.TrimSpace(in.PartnerGuide)
	v := validate.New()
	v.Check(in.VTCMode == VTCHidden || in.VTCMode == VTCPreregistration || in.VTCMode == VTCOpen, "vtc_mode", "Valeur attendue : hidden, preregistration ou open.")
	v.Check(utf8.RuneCountInString(in.PartnerGuide) <= 20000, "partner_guide", "Guide trop long (20 000 caractères au plus).")
	if err := v.Err(); err != nil {
		return DriverSettings{}, err
	}
	var out DriverSettings
	err := s.db.InTx(ctx, func(ctx context.Context) error {
		before, err := s.Settings(ctx)
		if err != nil {
			return err
		}
		r, err := store.New(s.db.Conn(ctx)).UpdateDriverSettings(ctx, store.UpdateDriverSettingsParams{
			VtcMode: in.VTCMode, DeliveryVehicleCheck: in.DeliveryVehicleCheck, PartnerGuide: in.PartnerGuide, UpdatedBy: &adminID,
		})
		if err != nil {
			return fmt.Errorf("réglages partenaires : %w", err)
		}
		out = DriverSettings{VTCMode: r.VtcMode, DeliveryVehicleCheck: r.DeliveryVehicleCheck, PartnerGuide: r.PartnerGuide, UpdatedAt: r.UpdatedAt}
		return s.admin.Record(ctx, admin.AuditEntry{
			AdminID: &adminID, Action: "driver.settings", TargetType: "driver_settings", TargetID: "driver_settings",
			Before: map[string]any{"vtc_mode": before.VTCMode, "delivery_vehicle_check": before.DeliveryVehicleCheck},
			After:  map[string]any{"vtc_mode": out.VTCMode, "delivery_vehicle_check": out.DeliveryVehicleCheck},
		})
	})
	return out, err
}

// Options liste les activités proposées à l'inscription : le taxi VTC n'apparaît pas tant qu'il
// est masqué dans le back-office.
func (s *Service) Options(ctx context.Context) ([]ActivityOption, error) {
	st, err := s.Settings(ctx)
	if err != nil {
		return nil, err
	}
	vehicles := func(activity string, types ...string) []VehicleOption {
		out := make([]VehicleOption, len(types))
		for i, t := range types {
			out[i] = VehicleOption{Type: t, RequiredDocuments: DocumentsFor(activity, t)}
		}
		return out
	}
	out := []ActivityOption{{Activity: ActivityDelivery, Label: activityLabels[ActivityDelivery], Mode: VTCOpen, Vehicles: vehicles(ActivityDelivery, "motorbike", "bicycle", "car")}}
	if st.VTCMode != VTCHidden {
		out = append(out, ActivityOption{Activity: ActivityVTC, Label: activityLabels[ActivityVTC], Mode: st.VTCMode, Vehicles: vehicles(ActivityVTC, "car")})
	}
	return out, nil
}

// WorkZones liste les zones de travail proposées au dossier (spec 033) ; vide si le module carte
// n'est pas branché.
func (s *Service) WorkZones(ctx context.Context) ([]WorkZone, error) {
	if s.zones == nil {
		return []WorkZone{}, nil
	}
	z, err := s.zones.WorkZones(ctx)
	if err != nil {
		return nil, fmt.Errorf("zones de travail : %w", err)
	}
	return z, nil
}

// Guide retourne le guide du partenaire, rédigé dans le back-office.
func (s *Service) Guide(ctx context.Context) (string, error) {
	st, err := s.Settings(ctx)
	return st.PartnerGuide, err
}

// --- Inscription du partenaire --------------------------------------------------------------

// SaveActivity déclare une activité et son véhicule, ou les corrige tant que le dossier n'est pas
// validé. Après un refus, la déclaration ouvre une nouvelle demande (brouillon).
func (s *Service) SaveActivity(ctx context.Context, userID uuid.UUID, activity string, in ActivityInput) (Driver, error) {
	if err := checkActivity(activity); err != nil {
		return Driver{}, err
	}
	in.Brand, in.Model = validate.Clean(in.Brand), validate.Clean(in.Model)
	in.Color, in.Plate = validate.Clean(in.Color), strings.ToUpper(validate.Clean(in.Plate))
	v := validate.New()
	if activity == ActivityVTC {
		if in.VehicleType == "" {
			in.VehicleType = "car"
		}
		v.Check(in.VehicleType == "car", "vehicle_type", "Le taxi VTC se fait en voiture.")
		v.Text("brand", in.Brand, 2, 60)
		v.Text("model", in.Model, 1, 60)
		v.Text("plate", in.Plate, 2, 20)
		v.Check(in.Seats != nil && *in.Seats >= 1 && *in.Seats <= 8, "seats", "Nombre de places attendu : de 1 à 8.")
	} else {
		v.Check(in.VehicleType == "bicycle" || in.VehicleType == "motorbike" || in.VehicleType == "car", "vehicle_type", "Véhicule attendu : bicycle, motorbike ou car.")
		if in.VehicleType != "bicycle" {
			v.Text("plate", in.Plate, 2, 20)
		}
		in.Seats = nil
	}
	v.Text("brand", in.Brand, 0, 60)
	v.Text("model", in.Model, 0, 60)
	v.Text("color", in.Color, 0, 40)
	v.Text("plate", in.Plate, 0, 20)
	if err := v.Err(); err != nil {
		return Driver{}, err
	}
	if activity == ActivityVTC {
		st, err := s.Settings(ctx)
		if err != nil {
			return Driver{}, err
		}
		if st.VTCMode == VTCHidden {
			return Driver{}, apperr.Conflict("vtc_unavailable", "Le taxi VTC n'est pas encore ouvert aux inscriptions.")
		}
	}
	q := store.New(s.db.Conn(ctx))
	if in.WorkZoneID != nil {
		ok, err := q.ActiveZoneExists(ctx, *in.WorkZoneID)
		if err != nil {
			return Driver{}, fmt.Errorf("zone de travail : %w", err)
		}
		if !ok {
			return Driver{}, apperr.Validation(map[string]string{"work_zone_id": "Zone inconnue."})
		}
	}
	u, err := s.users.Get(ctx, userID)
	if err != nil {
		return Driver{}, err
	}
	if !u.ProfileComplete {
		return Driver{}, apperr.Conflict("profile_incomplete", "Complétez votre profil (prénom, téléphone, consentement) avant de vous inscrire.")
	}
	err = s.db.InTx(ctx, func(ctx context.Context) error {
		q := store.New(s.db.Conn(ctx))
		if _, err := q.GetDriver(ctx, userID); database.IsNoRows(err) {
			if err := q.CreateDriverDraft(ctx, store.CreateDriverDraftParams{UserID: userID, VehicleType: in.VehicleType, VehiclePlate: in.Plate}); err != nil {
				return fmt.Errorf("création du partenaire : %w", err)
			}
		} else if err != nil {
			return fmt.Errorf("lecture du partenaire : %w", err)
		}
		cur, err := q.LockActivity(ctx, store.LockActivityParams{UserID: userID, Activity: activity})
		switch {
		case database.IsNoRows(err):
			err = q.InsertActivity(ctx, store.InsertActivityParams{
				UserID: userID, Activity: activity, VehicleType: in.VehicleType, VehicleBrand: in.Brand, VehicleModel: in.Model,
				VehicleColor: in.Color, VehiclePlate: in.Plate, VehicleSeats: in.Seats, WorkZoneID: in.WorkZoneID,
			})
		case err != nil:
			return fmt.Errorf("lecture de l'activité : %w", err)
		case cur.Status == ReviewApproved:
			return apperr.Conflict("application_locked", "Activité déjà validée : contactez l'équipe ivia pour modifier votre véhicule.")
		default:
			status := cur.Status
			if status == ReviewRejected {
				status = StatusDraft
			}
			err = q.UpdateActivityVehicle(ctx, store.UpdateActivityVehicleParams{
				UserID: userID, Activity: activity, VehicleType: in.VehicleType, VehicleBrand: in.Brand, VehicleModel: in.Model,
				VehicleColor: in.Color, VehiclePlate: in.Plate, VehicleSeats: in.Seats, WorkZoneID: in.WorkZoneID, Status: status,
			})
		}
		if err != nil {
			return fmt.Errorf("enregistrement de l'activité : %w", err)
		}
		if activity == ActivityDelivery {
			return q.MirrorDelivery(ctx, userID)
		}
		return nil
	})
	if err != nil {
		return Driver{}, err
	}
	return s.getDriver(ctx, userID, false)
}

// SetPayout enregistre le compte de versement Mobile Money. Après la validation d'une activité,
// seul l'équipe ivia peut le changer.
func (s *Service) SetPayout(ctx context.Context, userID uuid.UUID, in PayoutInput) (Driver, error) {
	in.Holder = validate.Clean(in.Holder)
	v := validate.New()
	v.Check(in.Operator == "flooz" || in.Operator == "tmoney", "operator", "Choisissez Moov Money (Flooz) ou Yas (T-Money).")
	v.Check(payoutPhone.MatchString(in.Phone), "phone", "Numéro attendu : +228 suivi de 8 chiffres.")
	v.Text("holder", in.Holder, 3, 100)
	if err := v.Err(); err != nil {
		return Driver{}, err
	}
	q := store.New(s.db.Conn(ctx))
	if _, err := q.GetDriver(ctx, userID); err != nil {
		if database.IsNoRows(err) {
			return Driver{}, apperr.Conflict("no_application", "Choisissez d'abord votre activité.")
		}
		return Driver{}, fmt.Errorf("lecture du partenaire : %w", err)
	}
	n, err := q.SetDriverPayout(ctx, store.SetDriverPayoutParams{UserID: userID, Operator: &in.Operator, Phone: &in.Phone, Holder: in.Holder})
	if err != nil {
		return Driver{}, fmt.Errorf("compte de versement : %w", err)
	}
	if n == 0 {
		return Driver{}, apperr.Conflict("payout_locked", "Compte partenaire validé : contactez l'équipe ivia pour changer de compte de versement.")
	}
	return s.getDriver(ctx, userID, false)
}

// Submit enregistre le dossier (statut en attente) et prévient le back-office. Exige les pièces
// de l'activité et du véhicule, le compte de versement et, pour la livraison, la zone de travail.
func (s *Service) Submit(ctx context.Context, userID uuid.UUID, activity string) (Driver, error) {
	if err := checkActivity(activity); err != nil {
		return Driver{}, err
	}
	err := s.db.InTx(ctx, func(ctx context.Context) error {
		q := store.New(s.db.Conn(ctx))
		cur, err := q.LockActivity(ctx, store.LockActivityParams{UserID: userID, Activity: activity})
		if database.IsNoRows(err) {
			return apperr.Conflict("no_application", "Choisissez d'abord votre activité.")
		}
		if err != nil {
			return fmt.Errorf("lecture de l'activité : %w", err)
		}
		switch cur.Status {
		case StatusDraft, StatusChangesRequested:
		case ReviewPending:
			return apperr.Conflict("already_submitted", "Votre dossier est déjà en cours de vérification.")
		default:
			return apperr.Conflict("invalid_driver_transition", "Ce dossier ne peut plus être envoyé.")
		}
		d, err := s.getDriver(ctx, userID, false)
		if err != nil {
			return err
		}
		var problems []string
		if missing := missingKinds(d.Documents, DocumentsFor(activity, cur.VehicleType)); len(missing) > 0 {
			problems = append(problems, labels(missing))
		}
		if d.Payout == nil {
			problems = append(problems, "compte de versement")
		}
		if activity == ActivityDelivery && cur.WorkZoneID == nil {
			// Sans zone desservie saisie au back-office, il n'y a rien à choisir : pas de blocage.
			zones, err := s.WorkZones(ctx)
			if err != nil {
				return err
			}
			if len(zones) > 0 {
				problems = append(problems, "zone de travail")
			}
		}
		if len(problems) > 0 {
			return apperr.Conflict("dossier_incomplete", "Dossier incomplet : "+strings.Join(problems, ", ")+" manquant(s).")
		}
		if _, err := q.SetActivityStatus(ctx, store.SetActivityStatusParams{
			UserID: userID, Activity: activity, Status: ReviewPending, FromStatuses: []string{StatusDraft, StatusChangesRequested},
		}); err != nil {
			return fmt.Errorf("envoi du dossier : %w", err)
		}
		if activity == ActivityDelivery {
			if err := q.MirrorDelivery(ctx, userID); err != nil {
				return fmt.Errorf("état de la livraison : %w", err)
			}
		}
		return s.notify.NotifyAdmins(ctx, "driver_application", "Nouveau dossier partenaire à vérifier",
			"Un partenaire ("+activityLabels[activity]+") attend la vérification de son dossier.",
			map[string]string{"driver_id": userID.String(), "activity": activity})
	})
	if err != nil {
		return Driver{}, err
	}
	return s.getDriver(ctx, userID, false)
}

// --- Back-office ----------------------------------------------------------------------------

// VehicleCheck enregistre le contrôle du véhicule sur place (journalisé).
func (s *Service) VehicleCheck(ctx context.Context, adminID, userID uuid.UUID, activity string, passed bool, note string) (AdminDriver, error) {
	if err := checkActivity(activity); err != nil {
		return AdminDriver{}, err
	}
	note = validate.Clean(note)
	v := validate.New()
	v.Text("note", note, 0, 500)
	v.Check(passed || note != "", "note", "Indiquez ce qui ne va pas (le partenaire le verra).")
	if err := v.Err(); err != nil {
		return AdminDriver{}, err
	}
	err := s.db.InTx(ctx, func(ctx context.Context) error {
		n, err := store.New(s.db.Conn(ctx)).SetVehicleCheck(ctx, store.SetVehicleCheckParams{
			UserID: userID, Activity: activity, AdminID: &adminID, Passed: &passed, Note: note,
		})
		if err != nil {
			return fmt.Errorf("contrôle du véhicule : %w", err)
		}
		if n == 0 {
			return apperr.Conflict("invalid_driver_transition", "Contrôle possible seulement sur un dossier en attente de vérification.")
		}
		return s.admin.Record(ctx, admin.AuditEntry{
			AdminID: &adminID, Action: "driver.vehicle_check", TargetType: "driver", TargetID: userID.String(),
			After: map[string]any{"activity": activity, "passed": passed}, Reason: note,
		})
	})
	if err != nil {
		return AdminDriver{}, err
	}
	return s.AdminGet(ctx, userID, false)
}

// ReviewActivity applique la décision du back-office sur une activité : approve, request_changes
// ou reject (journalisée, partenaire notifié avec le motif). La validation active le module.
func (s *Service) ReviewActivity(ctx context.Context, adminID, userID uuid.UUID, activity, decision, reason string) (AdminDriver, error) {
	if err := checkActivity(activity); err != nil {
		return AdminDriver{}, err
	}
	reason = validate.Clean(reason)
	if (decision == "reject" || decision == "request_changes") && reason == "" {
		return AdminDriver{}, apperr.Validation(map[string]string{"reason": "Indiquez le motif (il sera communiqué au partenaire)."})
	}
	label := activityLabels[activity]
	err := s.db.InTx(ctx, func(ctx context.Context) error {
		q := store.New(s.db.Conn(ctx))
		cur, err := q.LockActivity(ctx, store.LockActivityParams{UserID: userID, Activity: activity})
		if database.IsNoRows(err) {
			return apperr.NotFound("activity_not_found", "Ce partenaire n'a pas déclaré cette activité.")
		}
		if err != nil {
			return fmt.Errorf("lecture de l'activité : %w", err)
		}
		var to, kind, title, body string
		from := []string{ReviewPending}
		switch decision {
		case "approve":
			if err := s.readyForApproval(ctx, userID, activity, cur); err != nil {
				return err
			}
			to, kind, title = ReviewApproved, "driver_approve", "Compte partenaire validé"
			body = "Votre activité " + label + " est activée."
			if activity == ActivityDelivery {
				title, body = "Compte livreur validé", "Vous pouvez maintenant passer en ligne et recevoir des missions."
			}
		case "request_changes":
			to, kind, title, body = StatusChangesRequested, "driver_request_changes", "Compléments demandés", "Motif : "+reason
		case "reject":
			to, kind, title, body = ReviewRejected, "driver_reject", "Dossier refusé", "Motif : "+reason
			from = append(from, StatusChangesRequested)
		default:
			return fmt.Errorf("décision inconnue : %s", decision)
		}
		n, err := q.SetActivityStatus(ctx, store.SetActivityStatusParams{
			UserID: userID, Activity: activity, Status: to, Note: reason, Reviewed: true, ReviewedBy: &adminID, FromStatuses: from,
		})
		if err != nil {
			return fmt.Errorf("décision sur le dossier : %w", err)
		}
		if n == 0 {
			return apperr.Conflict("invalid_driver_transition", "Action impossible pour ce dossier dans son état actuel.")
		}
		if activity == ActivityDelivery {
			if err := q.MirrorDelivery(ctx, userID); err != nil {
				return fmt.Errorf("état de la livraison : %w", err)
			}
		}
		if decision == "approve" {
			if err := s.users.GrantRole(ctx, userID, identity.RoleDriver, &adminID); err != nil {
				return err
			}
		}
		if err := s.admin.Record(ctx, admin.AuditEntry{
			AdminID: &adminID, Action: "driver." + decision, TargetType: "driver", TargetID: userID.String(),
			Before: map[string]any{"activity": activity, "status": cur.Status}, After: map[string]any{"activity": activity, "status": to}, Reason: reason,
		}); err != nil {
			return err
		}
		return s.notify.Notify(ctx, notifications.Message{
			UserID: userID, App: notifications.AppDriver, Kind: kind, Title: title, Body: body,
			Data: map[string]string{"activity": activity},
		})
	})
	if err != nil {
		return AdminDriver{}, err
	}
	return s.AdminGet(ctx, userID, false)
}

// readyForApproval vérifie pièces, compte de versement et contrôle du véhicule (toujours pour le
// VTC, selon le réglage pour la livraison). Un dossier de l'ancien parcours garde ses exigences.
func (s *Service) readyForApproval(ctx context.Context, userID uuid.UUID, activity string, cur store.LockActivityRow) error {
	d, err := s.getDriver(ctx, userID, false)
	if err != nil {
		return err
	}
	i := slices.IndexFunc(d.Activities, func(a Activity) bool { return a.Activity == activity })
	if i < 0 {
		return apperr.NotFound("activity_not_found", "Ce partenaire n'a pas déclaré cette activité.")
	}
	if missing := d.Activities[i].MissingDocuments; len(missing) > 0 {
		return apperr.Conflict("driver_documents_missing", "Dossier incomplet : "+labels(missing)+" manquant(s).")
	}
	if cur.Legacy {
		return nil
	}
	if d.Payout == nil {
		return apperr.Conflict("payout_missing", "Le partenaire n'a pas renseigné son compte de versement.")
	}
	st, err := s.Settings(ctx)
	if err != nil {
		return err
	}
	if (activity == ActivityVTC || st.DeliveryVehicleCheck) && (cur.VehicleCheckPassed == nil || !*cur.VehicleCheckPassed) {
		return apperr.Conflict("vehicle_check_required", "Contrôlez d'abord le véhicule sur place.")
	}
	return nil
}
