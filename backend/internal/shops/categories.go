package shops

import (
	"context"
	"fmt"

	"github.com/google/uuid"

	"ivia/backend/internal/admin"
	"ivia/backend/internal/platform/apperr"
	"ivia/backend/internal/platform/database"
	"ivia/backend/internal/platform/validate"
	"ivia/backend/internal/shops/store"
)

// AdminCategory est une catégorie de boutique vue par l'admin (actives et désactivées).
type AdminCategory struct {
	ID       uuid.UUID `json:"id"`
	Name     string    `json:"name"`
	Position int32     `json:"position"`
	IsActive bool      `json:"is_active"`
}

// CategoryInput crée ou modifie une catégorie de boutique.
type CategoryInput struct {
	Name     string `json:"name"`
	Position int32  `json:"position"`
	IsActive *bool  `json:"is_active"`
}

func toAdminCategory(r store.ShopCategory) AdminCategory {
	return AdminCategory{ID: r.ID, Name: r.Name, Position: r.Position, IsActive: r.IsActive}
}

func validateCategory(in *CategoryInput) error {
	in.Name = validate.Clean(in.Name)
	v := validate.New()
	v.Text("name", in.Name, 1, 60)
	v.Check(in.Position >= 0 && in.Position <= 10000, "position", "Entre 0 et 10000.")
	return v.Err()
}

// AdminListCategories retourne toutes les catégories de boutique.
func (s *Service) AdminListCategories(ctx context.Context) ([]AdminCategory, error) {
	rows, err := store.New(s.db.Conn(ctx)).ListAllShopCategories(ctx)
	if err != nil {
		return nil, fmt.Errorf("lecture des catégories de boutique : %w", err)
	}
	out := make([]AdminCategory, len(rows))
	for i, r := range rows {
		out[i] = toAdminCategory(r)
	}
	return out, nil
}

// CreateCategory ajoute une catégorie de boutique (journalisé).
func (s *Service) CreateCategory(ctx context.Context, adminID uuid.UUID, in CategoryInput) (AdminCategory, error) {
	if err := validateCategory(&in); err != nil {
		return AdminCategory{}, err
	}
	var out AdminCategory
	err := s.db.InTx(ctx, func(ctx context.Context) error {
		row, err := store.New(s.db.Conn(ctx)).CreateShopCategory(ctx, store.CreateShopCategoryParams{Name: in.Name, Position: in.Position})
		if database.IsUniqueViolation(err, "") {
			return apperr.Conflict("shop_category_exists", "Cette catégorie de boutique existe déjà.")
		}
		if err != nil {
			return fmt.Errorf("création de la catégorie de boutique : %w", err)
		}
		out = toAdminCategory(row)
		return s.audit.Record(ctx, admin.AuditEntry{
			AdminID: &adminID, Action: "shop_category.create", TargetType: "shop_category", TargetID: out.ID.String(), After: out,
		})
	})
	return out, err
}

// UpdateCategory modifie une catégorie de boutique (journalisé). La désactiver la retire des choix
// proposés aux marchands ; les boutiques qui l'ont la gardent.
func (s *Service) UpdateCategory(ctx context.Context, adminID, id uuid.UUID, in CategoryInput) (AdminCategory, error) {
	if err := validateCategory(&in); err != nil {
		return AdminCategory{}, err
	}
	var out AdminCategory
	err := s.db.InTx(ctx, func(ctx context.Context) error {
		q := store.New(s.db.Conn(ctx))
		cur, err := q.GetShopCategory(ctx, id)
		if database.IsNoRows(err) {
			return apperr.NotFound("shop_category_not_found", "Catégorie de boutique introuvable.")
		}
		if err != nil {
			return fmt.Errorf("lecture de la catégorie de boutique : %w", err)
		}
		active := cur.IsActive
		if in.IsActive != nil {
			active = *in.IsActive
		}
		row, err := q.UpdateShopCategory(ctx, store.UpdateShopCategoryParams{ID: id, Name: in.Name, Position: in.Position, IsActive: active})
		if database.IsUniqueViolation(err, "") {
			return apperr.Conflict("shop_category_exists", "Cette catégorie de boutique existe déjà.")
		}
		if err != nil {
			return fmt.Errorf("mise à jour de la catégorie de boutique : %w", err)
		}
		out = toAdminCategory(row)
		return s.audit.Record(ctx, admin.AuditEntry{
			AdminID: &adminID, Action: "shop_category.update", TargetType: "shop_category", TargetID: id.String(),
			Before: toAdminCategory(cur), After: out,
		})
	})
	return out, err
}
