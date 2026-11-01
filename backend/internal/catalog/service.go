// Package catalog gère les catégories et les produits des boutiques (photos, prix, taille de colis,
// mode de stock).
package catalog

import (
	"context"
	"fmt"
	"slices"
	"strings"
	"time"

	"github.com/google/uuid"

	"ivia/backend/internal/admin"
	"ivia/backend/internal/catalog/store"
	"ivia/backend/internal/platform/apperr"
	"ivia/backend/internal/platform/database"
	"ivia/backend/internal/platform/validate"
	"ivia/backend/internal/shops"
	"ivia/backend/internal/stock"
	"ivia/backend/internal/uploads"
)

// ParcelSize est la taille de colis d'un produit ; elle détermine les véhicules compatibles.
type ParcelSize string

const (
	ParcelSmall  ParcelSize = "small"
	ParcelMedium ParcelSize = "medium"
	ParcelLarge  ParcelSize = "large"
)

// Rank ordonne les tailles (pour trouver la plus grande d'une commande).
func (p ParcelSize) Rank() int {
	return map[ParcelSize]int{ParcelSmall: 1, ParcelMedium: 2, ParcelLarge: 3}[p]
}

// StockMode : stock suivi (quantité connue) ou non suivi (le marchand confirme à chaque commande).
type StockMode string

const (
	StockTracked   StockMode = "tracked"
	StockUntracked StockMode = "untracked"
)

// maxImages par produit (la première est la photo principale).
const maxImages = 6

// Status est l'état de publication d'un produit, déduit de is_active et des dates.
type Status string

const (
	// StatusActive : en vente, visible des acheteurs si la boutique est publiée.
	StatusActive Status = "active"
	// StatusDraft : enregistré, jamais publié.
	StatusDraft Status = "draft"
	// StatusWithdrawn : publié puis retiré par le marchand.
	StatusWithdrawn Status = "withdrawn"
)

// SellerFilter filtre la liste du marchand. Status vide : tous les états ; Q : texte cherché
// dans le nom, sans accents ni majuscules.
type SellerFilter struct {
	Status Status
	Q      string
}

// Counts est le nombre de produits d'une boutique par état.
type Counts struct {
	Active    int64 `json:"active"`
	Draft     int64 `json:"draft"`
	Withdrawn int64 `json:"withdrawn"`
}

// Product est un produit avec ses photos et sa disponibilité.
type Product struct {
	ID          uuid.UUID  `json:"id"`
	ShopID      uuid.UUID  `json:"shop_id"`
	CategoryID  uuid.UUID  `json:"category_id"`
	Name        string     `json:"name"`
	Description string     `json:"description"`
	PriceXOF    int64      `json:"price_xof"`
	ParcelSize  ParcelSize `json:"parcel_size"`
	StockMode   StockMode  `json:"stock_mode"`
	// StockQuantity n'est renseigné que pour un stock suivi.
	StockQuantity *int32 `json:"stock_quantity"`
	Available     bool   `json:"available"`
	IsActive      bool   `json:"is_active"`
	Status        Status `json:"status"`
	// PublishedAt : dernière mise en vente (nil : brouillon).
	PublishedAt *time.Time `json:"published_at"`
	// WithdrawnAt : dernier retrait (nil : en vente ou brouillon).
	WithdrawnAt *time.Time `json:"withdrawn_at"`
	Images      []Image    `json:"images"`
	CreatedAt   time.Time  `json:"created_at"`
	UpdatedAt   time.Time  `json:"updated_at"`
}

// Image est une photo d'un produit.
type Image struct {
	URL       string `json:"url"`
	ObjectKey string `json:"object_key"`
	Position  int32  `json:"position"`
}

// ProductInput crée ou modifie un produit.
type ProductInput struct {
	CategoryID    uuid.UUID  `json:"category_id"`
	Name          string     `json:"name"`
	Description   string     `json:"description"`
	PriceXOF      int64      `json:"price_xof"`
	ParcelSize    ParcelSize `json:"parcel_size"`
	StockMode     StockMode  `json:"stock_mode"`
	StockQuantity *int32     `json:"stock_quantity"`
	// IsActive : en vente ou non. À la création, false crée un brouillon ; absent, le produit est
	// en vente. À la modification, absent garde l'état.
	IsActive  *bool    `json:"is_active"`
	ImageKeys []string `json:"image_keys"`
}

// Service gère le catalogue.
type Service struct {
	db      *database.DB
	shops   *shops.Service
	stock   *stock.Service
	uploads *uploads.Service
	audit   *admin.Service
}

