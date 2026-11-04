package pharmacy

import (
	"context"
	"fmt"
	"slices"
	"time"

	"github.com/google/uuid"

	"ivia/backend/internal/geo"
	"ivia/backend/internal/notifications"
	"ivia/backend/internal/pharmacy/store"
	"ivia/backend/internal/platform/apperr"
	"ivia/backend/internal/platform/database"
	"ivia/backend/internal/platform/jobs"
	"ivia/backend/internal/platform/validate"
	"ivia/backend/internal/uploads"
)

// AlertInput lance une alerte. Position : address_id (adresse enregistrée) ou location.
type AlertInput struct {
	Kind         string     `json:"kind"`
	MedicineName string     `json:"medicine_name"`
	Quantity     int32      `json:"quantity"`
	Note         string     `json:"note"`
	PhotoKey     *string    `json:"photo_key"`
	AddressID    *uuid.UUID `json:"address_id"`
	Location     *geo.Point `json:"location"`
}

// Alert est l'alerte vue par le client.
type Alert struct {
	ID           uuid.UUID `json:"id"`
	Kind         string    `json:"kind"`
	MedicineName string    `json:"medicine_name"`
	Quantity     int32     `json:"quantity"`
	Note         string    `json:"note"`
	HasPhoto     bool      `json:"has_photo"`
	Status       string    `json:"status"`
	Location     geo.Point `json:"location"`
	RadiusM      int32     `json:"radius_m"`
	SearchEndsAt time.Time `json:"search_ends_at"`
	// Unlocked : identités des pharmacies visibles (déblocage payé).
	Unlocked           bool            `json:"unlocked"`
	UnlockFeeXOF       int64           `json:"unlock_fee_xof"`
	PharmaciesNotified int64           `json:"pharmacies_notified"`
	Responses          []AlertResponse `json:"responses"`
	// ReservationID : réservation en cours (ou la dernière), s'il y en a une.
	ReservationID *uuid.UUID `json:"reservation_id"`
	CreatedAt     time.Time  `json:"created_at"`
}

// AlertResponse est une réponse de pharmacie, classée par distance. Avant déblocage, la
// pharmacie est masquée (pharmacy nul, libellé « Pharmacie 1 », note cachée).
type AlertResponse struct {
	ID                   uuid.UUID `json:"id"`
	Rank                 int       `json:"rank"`
	Label                string    `json:"label"`
	DistanceM            int32     `json:"distance_m"`
	ProductName          string    `json:"product_name"`
	UnitPriceXOF         int64     `json:"unit_price_xof"`
	QuantityAvailable    int32     `json:"quantity_available"`
	PrescriptionRequired bool      `json:"prescription_required"`
	// DeliveryAllowed : livraison ivia possible (jamais sur ordonnance).
	DeliveryAllowed bool             `json:"delivery_allowed"`
	Note            string           `json:"note"`
	Status          string           `json:"status"`
	Pharmacy        *PharmacyContact `json:"pharmacy"`
	CreatedAt       time.Time        `json:"created_at"`
}

// PharmacyContact est l'identité d'une pharmacie, donnée au client après déblocage.
type PharmacyContact struct {
	ID          uuid.UUID `json:"id"`
	Name        string    `json:"name"`
	Phone       string    `json:"phone"`
	AddressText string    `json:"address_text"`
	Location    geo.Point `json:"location"`
	OnDuty      bool      `json:"on_duty"`
}

// InboxItem est une alerte reçue par une pharmacie : jamais d'identité ni de position du client.
type InboxItem struct {
	AlertID      uuid.UUID `json:"alert_id"`
	Kind         string    `json:"kind"`
	MedicineName string    `json:"medicine_name"`
	Quantity     int32     `json:"quantity"`
	Note         string    `json:"note"`
	// PhotoURL : lien de 10 minutes vers la photo (ordonnance ou boîte), tant que l'alerte est ouverte.
	PhotoURL     string       `json:"photo_url,omitempty"`
	HasPhoto     bool         `json:"has_photo"`
	DistanceM    int32        `json:"distance_m"`
	Status       string       `json:"status"`
	AlertStatus  string       `json:"alert_status"`
	SearchEndsAt time.Time    `json:"search_ends_at"`
	MyResponse   *OwnResponse `json:"my_response"`
	ReceivedAt   time.Time    `json:"received_at"`
}

