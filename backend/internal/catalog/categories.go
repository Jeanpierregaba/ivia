package catalog

import (
	"context"
	"fmt"
	"time"

	"github.com/google/uuid"

	"ivia/backend/internal/admin"
	"ivia/backend/internal/catalog/store"
	"ivia/backend/internal/platform/apperr"
	"ivia/backend/internal/platform/database"
	"ivia/backend/internal/platform/validate"
)

// Category est une catégorie de produits (deux niveaux au plus).
type Category struct {
	ID        uuid.UUID  `json:"id"`
	Name      string     `json:"name"`
	ParentID  *uuid.UUID `json:"parent_id"`
	Position  int32      `json:"position"`
	IsActive  bool       `json:"is_active"`
	UpdatedAt time.Time  `json:"updated_at"`
}

// CategoryInput crée ou modifie une catégorie.
type CategoryInput struct {
	Name     string     `json:"name"`
	ParentID *uuid.UUID `json:"parent_id"`
	Position int32      `json:"position"`
	IsActive *bool      `json:"is_active"`
}

// ListCategories retourne les catégories (actives seulement, sauf includeInactive).
func (s *Service) ListCategories(ctx context.Context, includeInactive bool) ([]Category, error) {
	rows, err := store.New(s.db.Conn(ctx)).ListCategories(ctx, includeInactive)
	if err != nil {
		return nil, fmt.Errorf("liste des catégories : %w", err)
	}
	out := make([]Category, len(rows))
	for i, r := range rows {
		out[i] = toCategory(r)
	}
	return out, nil
}

func (s *Service) validateCategory(ctx context.Context, id *uuid.UUID, in *CategoryInput) error {
	in.Name = validate.Clean(in.Name)
	v := validate.New()
	v.Text("name", in.Name, 1, 100)
	v.Check(in.Position >= 0 && in.Position <= 10000, "position", "Entre 0 et 10000.")
	if err := v.Err(); err != nil {
		return err
	}
	if in.ParentID == nil {
		return nil
	}
	if id != nil && *in.ParentID == *id {
		return apperr.Validation(map[string]string{"parent_id": "Une catégorie ne peut pas être sa propre parente."})
	}
	parent, err := store.New(s.db.Conn(ctx)).GetCategory(ctx, *in.ParentID)
	if database.IsNoRows(err) {
		return apperr.Validation(map[string]string{"parent_id": "Catégorie parente inconnue."})
	}
	if err != nil {
		return fmt.Errorf("lecture de la catégorie : %w", err)
	}
	if parent.ParentID != nil {
		return apperr.Validation(map[string]string{"parent_id": "Deux niveaux de catégories au maximum."})
	}
	return nil
}

// CreateCategory ajoute une catégorie (admin, journalisé).
func (s *Service) CreateCategory(ctx context.Context, adminID uuid.UUID, in CategoryInput) (Category, error) {
	if err := s.validateCategory(ctx, nil, &in); err != nil {
		return Category{}, err
	}
	var out Category
	err := s.db.InTx(ctx, func(ctx context.Context) error {
		row, err := store.New(s.db.Conn(ctx)).CreateCategory(ctx, store.CreateCategoryParams{Name: in.Name, ParentID: in.ParentID, Position: in.Position})
		if database.IsUniqueViolation(err, "") {
			return apperr.Conflict("category_exists", "Cette catégorie existe déjà.")
		}
		if err != nil {
			return fmt.Errorf("création de la catégorie : %w", err)
		}
		out = toCategory(row)
		return s.audit.Record(ctx, admin.AuditEntry{
			AdminID: &adminID, Action: "category.create", TargetType: "category", TargetID: out.ID.String(), After: out,
		})
	})
	return out, err
}

// UpdateCategory modifie une catégorie (admin, journalisé). La désactiver la masque des listes de
// choix ; les produits existants la gardent.
func (s *Service) UpdateCategory(ctx context.Context, adminID, id uuid.UUID, in CategoryInput) (Category, error) {
	if err := s.validateCategory(ctx, &id, &in); err != nil {
		return Category{}, err
	}
	var out Category
	err := s.db.InTx(ctx, func(ctx context.Context) error {
		q := store.New(s.db.Conn(ctx))
		cur, err := q.GetCategory(ctx, id)
		if database.IsNoRows(err) {
			return apperr.NotFound("category_not_found", "Catégorie introuvable.")
		}
		if err != nil {
			return fmt.Errorf("lecture de la catégorie : %w", err)
		}
		active := cur.IsActive
		if in.IsActive != nil {
			active = *in.IsActive
		}
		row, err := q.UpdateCategory(ctx, store.UpdateCategoryParams{ID: id, Name: in.Name, ParentID: in.ParentID, Position: in.Position, IsActive: active})
		if database.IsUniqueViolation(err, "") {
			return apperr.Conflict("category_exists", "Cette catégorie existe déjà.")
		}
		if err != nil {
			return fmt.Errorf("mise à jour de la catégorie : %w", err)
		}
		out = toCategory(row)
		return s.audit.Record(ctx, admin.AuditEntry{
			AdminID: &adminID, Action: "category.update", TargetType: "category", TargetID: id.String(),
			Before: toCategory(cur), After: out,
		})
	})
	return out, err
}

func toCategory(r store.Category) Category {
	return Category{ID: r.ID, Name: r.Name, ParentID: r.ParentID, Position: r.Position, IsActive: r.IsActive, UpdatedAt: r.UpdatedAt}
}