// NewService crée le service.
func NewService(db *database.DB, shopSvc *shops.Service, stockSvc *stock.Service, up *uploads.Service, audit *admin.Service) *Service {
	return &Service{db: db, shops: shopSvc, stock: stockSvc, uploads: up, audit: audit}
}

var errProductNotFound = apperr.NotFound("product_not_found", "Produit introuvable.")

// validateProduct vérifie un produit. checkCategory : la catégorie doit être active (création,
// catégorie changée, produit en vente) ; un retrait reste possible si l'admin l'a désactivée.
func (s *Service) validateProduct(ctx context.Context, ownerID uuid.UUID, in *ProductInput, creating, checkCategory bool, currentKeys []string) error {
	in.Name = validate.Clean(in.Name)
	in.Description = validate.Clean(in.Description)
	v := validate.New()
	v.Text("name", in.Name, 2, 150)
	v.Text("description", in.Description, 0, 5000)
	v.Check(in.PriceXOF > 0 && in.PriceXOF <= 100_000_000, "price_xof", "Prix entre 1 et 100 000 000 FCFA.")
	v.Check(in.ParcelSize.Rank() > 0, "parcel_size", "Taille attendue : small, medium ou large.")
	if creating {
		v.Check(in.StockMode == StockTracked || in.StockMode == StockUntracked, "stock_mode", "Mode attendu : tracked ou untracked.")
		if in.StockMode == StockTracked {
			v.Check(in.StockQuantity != nil, "stock_quantity", "Indiquez la quantité disponible.")
		}
	}
	v.Check(len(in.ImageKeys) <= maxImages, "image_keys", "6 photos au maximum.")
	v.Check(!hasDuplicates(in.ImageKeys), "image_keys", "Photo en double.")
	if err := v.Err(); err != nil {
		return err
	}
	if checkCategory {
		cat, err := store.New(s.db.Conn(ctx)).GetCategory(ctx, in.CategoryID)
		if database.IsNoRows(err) || (err == nil && !cat.IsActive) {
			return apperr.Validation(map[string]string{"category_id": "Catégorie inconnue."})
		}
		if err != nil {
			return fmt.Errorf("lecture de la catégorie : %w", err)
		}
	}
	for _, k := range in.ImageKeys {
		if slices.Contains(currentKeys, k) {
			continue
		}
		if err := s.uploads.Check(ctx, uploads.ProductImage, ownerID, k, "image_keys"); err != nil {
			return err
		}
	}
	return nil
}

// Create ajoute un produit à une boutique du marchand.
func (s *Service) Create(ctx context.Context, ownerID, shopID uuid.UUID, in ProductInput) (Product, error) {
	if _, err := s.shops.RequireOwned(ctx, ownerID, shopID); err != nil {
		return Product{}, err
	}
	if err := s.validateProduct(ctx, ownerID, &in, true, true, nil); err != nil {
		return Product{}, err
	}
	active := in.IsActive == nil || *in.IsActive
	var id uuid.UUID
	err := s.db.InTx(ctx, func(ctx context.Context) error {
		q := store.New(s.db.Conn(ctx))
		var err error
		id, err = q.CreateProduct(ctx, store.CreateProductParams{
			ShopID: shopID, CategoryID: in.CategoryID, Name: in.Name, Description: in.Description,
			PriceXof: in.PriceXOF, ParcelSize: string(in.ParcelSize), StockMode: string(in.StockMode),
			IsActive: active,
		})
		if err != nil {
			return fmt.Errorf("création du produit : %w", err)
		}
		if err := s.replaceImages(ctx, id, in.ImageKeys); err != nil {
			return err
		}
		if in.StockMode == StockTracked {
			return s.stock.Init(ctx, id, *in.StockQuantity, ownerID)
		}
		return nil
	})
	if err != nil {
		return Product{}, err
	}
	return s.get(ctx, id)
}

// Update modifie un produit du marchand. Le mode de stock ne change pas après la création : des
// réservations peuvent être en cours sur la quantité.
func (s *Service) Update(ctx context.Context, ownerID, productID uuid.UUID, in ProductInput) (Product, error) {
	cur, err := s.RequireOwned(ctx, ownerID, productID)
	if err != nil {
		return Product{}, err
	}
	in.StockMode = cur.StockMode
	if in.ImageKeys == nil {
		in.ImageKeys = imageKeys(cur.Images)
	}
	active := cur.IsActive
	if in.IsActive != nil {
		active = *in.IsActive
	}
	checkCategory := active || in.CategoryID != cur.CategoryID
	if err := s.validateProduct(ctx, ownerID, &in, false, checkCategory, imageKeys(cur.Images)); err != nil {
		return Product{}, err
	}
	err = s.db.InTx(ctx, func(ctx context.Context) error {
		if err := store.New(s.db.Conn(ctx)).UpdateProduct(ctx, store.UpdateProductParams{
			ID: productID, CategoryID: in.CategoryID, Name: in.Name, Description: in.Description,
			PriceXof: in.PriceXOF, ParcelSize: string(in.ParcelSize), IsActive: active,
		}); err != nil {
			return fmt.Errorf("mise à jour du produit : %w", err)
		}
		if !slices.Equal(in.ImageKeys, imageKeys(cur.Images)) {
			return s.replaceImages(ctx, productID, in.ImageKeys)
		}
		return nil
	})
	if err != nil {
		return Product{}, err
	}
	return s.get(ctx, productID)
}