// OwnResponse est la réponse de la pharmacie à une alerte.
type OwnResponse struct {
	ID                   uuid.UUID `json:"id"`
	ProductName          string    `json:"product_name"`
	UnitPriceXOF         int64     `json:"unit_price_xof"`
	QuantityAvailable    int32     `json:"quantity_available"`
	PrescriptionRequired bool      `json:"prescription_required"`
	Note                 string    `json:"note"`
	Status               string    `json:"status"`
}

// ResponseInput : la pharmacie a le produit (ou un équivalent qu'elle nomme).
type ResponseInput struct {
	ProductName          string `json:"product_name"`
	UnitPriceXOF         int64  `json:"unit_price_xof"`
	QuantityAvailable    int32  `json:"quantity_available"`
	PrescriptionRequired bool   `json:"prescription_required"`
	Note                 string `json:"note"`
}

var openAlert = []string{AlertSearching, AlertAnswered, AlertUnlocked}

var errAlertNotFound = apperr.NotFound("alert_not_found", "Alerte introuvable.")

func (s *Service) attachedPhotos(ctx context.Context, keys []string) (map[string]bool, error) {
	// Une photo rattachée est encore référencée par une alerte (photo_key non nul).
	out := map[string]bool{}
	for _, k := range keys {
		var exists bool
		if err := s.db.Conn(ctx).QueryRow(ctx, "SELECT EXISTS (SELECT 1 FROM pharmacy_alerts WHERE photo_key = $1)", k).Scan(&exists); err != nil {
			return nil, fmt.Errorf("photos rattachées : %w", err)
		}
		out[k] = exists
	}
	return out, nil
}

// CreateAlert lance une alerte et la diffuse aux pharmacies autour du client.
func (s *Service) CreateAlert(ctx context.Context, buyerID uuid.UUID, in AlertInput) (Alert, error) {
	settings, err := s.Settings(ctx)
	if err != nil {
		return Alert{}, err
	}
	if !settings.Enabled {
		return Alert{}, apperr.Unavailable("pharmacy_disabled", "L'alerte médicament est momentanément indisponible.")
	}
	in.MedicineName = validate.Clean(in.MedicineName)
	in.Note = validate.Clean(in.Note)
	if in.Quantity == 0 {
		in.Quantity = 1
	}
	v := validate.New()
	v.Check(slices.Contains([]string{KindPrescription, KindBoxPhoto, KindName}, in.Kind), "kind", "Valeur attendue : prescription, box_photo ou name.")
	if in.Kind == KindName {
		v.Text("medicine_name", in.MedicineName, 2, 120)
	} else {
		v.Check(len(in.MedicineName) <= 120, "medicine_name", "120 caractères au plus.")
		v.Check(in.PhotoKey != nil && *in.PhotoKey != "", "photo_key", "Photo obligatoire (POST /v1/uploads, usage pharmacy_alert_photo).")
	}
	v.Check(in.Quantity >= 1 && in.Quantity <= 20, "quantity", "Entre 1 et 20.")
	v.Check(len(in.Note) <= 300, "note", "300 caractères au plus.")
	v.Check((in.AddressID == nil) != (in.Location == nil), "location", "Indiquez une adresse enregistrée ou une position.")
	if in.Location != nil {
		v.Coordinates("location.", in.Location.Lat, in.Location.Lng)
	}
	if err := v.Err(); err != nil {
		return Alert{}, err
	}
	var photo *string
	if in.Kind != KindName {
		if err := s.uploads.Check(ctx, uploads.PharmacyAlertPhoto, buyerID, *in.PhotoKey, "photo_key"); err != nil {
			return Alert{}, err
		}
		photo = in.PhotoKey
	}
	point := geo.Point{}
	if in.AddressID != nil {
		a, err := s.users.GetAddress(ctx, buyerID, *in.AddressID)
		if err != nil {
			return Alert{}, err
		}
		point = a.Location
	} else {
		point = *in.Location
	}

	var id uuid.UUID
	err = s.db.InTx(ctx, func(ctx context.Context) error {
		q := s.q(ctx)
		ends := time.Now().Add(time.Duration(settings.ResponseWindowMinutes) * time.Minute)
		id, err = q.CreateAlert(ctx, store.CreateAlertParams{
			BuyerID: buyerID, Kind: in.Kind, MedicineName: in.MedicineName, Quantity: in.Quantity, Note: in.Note,
			PhotoKey: photo, Lat: point.Lat, Lng: point.Lng, RadiusM: settings.SearchRadiusM, SearchEndsAt: ends,
		})
		if err != nil {
			return fmt.Errorf("création de l'alerte : %w", err)
		}
		n, err := s.broadcast(ctx, id, point, settings.SearchRadiusM)
		if err != nil {
			return err
		}
		if n == 0 && settings.MaxRadiusM > settings.SearchRadiusM {
			// Personne dans le rayon : élargi tout de suite.
			if err := q.WidenAlert(ctx, store.WidenAlertParams{ID: id, RadiusM: settings.MaxRadiusM}); err != nil {
				return fmt.Errorf("élargissement : %w", err)
			}
			if _, err := s.broadcast(ctx, id, point, settings.MaxRadiusM); err != nil {
				return err
			}
		} else if err := s.jobs.Enqueue(ctx, WidenArgs{AlertID: id}, jobs.At(time.Now().Add(time.Duration(settings.WidenAfterMinutes)*time.Minute))); err != nil {
			return err
		}
		return s.jobs.Enqueue(ctx, CloseSearchArgs{AlertID: id}, jobs.At(ends))
	})
	if err != nil {
		return Alert{}, err
	}
	return s.GetAlert(ctx, buyerID, id)
}

