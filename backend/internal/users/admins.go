package users

import (
	"context"
	"fmt"
	"net/http"
	"slices"
	"strings"
	"time"

	"github.com/google/uuid"

	"ivia/backend/internal/admin"
	"ivia/backend/internal/platform/adminperm"
	"ivia/backend/internal/platform/apperr"
	"ivia/backend/internal/platform/database"
	"ivia/backend/internal/platform/httpapi"
	"ivia/backend/internal/platform/identity"
	"ivia/backend/internal/platform/validate"
	"ivia/backend/internal/users/store"
)

// Comptes admin à rôles (spec 039) : le super admin crée les autres comptes admin, chacun avec un
// rôle précis. Un compte admin est toujours un compte distinct : on ne rend jamais admin un compte
// client, marchand, livreur ou pharmacie (adresse déjà utilisée = refus).

// AdminAccount est un compte admin.
type AdminAccount struct {
	ID        uuid.UUID `json:"id"`
	Email     string    `json:"email"`
	FirstName string    `json:"first_name"`
	LastName  string    `json:"last_name"`
	Role      string    `json:"role"`
	RoleLabel string    `json:"role_label"`
	CreatedAt time.Time `json:"created_at"`
}

// AdminInput décrit un compte admin à créer.
type AdminInput struct {
	Email     string `json:"email"`
	FirstName string `json:"first_name"`
	LastName  string `json:"last_name"`
	Role      string `json:"role"`
}

// AdminRole donne le rôle admin d'un compte ("" : aucun).
func (s *Service) AdminRole(ctx context.Context, id uuid.UUID) (string, error) {
	role, err := store.New(s.db.Conn(ctx)).GetAdminRole(ctx, id)
	if database.IsNoRows(err) {
		return "", nil
	}
	if err != nil {
		return "", fmt.Errorf("rôle admin : %w", err)
	}
	return role, nil
}

// ListAdmins liste les comptes admin.
func (s *Service) ListAdmins(ctx context.Context) ([]AdminAccount, error) {
	rows, err := store.New(s.db.Conn(ctx)).ListAdmins(ctx)
	if err != nil {
		return nil, fmt.Errorf("comptes admin : %w", err)
	}
	out := make([]AdminAccount, len(rows))
	for i, r := range rows {
		email := ""
		if r.Email != nil {
			email = *r.Email
		}
		out[i] = AdminAccount{
			ID: r.ID, Email: email, FirstName: r.FirstName, LastName: r.LastName,
			Role: r.Role, RoleLabel: adminperm.Label(r.Role), CreatedAt: r.CreatedAt,
		}
	}
	return out, nil
}

func (s *Service) admin(ctx context.Context, id uuid.UUID) (AdminAccount, error) {
	list, err := s.ListAdmins(ctx)
	if err != nil {
		return AdminAccount{}, err
	}
	for _, a := range list {
		if a.ID == id {
			return a, nil
		}
	}
	return AdminAccount{}, apperr.NotFound("admin_not_found", "Compte admin introuvable.")
}

// CreateAdmin crée un compte admin (adresse jamais utilisée sur ivia), journalisé. Le nouvel
// admin choisit son mot de passe avec « Mot de passe oublié » sur la page de connexion.
func (s *Service) CreateAdmin(ctx context.Context, by uuid.UUID, in AdminInput) (AdminAccount, error) {
	v := validate.New()
	email, ok := validate.NormalizeEmail(in.Email)
	v.Check(ok, "email", "Adresse e-mail invalide.")
	in.FirstName, in.LastName = validate.Clean(in.FirstName), validate.Clean(in.LastName)
	v.Text("first_name", in.FirstName, 1, 60)
	v.Text("last_name", in.LastName, 1, 60)
	v.Check(adminperm.Valid(in.Role), "role", "Choisissez un rôle.")
	if err := v.Err(); err != nil {
		return AdminAccount{}, err
	}
	var id uuid.UUID
	err := s.db.InTx(ctx, func(ctx context.Context) error {
		if existing, err := s.FindByEmail(ctx, email); err == nil {
			if slices.Contains(existing.Roles, identity.RoleAdmin) {
				return apperr.Conflict("admin_exists", "Ce compte admin existe déjà : changez son rôle dans la liste.")
			}
			return apperr.Conflict("email_in_use", "Cette adresse appartient déjà à un compte ivia (client, marchand, livreur ou pharmacie). Un compte admin doit utiliser une adresse dédiée.")
		} else if !apperr.IsCode(err, "user_not_found") {
			return err
		}
		u, _, err := s.FindOrCreateByEmail(ctx, email)
		if err != nil {
			return err
		}
		id = u.ID
		if _, err := s.UpdateProfile(ctx, id, ProfileInput{FirstName: &in.FirstName, LastName: &in.LastName}); err != nil {
			return err
		}
		if err := s.GrantRole(ctx, id, identity.RoleAdmin, &by); err != nil {
			return err
		}
		if err := store.New(s.db.Conn(ctx)).UpsertAdminProfile(ctx, store.UpsertAdminProfileParams{UserID: id, Role: in.Role, CreatedBy: &by}); err != nil {
			return fmt.Errorf("rôle admin : %w", err)
		}
		return s.audit.Record(ctx, admin.AuditEntry{
			AdminID: &by, Action: "admin.create", TargetType: "user", TargetID: id.String(),
			After: map[string]any{"email": email, "role": in.Role},
		})
	})
	if err != nil {
		return AdminAccount{}, err
	}
	return s.admin(ctx, id)
}