// SetStock fixe la quantité d'un produit suivi du marchand.
func (s *Service) SetStock(ctx context.Context, ownerID, productID uuid.UUID, qty int32, note string) (Product, error) {
	p, err := s.RequireOwned(ctx, ownerID, productID)
	if err != nil {
		return Product{}, err
	}
	if p.StockMode != StockTracked {
		return Product{}, apperr.Conflict("stock_not_tracked", "Ce produit n'a pas de stock suivi.")
	}
	if _, err := s.stock.SetQuantity(ctx, productID, qty, ownerID, validate.Clean(note)); err != nil {
		return Product{}, err
	}
	return s.get(ctx, productID)
}

// StockMovements retourne le journal de stock d'un produit du marchand.
func (s *Service) StockMovements(ctx context.Context, ownerID, productID uuid.UUID, limit, offset int32) ([]stock.Movement, error) {
	if _, err := s.RequireOwned(ctx, ownerID, productID); err != nil {
		return nil, err
	}
	return s.stock.Movements(ctx, productID, limit, offset)
}

// RequireOwned retourne un produit d'une boutique du marchand (boutique non suspendue).
func (s *Service) RequireOwned(ctx context.Context, ownerID, productID uuid.UUID) (Product, error) {
	p, err := s.get(ctx, productID)
	if err != nil {
		return Product{}, err
	}
	if _, err := s.shops.RequireOwned(ctx, ownerID, p.ShopID); err != nil {
		if apperr.IsCode(err, "shop_not_found") {
			return Product{}, errProductNotFound
		}
		return Product{}, err
	}
	return p, nil
}

// GetPublic retourne un produit actif d'une boutique publiée.
func (s *Service) GetPublic(ctx context.Context, productID uuid.UUID) (Product, shops.PublicShop, error) {
	p, err := s.get(ctx, productID)
	if err != nil {
		return Product{}, shops.PublicShop{}, err
	}
	shop, err := s.shops.RequirePublished(ctx, p.ShopID)
	if err != nil || !p.IsActive {
		return Product{}, shops.PublicShop{}, errProductNotFound
	}
	return p, shop.Public(), nil
}

// ListPublicForShop retourne les produits en vente d'une boutique publiée.
func (s *Service) ListPublicForShop(ctx context.Context, shopID uuid.UUID, limit, offset int32) ([]Product, error) {
	if _, err := s.shops.RequirePublished(ctx, shopID); err != nil {
		return nil, err
	}
	rows, err := store.New(s.db.Conn(ctx)).ListActiveProductsByShop(ctx, store.ListActiveProductsByShopParams{
		ShopID: shopID, Lim: limit, Off: offset,
	})
	if err != nil {
		return nil, fmt.Errorf("liste des produits : %w", err)
	}
	return s.enrich(ctx, rows)
}

// ListForSeller retourne les produits d'une boutique du marchand, filtrés par état et par nom.
func (s *Service) ListForSeller(ctx context.Context, ownerID, shopID uuid.UUID, f SellerFilter, limit, offset int32) ([]Product, error) {
	if _, err := s.shops.RequireOwned(ctx, ownerID, shopID); err != nil {
		return nil, err
	}
	rows, err := store.New(s.db.Conn(ctx)).ListSellerProducts(ctx, store.ListSellerProductsParams{
		ShopID: shopID, Status: string(f.Status), Q: likeEscape(f.Q), Lim: limit, Off: offset,
	})
	if err != nil {
		return nil, fmt.Errorf("liste des produits du marchand : %w", err)
	}
	return s.enrich(ctx, rows)
}

// CountForSeller retourne le nombre de produits par état d'une boutique du marchand.
func (s *Service) CountForSeller(ctx context.Context, ownerID, shopID uuid.UUID) (Counts, error) {
	if _, err := s.shops.RequireOwned(ctx, ownerID, shopID); err != nil {
		return Counts{}, err
	}
	c, err := store.New(s.db.Conn(ctx)).CountSellerProducts(ctx, shopID)
	if err != nil {
		return Counts{}, fmt.Errorf("compteurs des produits : %w", err)
	}
	return Counts{Active: c.Active, Draft: c.Draft, Withdrawn: c.Withdrawn}, nil
}