// broadcast sollicite les pharmacies joignables du rayon qui ne l'ont pas encore été.
func (s *Service) broadcast(ctx context.Context, alertID uuid.UUID, p geo.Point, radius int32) (int, error) {
	q := s.q(ctx)
	rows, err := q.FindReachablePharmacies(ctx, store.FindReachablePharmaciesParams{
		AlertID: alertID, Lat: p.Lat, Lng: p.Lng, RadiusM: float64(radius),
	})
	if err != nil {
		return 0, fmt.Errorf("pharmacies du rayon : %w", err)
	}
	for _, r := range rows {
		dist := int32(r.DistanceM + 0.5)
		n, err := q.InsertTarget(ctx, store.InsertTargetParams{AlertID: alertID, PharmacyID: r.ID, DistanceM: dist})
		if err != nil {
			return 0, fmt.Errorf("sollicitation de la pharmacie : %w", err)
		}
		if n == 0 {
			continue
		}
		if err := s.notify.Notify(ctx, notifications.Message{
			UserID: r.OwnerID, App: notifications.AppPharmacy, Kind: "pharmacy_alert",
			Title: "Alerte médicament", Body: fmt.Sprintf("Un client à %s cherche un médicament. Répondez vite !", formatDistance(dist)),
			Data: map[string]string{"alert_id": alertID.String()},
		}); err != nil {
			return 0, err
		}
	}
	return len(rows), nil
}

func formatDistance(m int32) string {
	if m < 1000 {
		return fmt.Sprintf("%d m", m)
	}
	return fmt.Sprintf("%.1f km", float64(m)/1000)
}

// widen élargit la recherche si les réponses manquent (tâche planifiée).
func (s *Service) widen(ctx context.Context, alertID uuid.UUID) error {
	settings, err := s.Settings(ctx)
	if err != nil {
		return err
	}
	return s.db.InTx(ctx, func(ctx context.Context) error {
		q := s.q(ctx)
		cur, err := q.LockAlert(ctx, alertID)
		if database.IsNoRows(err) {
			return nil
		}
		if err != nil {
			return fmt.Errorf("verrou de l'alerte : %w", err)
		}
		if cur.Status != AlertSearching {
			return nil
		}
		a, err := q.GetAlert(ctx, alertID)
		if err != nil {
			return fmt.Errorf("lecture de l'alerte : %w", err)
		}
		if a.WidenedAt != nil || a.RadiusM >= settings.MaxRadiusM {
			return nil
		}
		n, err := q.CountActiveResponses(ctx, alertID)
		if err != nil {
			return fmt.Errorf("décompte des réponses : %w", err)
		}
		if n >= int64(settings.TargetResponses) {
			return nil
		}
		if err := q.WidenAlert(ctx, store.WidenAlertParams{ID: alertID, RadiusM: settings.MaxRadiusM}); err != nil {
			return fmt.Errorf("élargissement : %w", err)
		}
		_, err = s.broadcast(ctx, alertID, geo.Point{Lat: a.Lat, Lng: a.Lng}, settings.MaxRadiusM)
		return err
	})
}

