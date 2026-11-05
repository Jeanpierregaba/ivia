// Package users gère les comptes, rôles, adresses de livraison, jetons push et la suppression
// de compte.
package users

import (
	"context"
	"fmt"
	"slices"
	"time"

	"github.com/google/uuid"

	"ivia/backend/internal/admin"
	"ivia/backend/internal/geo"
	"ivia/backend/internal/platform/apperr"
	"ivia/backend/internal/platform/database"
	"ivia/backend/internal/platform/identity"
	"ivia/backend/internal/platform/validate"
	"ivia/backend/internal/users/store"
)

// User est le profil d'un utilisateur, tel que vu par lui-même ou par un admin.
type User struct {
	ID        uuid.UUID       `json:"id"`
	Email     *string         `json:"email"`
	Phone     *string         `json:"phone"`
	FirstName string          `json:"first_name"`
	LastName  string          `json:"last_name"`
	Roles     []identity.Role `json:"roles"`
	// PrivacyConsentAt : date d'acceptation de la politique de confidentialité.
	PrivacyConsentAt *time.Time `json:"privacy_consent_at"`
	// AvatarURL : photo de profil, ou null.
	AvatarURL *string `json:"avatar_url"`
	// PhoneVerified : numéro prouvé par un code (WhatsApp ou SMS) ; c'est alors l'identifiant de
	// connexion, qui ne se change qu'avec un nouveau code.
	PhoneVerified bool `json:"phone_verified"`
	// ProfileComplete : prénom, téléphone et consentement renseignés.
	ProfileComplete bool      `json:"profile_complete"`
	CreatedAt       time.Time `json:"created_at"`
}

// Contact est ce qu'un autre acteur peut connaître d'un utilisateur, selon le contexte.
type Contact struct {
	FirstName string
	Phone     string
}

// ProfileInput modifie le profil.
type ProfileInput struct {
	FirstName *string `json:"first_name"`
	LastName  *string `json:"last_name"`
	Phone     *string `json:"phone"`
	// AcceptPrivacyPolicy : true enregistre le consentement ; false est refusé.
	AcceptPrivacyPolicy *bool `json:"accept_privacy_policy"`
	// AvatarKey : photo de profil envoyée avec l'usage « avatar » ; "" la retire.
	AvatarKey *string `json:"avatar_key"`
}

// Avatars vérifie les photos de profil envoyées et donne leur adresse publique (module uploads).
type Avatars interface {
	CheckAvatar(ctx context.Context, userID uuid.UUID, key string) error
	PublicURL(key string) string
}

// SetAvatars branche le stockage des photos de profil.
func (s *Service) SetAvatars(a Avatars) { s.avatars = a }

// DeletionGuard refuse la suppression d'un compte qui a une activité en cours (commande, mission).
type DeletionGuard interface {
	CheckAccountDeletable(ctx context.Context, userID uuid.UUID) error
}

// DeletionHook efface ou anonymise les données d'un module lors de la suppression d'un compte.
// Appelé dans la transaction de suppression.
type DeletionHook interface {
	OnAccountDeleted(ctx context.Context, userID uuid.UUID) error
}

// Service gère les comptes.
type Service struct {
	db      *database.DB
	geo     *geo.Service
	audit   *admin.Service
	guards  []DeletionGuard
	hooks   []DeletionHook
	avatars Avatars
}

// NewService crée le service.
func NewService(db *database.DB, geoSvc *geo.Service, audit *admin.Service) *Service {
	return &Service{db: db, geo: geoSvc, audit: audit}
}

// AddDeletionGuard enregistre un module qui peut bloquer la suppression d'un compte (au démarrage).
func (s *Service) AddDeletionGuard(g DeletionGuard) { s.guards = append(s.guards, g) }

// AddDeletionHook enregistre un module à prévenir lors d'une suppression de compte (au démarrage).
func (s *Service) AddDeletionHook(h DeletionHook) { s.hooks = append(s.hooks, h) }

var errUserNotFound = apperr.NotFound("user_not_found", "Utilisateur introuvable.")

