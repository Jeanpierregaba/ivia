package properties

import (
	"context"
	"fmt"
	"net/http"
	"regexp"
	"slices"
	"time"

	"github.com/google/uuid"

	"ivia/backend/internal/admin"
	"ivia/backend/internal/platform/apperr"
	"ivia/backend/internal/platform/database"
	"ivia/backend/internal/platform/httpapi"
	"ivia/backend/internal/platform/identity"
	"ivia/backend/internal/platform/validate"
	"ivia/backend/internal/properties/store"
)

const maxPhotos = 8

var (
	kinds = []string{"sale", "rent"}
	types = []string{"house", "villa", "apartment", "land", "office", "room"}
	phone = regexp.MustCompile(`^\+228[0-9]{8}$`)
)

// AdminProperty est une annonce vue par le back-office, retirée ou non.
type AdminProperty struct {
	Property
	PhotoKeys []string  `json:"photo_keys"`
	IsActive  bool      `json:"is_active"`
	UpdatedAt time.Time `json:"updated_at"`
}

// AdminInput est le contenu d'une annonce. Reason complète le journal.
type AdminInput struct {
	Title        string   `json:"title"`
	Kind         string   `json:"kind"`
	PropertyType string   `json:"property_type"`
	PriceXOF     int64    `json:"price_xof"`
	Bedrooms     int32    `json:"bedrooms"`
	SurfaceM2    int32    `json:"surface_m2"`
	Neighborhood string   `json:"neighborhood"`
	AddressText  string   `json:"address_text"`
	Lat          float64  `json:"lat"`
	Lng          float64  `json:"lng"`
	Description  string   `json:"description"`
	PhotoKeys    []string `json:"photo_keys"`
	ContactName  string   `json:"contact_name"`
	ContactPhone string   `json:"contact_phone"`
	IsActive     bool     `json:"is_active"`
	Reason       string   `json:"reason"`
}

func (in *AdminInput) clean() error {
	in.Title = validate.Clean(in.Title)
	in.Neighborhood = validate.Clean(in.Neighborhood)
	in.AddressText = validate.Clean(in.AddressText)
	in.Description = validate.Clean(in.Description)
	in.ContactName = validate.Clean(in.ContactName)
	v := validate.New()
	v.Text("title", in.Title, 3, 120)
	v.Check(slices.Contains(kinds, in.Kind), "kind", "Valeur attendue : sale ou rent.")
	v.Check(slices.Contains(types, in.PropertyType), "property_type", "Type de bien inconnu.")
	v.Check(in.PriceXOF > 0, "price_xof", "Prix en FCFA, supérieur à zéro.")
	v.Check(in.Bedrooms >= 0 && in.Bedrooms <= 30, "bedrooms", "Entre 0 et 30 chambres.")
	v.Check(in.SurfaceM2 >= 0 && in.SurfaceM2 <= 100000, "surface_m2", "Surface entre 0 et 100 000 m².")
	v.Text("neighborhood", in.Neighborhood, 2, 80)
	v.Text("address_text", in.AddressText, 0, 300)
	v.Text("description", in.Description, 0, 2000)
	v.Text("contact_name", in.ContactName, 0, 80)
	v.Check(phone.MatchString(in.ContactPhone), "contact_phone", "Numéro attendu : +228 suivi de 8 chiffres.")
	// Bornes du Togo : évite une latitude et une longitude inversées.
	v.Check(in.Lat >= 6 && in.Lat <= 11.2, "lat", "Latitude hors du Togo (entre 6 et 11,2).")
	v.Check(in.Lng >= -0.2 && in.Lng <= 1.9, "lng", "Longitude hors du Togo (entre -0,2 et 1,9).")
	v.Check(len(in.PhotoKeys) >= 1 && len(in.PhotoKeys) <= maxPhotos, "photo_keys", "Entre 1 et 8 photos.")
	return v.Err()
}

// checkPhotos vérifie les nouvelles photos ; celles déjà sur l'annonce restent permises.
func (s *Service) checkPhotos(ctx context.Context, adminID uuid.UUID, keys, existing []string) error {
	for _, k := range keys {
		if slices.Contains(existing, k) {
			continue
		}
		if err := s.urls.CheckPropertyPhoto(ctx, adminID, k); err != nil {
			return err
		}
	}
	return nil
}

func (s *Service) toAdmin(r store.AdminGetPropertyRow) AdminProperty {
	return AdminProperty{
		Property: Property{
			ID: r.ID, Title: r.Title, Kind: r.Kind, PropertyType: r.PropertyType, PriceXOF: r.PriceXof,
			Bedrooms: r.Bedrooms, SurfaceM2: r.SurfaceM2, Neighborhood: r.Neighborhood, AddressText: r.AddressText,
			Lat: r.Lat, Lng: r.Lng, Description: r.Description, PhotoURLs: s.photos(r.PhotoKeys),
			ContactName: r.ContactName, ContactPhone: r.ContactPhone, CreatedAt: r.CreatedAt,
		},
		PhotoKeys: r.PhotoKeys, IsActive: r.IsActive, UpdatedAt: r.UpdatedAt,
	}
}