// closeSearch termine la recherche : réponses reçues ou non, sollicitations restantes expirées.
// Appelée à la fin de la fenêtre (tâche) ou dès que le nombre de réponses visé est atteint.
func (s *Service) closeSearch(ctx context.Context, alertID uuid.UUID) error {
	return s.db.InTx(ctx, func(ctx context.Context) error {
		q := s.q(ctx)
		cur, err := q.LockAlert(ctx, alertID)
		if database.IsNoRows(err) {
			return nil
		}
		if err != nil {
			return fmt.Errorf("verrou de l'alerte : %w", err)
		}
		if cur.Status != AlertSearching {
			return nil
		}
		n, err := q.CountActiveResponses(ctx, alertID)
		if err != nil {
			return fmt.Errorf("décompte des réponses : %w", err)
		}
		next, title, body := AlertNoResponse, "Aucune pharmacie n'a répondu",
			"Aucune pharmacie proche n'a ce médicament pour le moment. Réessayez plus tard ou modifiez votre recherche."
		if n > 0 {
			next, title, body = AlertAnswered, "Des pharmacies ont votre médicament",
				fmt.Sprintf("%d pharmacie(s) ont répondu. Consultez les réponses.", n)
			if cur.UnlockedAt != nil {
				next = AlertUnlocked
			}
		}
		if _, err := q.SetAlertStatus(ctx, store.SetAlertStatusParams{ID: alertID, NewStatus: next, FromStatuses: []string{AlertSearching}}); err != nil {
			return fmt.Errorf("fin de la recherche : %w", err)
		}
		if err := q.ExpirePendingTargets(ctx, alertID); err != nil {
			return fmt.Errorf("sollicitations expirées : %w", err)
		}
		a, err := q.GetAlert(ctx, alertID)
		if err != nil {
			return fmt.Errorf("lecture de l'alerte : %w", err)
		}
		return s.notify.Notify(ctx, notifications.Message{
			UserID: a.BuyerID, App: notifications.AppBuyer, Kind: "pharmacy_alert_closed", Title: title, Body: body,
			Data: map[string]string{"alert_id": alertID.String()},
		})
	})
}

// GetAlert retourne une alerte du client avec ses réponses classées.
func (s *Service) GetAlert(ctx context.Context, buyerID, id uuid.UUID) (Alert, error) {
	q := s.q(ctx)
	a, err := q.GetAlert(ctx, id)
	if database.IsNoRows(err) || (err == nil && a.BuyerID != buyerID) {
		return Alert{}, errAlertNotFound
	}
	if err != nil {
		return Alert{}, fmt.Errorf("lecture de l'alerte : %w", err)
	}
	return s.alertView(ctx, a)
}