// lastSuperAdmin refuse de retirer le dernier super admin.
func (s *Service) lastSuperAdmin(ctx context.Context, id uuid.UUID) error {
	role, err := s.AdminRole(ctx, id)
	if err != nil || role != adminperm.SuperAdmin {
		return err
	}
	n, err := store.New(s.db.Conn(ctx)).CountSuperAdmins(ctx)
	if err != nil {
		return fmt.Errorf("décompte des super admins : %w", err)
	}
	if n <= 1 {
		return apperr.Conflict("last_super_admin", "Il faut toujours au moins un super admin.")
	}
	return nil
}

// SetAdminRole change le rôle d'un autre compte admin, journalisé.
func (s *Service) SetAdminRole(ctx context.Context, by, id uuid.UUID, role string) (AdminAccount, error) {
	if by == id {
		return AdminAccount{}, apperr.Conflict("cannot_change_self", "Vous ne pouvez pas changer votre propre rôle.")
	}
	if !adminperm.Valid(role) {
		return AdminAccount{}, apperr.Validation(map[string]string{"role": "Rôle inconnu."})
	}
	err := s.db.InTx(ctx, func(ctx context.Context) error {
		before, err := s.admin(ctx, id)
		if err != nil {
			return err
		}
		if role != adminperm.SuperAdmin {
			if err := s.lastSuperAdmin(ctx, id); err != nil {
				return err
			}
		}
		if err := store.New(s.db.Conn(ctx)).UpsertAdminProfile(ctx, store.UpsertAdminProfileParams{UserID: id, Role: role, CreatedBy: &by}); err != nil {
			return fmt.Errorf("rôle admin : %w", err)
		}
		return s.audit.Record(ctx, admin.AuditEntry{
			AdminID: &by, Action: "admin.role", TargetType: "user", TargetID: id.String(),
			Before: map[string]any{"role": before.Role}, After: map[string]any{"role": role},
		})
	})
	if err != nil {
		return AdminAccount{}, err
	}
	return s.admin(ctx, id)
}

// RemoveAdmin retire l'accès au back-office d'un autre compte admin, journalisé.
func (s *Service) RemoveAdmin(ctx context.Context, by, id uuid.UUID) error {
	if by == id {
		return apperr.Conflict("cannot_revoke_self", "Vous ne pouvez pas retirer votre propre accès.")
	}
	return s.db.InTx(ctx, func(ctx context.Context) error {
		before, err := s.admin(ctx, id)
		if err != nil {
			return err
		}
		if err := s.lastSuperAdmin(ctx, id); err != nil {
			return err
		}
		if err := s.RevokeRole(ctx, id, identity.RoleAdmin); err != nil {
			return err
		}
		if err := store.New(s.db.Conn(ctx)).DeleteAdminProfile(ctx, id); err != nil {
			return fmt.Errorf("rôle admin : %w", err)
		}
		return s.audit.Record(ctx, admin.AuditEntry{
			AdminID: &by, Action: "admin.remove", TargetType: "user", TargetID: id.String(),
			Before: map[string]any{"email": before.Email, "role": before.Role},
		})
	})
}

// --- HTTP -------------------------------------------------------------------------------------

func (h *Handler) registerAdmins(rt *httpapi.Router) {
	rt.Roles("GET /v1/admin/me", h.adminMe, identity.RoleAdmin)
	rt.Roles("GET /v1/admin/admins", h.adminsList, identity.RoleAdmin)
	rt.Roles("POST /v1/admin/admins", h.adminsCreate, identity.RoleAdmin)
	rt.Roles("PUT /v1/admin/admins/{id}/role", h.adminsRole, identity.RoleAdmin)
	rt.Roles("DELETE /v1/admin/admins/{id}", h.adminsRemove, identity.RoleAdmin)
}

func (h *Handler) adminMe(w http.ResponseWriter, r *http.Request) error {
	p := identity.MustFromContext(r.Context())
	return httpapi.OK(w, map[string]any{
		"role": p.AdminRole, "role_label": adminperm.Label(p.AdminRole),
		"sections": adminperm.Sections(p.AdminRole), "roles": adminperm.Roles,
	})
}

func (h *Handler) adminsList(w http.ResponseWriter, r *http.Request) error {
	items, err := h.svc.ListAdmins(r.Context())
	if err != nil {
		return err
	}
	return httpapi.OK(w, map[string]any{"items": items, "roles": adminperm.Roles})
}

func (h *Handler) adminsCreate(w http.ResponseWriter, r *http.Request) error {
	var in AdminInput
	if err := httpapi.Decode(r, &in); err != nil {
		return err
	}
	in.Email = strings.TrimSpace(in.Email)
	a, err := h.svc.CreateAdmin(r.Context(), identity.MustFromContext(r.Context()).UserID, in)
	if err != nil {
		return err
	}
	return httpapi.Created(w, a)
}

func (h *Handler) adminsRole(w http.ResponseWriter, r *http.Request) error {
	id, err := httpapi.PathUUID(r, "id")
	if err != nil {
		return err
	}
	var in struct {
		Role string `json:"role"`
	}
	if err := httpapi.Decode(r, &in); err != nil {
		return err
	}
	a, err := h.svc.SetAdminRole(r.Context(), identity.MustFromContext(r.Context()).UserID, id, in.Role)
	if err != nil {
		return err
	}
	return httpapi.OK(w, a)
}

func (h *Handler) adminsRemove(w http.ResponseWriter, r *http.Request) error {
	id, err := httpapi.PathUUID(r, "id")
	if err != nil {
		return err
	}
	if err := h.svc.RemoveAdmin(r.Context(), identity.MustFromContext(r.Context()).UserID, id); err != nil {
		return err
	}
	return httpapi.NoContent(w)
}
