// Package shops gère les boutiques : création par un utilisateur (qui devient marchand), validation,
// refus et suspension par l'admin.
//
// Une boutique n'est visible des acheteurs qu'au statut « published ». Une boutique suspendue perd
// l'accès aux actions marchand dès la requête suivante (RequireOwned vérifie le statut à chaque appel).
package shops

import (
	"context"
	"fmt"
	"time"

	"github.com/google/uuid"

	"ivia/backend/internal/admin"
	"ivia/backend/internal/geo"
	"ivia/backend/internal/notifications"
	"ivia/backend/internal/platform/apperr"
	"ivia/backend/internal/platform/database"
	"ivia/backend/internal/platform/identity"
	"ivia/backend/internal/platform/validate"
	"ivia/backend/internal/shops/store"
	"ivia/backend/internal/uploads"
	"ivia/backend/internal/users"
)

// Status d'une boutique.
type Status string

const (
	StatusPendingReview Status = "pending_review"
	StatusPublished     Status = "published"
	StatusRejected      Status = "rejected"
	StatusSuspended     Status = "suspended"
)

// maxShopsPerOwner limite les créations abusives.
const maxShopsPerOwner = 5

// Shop est la vue complète d'une boutique (propriétaire, admin).
type Shop struct {
	ID               uuid.UUID  `json:"id"`
	OwnerID          uuid.UUID  `json:"owner_id"`
	Name             string     `json:"name"`
	Description      string     `json:"description"`
	Phone            string     `json:"phone"`
	AddressText      string     `json:"address_text"`
	NeighborhoodID   *uuid.UUID `json:"neighborhood_id"`
	NeighborhoodName string     `json:"neighborhood_name"`
	CategoryID       *uuid.UUID `json:"category_id"`
	CategoryName     string     `json:"category_name"`
	Location         geo.Point  `json:"location"`
	LogoURL          *string    `json:"logo_url"`
	LogoKey          *string    `json:"-"`
	Status           Status     `json:"status"`
	StatusReason     string     `json:"status_reason"`
	AcceptingOrders  bool       `json:"accepting_orders"`
	ReviewedAt       *time.Time `json:"reviewed_at"`
	CreatedAt        time.Time  `json:"created_at"`
	UpdatedAt        time.Time  `json:"updated_at"`
}

// PublicShop est ce que voit un acheteur.
type PublicShop struct {
	ID               uuid.UUID  `json:"id"`
	Name             string     `json:"name"`
	Description      string     `json:"description"`
	Phone            string     `json:"phone"`
	AddressText      string     `json:"address_text"`
	NeighborhoodID   *uuid.UUID `json:"neighborhood_id"`
	NeighborhoodName string     `json:"neighborhood_name"`
	Location         geo.Point  `json:"location"`
	LogoURL          *string    `json:"logo_url"`
	AcceptingOrders  bool       `json:"accepting_orders"`
}

// Public retourne la vue acheteur.
func (s Shop) Public() PublicShop {
	return PublicShop{
		ID: s.ID, Name: s.Name, Description: s.Description, Phone: s.Phone, AddressText: s.AddressText,
		NeighborhoodID: s.NeighborhoodID, NeighborhoodName: s.NeighborhoodName, Location: s.Location,
		LogoURL: s.LogoURL, AcceptingOrders: s.AcceptingOrders,
	}
}

// Input crée ou modifie une boutique.
type Input struct {
	Name           string     `json:"name"`
	Description    string     `json:"description"`
	Phone          string     `json:"phone"`
	AddressText    string     `json:"address_text"`
	NeighborhoodID *uuid.UUID `json:"neighborhood_id"`
	// CategoryID : obligatoire à la création ; absent d'une modification, inchangé.
	CategoryID      *uuid.UUID `json:"category_id"`
	Location        geo.Point  `json:"location"`
	LogoKey         *string    `json:"logo_key"`
	AcceptingOrders *bool      `json:"accepting_orders"`
}

// Category est une catégorie de boutique.
type Category struct {
	ID   uuid.UUID `json:"id"`
	Name string    `json:"name"`
}

// ListCategories retourne les catégories de boutique actives.
func (s *Service) ListCategories(ctx context.Context) ([]Category, error) {
	rows, err := store.New(s.db.Conn(ctx)).ListActiveShopCategories(ctx)
	if err != nil {
		return nil, fmt.Errorf("lecture des catégories de boutique : %w", err)
	}
	out := make([]Category, len(rows))
	for i, r := range rows {
		out[i] = Category{ID: r.ID, Name: r.Name}
	}
	return out, nil
}

// Service gère les boutiques.
type Service struct {
	db      *database.DB
	geo     *geo.Service
	users   *users.Service
	uploads *uploads.Service
	audit   *admin.Service
	notify  *notifications.Service
}

