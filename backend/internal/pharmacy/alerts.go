package pharmacy

import (
	"context"
	"fmt"
	"slices"
	"strings"
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

// Limites d'une alerte.
const (
	maxAlertItems  = 20
	maxAlertPhotos = 10
	maxLines       = 30
)

// AlertItemInput : un produit recherché, choisi dans la base (medicine_id) ou saisi librement.
type AlertItemInput struct {
	MedicineID *uuid.UUID `json:"medicine_id"`
	Name       string     `json:"name"`
	Form       string     `json:"form"`
	Quantity   int32      `json:"quantity"`
}

// AlertPhotoInput : une photo envoyée par POST /v1/uploads (usage pharmacy_alert_photo).
type AlertPhotoInput struct {
	Kind      string `json:"kind"`
	ObjectKey string `json:"object_key"`
}

// AlertInput lance une alerte : produits saisis et/ou photos (ordonnance, boîte), combinables.
// Position : address_id (adresse enregistrée) ou location. RadiusM : un des rayons proposés.
type AlertInput struct {
	Items           []AlertItemInput  `json:"items"`
	Photos          []AlertPhotoInput `json:"photos"`
	Note            string            `json:"note"`
	GenericAccepted bool              `json:"generic_accepted"`
	RadiusM         int32             `json:"radius_m"`
	AddressID       *uuid.UUID        `json:"address_id"`
	Location        *geo.Point        `json:"location"`
}

// RelaunchInput relance une alerte terminée (rayon élargi, produits modifiés). Champs absents :
// repris de l'alerte d'origine (photos comprises tant qu'elles ne sont pas supprimées).
type RelaunchInput struct {
	RadiusM         int32             `json:"radius_m"`
	Items           *[]AlertItemInput `json:"items"`
	Note            *string           `json:"note"`
	GenericAccepted *bool             `json:"generic_accepted"`
}

// AlertItem est un produit recherché.
type AlertItem struct {
	ID         uuid.UUID  `json:"id"`
	Position   int32      `json:"position"`
	MedicineID *uuid.UUID `json:"medicine_id"`
	Name       string     `json:"name"`
	Form       string     `json:"form"`
	Quantity   int32      `json:"quantity"`
}

// AlertPhoto est une photo de l'alerte. URL : lien de 10 minutes, tant qu'elle n'est pas supprimée.
type AlertPhoto struct {
	ID       uuid.UUID `json:"id"`
	Kind     string    `json:"kind"`
	Position int32     `json:"position"`
	URL      string    `json:"url,omitempty"`
	Purged   bool      `json:"purged"`
}

// AlertStats : pharmacies alertées, qui ont ouvert l'alerte, qui ont répondu « disponible ».
type AlertStats struct {
	Notified  int64 `json:"notified"`
	Seen      int64 `json:"seen"`
	Responded int64 `json:"responded"`
}

// Alert est l'alerte vue par le client.
type Alert struct {
	ID              uuid.UUID    `json:"id"`
	Kind            string       `json:"kind"`
	Items           []AlertItem  `json:"items"`
	Photos          []AlertPhoto `json:"photos"`
	Note            string       `json:"note"`
	GenericAccepted bool         `json:"generic_accepted"`
	Status          string       `json:"status"`
	Location        geo.Point    `json:"location"`
	RadiusM         int32        `json:"radius_m"`
	SearchEndsAt    time.Time    `json:"search_ends_at"`
	Stats           AlertStats   `json:"stats"`
	// UnlockFeeXOF : forfait pour débloquer UNE pharmacie (chaque déblocage se paie).
	UnlockFeeXOF   int64           `json:"unlock_fee_xof"`
	Responses      []AlertResponse `json:"responses"`
	RelaunchedFrom *uuid.UUID      `json:"relaunched_from"`
	CreatedAt      time.Time       `json:"created_at"`
	ClosedAt       *time.Time      `json:"closed_at"`
}

// ResponseLine est une ligne de réponse : un produit, disponible ou non, avec son prix.
type ResponseLine struct {
	ID                   uuid.UUID  `json:"id"`
	AlertItemID          *uuid.UUID `json:"alert_item_id"`
	Name                 string     `json:"name"`
	Quantity             int32      `json:"quantity"`
	UnitPriceXOF         int64      `json:"unit_price_xof"`
	LineTotalXOF         int64      `json:"line_total_xof"`
	Available            bool       `json:"available"`
	PrescriptionRequired bool       `json:"prescription_required"`
}

// AlertResponse est une réponse de pharmacie, classée par distance. Tant qu'elle n'est pas
// débloquée, la pharmacie est masquée (pharmacy nul, libellé « Pharmacie N », note cachée).
type AlertResponse struct {
	ID             uuid.UUID      `json:"id"`
	Rank           int            `json:"rank"`
	Label          string         `json:"label"`
	DistanceM      int32          `json:"distance_m"`
	Lines          []ResponseLine `json:"lines"`
	AvailableCount int32          `json:"available_count"`
	LineCount      int32          `json:"line_count"`
	AllAvailable   bool           `json:"all_available"`
	// TotalXOF : total indicatif des produits disponibles.
	TotalXOF             int64     `json:"total_xof"`
	PrescriptionRequired bool      `json:"prescription_required"`
	Note                 string    `json:"note"`
	Status               string    `json:"status"`
	Unlocked             bool      `json:"unlocked"`
	RespondedAt          time.Time `json:"responded_at"`
	// ReservationID : réservation créée au déblocage (mise de côté).
	ReservationID *uuid.UUID       `json:"reservation_id"`
	Pharmacy      *PharmacyContact `json:"pharmacy"`
}

// PharmacyContact est l'identité d'une pharmacie, donnée au client après déblocage.
type PharmacyContact struct {
	ID          uuid.UUID  `json:"id"`
	Name        string     `json:"name"`
	Phone       string     `json:"phone"`
	AddressText string     `json:"address_text"`
	Location    geo.Point  `json:"location"`
	OnDuty      bool       `json:"on_duty"`
	Open24h     bool       `json:"open_24h"`
	DutyUntil   *time.Time `json:"duty_until"`
}

// InboxItem est une alerte reçue par une pharmacie : jamais d'identité ni de position du client.
type InboxItem struct {
	AlertID uuid.UUID   `json:"alert_id"`
	Kind    string      `json:"kind"`
	Items   []AlertItem `json:"items"`
	// Photos : liens de 10 minutes (détail seulement), tant que l'alerte est ouverte.
	Photos          []AlertPhoto `json:"photos"`
	PhotoCount      int          `json:"photo_count"`
	Note            string       `json:"note"`
	GenericAccepted bool         `json:"generic_accepted"`
	DistanceM       int32        `json:"distance_m"`
	Status          string       `json:"status"`
	AlertStatus     string       `json:"alert_status"`
	SearchEndsAt    time.Time    `json:"search_ends_at"`
	Seen            bool         `json:"seen"`
	MyResponse      *OwnResponse `json:"my_response"`
	ReceivedAt      time.Time    `json:"received_at"`
}

// OwnResponse est la réponse de la pharmacie à une alerte.
type OwnResponse struct {
	ID       uuid.UUID      `json:"id"`
	Lines    []ResponseLine `json:"lines"`
	TotalXOF int64          `json:"total_xof"`
	Note     string         `json:"note"`
	Status   string         `json:"status"`
	Unlocked bool           `json:"unlocked"`
}

// ResponseLineInput : une ligne de réponse. alert_item_id relie la ligne à un produit saisi par
// le client ; une ligne sans lien vient de la lecture de l'ordonnance ou d'une photo de boîte.
type ResponseLineInput struct {
	AlertItemID          *uuid.UUID `json:"alert_item_id"`
	Name                 string     `json:"name"`
	Quantity             int32      `json:"quantity"`
	UnitPriceXOF         int64      `json:"unit_price_xof"`
	Available            bool       `json:"available"`
	PrescriptionRequired bool       `json:"prescription_required"`
}

// ResponseInput : la réponse de la pharmacie, ligne par ligne (au moins un produit disponible).
type ResponseInput struct {
	Lines []ResponseLineInput `json:"lines"`
	Note  string              `json:"note"`
}

// RadiusCount : pharmacies de garde dans un rayon.
type RadiusCount struct {
	RadiusM    int32 `json:"radius_m"`
	Pharmacies int64 `json:"pharmacies"`
}

// AlertPreview prépare l'écran « Lancer l'alerte » : rayons proposés et pharmacies jointes.
type AlertPreview struct {
	DefaultRadiusM        int32         `json:"default_radius_m"`
	Radii                 []RadiusCount `json:"radii"`
	UnlockFeeXOF          int64         `json:"unlock_fee_xof"`
	ResponseWindowMinutes int32         `json:"response_window_minutes"`
	PickupHoldMinutes     int32         `json:"pickup_hold_minutes"`
	PhotoRetentionHours   int32         `json:"photo_retention_hours"`
}

var openAlert = []string{AlertSearching, AlertAnswered, AlertUnlocked}

var errAlertNotFound = apperr.NotFound("alert_not_found", "Alerte introuvable.")

func (s *Service) attachedPhotos(ctx context.Context, keys []string) (map[string]bool, error) {
	found, err := s.q(ctx).AlertPhotoKeysIn(ctx, keys)
	if err != nil {
		return nil, fmt.Errorf("photos rattachées : %w", err)
	}
	out := make(map[string]bool, len(found))
	for _, k := range found {
		out[k] = true
	}
	return out, nil
}

// alertPoint résout la position de l'alerte : adresse enregistrée ou position donnée.
func (s *Service) alertPoint(ctx context.Context, buyerID uuid.UUID, addressID *uuid.UUID, loc *geo.Point) (geo.Point, error) {
	v := validate.New()
	v.Check((addressID == nil) != (loc == nil), "location", "Indiquez une adresse enregistrée ou une position.")
	if loc != nil {
		v.Coordinates("location.", loc.Lat, loc.Lng)
	}
	if err := v.Err(); err != nil {
		return geo.Point{}, err
	}
	if addressID != nil {
		a, err := s.users.GetAddress(ctx, buyerID, *addressID)
		if err != nil {
			return geo.Point{}, err
		}
		return a.Location, nil
	}
	return *loc, nil
}

// Preview compte les pharmacies de garde jointes pour chaque rayon proposé.
func (s *Service) Preview(ctx context.Context, buyerID uuid.UUID, addressID *uuid.UUID, loc *geo.Point) (AlertPreview, error) {
	settings, err := s.Settings(ctx)
	if err != nil {
		return AlertPreview{}, err
	}
	p, err := s.alertPoint(ctx, buyerID, addressID, loc)
	if err != nil {
		return AlertPreview{}, err
	}
	out := AlertPreview{
		DefaultRadiusM: settings.SearchRadiusM, UnlockFeeXOF: settings.UnlockFeeXOF,
		ResponseWindowMinutes: settings.ResponseWindowMinutes, PickupHoldMinutes: settings.PickupHoldMinutes,
		PhotoRetentionHours: settings.PhotoRetentionHours, Radii: make([]RadiusCount, 0, len(settings.RadiusOptionsM)),
	}
	for _, r := range settings.RadiusOptionsM {
		night, err := s.isNight(ctx)
		if err != nil {
			return AlertPreview{}, err
		}
		n, err := s.q(ctx).CountReachablePharmacies(ctx, store.CountReachablePharmaciesParams{Lat: p.Lat, Lng: p.Lng, RadiusM: float64(r), Night: night})
		if err != nil {
			return AlertPreview{}, fmt.Errorf("pharmacies du rayon : %w", err)
		}
		out.Radii = append(out.Radii, RadiusCount{RadiusM: r, Pharmacies: n})
	}
	return out, nil
}

type cleanItem struct {
	medicineID *uuid.UUID
	name, form string
	quantity   int32
}

// cleanItems valide les produits ; un produit de la base reprend son nom, dosage et forme.
func (s *Service) cleanItems(ctx context.Context, v validate.Errors, in []AlertItemInput) ([]cleanItem, error) {
	v.Check(len(in) <= maxAlertItems, "items", fmt.Sprintf("%d produits au plus.", maxAlertItems))
	out := make([]cleanItem, 0, len(in))
	for i, it := range in {
		f := fmt.Sprintf("items.%d.", i)
		c := cleanItem{medicineID: it.MedicineID, name: validate.Clean(it.Name), form: validate.Clean(it.Form), quantity: it.Quantity}
		if c.quantity == 0 {
			c.quantity = 1
		}
		if it.MedicineID != nil {
			m, err := s.q(ctx).GetMedicine(ctx, *it.MedicineID)
			if database.IsNoRows(err) || (err == nil && !m.IsActive) {
				v.Check(false, f+"medicine_id", "Médicament introuvable.")
				continue
			}
			if err != nil {
				return nil, fmt.Errorf("lecture du médicament : %w", err)
			}
			if c.name == "" {
				c.name = strings.TrimSpace(m.Name + " " + m.Dosage)
			}
			if c.form == "" {
				c.form = m.Form
			}
		}
		v.Text(f+"name", c.name, 2, 160)
		v.Check(len(c.form) <= 60, f+"form", "60 caractères au plus.")
		v.Check(c.quantity >= 1 && c.quantity <= 20, f+"quantity", "Entre 1 et 20.")
		out = append(out, c)
	}
	return out, nil
}

func alertKind(items int, photos []AlertPhotoInput) string {
	kinds := map[string]bool{}
	for _, p := range photos {
		kinds[p.Kind] = true
	}
	switch {
	case items > 0 && len(kinds) == 0:
		return KindName
	case items == 0 && len(kinds) == 1 && kinds[PhotoPrescription]:
		return KindPrescription
	case items == 0 && len(kinds) == 1 && kinds[PhotoBox]:
		return KindBoxPhoto
	}
	return KindMixed
}

// alertSummary : libellé court de l'alerte (notifications, back-office).
func alertSummary(items []cleanItem, photos []AlertPhotoInput) string {
	var parts []string
	for _, it := range items {
		parts = append(parts, it.name)
	}
	pages := 0
	for _, p := range photos {
		if p.Kind == PhotoPrescription {
			pages++
		}
	}
	if pages > 0 {
		parts = append(parts, fmt.Sprintf("Ordonnance (%d p.)", pages))
	}
	out := strings.Join(parts, ", ")
	if out == "" {
		out = "Photo de boîte"
	}
	if r := []rune(out); len(r) > 120 {
		out = string(r[:117]) + "…"
	}
	return out
}

// CreateAlert lance une alerte et la diffuse aux pharmacies de garde du rayon choisi.
func (s *Service) CreateAlert(ctx context.Context, buyerID uuid.UUID, in AlertInput) (Alert, error) {
	return s.createAlert(ctx, buyerID, in, nil)
}

func (s *Service) createAlert(ctx context.Context, buyerID uuid.UUID, in AlertInput, relaunchedFrom *uuid.UUID) (Alert, error) {
	settings, err := s.Settings(ctx)
	if err != nil {
		return Alert{}, err
	}
	if !settings.Enabled {
		return Alert{}, apperr.Unavailable("pharmacy_disabled", "L'alerte médicament est momentanément indisponible.")
	}
	in.Note = validate.Clean(in.Note)
	if in.RadiusM == 0 {
		in.RadiusM = settings.SearchRadiusM
	}
	carried, err := s.carriedPhotos(ctx, relaunchedFrom)
	if err != nil {
		return Alert{}, err
	}
	v := validate.New()
	items, err := s.cleanItems(ctx, v, in.Items)
	if err != nil {
		return Alert{}, err
	}
	v.Check(len(in.Items) > 0 || len(in.Photos)+len(carried) > 0, "items", "Indiquez au moins un produit ou une photo.")
	v.Check(len(in.Photos) <= maxAlertPhotos, "photos", fmt.Sprintf("%d photos au plus.", maxAlertPhotos))
	seen := map[string]bool{}
	for i, p := range in.Photos {
		f := fmt.Sprintf("photos.%d.", i)
		v.Check(p.Kind == PhotoPrescription || p.Kind == PhotoBox, f+"kind", "Valeur attendue : prescription ou box.")
		v.Check(p.ObjectKey != "" && !seen[p.ObjectKey], f+"object_key", "Photo manquante ou en double.")
		seen[p.ObjectKey] = true
	}
	v.Check(len(in.Note) <= 300, "note", "300 caractères au plus.")
	v.Check(slices.Contains(settings.RadiusOptionsM, in.RadiusM), "radius_m", "Rayon non proposé.")
	if err := v.Err(); err != nil {
		return Alert{}, err
	}
	for i, p := range in.Photos {
		if err := s.uploads.Check(ctx, uploads.PharmacyAlertPhoto, buyerID, p.ObjectKey, fmt.Sprintf("photos.%d.object_key", i)); err != nil {
			return Alert{}, err
		}
	}
	point, err := s.alertPoint(ctx, buyerID, in.AddressID, in.Location)
	if err != nil {
		return Alert{}, err
	}
	allPhotos := slices.Concat(carried, in.Photos)
	var id uuid.UUID
	err = s.db.InTx(ctx, func(ctx context.Context) error {
		q := s.q(ctx)
		ends := time.Now().Add(time.Duration(settings.ResponseWindowMinutes) * time.Minute)
		id, err = q.CreateAlert(ctx, store.CreateAlertParams{
			BuyerID: buyerID, Kind: alertKind(len(items), allPhotos), MedicineName: alertSummary(items, allPhotos), Note: in.Note,
			Lat: point.Lat, Lng: point.Lng, RadiusM: in.RadiusM, SearchEndsAt: ends, GenericAccepted: in.GenericAccepted,
			RelaunchedFrom: relaunchedFrom,
		})
		if err != nil {
			return fmt.Errorf("création de l'alerte : %w", err)
		}
		for i, it := range items {
			if err := q.InsertAlertItem(ctx, store.InsertAlertItemParams{
				AlertID: id, Position: int32(i + 1), MedicineID: it.medicineID, Name: it.name, Form: it.form, Quantity: it.quantity,
			}); err != nil {
				return fmt.Errorf("produit de l'alerte : %w", err)
			}
		}
		if relaunchedFrom != nil {
			if err := q.MoveAlertPhotos(ctx, store.MoveAlertPhotosParams{ToAlert: id, FromAlert: *relaunchedFrom}); err != nil {
				return fmt.Errorf("photos reprises : %w", err)
			}
		}
		for i, p := range in.Photos {
			key := p.ObjectKey
			err := q.InsertAlertPhoto(ctx, store.InsertAlertPhotoParams{AlertID: id, Kind: p.Kind, Position: int32(i + 1), ObjectKey: &key})
			if database.IsUniqueViolation(err, "") {
				return apperr.Validation(map[string]string{fmt.Sprintf("photos.%d.object_key", i): "Photo déjà utilisée par une autre alerte."})
			}
			if err != nil {
				return fmt.Errorf("photo de l'alerte : %w", err)
			}
		}
		if _, err := s.broadcast(ctx, id, point, in.RadiusM); err != nil {
			return err
		}
		if settings.AutoWiden && settings.MaxRadiusM > in.RadiusM {
			if err := s.jobs.Enqueue(ctx, WidenArgs{AlertID: id}, jobs.At(time.Now().Add(time.Duration(settings.WidenAfterMinutes)*time.Minute))); err != nil {
				return err
			}
		}
		return s.jobs.Enqueue(ctx, CloseSearchArgs{AlertID: id}, jobs.At(ends))
	})
	if err != nil {
		return Alert{}, err
	}
	return s.GetAlert(ctx, buyerID, id)
}

// Relaunch relance une alerte terminée sans réponse (ou annulée) : nouveau rayon, produits
// éventuellement modifiés. Les photos encore présentes sont réutilisées (copiées par référence).
func (s *Service) Relaunch(ctx context.Context, buyerID, alertID uuid.UUID, in RelaunchInput) (Alert, error) {
	q := s.q(ctx)
	a, err := q.GetAlert(ctx, alertID)
	if database.IsNoRows(err) || (err == nil && a.BuyerID != buyerID) {
		return Alert{}, errAlertNotFound
	}
	if err != nil {
		return Alert{}, fmt.Errorf("lecture de l'alerte : %w", err)
	}
	if slices.Contains([]string{AlertSearching, AlertUnlocked, AlertFulfilled}, a.Status) {
		return Alert{}, apperr.Conflict("alert_not_relaunchable", "Seule une alerte terminée sans suite peut être relancée.")
	}
	next := AlertInput{
		Note: a.Note, GenericAccepted: a.GenericAccepted, RadiusM: in.RadiusM, Location: &geo.Point{Lat: a.Lat, Lng: a.Lng},
	}
	if in.Note != nil {
		next.Note = *in.Note
	}
	if in.GenericAccepted != nil {
		next.GenericAccepted = *in.GenericAccepted
	}
	if in.Items != nil {
		next.Items = *in.Items
	} else {
		items, err := q.ListAlertItems(ctx, alertID)
		if err != nil {
			return Alert{}, fmt.Errorf("produits de l'alerte : %w", err)
		}
		for _, it := range items {
			next.Items = append(next.Items, AlertItemInput{MedicineID: it.MedicineID, Name: it.Name, Form: it.Form, Quantity: it.Quantity})
		}
	}
	return s.createAlert(ctx, buyerID, next, &alertID)
}

// carriedPhotos : photos encore présentes de l'alerte relancée (reprises par la nouvelle alerte).
func (s *Service) carriedPhotos(ctx context.Context, from *uuid.UUID) ([]AlertPhotoInput, error) {
	if from == nil {
		return nil, nil
	}
	rows, err := s.q(ctx).ListAlertPhotos(ctx, *from)
	if err != nil {
		return nil, fmt.Errorf("photos de l'alerte : %w", err)
	}
	var out []AlertPhotoInput
	for _, r := range rows {
		if r.ObjectKey != nil {
			out = append(out, AlertPhotoInput{Kind: r.Kind, ObjectKey: *r.ObjectKey})
		}
	}
	return out, nil
}

// broadcast sollicite les pharmacies joignables du rayon qui ne l'ont pas encore été.
func (s *Service) broadcast(ctx context.Context, alertID uuid.UUID, p geo.Point, radius int32) (int, error) {
	q := s.q(ctx)
	night, err := s.isNight(ctx)
	if err != nil {
		return 0, err
	}
	rows, err := q.FindReachablePharmacies(ctx, store.FindReachablePharmaciesParams{
		Night:   night,
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
			Title: "Alerte médicament", Body: fmt.Sprintf("Un client à %s cherche des produits. Répondez vite !", formatDistance(dist)),
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
	return strings.Replace(fmt.Sprintf("%.1f km", float64(m)/1000), ".", ",", 1)
}

// widen élargit la recherche au rayon maximal si les réponses manquent (réglage auto_widen).
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

// closeSearch termine la fenêtre de réponse : sollicitations restantes expirées, client prévenu.
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
		next, title, body := AlertNoResponse, "Aucune pharmacie n'a confirmé vos produits",
			"Vous n'avez rien payé. Élargissez la recherche ou modifiez les produits."
		if n > 0 {
			next, title, body = AlertAnswered, "Réponses des pharmacies",
				fmt.Sprintf("%d pharmacie(s) ont vos produits. Débloquez celle de votre choix.", n)
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
		if next == AlertUnlocked {
			return nil // le client suit déjà sa pharmacie débloquée
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

func toItems(rows []store.PharmacyAlertItem) []AlertItem {
	out := make([]AlertItem, len(rows))
	for i, r := range rows {
		out[i] = AlertItem{ID: r.ID, Position: r.Position, MedicineID: r.MedicineID, Name: r.Name, Form: r.Form, Quantity: r.Quantity}
	}
	return out
}

// photos retourne les photos de l'alerte ; withURLs ajoute les liens de 10 minutes.
func (s *Service) photos(ctx context.Context, alertID uuid.UUID, withURLs bool) ([]AlertPhoto, error) {
	rows, err := s.q(ctx).ListAlertPhotos(ctx, alertID)
	if err != nil {
		return nil, fmt.Errorf("photos de l'alerte : %w", err)
	}
	out := make([]AlertPhoto, len(rows))
	for i, r := range rows {
		out[i] = AlertPhoto{ID: r.ID, Kind: r.Kind, Position: r.Position, Purged: r.ObjectKey == nil}
		if withURLs && r.ObjectKey != nil {
			if out[i].URL, err = s.uploads.PrivateURL(ctx, *r.ObjectKey); err != nil {
				return nil, err
			}
		}
	}
	return out, nil
}

func (s *Service) responseLines(ctx context.Context, responseID uuid.UUID) ([]ResponseLine, error) {
	rows, err := s.q(ctx).ListResponseLines(ctx, responseID)
	if err != nil {
		return nil, fmt.Errorf("lignes de la réponse : %w", err)
	}
	out := make([]ResponseLine, len(rows))
	for i, r := range rows {
		out[i] = ResponseLine{
			ID: r.ID, AlertItemID: r.AlertItemID, Name: r.Name, Quantity: r.Quantity, UnitPriceXOF: r.UnitPriceXof,
			Available: r.Available, PrescriptionRequired: r.PrescriptionRequired,
		}
		if r.Available {
			out[i].LineTotalXOF = r.UnitPriceXof * int64(r.Quantity)
		}
	}
	return out, nil
}

// GetAlert retourne une alerte du client avec ses réponses classées.
func (s *Service) GetAlert(ctx context.Context, buyerID, id uuid.UUID) (Alert, error) {
	a, err := s.q(ctx).GetAlert(ctx, id)
	if database.IsNoRows(err) || (err == nil && a.BuyerID != buyerID) {
		return Alert{}, errAlertNotFound
	}
	if err != nil {
		return Alert{}, fmt.Errorf("lecture de l'alerte : %w", err)
	}
	return s.alertView(ctx, a, false)
}

// alertView construit l'alerte ; unmask (back-office) montre toutes les pharmacies.
func (s *Service) alertView(ctx context.Context, a store.GetAlertRow, unmask bool) (Alert, error) {
	q := s.q(ctx)
	settings, err := s.Settings(ctx)
	if err != nil {
		return Alert{}, err
	}
	st, err := q.AlertStats(ctx, a.ID)
	if err != nil {
		return Alert{}, fmt.Errorf("décompte des pharmacies : %w", err)
	}
	items, err := q.ListAlertItems(ctx, a.ID)
	if err != nil {
		return Alert{}, fmt.Errorf("produits de l'alerte : %w", err)
	}
	photos, err := s.photos(ctx, a.ID, true)
	if err != nil {
		return Alert{}, err
	}
	rows, err := q.ListResponses(ctx, a.ID)
	if err != nil {
		return Alert{}, fmt.Errorf("réponses : %w", err)
	}
	out := Alert{
		ID: a.ID, Kind: a.Kind, Items: toItems(items), Photos: photos, Note: a.Note, GenericAccepted: a.GenericAccepted,
		Status: a.Status, Location: geo.Point{Lat: a.Lat, Lng: a.Lng}, RadiusM: a.RadiusM, SearchEndsAt: a.SearchEndsAt,
		Stats: AlertStats{Notified: st.Notified, Seen: st.Seen, Responded: st.Responded}, UnlockFeeXOF: settings.UnlockFeeXOF,
		Responses: make([]AlertResponse, 0, len(rows)), RelaunchedFrom: a.RelaunchedFrom, CreatedAt: a.CreatedAt, ClosedAt: a.ClosedAt,
	}
	for i, r := range rows {
		lines, err := s.responseLines(ctx, r.ID)
		if err != nil {
			return Alert{}, err
		}
		resp := AlertResponse{
			ID: r.ID, Rank: i + 1, Label: fmt.Sprintf("Pharmacie %d", i+1), DistanceM: r.DistanceM, Lines: lines,
			AvailableCount: r.AvailableCount, LineCount: r.LineCount, AllAvailable: r.AvailableCount == r.LineCount && r.LineCount > 0,
			TotalXOF: r.TotalXof, PrescriptionRequired: r.PrescriptionRequired, Status: r.Status, Unlocked: r.UnlockedAt != nil,
			RespondedAt: r.UpdatedAt,
		}
		if rid, err := q.LatestReservationForResponse(ctx, r.ID); err == nil {
			resp.ReservationID = &rid
		} else if !database.IsNoRows(err) {
			return Alert{}, fmt.Errorf("réservation de la réponse : %w", err)
		}
		if resp.Unlocked || unmask {
			resp.Label = r.PharmacyName
			resp.Note = r.Note
			resp.Pharmacy = &PharmacyContact{
				ID: r.PharmacyID, Name: r.PharmacyName, Phone: r.PharmacyPhone, AddressText: r.PharmacyAddress,
				Location: geo.Point{Lat: r.PharmacyLat, Lng: r.PharmacyLng}, OnDuty: r.PharmacyOnDuty,
				Open24h: r.PharmacyOpen24h, DutyUntil: dutyUntil(r.PharmacyDutyUntil),
			}
		}
		out.Responses = append(out.Responses, resp)
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

// CancelAlert annule l'alerte du client. Les mises de côté non payées sont annulées avec elle ;
// une livraison payée doit d'abord être annulée (remboursement).
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
		rids, err := q.ActiveReservationsForAlert(ctx, id)
		if err != nil {
			return fmt.Errorf("réservations en cours : %w", err)
		}
		for _, rid := range rids {
			r, err := q.GetReservation(ctx, rid)
			if err != nil {
				return fmt.Errorf("lecture de la réservation : %w", err)
			}
			if !slices.Contains([]string{ResReserved, ResCourierSearch, ResAwaitingPayment}, r.Status) {
				return apperr.Conflict("reservation_in_progress", "Une livraison payée est en cours : annulez-la d'abord.")
			}
			if err := s.endReservation(ctx, r, ResCancelled, "Alerte annulée par le client.", byBuyer); err != nil {
				return err
			}
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

type inboxRow struct {
	alertID      uuid.UUID
	distanceM    int32
	targetStatus string
	notifiedAt   time.Time
	kind, note   string
	alertStatus  string
	searchEndsAt time.Time
	generic      bool
	seenAt       *time.Time
}

func (s *Service) inboxItem(ctx context.Context, pharmacyID uuid.UUID, r inboxRow, detail bool) (InboxItem, error) {
	q := s.q(ctx)
	items, err := q.ListAlertItems(ctx, r.alertID)
	if err != nil {
		return InboxItem{}, fmt.Errorf("produits de l'alerte : %w", err)
	}
	// Photos lisibles seulement tant que la pharmacie peut répondre.
	canSee := detail && slices.Contains(openAlert, r.alertStatus) && (r.targetStatus == "pending" || r.targetStatus == "responded")
	photos, err := s.photos(ctx, r.alertID, canSee)
	if err != nil {
		return InboxItem{}, err
	}
	it := InboxItem{
		AlertID: r.alertID, Kind: r.kind, Items: toItems(items), Photos: photos, PhotoCount: len(photos), Note: r.note,
		GenericAccepted: r.generic, DistanceM: r.distanceM, Status: r.targetStatus, AlertStatus: r.alertStatus,
		SearchEndsAt: r.searchEndsAt, Seen: r.seenAt != nil || detail, ReceivedAt: r.notifiedAt,
	}
	resp, err := q.ResponseOf(ctx, store.ResponseOfParams{AlertID: r.alertID, PharmacyID: pharmacyID})
	if err == nil {
		lines, err := s.responseLines(ctx, resp.ID)
		if err != nil {
			return InboxItem{}, err
		}
		it.MyResponse = &OwnResponse{ID: resp.ID, Lines: lines, TotalXOF: resp.TotalXof, Note: resp.Note, Status: resp.Status, Unlocked: resp.UnlockedAt != nil}
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
		it, err := s.inboxItem(ctx, ph.ID, inboxRow{
			alertID: r.AlertID, distanceM: r.DistanceM, targetStatus: r.TargetStatus, notifiedAt: r.NotifiedAt, kind: r.Kind,
			note: r.Note, alertStatus: r.AlertStatus, searchEndsAt: r.SearchEndsAt, generic: r.GenericAccepted, seenAt: r.SeenAt,
		}, false)
		if err != nil {
			return nil, err
		}
		out = append(out, it)
	}
	return out, nil
}

// InboxGet retourne une alerte reçue avec les liens temporaires vers ses photos ; l'alerte est
// comptée comme vue (« Ont vu » côté client).
func (s *Service) InboxGet(ctx context.Context, ownerID, alertID uuid.UUID) (InboxItem, error) {
	ph, err := s.requireActivePharmacy(ctx, ownerID)
	if err != nil {
		return InboxItem{}, err
	}
	q := s.q(ctx)
	r, err := q.InboxItem(ctx, store.InboxItemParams{AlertID: alertID, PharmacyID: ph.ID})
	if database.IsNoRows(err) {
		return InboxItem{}, errAlertNotFound
	}
	if err != nil {
		return InboxItem{}, fmt.Errorf("alerte reçue : %w", err)
	}
	if err := q.MarkTargetSeen(ctx, store.MarkTargetSeenParams{AlertID: alertID, PharmacyID: ph.ID}); err != nil {
		return InboxItem{}, fmt.Errorf("alerte vue : %w", err)
	}
	return s.inboxItem(ctx, ph.ID, inboxRow{
		alertID: r.AlertID, distanceM: r.DistanceM, targetStatus: r.TargetStatus, notifiedAt: r.NotifiedAt, kind: r.Kind,
		note: r.Note, alertStatus: r.AlertStatus, searchEndsAt: r.SearchEndsAt, generic: r.GenericAccepted, seenAt: r.SeenAt,
	}, true)
}

type cleanLine struct {
	itemID     *uuid.UUID
	name       string
	quantity   int32
	price      int64
	available  bool
	rxRequired bool
}

// Respond : la pharmacie répond ligne par ligne. Modifiable tant qu'aucun client ne l'a débloquée.
func (s *Service) Respond(ctx context.Context, ownerID, alertID uuid.UUID, in ResponseInput) (InboxItem, error) {
	ph, err := s.requireActivePharmacy(ctx, ownerID)
	if err != nil {
		return InboxItem{}, err
	}
	in.Note = validate.Clean(in.Note)
	items, err := s.q(ctx).ListAlertItems(ctx, alertID)
	if err != nil {
		return InboxItem{}, fmt.Errorf("produits de l'alerte : %w", err)
	}
	byID := map[uuid.UUID]store.PharmacyAlertItem{}
	for _, it := range items {
		byID[it.ID] = it
	}
	v := validate.New()
	v.Check(len(in.Lines) >= 1 && len(in.Lines) <= maxLines, "lines", fmt.Sprintf("Entre 1 et %d lignes.", maxLines))
	v.Check(len(in.Note) <= 300, "note", "300 caractères au plus.")
	lines := make([]cleanLine, 0, len(in.Lines))
	var total int64
	var available int32
	rx := false
	for i, l := range in.Lines {
		f := fmt.Sprintf("lines.%d.", i)
		c := cleanLine{itemID: l.AlertItemID, name: validate.Clean(l.Name), quantity: l.Quantity, price: l.UnitPriceXOF,
			available: l.Available, rxRequired: l.PrescriptionRequired}
		if l.AlertItemID != nil {
			it, ok := byID[*l.AlertItemID]
			v.Check(ok, f+"alert_item_id", "Produit inconnu pour cette alerte.")
			if ok {
				if c.name == "" {
					c.name = it.Name
				}
				if c.quantity == 0 {
					c.quantity = it.Quantity
				}
			}
		}
		if c.quantity == 0 {
			c.quantity = 1
		}
		v.Text(f+"name", c.name, 2, 160)
		v.Check(c.quantity >= 1 && c.quantity <= 100, f+"quantity", "Entre 1 et 100.")
		if c.available {
			v.Check(c.price >= 1 && c.price <= 10_000_000, f+"unit_price_xof", "Prix unitaire en FCFA attendu.")
			total += c.price * int64(c.quantity)
			available++
			rx = rx || c.rxRequired
		} else {
			c.price = 0
		}
		lines = append(lines, c)
	}
	v.Check(available > 0, "lines", "Au moins un produit disponible ; sinon, refusez l'alerte.")
	if err := v.Err(); err != nil {
		return InboxItem{}, err
	}
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
			if prev.UnlockedAt != nil {
				return apperr.Conflict("response_unlocked", "Un client a débloqué cette réponse : annulez sa réservation pour la modifier.")
			}
		} else if !database.IsNoRows(err) {
			return fmt.Errorf("réponse précédente : %w", err)
		}
		resp, err := q.UpsertResponse(ctx, store.UpsertResponseParams{
			AlertID: alertID, PharmacyID: ph.ID, ProductName: firstAvailable(lines), UnitPriceXof: total,
			QuantityAvailable: available, PrescriptionRequired: rx, Note: in.Note, DistanceM: t.DistanceM,
			TotalXof: total, AvailableCount: available, LineCount: int32(len(lines)),
		})
		if err != nil {
			return fmt.Errorf("enregistrement de la réponse : %w", err)
		}
		if err := q.DeleteResponseLines(ctx, resp.ID); err != nil {
			return fmt.Errorf("lignes précédentes : %w", err)
		}
		for i, l := range lines {
			if err := q.InsertResponseLine(ctx, store.InsertResponseLineParams{
				ResponseID: resp.ID, Position: int32(i + 1), AlertItemID: l.itemID, Name: l.name, Quantity: l.quantity,
				UnitPriceXof: l.price, Available: l.available, PrescriptionRequired: l.rxRequired,
			}); err != nil {
				return fmt.Errorf("ligne de la réponse : %w", err)
			}
		}
		if err := q.SetTargetStatus(ctx, store.SetTargetStatusParams{AlertID: alertID, PharmacyID: ph.ID, Status: "responded"}); err != nil {
			return fmt.Errorf("sollicitation : %w", err)
		}
		if t.Status != "pending" {
			return nil // correction d'une réponse : pas de nouvelle notification
		}
		a, err := q.GetAlert(ctx, alertID)
		if err != nil {
			return fmt.Errorf("lecture de l'alerte : %w", err)
		}
		return s.notify.Notify(ctx, notifications.Message{
			UserID: a.BuyerID, App: notifications.AppBuyer, Kind: "pharmacy_response",
			Title: "Une pharmacie a vos produits",
			Body:  fmt.Sprintf("%d sur %d disponible(s) · %s", available, len(lines), formatDistance(t.DistanceM)),
			Data:  map[string]string{"alert_id": alertID.String()},
		})
	})
	if err != nil {
		return InboxItem{}, err
	}
	return s.InboxGet(ctx, ownerID, alertID)
}

func firstAvailable(lines []cleanLine) string {
	for _, l := range lines {
		if l.available {
			return l.name
		}
	}
	return lines[0].name
}

// Decline : la pharmacie n'a pas les produits (ou ne les a plus : sa réponse est retirée).
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
			if prev.UnlockedAt != nil {
				return apperr.Conflict("response_unlocked", "Un client a débloqué cette réponse : annulez sa réservation.")
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
	v, err := s.alertView(ctx, a, true)
	if err != nil {
		return AdminAlert{}, err
	}
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