func (s *Service) alertView(ctx context.Context, a store.GetAlertRow) (Alert, error) {
	q := s.q(ctx)
	settings, err := s.Settings(ctx)
	if err != nil {
		return Alert{}, err
	}
	notified, err := q.CountTargets(ctx, a.ID)
	if err != nil {
		return Alert{}, fmt.Errorf("pharmacies sollicitées : %w", err)
	}
	rows, err := q.ListResponses(ctx, a.ID)
	if err != nil {
		return Alert{}, fmt.Errorf("réponses : %w", err)
	}
	unlocked := a.UnlockedAt != nil
	out := Alert{
		ID: a.ID, Kind: a.Kind, MedicineName: a.MedicineName, Quantity: a.Quantity, Note: a.Note,
		HasPhoto: a.PhotoKey != nil, Status: a.Status, Location: geo.Point{Lat: a.Lat, Lng: a.Lng}, RadiusM: a.RadiusM,
		SearchEndsAt: a.SearchEndsAt, Unlocked: unlocked, UnlockFeeXOF: settings.UnlockFeeXOF, PharmaciesNotified: notified,
		Responses: make([]AlertResponse, 0, len(rows)), CreatedAt: a.CreatedAt,
	}
	for i, r := range rows {
		resp := AlertResponse{
			ID: r.ID, Rank: i + 1, Label: fmt.Sprintf("Pharmacie %d", i+1), DistanceM: r.DistanceM,
			ProductName: r.ProductName, UnitPriceXOF: r.UnitPriceXof, QuantityAvailable: r.QuantityAvailable,
			PrescriptionRequired: r.PrescriptionRequired, DeliveryAllowed: a.Kind != KindPrescription && !r.PrescriptionRequired,
			Status: r.Status, CreatedAt: r.CreatedAt,
		}
		if unlocked {
			resp.Label = r.PharmacyName
			resp.Note = r.Note
			resp.Pharmacy = &PharmacyContact{
				ID: r.PharmacyID, Name: r.PharmacyName, Phone: r.PharmacyPhone, AddressText: r.PharmacyAddress,
				Location: geo.Point{Lat: r.PharmacyLat, Lng: r.PharmacyLng}, OnDuty: r.PharmacyOnDuty,
			}
		}
		out.Responses = append(out.Responses, resp)
	}
	if rid, err := q.LatestReservationForAlert(ctx, a.ID); err == nil {
		out.ReservationID = &rid
	} else if !database.IsNoRows(err) {
		return Alert{}, fmt.Errorf("réservation de l'alerte : %w", err)
	}
	return out, nil
}

// ListAlerts retourne les alertes du client, les plus récentes d'abord.
func (s *Service) ListAlerts(ctx context.Context, buyerID uuid.UUID, limit, offset int32) ([]Alert, error) {
	ids, err := s.q(ctx).ListBuyerAlertIDs(ctx, store.ListBuyerAlertIDsParams{BuyerID: buyerID, Lim: limit, Off: offset})
	if err != nil {
		return nil, fmt.Errorf("liste des alertes : %w", err)
	}
	out := make([]Alert, 0, len(ids))
	for _, id := range ids {
		a, err := s.GetAlert(ctx, buyerID, id)
		if err != nil {
			return nil, err
		}
		out = append(out, a)
	}
	return out, nil
}

// CancelAlert annule l'alerte du client. Une réservation non payée est annulée avec elle ; une
// livraison payée doit d'abord être annulée (remboursement).
func (s *Service) CancelAlert(ctx context.Context, buyerID, id uuid.UUID) (Alert, error) {
	if _, err := s.GetAlert(ctx, buyerID, id); err != nil {
		return Alert{}, err
	}
	err := s.db.InTx(ctx, func(ctx context.Context) error {
		q := s.q(ctx)
		cur, err := q.LockAlert(ctx, id)
		if err != nil {
			return fmt.Errorf("verrou de l'alerte : %w", err)
		}
		if !slices.Contains([]string{AlertSearching, AlertAnswered, AlertNoResponse, AlertUnlocked}, cur.Status) {
			return apperr.Conflict("alert_closed", "Cette alerte est déjà terminée.")
		}
		if rid, err := q.ActiveReservationForAlert(ctx, id); err == nil {
			r, err := q.GetReservation(ctx, rid)
			if err != nil {
				return fmt.Errorf("lecture de la réservation : %w", err)
			}
			if r.Status != ResReserved && r.Status != ResAwaitingPayment {
				return apperr.Conflict("reservation_in_progress", "Une livraison payée est en cours : annulez-la d'abord.")
			}
			if err := s.endReservation(ctx, r, ResCancelled, "Alerte annulée par le client.", true); err != nil {
				return err
			}
		} else if !database.IsNoRows(err) {
			return fmt.Errorf("réservation en cours : %w", err)
		}
		if _, err := q.SetAlertStatus(ctx, store.SetAlertStatusParams{
			ID: id, NewStatus: AlertCancelled, FromStatuses: []string{AlertSearching, AlertAnswered, AlertNoResponse, AlertUnlocked},
		}); err != nil {
			return fmt.Errorf("annulation de l'alerte : %w", err)
		}
		return q.ExpirePendingTargets(ctx, id)
	})
	if err != nil {
		return Alert{}, err
	}
	return s.GetAlert(ctx, buyerID, id)
}