// NewService crée le service.
func NewService(db *database.DB, geoSvc *geo.Service, userSvc *users.Service, up *uploads.Service, audit *admin.Service, notify *notifications.Service) *Service {
	return &Service{db: db, geo: geoSvc, users: userSvc, uploads: up, audit: audit, notify: notify}
}

var (
	errNotFound  = apperr.NotFound("shop_not_found", "Boutique introuvable.")
	errSuspended = apperr.Forbidden("shop_suspended", "Cette boutique est suspendue. Contactez l'équipe ivia.")
)

func (s *Service) validate(ctx context.Context, userID uuid.UUID, in *Input, current *Shop) error {
	var currentCategory *uuid.UUID
	var currentLogoKey *string
	if current != nil {
		currentLogoKey = current.LogoKey
		currentCategory = current.CategoryID
	}
	in.Name = validate.Clean(in.Name)
	in.Description = validate.Clean(in.Description)
	in.AddressText = validate.Clean(in.AddressText)
	v := validate.New()
	v.Text("name", in.Name, 2, 100)
	v.Text("description", in.Description, 0, 2000)
	v.Text("address_text", in.AddressText, 1, 300)
	v.Coordinates("location.", in.Location.Lat, in.Location.Lng)
	if in.CategoryID == nil {
		if current == nil {
			v.Add("category_id", "Choisissez la catégorie de la boutique.")
		} else {
			in.CategoryID = currentCategory
		}
	}
	if phone, ok := validate.NormalizeTogoPhone(in.Phone); ok {
		in.Phone = phone
	} else {
		v.Add("phone", "Numéro mobile togolais attendu (8 chiffres commençant par 7 ou 9).")
	}
	if err := v.Err(); err != nil {
		return err
	}
	if in.NeighborhoodID != nil {
		if _, err := s.geo.RequireActive(ctx, *in.NeighborhoodID); err != nil {
			return err
		}
	}
	if in.CategoryID != nil && (currentCategory == nil || *currentCategory != *in.CategoryID) {
		active, err := store.New(s.db.Conn(ctx)).ShopCategoryIsActive(ctx, *in.CategoryID)
		if err != nil {
			return fmt.Errorf("lecture de la catégorie : %w", err)
		}
		if !active {
			return apperr.Validation(map[string]string{"category_id": "Catégorie inconnue."})
		}
	}
	if in.LogoKey != nil && *in.LogoKey != "" && (currentLogoKey == nil || *currentLogoKey != *in.LogoKey) {
		if err := s.uploads.Check(ctx, uploads.ShopLogo, userID, *in.LogoKey, "logo_key"); err != nil {
			return err
		}
	}
	if in.LogoKey != nil && *in.LogoKey == "" {
		in.LogoKey = nil
	}
	return nil
}

// Create crée une boutique en attente de validation et donne le rôle marchand à son créateur.
func (s *Service) Create(ctx context.Context, ownerID uuid.UUID, in Input) (Shop, error) {
	if err := s.validate(ctx, ownerID, &in, nil); err != nil {
		return Shop{}, err
	}
	var out Shop
	err := s.db.InTx(ctx, func(ctx context.Context) error {
		q := store.New(s.db.Conn(ctx))
		n, err := q.CountShopsByOwner(ctx, ownerID)
		if err != nil {
			return fmt.Errorf("décompte des boutiques : %w", err)
		}
		if n >= maxShopsPerOwner {
			return apperr.Conflict("too_many_shops", "Vous avez atteint le nombre maximal de boutiques.")
		}
		id, err := q.CreateShop(ctx, store.CreateShopParams{
			OwnerID: ownerID, Name: in.Name, Description: in.Description, Phone: in.Phone,
			AddressText: in.AddressText, NeighborhoodID: in.NeighborhoodID,
			Lat: in.Location.Lat, Lng: in.Location.Lng, LogoKey: in.LogoKey, CategoryID: in.CategoryID,
		})
		if err != nil {
			return fmt.Errorf("création de la boutique : %w", err)
		}
		if err := s.users.GrantRole(ctx, ownerID, identity.RoleSeller, nil); err != nil {
			return err
		}
		out, err = s.get(ctx, id)
		if err != nil {
			return err
		}
		return s.notify.NotifyAdmins(ctx, "shop_pending_review", "Nouvelle boutique à valider",
			out.Name+" attend votre validation.", map[string]string{"shop_id": id.String()})
	})
	return out, err
}