// FindOrCreateByEmail retourne le compte lié à l'e-mail, en le créant (rôle buyer) s'il n'existe pas.
func (s *Service) FindOrCreateByEmail(ctx context.Context, email string) (User, bool, error) {
	var (
		out     User
		created bool
	)
	err := s.db.InTx(ctx, func(ctx context.Context) error {
		q := store.New(s.db.Conn(ctx))
		row, err := q.CreateUser(ctx, &email)
		switch {
		case err == nil:
			if err := q.GrantRole(ctx, store.GrantRoleParams{UserID: row.ID, Role: string(identity.RoleBuyer)}); err != nil {
				return fmt.Errorf("attribution du rôle buyer : %w", err)
			}
			created = true
		case database.IsNoRows(err):
			// Compte existant (ou créé à l'instant par une requête simultanée).
			if row, err = q.GetUserByEmail(ctx, &email); err != nil {
				return fmt.Errorf("lecture du compte : %w", err)
			}
		default:
			return fmt.Errorf("création du compte : %w", err)
		}
		out, err = s.withRoles(ctx, row)
		return err
	})
	return out, created, err
}

// FindByEmail retourne le compte actif lié à l'e-mail (normalisé), sans le créer.
func (s *Service) FindByEmail(ctx context.Context, email string) (User, error) {
	row, err := store.New(s.db.Conn(ctx)).GetUserByEmail(ctx, &email)
	if database.IsNoRows(err) {
		return User{}, errUserNotFound
	}
	if err != nil {
		return User{}, fmt.Errorf("lecture du compte : %w", err)
	}
	return s.withRoles(ctx, row)
}

// FindByPhone retourne le compte actif lié au numéro (normalisé), sans le créer.
func (s *Service) FindByPhone(ctx context.Context, phone string) (User, error) {
	row, err := store.New(s.db.Conn(ctx)).GetUserByPhone(ctx, &phone)
	if database.IsNoRows(err) {
		return User{}, errUserNotFound
	}
	if err != nil {
		return User{}, fmt.Errorf("lecture du compte : %w", err)
	}
	return s.withRoles(ctx, row)
}

// MarkPhoneVerified note que le numéro du compte a été prouvé par un code.
func (s *Service) MarkPhoneVerified(ctx context.Context, id uuid.UUID) error {
	if err := store.New(s.db.Conn(ctx)).MarkPhoneVerified(ctx, id); err != nil {
		return fmt.Errorf("vérification du numéro : %w", err)
	}
	return nil
}

// PhoneSignup est le profil saisi à la création d'un compte par numéro.
type PhoneSignup struct {
	FirstName           string `json:"first_name"`
	LastName            string `json:"last_name"`
	AcceptPrivacyPolicy bool   `json:"accept_privacy_policy"`
}

// ValidatePhoneSignup contrôle le profil avant la création du compte.
func ValidatePhoneSignup(in *PhoneSignup) error {
	in.FirstName, in.LastName = validate.Clean(in.FirstName), validate.Clean(in.LastName)
	v := validate.New()
	v.Text("first_name", in.FirstName, 1, 100)
	v.Text("last_name", in.LastName, 1, 100)
	if !in.AcceptPrivacyPolicy {
		v.Add("accept_privacy_policy", "Acceptez la politique de confidentialité pour créer votre compte.")
	}
	return v.Err()
}

// CreateWithPhone crée un compte acheteur dont le numéro vient d'être vérifié. created vaut faux
// si le numéro avait déjà un compte (inscription simultanée) : ce compte est alors retourné.
func (s *Service) CreateWithPhone(ctx context.Context, phone string, in PhoneSignup) (User, bool, error) {
	if err := ValidatePhoneSignup(&in); err != nil {
		return User{}, false, err
	}
	var (
		out     User
		created bool
	)
	err := s.db.InTx(ctx, func(ctx context.Context) error {
		q := store.New(s.db.Conn(ctx))
		row, err := q.CreateUserWithPhone(ctx, store.CreateUserWithPhoneParams{Phone: &phone, FirstName: in.FirstName, LastName: in.LastName})
		switch {
		case err == nil:
			if err := q.GrantRole(ctx, store.GrantRoleParams{UserID: row.ID, Role: string(identity.RoleBuyer)}); err != nil {
				return fmt.Errorf("attribution du rôle buyer : %w", err)
			}
			created = true
		case database.IsNoRows(err):
			if row, err = q.GetUserByPhone(ctx, &phone); err != nil {
				return fmt.Errorf("lecture du compte : %w", err)
			}
		default:
			return fmt.Errorf("création du compte : %w", err)
		}
		out, err = s.withRoles(ctx, row)
		return err
	})
	return out, created, err
}