// --- Côté pharmacie -------------------------------------------------------------------------

func (s *Service) inboxItem(ctx context.Context, pharmacyID uuid.UUID, r store.InboxItemRow, withPhoto bool) (InboxItem, error) {
	it := InboxItem{
		AlertID: r.AlertID, Kind: r.Kind, MedicineName: r.MedicineName, Quantity: r.Quantity, Note: r.Note,
		HasPhoto: r.PhotoKey != nil, DistanceM: r.DistanceM, Status: r.TargetStatus, AlertStatus: r.AlertStatus,
		SearchEndsAt: r.SearchEndsAt, ReceivedAt: r.NotifiedAt,
	}
	if withPhoto && r.PhotoKey != nil && slices.Contains(openAlert, r.AlertStatus) && r.TargetStatus != "expired" && r.TargetStatus != "declined" {
		url, err := s.uploads.PrivateURL(ctx, *r.PhotoKey)
		if err != nil {
			return InboxItem{}, err
		}
		it.PhotoURL = url
	}
	resp, err := s.q(ctx).ResponseOf(ctx, store.ResponseOfParams{AlertID: r.AlertID, PharmacyID: pharmacyID})
	if err == nil {
		it.MyResponse = &OwnResponse{
			ID: resp.ID, ProductName: resp.ProductName, UnitPriceXOF: resp.UnitPriceXof, QuantityAvailable: resp.QuantityAvailable,
			PrescriptionRequired: resp.PrescriptionRequired, Note: resp.Note, Status: resp.Status,
		}
	} else if !database.IsNoRows(err) {
		return InboxItem{}, fmt.Errorf("réponse de la pharmacie : %w", err)
	}
	return it, nil
}

// Inbox liste les alertes reçues par la pharmacie (openOnly : celles auxquelles on peut répondre).
func (s *Service) Inbox(ctx context.Context, ownerID uuid.UUID, openOnly bool, limit, offset int32) ([]InboxItem, error) {
	ph, err := s.requireActivePharmacy(ctx, ownerID)
	if err != nil {
		return nil, err
	}
	rows, err := s.q(ctx).Inbox(ctx, store.InboxParams{PharmacyID: ph.ID, OpenOnly: openOnly, Lim: limit, Off: offset})
	if err != nil {
		return nil, fmt.Errorf("alertes reçues : %w", err)
	}
	out := make([]InboxItem, 0, len(rows))
	for _, r := range rows {
		it, err := s.inboxItem(ctx, ph.ID, store.InboxItemRow(r), false)
		if err != nil {
			return nil, err
		}
		out = append(out, it)
	}
	return out, nil
}

// InboxGet retourne une alerte reçue, avec le lien temporaire vers sa photo.
func (s *Service) InboxGet(ctx context.Context, ownerID, alertID uuid.UUID) (InboxItem, error) {
	ph, err := s.requireActivePharmacy(ctx, ownerID)
	if err != nil {
		return InboxItem{}, err
	}
	r, err := s.q(ctx).InboxItem(ctx, store.InboxItemParams{AlertID: alertID, PharmacyID: ph.ID})
	if database.IsNoRows(err) {
		return InboxItem{}, errAlertNotFound
	}
	if err != nil {
		return InboxItem{}, fmt.Errorf("alerte reçue : %w", err)
	}
	return s.inboxItem(ctx, ph.ID, r, true)
}