// Update modifie une boutique de son propriétaire.
func (s *Service) Update(ctx context.Context, ownerID, shopID uuid.UUID, in Input) (Shop, error) {
	cur, err := s.RequireOwned(ctx, ownerID, shopID)
	if err != nil {
		return Shop{}, err
	}
	if err := s.validate(ctx, ownerID, &in, &cur); err != nil {
		return Shop{}, err
	}
	accepting := cur.AcceptingOrders
	if in.AcceptingOrders != nil {
		accepting = *in.AcceptingOrders
	}
	err = store.New(s.db.Conn(ctx)).UpdateShop(ctx, store.UpdateShopParams{
		ID: shopID, Name: in.Name, Description: in.Description, Phone: in.Phone, AddressText: in.AddressText,
		NeighborhoodID: in.NeighborhoodID, Lat: in.Location.Lat, Lng: in.Location.Lng, LogoKey: in.LogoKey,
		CategoryID: in.CategoryID, AcceptingOrders: accepting,
	})
	if err != nil {
		return Shop{}, fmt.Errorf("mise à jour de la boutique : %w", err)
	}
	return s.get(ctx, shopID)
}

// ListMine retourne les boutiques de l'utilisateur.
func (s *Service) ListMine(ctx context.Context, ownerID uuid.UUID) ([]Shop, error) {
	rows, err := store.New(s.db.Conn(ctx)).ListShopsByOwner(ctx, ownerID)
	if err != nil {
		return nil, fmt.Errorf("liste des boutiques : %w", err)
	}
	out := make([]Shop, len(rows))
	for i, r := range rows {
		if out[i], err = s.fromRow(ctx, store.GetShopRow(r)); err != nil {
			return nil, err
		}
	}
	return out, nil
}

// OwnedShopIDs retourne les identifiants des boutiques d'un utilisateur (toutes, même suspendues).
func (s *Service) OwnedShopIDs(ctx context.Context, ownerID uuid.UUID) ([]uuid.UUID, error) {
	ids, err := store.New(s.db.Conn(ctx)).ListShopIDsByOwner(ctx, ownerID)
	if err != nil {
		return nil, fmt.Errorf("liste des boutiques : %w", err)
	}
	return ids, nil
}

// Get retourne une boutique quel que soit son statut (usage interne et admin).
func (s *Service) Get(ctx context.Context, id uuid.UUID) (Shop, error) { return s.get(ctx, id) }

// GetForViewer retourne une boutique publiée, ou n'importe quelle boutique à son propriétaire.
func (s *Service) GetForViewer(ctx context.Context, viewer *identity.Principal, id uuid.UUID) (Shop, bool, error) {
	shop, err := s.get(ctx, id)
	if err != nil {
		return Shop{}, false, err
	}
	isOwner := viewer != nil && viewer.UserID == shop.OwnerID
	if shop.Status != StatusPublished && !isOwner {
		return Shop{}, false, errNotFound
	}
	return shop, isOwner, nil
}

// RequirePublished retourne une boutique publiée (catalogue, panier, commande).
func (s *Service) RequirePublished(ctx context.Context, id uuid.UUID) (Shop, error) {
	shop, err := s.get(ctx, id)
	if err != nil {
		return Shop{}, err
	}
	if shop.Status != StatusPublished {
		return Shop{}, errNotFound
	}
	return shop, nil
}

// RequireOwned retourne la boutique si l'utilisateur en est propriétaire et qu'elle n'est pas
// suspendue. La boutique d'un autre est introuvable (404).
func (s *Service) RequireOwned(ctx context.Context, ownerID, shopID uuid.UUID) (Shop, error) {
	shop, err := s.get(ctx, shopID)
	if err != nil {
		return Shop{}, err
	}
	if shop.OwnerID != ownerID {
		return Shop{}, errNotFound
	}
	if shop.Status == StatusSuspended {
		return Shop{}, errSuspended
	}
	return shop, nil
}

// AdminList liste les boutiques pour le back-office.
func (s *Service) AdminList(ctx context.Context, status Status, q string, limit, offset int32) ([]Shop, error) {
	var st, search *string
	if status != "" {
		v := string(status)
		st = &v
	}
	if q != "" {
		search = &q
	}
	rows, err := store.New(s.db.Conn(ctx)).ListShopsByStatus(ctx, store.ListShopsByStatusParams{Status: st, Q: search, Lim: limit, Off: offset})
	if err != nil {
		return nil, fmt.Errorf("liste des boutiques : %w", err)
	}
	out := make([]Shop, len(rows))
	for i, r := range rows {
		if out[i], err = s.fromRow(ctx, store.GetShopRow(r)); err != nil {
			return nil, err
		}
	}
	return out, nil
}