var errNotFound = apperr.NotFound("property_not_found", "Annonce introuvable.")

func conflict(err error, what string) error {
	if database.IsUniqueViolation(err, "properties_title_neighborhood_key") {
		return apperr.Conflict("property_exists", "Une annonce porte déjà ce titre dans ce quartier.")
	}
	return fmt.Errorf("%s : %w", what, err)
}

// AdminList retourne les annonces du back-office.
func (s *Service) AdminList(ctx context.Context, search *string, active *bool, limit, offset int32) ([]AdminProperty, error) {
	rows, err := store.New(s.db.Conn(ctx)).AdminListProperties(ctx, store.AdminListPropertiesParams{
		Search: search, Active: active, Lim: limit, Off: offset,
	})
	if err != nil {
		return nil, fmt.Errorf("annonces : %w", err)
	}
	out := make([]AdminProperty, len(rows))
	for i, r := range rows {
		out[i] = s.toAdmin(store.AdminGetPropertyRow(r))
	}
	return out, nil
}

// AdminGet retourne une annonce, retirée ou non.
func (s *Service) AdminGet(ctx context.Context, id uuid.UUID) (AdminProperty, error) {
	r, err := store.New(s.db.Conn(ctx)).AdminGetProperty(ctx, id)
	if database.IsNoRows(err) {
		return AdminProperty{}, errNotFound
	}
	if err != nil {
		return AdminProperty{}, fmt.Errorf("annonce : %w", err)
	}
	return s.toAdmin(r), nil
}

// AdminCreate publie une annonce (journalisé).
func (s *Service) AdminCreate(ctx context.Context, adminID uuid.UUID, in AdminInput) (AdminProperty, error) {
	if err := in.clean(); err != nil {
		return AdminProperty{}, err
	}
	if err := s.checkPhotos(ctx, adminID, in.PhotoKeys, nil); err != nil {
		return AdminProperty{}, err
	}
	var out AdminProperty
	err := s.db.InTx(ctx, func(ctx context.Context) error {
		id, err := store.New(s.db.Conn(ctx)).InsertProperty(ctx, store.InsertPropertyParams{
			Title: in.Title, Kind: in.Kind, PropertyType: in.PropertyType, PriceXof: in.PriceXOF, Bedrooms: in.Bedrooms,
			SurfaceM2: in.SurfaceM2, Neighborhood: in.Neighborhood, AddressText: in.AddressText, Lat: in.Lat, Lng: in.Lng,
			Description: in.Description, PhotoKeys: in.PhotoKeys, ContactName: in.ContactName,
			ContactPhone: in.ContactPhone, IsActive: in.IsActive,
		})
		if err != nil {
			return conflict(err, "création de l'annonce")
		}
		if out, err = s.AdminGet(ctx, id); err != nil {
			return err
		}
		return s.admin.Record(ctx, admin.AuditEntry{
			AdminID: &adminID, Action: "property.created", TargetType: "property", TargetID: id.String(),
			After: out, Reason: validate.Clean(in.Reason),
		})
	})
	return out, err
}

// AdminUpdate remplace le contenu d'une annonce (journalisé).
func (s *Service) AdminUpdate(ctx context.Context, adminID, id uuid.UUID, in AdminInput) (AdminProperty, error) {
	if err := in.clean(); err != nil {
		return AdminProperty{}, err
	}
	var out AdminProperty
	err := s.db.InTx(ctx, func(ctx context.Context) error {
		q := store.New(s.db.Conn(ctx))
		r, err := q.LockProperty(ctx, id)
		if database.IsNoRows(err) {
			return errNotFound
		}
		if err != nil {
			return fmt.Errorf("verrou de l'annonce : %w", err)
		}
		before := s.toAdmin(store.AdminGetPropertyRow(r))
		if err := s.checkPhotos(ctx, adminID, in.PhotoKeys, before.PhotoKeys); err != nil {
			return err
		}
		if err := q.UpdateProperty(ctx, store.UpdatePropertyParams{
			ID: id, Title: in.Title, Kind: in.Kind, PropertyType: in.PropertyType, PriceXof: in.PriceXOF, Bedrooms: in.Bedrooms,
			SurfaceM2: in.SurfaceM2, Neighborhood: in.Neighborhood, AddressText: in.AddressText, Lat: in.Lat, Lng: in.Lng,
			Description: in.Description, PhotoKeys: in.PhotoKeys, ContactName: in.ContactName,
			ContactPhone: in.ContactPhone, IsActive: in.IsActive,
		}); err != nil {
			return conflict(err, "modification de l'annonce")
		}
		if out, err = s.AdminGet(ctx, id); err != nil {
			return err
		}
		return s.admin.Record(ctx, admin.AuditEntry{
			AdminID: &adminID, Action: "property.updated", TargetType: "property", TargetID: id.String(),
			Before: before, After: out, Reason: validate.Clean(in.Reason),
		})
	})
	return out, err
}