// SetVerifiedPhone remplace le numéro du compte par un numéro prouvé par un code.
func (s *Service) SetVerifiedPhone(ctx context.Context, id uuid.UUID, phone string) (User, error) {
	row, err := store.New(s.db.Conn(ctx)).SetVerifiedPhone(ctx, store.SetVerifiedPhoneParams{ID: id, Phone: &phone})
	if database.IsUniqueViolation(err, "users_phone_key") {
		return User{}, apperr.Conflict("phone_taken", "Ce numéro est déjà utilisé par un autre compte.")
	}
	if database.IsNoRows(err) {
		return User{}, errUserNotFound
	}
	if err != nil {
		return User{}, fmt.Errorf("changement de numéro : %w", err)
	}
	return s.withRoles(ctx, row)
}

// Get retourne le profil d'un utilisateur actif.
func (s *Service) Get(ctx context.Context, id uuid.UUID) (User, error) {
	row, err := store.New(s.db.Conn(ctx)).GetUser(ctx, id)
	if database.IsNoRows(err) || (err == nil && row.DeletedAt != nil) {
		return User{}, errUserNotFound
	}
	if err != nil {
		return User{}, fmt.Errorf("lecture du compte : %w", err)
	}
	return s.withRoles(ctx, row)
}

// Roles retourne les rôles d'un utilisateur actif (utilisé à chaque requête authentifiée).
func (s *Service) Roles(ctx context.Context, id uuid.UUID) ([]identity.Role, error) {
	u, err := s.Get(ctx, id)
	if err != nil {
		return nil, err
	}
	return u.Roles, nil
}

// Contact retourne le prénom et le numéro d'un utilisateur. Les modules appelants décident de ce
// qu'ils exposent (le livreur pendant sa mission ; jamais le numéro au marchand).
func (s *Service) Contact(ctx context.Context, id uuid.UUID) (Contact, error) {
	row, err := store.New(s.db.Conn(ctx)).GetUser(ctx, id)
	if database.IsNoRows(err) {
		return Contact{}, errUserNotFound
	}
	if err != nil {
		return Contact{}, fmt.Errorf("lecture du compte : %w", err)
	}
	c := Contact{FirstName: row.FirstName}
	if row.Phone != nil {
		c.Phone = *row.Phone
	}
	return c, nil
}

// UpdateProfile modifie prénom, nom et numéro.
func (s *Service) UpdateProfile(ctx context.Context, id uuid.UUID, in ProfileInput) (User, error) {
	cur, err := store.New(s.db.Conn(ctx)).GetUser(ctx, id)
	if err != nil || cur.DeletedAt != nil {
		return User{}, errUserNotFound
	}
	first, last, phone := cur.FirstName, cur.LastName, cur.Phone
	v := validate.New()
	if in.FirstName != nil {
		first = validate.Clean(*in.FirstName)
		v.Text("first_name", first, 1, 100)
	}
	if in.LastName != nil {
		last = validate.Clean(*in.LastName)
		v.Text("last_name", last, 0, 100)
	}
	if in.Phone != nil && cur.PhoneVerifiedAt != nil {
		// Le numéro vérifié est l'identifiant de connexion : il ne change qu'avec un code.
		if p, ok := validate.NormalizeTogoPhone(*in.Phone); !ok || cur.Phone == nil || p != *cur.Phone {
			v.Add("phone", "Pour changer de numéro, confirmez le nouveau avec un code (« Changer de numéro »).")
		}
	} else if in.Phone != nil {
		if *in.Phone == "" {
			phone = nil
		} else if p, ok := validate.NormalizeTogoPhone(*in.Phone); ok {
			phone = &p
		} else {
			v.Add("phone", "Numéro mobile togolais attendu (8 chiffres commençant par 7 ou 9).")
		}
	}
	accept := in.AcceptPrivacyPolicy != nil && *in.AcceptPrivacyPolicy
	if in.AcceptPrivacyPolicy != nil && !accept {
		v.Add("accept_privacy_policy", "Pour retirer votre consentement, supprimez votre compte.")
	}
	if err := v.Err(); err != nil {
		return User{}, err
	}
	if in.AvatarKey != nil {
		var key *string
		if *in.AvatarKey != "" {
			if s.avatars == nil {
				return User{}, apperr.Validation(map[string]string{"avatar_key": "Photo de profil indisponible."})
			}
			if err := s.avatars.CheckAvatar(ctx, id, *in.AvatarKey); err != nil {
				return User{}, err
			}
			key = in.AvatarKey
		}
		if _, err := store.New(s.db.Conn(ctx)).SetAvatar(ctx, store.SetAvatarParams{ID: id, AvatarKey: key}); err != nil {
			return User{}, fmt.Errorf("photo de profil : %w", err)
		}
	}
	row, err := store.New(s.db.Conn(ctx)).UpdateProfile(ctx, store.UpdateProfileParams{
		ID: id, FirstName: first, LastName: last, Phone: phone, AcceptPrivacyPolicy: accept,
	})
	if database.IsUniqueViolation(err, "users_phone_key") {
		return User{}, apperr.Conflict("phone_taken", "Ce numéro est déjà utilisé par un autre compte.")
	}
	if err != nil {
		return User{}, fmt.Errorf("mise à jour du profil : %w", err)
	}
	return s.withRoles(ctx, row)
}