// Décisions de l'admin : transitions permises.
var reviewTransitions = map[string]struct {
	from   []string
	to     Status
	notify string
}{
	"approve":   {from: []string{"pending_review", "rejected"}, to: StatusPublished, notify: "Votre boutique est publiée : les acheteurs peuvent la voir."},
	"reject":    {from: []string{"pending_review"}, to: StatusRejected, notify: "Votre boutique n'a pas été validée."},
	"suspend":   {from: []string{"published"}, to: StatusSuspended, notify: "Votre boutique est suspendue."},
	"reinstate": {from: []string{"suspended"}, to: StatusPublished, notify: "Votre boutique est de nouveau publiée."},
}

// Review applique une décision admin (approve, reject, suspend, reinstate), journalisée et notifiée.
func (s *Service) Review(ctx context.Context, adminID, shopID uuid.UUID, decision, reason string) (Shop, error) {
	t, ok := reviewTransitions[decision]
	if !ok {
		return Shop{}, fmt.Errorf("décision inconnue : %s", decision)
	}
	reason = validate.Clean(reason)
	if (decision == "reject" || decision == "suspend") && reason == "" {
		return Shop{}, apperr.Validation(map[string]string{"reason": "Indiquez le motif (il sera communiqué au marchand)."})
	}
	var out Shop
	err := s.db.InTx(ctx, func(ctx context.Context) error {
		before, err := s.get(ctx, shopID)
		if err != nil {
			return err
		}
		n, err := store.New(s.db.Conn(ctx)).SetShopStatus(ctx, store.SetShopStatusParams{
			ID: shopID, NewStatus: string(t.to), Reason: reason, ReviewedBy: &adminID, FromStatuses: t.from,
		})
		if err != nil {
			return fmt.Errorf("changement de statut de la boutique : %w", err)
		}
		if n == 0 {
			return apperr.Conflict("invalid_shop_transition", "Action impossible pour une boutique au statut « "+string(before.Status)+" ».")
		}
		if out, err = s.get(ctx, shopID); err != nil {
			return err
		}
		if err := s.audit.Record(ctx, admin.AuditEntry{
			AdminID: &adminID, Action: "shop." + decision, TargetType: "shop", TargetID: shopID.String(),
			Before: map[string]any{"status": before.Status}, After: map[string]any{"status": out.Status}, Reason: reason,
		}); err != nil {
			return err
		}
		body := t.notify
		if reason != "" {
			body += " Motif : " + reason
		}
		return s.notify.Notify(ctx, notifications.Message{
			UserID: out.OwnerID, App: notifications.AppSeller, Kind: "shop_" + decision,
			Title: out.Name, Body: body, Data: map[string]string{"shop_id": shopID.String()},
		})
	})
	return out, err
}

// OnAccountDeleted suspend les boutiques d'un marchand qui supprime son compte (users.DeletionHook).
func (s *Service) OnAccountDeleted(ctx context.Context, userID uuid.UUID) error {
	err := store.New(s.db.Conn(ctx)).SuspendShopsOfOwner(ctx, store.SuspendShopsOfOwnerParams{OwnerID: userID, Reason: "Compte du marchand supprimé."})
	if err != nil {
		return fmt.Errorf("suspension des boutiques : %w", err)
	}
	return nil
}

func (s *Service) get(ctx context.Context, id uuid.UUID) (Shop, error) {
	r, err := store.New(s.db.Conn(ctx)).GetShop(ctx, id)
	if database.IsNoRows(err) {
		return Shop{}, errNotFound
	}
	if err != nil {
		return Shop{}, fmt.Errorf("lecture de la boutique : %w", err)
	}
	return s.fromRow(ctx, r)
}

func (s *Service) fromRow(ctx context.Context, r store.GetShopRow) (Shop, error) {
	shop := Shop{
		ID: r.ID, OwnerID: r.OwnerID, Name: r.Name, Description: r.Description, Phone: r.Phone,
		AddressText: r.AddressText, NeighborhoodID: r.NeighborhoodID, Location: geo.Point{Lat: r.Lat, Lng: r.Lng},
		LogoKey: r.LogoKey, Status: Status(r.Status), StatusReason: r.StatusReason, AcceptingOrders: r.AcceptingOrders,
		ReviewedAt: r.ReviewedAt, CreatedAt: r.CreatedAt, UpdatedAt: r.UpdatedAt,
		CategoryID: r.CategoryID, CategoryName: r.CategoryName,
	}
	if r.LogoKey != nil {
		u := s.uploads.PublicURL(*r.LogoKey)
		shop.LogoURL = &u
	}
	if r.NeighborhoodID != nil {
		n, err := s.geo.Get(ctx, *r.NeighborhoodID)
		if err != nil {
			return Shop{}, err
		}
		shop.NeighborhoodName = n.Name
	}
	return shop, nil
}