// AdminSetActive publie ou retire une annonce (journalisé) ; le retrait exige un motif.
func (s *Service) AdminSetActive(ctx context.Context, adminID, id uuid.UUID, active bool, reason string) (AdminProperty, error) {
	reason = validate.Clean(reason)
	v := validate.New()
	v.Check(active || len(reason) >= 3, "reason", "Motif obligatoire (3 caractères au moins).")
	if err := v.Err(); err != nil {
		return AdminProperty{}, err
	}
	var out AdminProperty
	err := s.db.InTx(ctx, func(ctx context.Context) error {
		q := store.New(s.db.Conn(ctx))
		r, err := q.LockProperty(ctx, id)
		if database.IsNoRows(err) {
			return errNotFound
		}
		if err != nil {
			return fmt.Errorf("verrou de l'annonce : %w", err)
		}
		before := s.toAdmin(store.AdminGetPropertyRow(r))
		if err := q.SetPropertyActive(ctx, store.SetPropertyActiveParams{ID: id, IsActive: active}); err != nil {
			return fmt.Errorf("publication de l'annonce : %w", err)
		}
		if out, err = s.AdminGet(ctx, id); err != nil {
			return err
		}
		action := "property.withdrawn"
		if active {
			action = "property.published"
		}
		return s.admin.Record(ctx, admin.AuditEntry{
			AdminID: &adminID, Action: action, TargetType: "property", TargetID: id.String(),
			Before: before, After: out, Reason: reason,
		})
	})
	return out, err
}

func (s *Service) registerAdmin(rt *httpapi.Router) {
	ad := identity.RoleAdmin
	me := func(r *http.Request) uuid.UUID { return identity.MustFromContext(r.Context()).UserID }
	rt.Roles("GET /v1/admin/properties", func(w http.ResponseWriter, r *http.Request) error {
		q := httpapi.NewQuery(r)
		p := q.Page()
		text := q.String("q", 100)
		state := q.Enum("state", "", "active", "withdrawn")
		if err := q.Err(); err != nil {
			return err
		}
		var search *string
		if text != "" {
			search = &text
		}
		var active *bool
		if state != "" {
			v := state == "active"
			active = &v
		}
		items, err := s.AdminList(r.Context(), search, active, p.FetchLimit(), int32(p.Offset))
		if err != nil {
			return err
		}
		return httpapi.OK(w, httpapi.NewList(items, p))
	}, ad)
	rt.Roles("POST /v1/admin/properties", func(w http.ResponseWriter, r *http.Request) error {
		var in AdminInput
		if err := httpapi.Decode(r, &in); err != nil {
			return err
		}
		v, err := s.AdminCreate(r.Context(), me(r), in)
		if err != nil {
			return err
		}
		return httpapi.Created(w, v)
	}, ad)
	rt.Roles("GET /v1/admin/properties/{id}", func(w http.ResponseWriter, r *http.Request) error {
		id, err := httpapi.PathUUID(r, "id")
		if err != nil {
			return err
		}
		v, err := s.AdminGet(r.Context(), id)
		if err != nil {
			return err
		}
		return httpapi.OK(w, v)
	}, ad)
	rt.Roles("PUT /v1/admin/properties/{id}", func(w http.ResponseWriter, r *http.Request) error {
		id, err := httpapi.PathUUID(r, "id")
		if err != nil {
			return err
		}
		var in AdminInput
		if err := httpapi.Decode(r, &in); err != nil {
			return err
		}
		v, err := s.AdminUpdate(r.Context(), me(r), id, in)
		if err != nil {
			return err
		}
		return httpapi.OK(w, v)
	}, ad)
	rt.Roles("PUT /v1/admin/properties/{id}/active", func(w http.ResponseWriter, r *http.Request) error {
		id, err := httpapi.PathUUID(r, "id")
		if err != nil {
			return err
		}
		var in struct {
			IsActive bool   `json:"is_active"`
			Reason   string `json:"reason"`
		}
		if err := httpapi.Decode(r, &in); err != nil {
			return err
		}
		v, err := s.AdminSetActive(r.Context(), me(r), id, in.IsActive, in.Reason)
		if err != nil {
			return err
		}
		return httpapi.OK(w, v)
	}, ad)
}