// GrantRole ajoute un rôle. grantedBy nil : attribution automatique (création de boutique).
func (s *Service) GrantRole(ctx context.Context, userID uuid.UUID, role identity.Role, grantedBy *uuid.UUID) error {
	if !role.Valid() {
		return fmt.Errorf("rôle inconnu : %q", role)
	}
	err := store.New(s.db.Conn(ctx)).GrantRole(ctx, store.GrantRoleParams{UserID: userID, Role: string(role), GrantedBy: grantedBy})
	if err != nil {
		return fmt.Errorf("attribution du rôle %s : %w", role, err)
	}
	return nil
}

// RevokeRole retire un rôle (sans effet s'il est absent).
func (s *Service) RevokeRole(ctx context.Context, userID uuid.UUID, role identity.Role) error {
	if _, err := store.New(s.db.Conn(ctx)).RevokeRole(ctx, store.RevokeRoleParams{UserID: userID, Role: string(role)}); err != nil {
		return fmt.Errorf("retrait du rôle %s : %w", role, err)
	}
	return nil
}

// UserIDsWithRole liste les comptes actifs ayant un rôle (ex. tous les admins à alerter).
func (s *Service) UserIDsWithRole(ctx context.Context, role identity.Role) ([]uuid.UUID, error) {
	ids, err := store.New(s.db.Conn(ctx)).ListUserIDsByRole(ctx, string(role))
	if err != nil {
		return nil, fmt.Errorf("liste des comptes %s : %w", role, err)
	}
	return ids, nil
}

// DeleteAccount supprime le compte : sessions révoquées, données personnelles effacées ou
// anonymisées par chaque module, données financières conservées. Refusé si une commande ou une
// mission est en cours.
func (s *Service) DeleteAccount(ctx context.Context, id uuid.UUID) error {
	return s.db.InTx(ctx, func(ctx context.Context) error {
		if _, err := s.Get(ctx, id); err != nil {
			return err
		}
		for _, g := range s.guards {
			if err := g.CheckAccountDeletable(ctx, id); err != nil {
				return err
			}
		}
		for _, h := range s.hooks {
			if err := h.OnAccountDeleted(ctx, id); err != nil {
				return err
			}
		}
		q := store.New(s.db.Conn(ctx))
		if err := q.DeleteAllAddresses(ctx, id); err != nil {
			return fmt.Errorf("suppression des adresses : %w", err)
		}
		if err := q.DeleteAllDeviceTokens(ctx, id); err != nil {
			return fmt.Errorf("suppression des jetons push : %w", err)
		}
		if err := q.RevokeAllRoles(ctx, id); err != nil {
			return fmt.Errorf("retrait des rôles : %w", err)
		}
		if err := q.AnonymizeUser(ctx, id); err != nil {
			return fmt.Errorf("anonymisation du compte : %w", err)
		}
		return nil
	})
}