// likeEscape rend littéraux les jokers de LIKE (la requête utilise ESCAPE '\').
func likeEscape(q string) string {
	return strings.NewReplacer(`\`, `\\`, `%`, `\%`, `_`, `\_`).Replace(q)
}

// ProductsByIDs retourne les produits demandés (panier, commande), quel que soit leur état :
// l'appelant vérifie qu'ils sont actifs et de la bonne boutique.
func (s *Service) ProductsByIDs(ctx context.Context, ids []uuid.UUID) (map[uuid.UUID]Product, error) {
	rows, err := store.New(s.db.Conn(ctx)).GetProductsByIDs(ctx, ids)
	if err != nil {
		return nil, fmt.Errorf("lecture des produits : %w", err)
	}
	list, err := s.enrich(ctx, rows)
	if err != nil {
		return nil, err
	}
	out := make(map[uuid.UUID]Product, len(list))
	for _, p := range list {
		out[p.ID] = p
	}
	return out, nil
}

func (s *Service) get(ctx context.Context, id uuid.UUID) (Product, error) {
	row, err := store.New(s.db.Conn(ctx)).GetProduct(ctx, id)
	if database.IsNoRows(err) {
		return Product{}, errProductNotFound
	}
	if err != nil {
		return Product{}, fmt.Errorf("lecture du produit : %w", err)
	}
	list, err := s.enrich(ctx, []store.Product{row})
	if err != nil {
		return Product{}, err
	}
	return list[0], nil
}

// enrich ajoute photos et stock à des lignes de produits (2 requêtes pour toute la liste).
func (s *Service) enrich(ctx context.Context, rows []store.Product) ([]Product, error) {
	if len(rows) == 0 {
		return []Product{}, nil
	}
	ids := make([]uuid.UUID, len(rows))
	for i, r := range rows {
		ids[i] = r.ID
	}
	imgs, err := store.New(s.db.Conn(ctx)).ListImages(ctx, ids)
	if err != nil {
		return nil, fmt.Errorf("lecture des photos : %w", err)
	}
	levels, err := s.stock.Levels(ctx, ids)
	if err != nil {
		return nil, err
	}
	byProduct := map[uuid.UUID][]Image{}
	for _, im := range imgs {
		byProduct[im.ProductID] = append(byProduct[im.ProductID], Image{URL: s.uploads.PublicURL(im.ObjectKey), ObjectKey: im.ObjectKey, Position: im.Position})
	}
	out := make([]Product, len(rows))
	for i, r := range rows {
		p := Product{
			ID: r.ID, ShopID: r.ShopID, CategoryID: r.CategoryID, Name: r.Name, Description: r.Description,
			PriceXOF: r.PriceXof, ParcelSize: ParcelSize(r.ParcelSize), StockMode: StockMode(r.StockMode),
			IsActive: r.IsActive, Status: statusOf(r), PublishedAt: r.PublishedAt, WithdrawnAt: r.WithdrawnAt,
			Images: byProduct[r.ID], CreatedAt: r.CreatedAt, UpdatedAt: r.UpdatedAt,
		}
		if p.Images == nil {
			p.Images = []Image{}
		}
		p.Available = r.IsActive
		if p.StockMode == StockTracked {
			q := levels[r.ID]
			p.StockQuantity = &q
			p.Available = r.IsActive && q > 0
		}
		out[i] = p
	}
	return out, nil
}

func statusOf(r store.Product) Status {
	switch {
	case r.IsActive:
		return StatusActive
	case r.PublishedAt == nil:
		return StatusDraft
	default:
		return StatusWithdrawn
	}
}

func (s *Service) replaceImages(ctx context.Context, productID uuid.UUID, keys []string) error {
	q := store.New(s.db.Conn(ctx))
	if err := q.DeleteImages(ctx, productID); err != nil {
		return fmt.Errorf("remplacement des photos : %w", err)
	}
	for i, k := range keys {
		if err := q.InsertImage(ctx, store.InsertImageParams{ProductID: productID, ObjectKey: k, Position: int32(i)}); err != nil {
			return fmt.Errorf("ajout de photo : %w", err)
		}
	}
	return nil
}

func imageKeys(imgs []Image) []string {
	out := make([]string, len(imgs))
	for i, im := range imgs {
		out[i] = im.ObjectKey
	}
	return out
}

func hasDuplicates(keys []string) bool {
	seen := map[string]bool{}
	for _, k := range keys {
		if seen[k] {
			return true
		}
		seen[k] = true
	}
	return false
}