// Respond : la pharmacie a le produit. Une réponse peut être corrigée tant qu'aucune
// réservation n'est en cours dessus.
func (s *Service) Respond(ctx context.Context, ownerID, alertID uuid.UUID, in ResponseInput) (InboxItem, error) {
	ph, err := s.requireActivePharmacy(ctx, ownerID)
	if err != nil {
		return InboxItem{}, err
	}
	in.ProductName = validate.Clean(in.ProductName)
	in.Note = validate.Clean(in.Note)
	v := validate.New()
	v.Text("product_name", in.ProductName, 2, 120)
	v.Check(in.UnitPriceXOF >= 1 && in.UnitPriceXOF <= 10_000_000, "unit_price_xof", "Prix unitaire en FCFA attendu.")
	v.Check(in.QuantityAvailable >= 1 && in.QuantityAvailable <= 1000, "quantity_available", "Entre 1 et 1 000.")
	v.Check(len(in.Note) <= 300, "note", "300 caractères au plus.")
	if err := v.Err(); err != nil {
		return InboxItem{}, err
	}
	settings, err := s.Settings(ctx)
	if err != nil {
		return InboxItem{}, err
	}
	closeNow := false
	err = s.db.InTx(ctx, func(ctx context.Context) error {
		q := s.q(ctx)
		cur, err := q.LockAlert(ctx, alertID)
		if database.IsNoRows(err) {
			return errAlertNotFound
		}
		if err != nil {
			return fmt.Errorf("verrou de l'alerte : %w", err)
		}
		t, err := q.GetTarget(ctx, store.GetTargetParams{AlertID: alertID, PharmacyID: ph.ID})
		if database.IsNoRows(err) {
			return errAlertNotFound
		}
		if err != nil {
			return fmt.Errorf("sollicitation : %w", err)
		}
		if !slices.Contains(openAlert, cur.Status) || (t.Status != "pending" && t.Status != "responded") {
			return apperr.Conflict("alert_closed", "Cette alerte n'attend plus de réponse.")
		}
		if prev, err := q.ResponseOf(ctx, store.ResponseOfParams{AlertID: alertID, PharmacyID: ph.ID}); err == nil {
			if err := s.requireNoReservationOn(ctx, alertID, prev.ID); err != nil {
				return err
			}
		} else if !database.IsNoRows(err) {
			return fmt.Errorf("réponse précédente : %w", err)
		}
		if _, err := q.UpsertResponse(ctx, store.UpsertResponseParams{
			AlertID: alertID, PharmacyID: ph.ID, ProductName: in.ProductName, UnitPriceXof: in.UnitPriceXOF,
			QuantityAvailable: in.QuantityAvailable, PrescriptionRequired: in.PrescriptionRequired, Note: in.Note, DistanceM: t.DistanceM,
		}); err != nil {
			return fmt.Errorf("enregistrement de la réponse : %w", err)
		}
		if err := q.SetTargetStatus(ctx, store.SetTargetStatusParams{AlertID: alertID, PharmacyID: ph.ID, Status: "responded"}); err != nil {
			return fmt.Errorf("sollicitation : %w", err)
		}
		n, err := q.CountActiveResponses(ctx, alertID)
		if err != nil {
			return fmt.Errorf("décompte des réponses : %w", err)
		}
		closeNow = cur.Status == AlertSearching && n >= int64(settings.TargetResponses)
		if t.Status == "pending" && !closeNow && cur.Status == AlertSearching {
			a, err := q.GetAlert(ctx, alertID)
			if err != nil {
				return fmt.Errorf("lecture de l'alerte : %w", err)
			}
			return s.notify.Notify(ctx, notifications.Message{
				UserID: a.BuyerID, App: notifications.AppBuyer, Kind: "pharmacy_response",
				Title: "Une pharmacie a votre médicament", Body: fmt.Sprintf("Réponse à %s de vous.", formatDistance(t.DistanceM)),
				Data: map[string]string{"alert_id": alertID.String()},
			})
		}
		return nil
	})
	if err != nil {
		return InboxItem{}, err
	}
	if closeNow {
		if err := s.closeSearch(ctx, alertID); err != nil {
			return InboxItem{}, err
		}
	}
	return s.InboxGet(ctx, ownerID, alertID)
}