// AdminSearch liste les comptes pour le back-office.
func (s *Service) AdminSearch(ctx context.Context, q string, role string, limit, offset int32) ([]User, error) {
	rows, err := store.New(s.db.Conn(ctx)).SearchUsers(ctx, store.SearchUsersParams{
		Q: nilIfEmpty(q), Role: nilIfEmpty(role), Lim: limit, Off: offset,
	})
	if err != nil {
		return nil, fmt.Errorf("recherche de comptes : %w", err)
	}
	out := make([]User, len(rows))
	for i, r := range rows {
		roles := make([]identity.Role, len(r.Roles))
		for j, ro := range r.Roles {
			roles[j] = identity.Role(ro)
		}
		out[i] = toUser(store.User{
			ID: r.ID, Email: r.Email, Phone: r.Phone, FirstName: r.FirstName, LastName: r.LastName,
			PrivacyConsentAt: r.PrivacyConsentAt,
			DeletedAt:        r.DeletedAt, CreatedAt: r.CreatedAt, UpdatedAt: r.UpdatedAt,
		}, roles)
	}
	return out, nil
}

// AdminGrantAdmin donne le rôle admin (journalisé). grantedBy nil : ligne de commande d'administration.
func (s *Service) AdminGrantAdmin(ctx context.Context, grantedBy *uuid.UUID, userID uuid.UUID, reason string) (User, error) {
	var out User
	err := s.db.InTx(ctx, func(ctx context.Context) error {
		before, err := s.Get(ctx, userID)
		if err != nil {
			return err
		}
		if err := s.GrantRole(ctx, userID, identity.RoleAdmin, grantedBy); err != nil {
			return err
		}
		if out, err = s.Get(ctx, userID); err != nil {
			return err
		}
		return s.audit.Record(ctx, admin.AuditEntry{
			AdminID: grantedBy, Action: "user.grant_admin", TargetType: "user", TargetID: userID.String(),
			Before: map[string]any{"roles": before.Roles}, After: map[string]any{"roles": out.Roles}, Reason: reason,
		})
	})
	return out, err
}

// AdminRevokeAdmin retire le rôle admin (journalisé). On ne peut ni se le retirer à soi-même ni
// retirer le dernier admin.
func (s *Service) AdminRevokeAdmin(ctx context.Context, by, userID uuid.UUID, reason string) (User, error) {
	if by == userID {
		return User{}, apperr.Conflict("cannot_revoke_self", "Vous ne pouvez pas retirer votre propre rôle admin.")
	}
	var out User
	err := s.db.InTx(ctx, func(ctx context.Context) error {
		before, err := s.Get(ctx, userID)
		if err != nil {
			return err
		}
		if !slices.Contains(before.Roles, identity.RoleAdmin) {
			out = before
			return nil
		}
		n, err := store.New(s.db.Conn(ctx)).CountRoleHolders(ctx, string(identity.RoleAdmin))
		if err != nil {
			return fmt.Errorf("décompte des admins : %w", err)
		}
		if n <= 1 {
			return apperr.Conflict("last_admin", "Impossible de retirer le dernier admin.")
		}
		if err := s.RevokeRole(ctx, userID, identity.RoleAdmin); err != nil {
			return err
		}
		if out, err = s.Get(ctx, userID); err != nil {
			return err
		}
		return s.audit.Record(ctx, admin.AuditEntry{
			AdminID: &by, Action: "user.revoke_admin", TargetType: "user", TargetID: userID.String(),
			Before: map[string]any{"roles": before.Roles}, After: map[string]any{"roles": out.Roles}, Reason: reason,
		})
	})
	return out, err
}

func (s *Service) withRoles(ctx context.Context, row store.User) (User, error) {
	rs, err := store.New(s.db.Conn(ctx)).ListRoles(ctx, row.ID)
	if err != nil {
		return User{}, fmt.Errorf("lecture des rôles : %w", err)
	}
	roles := make([]identity.Role, len(rs))
	for i, r := range rs {
		roles[i] = identity.Role(r)
	}
	u := toUser(row, roles)
	if row.AvatarKey != nil && s.avatars != nil {
		url := s.avatars.PublicURL(*row.AvatarKey)
		u.AvatarURL = &url
	}
	return u, nil
}

func toUser(row store.User, roles []identity.Role) User {
	return User{
		ID: row.ID, Email: row.Email, Phone: row.Phone, FirstName: row.FirstName, LastName: row.LastName,
		Roles: roles, PrivacyConsentAt: row.PrivacyConsentAt, PhoneVerified: row.PhoneVerifiedAt != nil,
		ProfileComplete: row.FirstName != "" && row.Phone != nil && row.PrivacyConsentAt != nil,
		CreatedAt:       row.CreatedAt,
	}
}

func nilIfEmpty(s string) *string {
	if s == "" {
		return nil
	}
	return &s
}