// Decline : la pharmacie n'a pas le produit (ou ne l'a plus : sa réponse est retirée).
func (s *Service) Decline(ctx context.Context, ownerID, alertID uuid.UUID) (InboxItem, error) {
	ph, err := s.requireActivePharmacy(ctx, ownerID)
	if err != nil {
		return InboxItem{}, err
	}
	err = s.db.InTx(ctx, func(ctx context.Context) error {
		q := s.q(ctx)
		if _, err := q.LockAlert(ctx, alertID); database.IsNoRows(err) {
			return errAlertNotFound
		} else if err != nil {
			return fmt.Errorf("verrou de l'alerte : %w", err)
		}
		t, err := q.GetTarget(ctx, store.GetTargetParams{AlertID: alertID, PharmacyID: ph.ID})
		if database.IsNoRows(err) {
			return errAlertNotFound
		}
		if err != nil {
			return fmt.Errorf("sollicitation : %w", err)
		}
		if t.Status == "expired" {
			return apperr.Conflict("alert_closed", "Cette alerte n'attend plus de réponse.")
		}
		if prev, err := q.ResponseOf(ctx, store.ResponseOfParams{AlertID: alertID, PharmacyID: ph.ID}); err == nil {
			if err := s.requireNoReservationOn(ctx, alertID, prev.ID); err != nil {
				return err
			}
			if err := q.WithdrawResponse(ctx, prev.ID); err != nil {
				return fmt.Errorf("retrait de la réponse : %w", err)
			}
		} else if !database.IsNoRows(err) {
			return fmt.Errorf("réponse précédente : %w", err)
		}
		return q.SetTargetStatus(ctx, store.SetTargetStatusParams{AlertID: alertID, PharmacyID: ph.ID, Status: "declined"})
	})
	if err != nil {
		return InboxItem{}, err
	}
	return s.InboxGet(ctx, ownerID, alertID)
}

// requireNoReservationOn refuse de modifier une réponse sur laquelle une réservation est en cours
// (la pharmacie annule alors la réservation : POST /v1/pharmacy/reservations/{id}/cancel).
func (s *Service) requireNoReservationOn(ctx context.Context, alertID, responseID uuid.UUID) error {
	q := s.q(ctx)
	rid, err := q.ActiveReservationForAlert(ctx, alertID)
	if database.IsNoRows(err) {
		return nil
	}
	if err != nil {
		return fmt.Errorf("réservation en cours : %w", err)
	}
	r, err := q.GetReservation(ctx, rid)
	if err != nil {
		return fmt.Errorf("lecture de la réservation : %w", err)
	}
	if r.ResponseID == responseID {
		return apperr.Conflict("reservation_in_progress", "Un client a réservé sur cette réponse : annulez la réservation pour la modifier.")
	}
	return nil
}

// --- Back-office ----------------------------------------------------------------------------

// AdminAlert ajoute le client et les paiements pour le back-office (identités visibles).
type AdminAlert struct {
	Alert
	BuyerID  uuid.UUID `json:"buyer_id"`
	Payments []Payment `json:"payments"`
}

// AdminListAlerts liste les alertes (filtre de statut).
func (s *Service) AdminListAlerts(ctx context.Context, status string, limit, offset int32) ([]AdminAlert, error) {
	var st *string
	if status != "" {
		st = &status
	}
	ids, err := s.q(ctx).ListAlertIDs(ctx, store.ListAlertIDsParams{Status: st, Lim: limit, Off: offset})
	if err != nil {
		return nil, fmt.Errorf("liste des alertes : %w", err)
	}
	out := make([]AdminAlert, 0, len(ids))
	for _, id := range ids {
		a, err := s.AdminGetAlert(ctx, id)
		if err != nil {
			return nil, err
		}
		out = append(out, a)
	}
	return out, nil
}

// AdminGetAlert retourne une alerte, identités des pharmacies visibles.
func (s *Service) AdminGetAlert(ctx context.Context, id uuid.UUID) (AdminAlert, error) {
	q := s.q(ctx)
	a, err := q.GetAlert(ctx, id)
	if database.IsNoRows(err) {
		return AdminAlert{}, errAlertNotFound
	}
	if err != nil {
		return AdminAlert{}, fmt.Errorf("lecture de l'alerte : %w", err)
	}
	unmasked := a
	if unmasked.UnlockedAt == nil {
		now := time.Now()
		unmasked.UnlockedAt = &now // le back-office voit toujours les pharmacies
	}
	v, err := s.alertView(ctx, unmasked)
	if err != nil {
		return AdminAlert{}, err
	}
	v.Unlocked = a.UnlockedAt != nil
	pays, err := q.ListAlertPayments(ctx, id)
	if err != nil {
		return AdminAlert{}, fmt.Errorf("paiements de l'alerte : %w", err)
	}
	out := AdminAlert{Alert: v, BuyerID: a.BuyerID, Payments: make([]Payment, len(pays))}
	for i, p := range pays {
		out.Payments[i] = toPayment(p)
	}
	return out, nil
}
