// Package coupons gère les codes promo (spec 034) : codes des boutiques (à leurs frais, créés
// dans Ivia Business ou au back-office pour la boutique IVI) et coupon de bienvenue offert par
// ivia. Une réduction porte sur les produits ; une utilisation est réservée à la création de la
// commande, confirmée au paiement et libérée si la commande n'est jamais payée.
package coupons

import (
	"context"
	"crypto/rand"
	"fmt"
	"math/big"
	"regexp"
	"slices"
	"strings"
	"sync"
	"time"

	"github.com/google/uuid"

	"ivia/backend/internal/admin"
	"ivia/backend/internal/catalog"
	"ivia/backend/internal/coupons/store"
	"ivia/backend/internal/platform/apperr"
	"ivia/backend/internal/platform/database"
	"ivia/backend/internal/platform/validate"
	"ivia/backend/internal/shops"
)

// Qui paie la réduction.
const (
	FundedByShop = "shop"
	FundedByIvia = "ivia"
)

// MinTotalXOF : total minimum à payer avec un code (pas de paiement Mobile Money à 0 F).
const MinTotalXOF = 100

// Code est un code promo, avec ses utilisations.
type Code struct {
	ID               uuid.UUID  `json:"id"`
	Code             string     `json:"code"`
	ShopID           *uuid.UUID `json:"shop_id"`
	ShopName         string     `json:"shop_name"`
	FundedBy         string     `json:"funded_by"`
	Kind             string     `json:"kind"`
	Value            int32      `json:"value"`
	MaxDiscountXOF   *int64     `json:"max_discount_xof"`
	MinOrderXOF      int64      `json:"min_order_xof"`
	StartsAt         time.Time  `json:"starts_at"`
	EndsAt           *time.Time `json:"ends_at"`
	MaxUses          *int32     `json:"max_uses"`
	MaxUsesPerUser   int32      `json:"max_uses_per_user"`
	Visibility       string     `json:"visibility"`
	Welcome          bool       `json:"welcome"`
	Status           string     `json:"status"`
	State            string     `json:"state"`
	SuspensionReason string     `json:"suspension_reason"`
	UsesCount        int32      `json:"uses_count"`
	UsedCount        int32      `json:"used_count"`
	DiscountGivenXOF int64      `json:"discount_given_xof"`
	CreatedAt        time.Time  `json:"created_at"`
	// Scope : « shop » (tous les produits de la boutique) ou « products » (ceux de Products).
	Scope    string       `json:"scope"`
	Products []ProductRef `json:"products"`
}

// ProductRef est un produit visé par un code.
type ProductRef struct {
	ID   uuid.UUID `json:"id"`
	Name string    `json:"name"`
}

// Line est une ligne de commande : la réduction d'un code limité à certains produits ne porte
// que sur leurs lignes.
type Line struct {
	ProductID uuid.UUID
	TotalXOF  int64
}

// MaxCodeProducts : produits au plus par code.
const MaxCodeProducts = 100

// Applied est un code accepté pour une commande.
type Applied struct {
	CodeID      uuid.UUID
	Code        string
	DiscountXOF int64
	FundedBy    string
}

// Settings sont les réglages du coupon de bienvenue.
type Settings struct {
	WelcomeEnabled     bool  `json:"welcome_enabled"`
	WelcomeAmountXOF   int64 `json:"welcome_amount_xof"`
	WelcomeMinOrderXOF int64 `json:"welcome_min_order_xof"`
	WelcomeValidDays   int32 `json:"welcome_valid_days"`
}

// Input décrit un code à créer.
type Input struct {
	Code           string     `json:"code"`
	ShopID         *uuid.UUID `json:"shop_id"`
	Kind           string     `json:"kind"`
	Value          int32      `json:"value"`
	MaxDiscountXOF *int64     `json:"max_discount_xof"`
	MinOrderXOF    int64      `json:"min_order_xof"`
	StartsAt       *time.Time `json:"starts_at"`
	EndsAt         *time.Time `json:"ends_at"`
	MaxUses        *int32     `json:"max_uses"`
	MaxUsesPerUser int32      `json:"max_uses_per_user"`
	Visibility     string     `json:"visibility"`
	// ProductIDs : produits de la boutique visés ; vide : toute la boutique.
	ProductIDs []uuid.UUID `json:"product_ids"`
}

// OrderHistory dit si un compte a déjà une commande payée (coupon de bienvenue).
type OrderHistory interface {
	HasPaidOrder(ctx context.Context, userID uuid.UUID) (bool, error)
}

// Service gère les codes promo.
type Service struct {
	db      *database.DB
	shops   *shops.Service
	admin   *admin.Service
	history OrderHistory
	fails   *failures
	catalog *catalog.Service
}

// NewService crée le service.
func NewService(db *database.DB, sh *shops.Service, ad *admin.Service) *Service {
	return &Service{db: db, shops: sh, admin: ad, fails: &failures{seen: map[uuid.UUID][]time.Time{}}}
}

// SetOrderHistory branche l'historique des commandes (évite une dépendance circulaire).
func (s *Service) SetOrderHistory(h OrderHistory) { s.history = h }

// SetCatalog branche le catalogue : produits visés par un code (boutique, nom).
func (s *Service) SetCatalog(c *catalog.Service) { s.catalog = c }

var codeRe = regexp.MustCompile(`^[A-Z0-9-]{3,24}$`)

// Normalize met un code saisi au format stocké : majuscules, sans espaces.
func Normalize(raw string) string {
	return strings.ToUpper(strings.Join(strings.Fields(raw), ""))
}

// Discount calcule la réduction d'un code sur un montant de produits (sans le minimum à payer).
func Discount(kind string, value int32, maxDiscount *int64, subtotal int64) int64 {
	var d int64
	if kind == "percent" {
		d = subtotal * int64(value) / 100
		if maxDiscount != nil && d > *maxDiscount {
			d = *maxDiscount
		}
	} else {
		d = int64(value)
	}
	return max(0, min(d, subtotal))
}

// CapToMinTotal borne la réduction pour laisser au moins MinTotalXOF à payer ; 0 si impossible.
func CapToMinTotal(discount, total int64) int64 {
	return max(0, min(discount, total-MinTotalXOF))
}

func state(c store.PromoCode, now time.Time) string {
	switch {
	case c.Status == "suspended":
		return "suspended"
	case c.Status == "ended", c.EndsAt != nil && !now.Before(*c.EndsAt),
		c.MaxUses != nil && c.UsesCount >= *c.MaxUses:
		return "ended"
	case now.Before(c.StartsAt):
		return "scheduled"
	}
	return "active"
}

func (s *Service) view(ctx context.Context, c store.PromoCode, used int32, given int64) Code {
	out := Code{
		ID: c.ID, Code: c.Code, ShopID: c.ShopID, FundedBy: c.FundedBy, Kind: c.Kind, Value: c.Value,
		MaxDiscountXOF: c.MaxDiscountXof, MinOrderXOF: c.MinOrderXof, StartsAt: c.StartsAt, EndsAt: c.EndsAt,
		MaxUses: c.MaxUses, MaxUsesPerUser: c.MaxUsesPerUser, Visibility: c.Visibility, Welcome: c.Welcome,
		Status: c.Status, State: state(c, time.Now()), SuspensionReason: c.SuspensionReason,
		UsesCount: c.UsesCount, UsedCount: used, DiscountGivenXOF: given, CreatedAt: c.CreatedAt,
	}
	if c.ShopID != nil {
		if sh, err := s.shops.Get(ctx, *c.ShopID); err == nil {
			out.ShopName = sh.Name
		}
	} else {
		out.ShopName = "Toutes les boutiques"
	}
	out.Scope, out.Products = "shop", []ProductRef{}
	ids, err := store.New(s.db.Conn(ctx)).ListCodeProducts(ctx, c.ID)
	if err == nil && len(ids) > 0 {
		out.Scope = "products"
		if s.catalog != nil {
			if ps, err := s.catalog.ProductsByIDs(ctx, ids); err == nil {
				for _, id := range ids {
					if p, ok := ps[id]; ok {
						out.Products = append(out.Products, ProductRef{ID: id, Name: p.Name})
					}
				}
			}
		}
	}
	return out
}

// --- Application à une commande --------------------------------------------------------------

func refuse(code, msg string) error { return apperr.Conflict(code, msg) }

// Quote vérifie un code pour une commande et calcule la réduction, sans rien enregistrer.
// Trop d'essais ratés : refus pendant une heure.
func (s *Service) Quote(ctx context.Context, userID uuid.UUID, raw string, shopID uuid.UUID, lines []Line) (Applied, error) {
	if s.fails.blocked(userID) {
		return Applied{}, apperr.TooManyRequests("promo_rate_limited", "Trop de codes essayés. Réessayez dans une heure.", 3600)
	}
	a, err := s.quote(ctx, userID, raw, shopID, lines)
	if err != nil && (apperr.IsCode(err, "promo_not_found") || apperr.IsCode(err, "promo_not_applicable")) {
		s.fails.add(userID)
	}
	return a, err
}

func (s *Service) quote(ctx context.Context, userID uuid.UUID, raw string, shopID uuid.UUID, lines []Line) (Applied, error) {
	var subtotal int64
	for _, l := range lines {
		subtotal += l.TotalXOF
	}
	if s.history != nil {
		_ = s.ensureWelcome(ctx, userID)
	}
	code := Normalize(raw)
	if !codeRe.MatchString(code) {
		return Applied{}, refuse("promo_not_found", "Ce code promo n'existe pas.")
	}
	st := store.New(s.db.Conn(ctx))
	c, err := st.GetCodeByCode(ctx, code)
	if database.IsNoRows(err) {
		return Applied{}, refuse("promo_not_found", "Ce code promo n'existe pas.")
	}
	if err != nil {
		return Applied{}, fmt.Errorf("lecture du code : %w", err)
	}
	if c.ReservedFor != nil && *c.ReservedFor != userID {
		return Applied{}, refuse("promo_not_found", "Ce code promo n'existe pas.")
	}
	now := time.Now()
	switch {
	case c.Status == "suspended":
		return Applied{}, refuse("promo_suspended", "Ce code promo est suspendu.")
	case c.Status == "ended", c.EndsAt != nil && !now.Before(*c.EndsAt):
		return Applied{}, refuse("promo_expired", "Ce code promo a expiré.")
	case now.Before(c.StartsAt):
		return Applied{}, refuse("promo_not_started", "Ce code promo n'est pas encore valable.")
	case c.MaxUses != nil && c.UsesCount >= *c.MaxUses:
		return Applied{}, refuse("promo_exhausted", "Ce code promo a déjà été utilisé autant de fois que prévu.")
	case c.ShopID != nil && *c.ShopID != shopID:
		return Applied{}, refuse("promo_not_applicable", "Ce code promo n'est pas valable dans cette boutique.")
	}
	n, err := st.CountUserUses(ctx, store.CountUserUsesParams{CodeID: c.ID, UserID: userID})
	if err != nil {
		return Applied{}, fmt.Errorf("utilisations du code : %w", err)
	}
	if n >= c.MaxUsesPerUser {
		return Applied{}, refuse("promo_already_used", "Vous avez déjà utilisé ce code promo.")
	}
	if c.Welcome && s.history != nil {
		paid, err := s.history.HasPaidOrder(ctx, userID)
		if err != nil {
			return Applied{}, err
		}
		if paid {
			return Applied{}, refuse("promo_already_used", "Ce coupon est réservé à votre première commande.")
		}
	}
	if subtotal < c.MinOrderXof {
		return Applied{}, refuse("promo_min_not_reached",
			fmt.Sprintf("Ce code demande au moins %s d'achats.", formatXOF(c.MinOrderXof)))
	}
	// Code limité à certains produits : la réduction porte sur leurs lignes seulement.
	base := subtotal
	targets, err := st.ListCodeProducts(ctx, c.ID)
	if err != nil {
		return Applied{}, fmt.Errorf("produits du code : %w", err)
	}
	if len(targets) > 0 {
		base = EligibleSubtotal(lines, targets)
		if base == 0 {
			return Applied{}, refuse("promo_not_applicable", "Ce code promo ne concerne aucun produit de votre panier.")
		}
	}
	d := Discount(c.Kind, c.Value, c.MaxDiscountXof, base)
	return Applied{CodeID: c.ID, Code: c.Code, DiscountXOF: d, FundedBy: c.FundedBy}, nil
}

// Reserve réserve une utilisation pour une commande (dans la transaction de création).
func (s *Service) Reserve(ctx context.Context, a Applied, orderID, userID uuid.UUID) error {
	st := store.New(s.db.Conn(ctx))
	n, err := st.ReserveUse(ctx, a.CodeID)
	if err != nil {
		return fmt.Errorf("réservation du code : %w", err)
	}
	if n == 0 {
		return refuse("promo_exhausted", "Ce code promo vient d'être épuisé ou suspendu.")
	}
	if err := st.InsertRedemption(ctx, store.InsertRedemptionParams{
		CodeID: a.CodeID, OrderID: orderID, UserID: userID, DiscountXof: a.DiscountXOF,
	}); err != nil {
		return fmt.Errorf("utilisation du code : %w", err)
	}
	return nil
}

// Confirm compte l'utilisation au paiement réussi (même transaction que le statut).
func (s *Service) Confirm(ctx context.Context, orderID uuid.UUID) error {
	if _, err := store.New(s.db.Conn(ctx)).ConfirmRedemption(ctx, orderID); err != nil {
		return fmt.Errorf("confirmation du code : %w", err)
	}
	return nil
}

// Release rend l'utilisation d'une commande jamais payée (expirée ou annulée avant paiement).
func (s *Service) Release(ctx context.Context, orderID uuid.UUID) error {
	st := store.New(s.db.Conn(ctx))
	codeID, err := st.ReleaseRedemption(ctx, orderID)
	if database.IsNoRows(err) {
		return nil
	}
	if err != nil {
		return fmt.Errorf("libération du code : %w", err)
	}
	return st.DecrementUse(ctx, codeID)
}

// EligibleSubtotal additionne les lignes des produits visés.
func EligibleSubtotal(lines []Line, targets []uuid.UUID) int64 {
	var sum int64
	for _, l := range lines {
		if slices.Contains(targets, l.ProductID) {
			sum += l.TotalXOF
		}
	}
	return sum
}

// --- Création et gestion ---------------------------------------------------------------------

func (s *Service) validate(in *Input) error {
	v := validate.New()
	in.Code = Normalize(in.Code)
	if in.Code == "" {
		in.Code = randomCode("")
	}
	v.Check(codeRe.MatchString(in.Code), "code", "3 à 24 lettres, chiffres ou tirets.")
	v.Check(in.Kind == "percent" || in.Kind == "fixed", "kind", "Type attendu : percent ou fixed.")
	if in.Kind == "percent" {
		v.Check(in.Value >= 1 && in.Value <= 90, "value", "Pourcentage entre 1 et 90.")
	} else {
		v.Check(in.Value >= 50 && in.Value <= 1_000_000, "value", "Montant entre 50 et 1 000 000 F.")
		in.MaxDiscountXOF = nil
	}
	v.Check(in.MaxDiscountXOF == nil || *in.MaxDiscountXOF > 0, "max_discount_xof", "Plafond positif attendu.")
	v.Check(in.MinOrderXOF >= 0 && in.MinOrderXOF <= 100_000_000, "min_order_xof", "Minimum invalide.")
	v.Check(in.MaxUses == nil || (*in.MaxUses >= 1 && *in.MaxUses <= 1_000_000), "max_uses", "Entre 1 et 1 000 000.")
	if in.MaxUsesPerUser == 0 {
		in.MaxUsesPerUser = 1
	}
	v.Check(in.MaxUsesPerUser >= 1 && in.MaxUsesPerUser <= 100, "max_uses_per_user", "Entre 1 et 100.")
	if in.Visibility == "" {
		in.Visibility = "public"
	}
	v.Check(in.Visibility == "public" || in.Visibility == "private", "visibility", "public ou private.")
	if in.StartsAt == nil {
		now := time.Now()
		in.StartsAt = &now
	}
	v.Check(in.EndsAt == nil || in.EndsAt.After(*in.StartsAt), "ends_at", "La fin doit suivre le début.")
	v.Check(len(in.ProductIDs) <= MaxCodeProducts, "product_ids", fmt.Sprintf("%d produits au plus.", MaxCodeProducts))
	seen := map[uuid.UUID]bool{}
	for _, id := range in.ProductIDs {
		v.Check(!seen[id], "product_ids", "Produit en double.")
		seen[id] = true
	}
	return v.Err()
}

// checkProducts vérifie que chaque produit visé appartient à la boutique du code.
func (s *Service) checkProducts(ctx context.Context, shopID uuid.UUID, ids []uuid.UUID) error {
	if len(ids) == 0 {
		return nil
	}
	if s.catalog == nil {
		return fmt.Errorf("catalogue non branché")
	}
	ps, err := s.catalog.ProductsByIDs(ctx, ids)
	if err != nil {
		return err
	}
	for _, id := range ids {
		if p, ok := ps[id]; !ok || p.ShopID != shopID {
			return apperr.Validation(map[string]string{"product_ids": "Un des produits choisis n'est pas dans cette boutique."})
		}
	}
	return nil
}

func (s *Service) create(ctx context.Context, in Input, shopID uuid.UUID, by uuid.UUID) (Code, error) {
	if err := s.validate(&in); err != nil {
		return Code{}, err
	}
	if err := s.checkProducts(ctx, shopID, in.ProductIDs); err != nil {
		return Code{}, err
	}
	var id uuid.UUID
	err := s.db.InTx(ctx, func(ctx context.Context) error {
		st := store.New(s.db.Conn(ctx))
		var err error
		id, err = st.CreateCode(ctx, store.CreateCodeParams{
			Code: in.Code, ShopID: &shopID, FundedBy: FundedByShop, Kind: in.Kind, Value: in.Value,
			MaxDiscountXof: in.MaxDiscountXOF, MinOrderXof: in.MinOrderXOF, StartsAt: *in.StartsAt, EndsAt: in.EndsAt,
			MaxUses: in.MaxUses, MaxUsesPerUser: in.MaxUsesPerUser, Visibility: in.Visibility, CreatedBy: &by,
		})
		if database.IsUniqueViolation(err, "promo_codes_code_key") {
			return apperr.Conflict("promo_code_taken", "Ce code existe déjà. Choisissez-en un autre.")
		}
		if err != nil {
			return fmt.Errorf("création du code : %w", err)
		}
		for _, p := range in.ProductIDs {
			if err := st.InsertCodeProduct(ctx, store.InsertCodeProductParams{CodeID: id, ProductID: p}); err != nil {
				return fmt.Errorf("produits du code : %w", err)
			}
		}
		return nil
	})
	if err != nil {
		return Code{}, err
	}
	return s.get(ctx, id)
}

func (s *Service) get(ctx context.Context, id uuid.UUID) (Code, error) {
	c, err := store.New(s.db.Conn(ctx)).GetCode(ctx, id)
	if database.IsNoRows(err) {
		return Code{}, apperr.NotFound("promo_not_found", "Code promo introuvable.")
	}
	if err != nil {
		return Code{}, fmt.Errorf("lecture du code : %w", err)
	}
	return s.view(ctx, c, 0, 0), nil
}

func (s *Service) list(ctx context.Context, shopID *uuid.UUID, welcome bool, limit, offset int32) ([]Code, error) {
	rows, err := store.New(s.db.Conn(ctx)).ListCodes(ctx, store.ListCodesParams{
		ShopID: shopID, IncludeWelcome: welcome, Lim: limit, Off: offset,
	})
	if err != nil {
		return nil, fmt.Errorf("liste des codes : %w", err)
	}
	out := make([]Code, len(rows))
	for i, r := range rows {
		c := store.PromoCode{
			ID: r.ID, Code: r.Code, ShopID: r.ShopID, FundedBy: r.FundedBy, Kind: r.Kind, Value: r.Value,
			MaxDiscountXof: r.MaxDiscountXof, MinOrderXof: r.MinOrderXof, StartsAt: r.StartsAt, EndsAt: r.EndsAt,
			MaxUses: r.MaxUses, MaxUsesPerUser: r.MaxUsesPerUser, Visibility: r.Visibility, ReservedFor: r.ReservedFor,
			Welcome: r.Welcome, Status: r.Status, SuspensionReason: r.SuspensionReason, UsesCount: r.UsesCount,
			CreatedAt: r.CreatedAt,
		}
		out[i] = s.view(ctx, c, r.UsedCount, r.DiscountGivenXof)
	}
	return out, nil
}

var actions = map[string]string{"suspend": "suspended", "resume": "active", "end": "ended"}

func (s *Service) setStatus(ctx context.Context, id uuid.UUID, action, reason string) (Code, error) {
	to, ok := actions[action]
	if !ok {
		return Code{}, apperr.Validation(map[string]string{"action": "suspend, resume ou end."})
	}
	n, err := store.New(s.db.Conn(ctx)).SetCodeStatus(ctx, store.SetCodeStatusParams{ID: id, Status: to, Reason: reason})
	if err != nil {
		return Code{}, fmt.Errorf("statut du code : %w", err)
	}
	if n == 0 {
		return Code{}, apperr.Conflict("promo_ended", "Ce code est terminé : il ne peut plus changer.")
	}
	return s.get(ctx, id)
}

// --- Marchand ---------------------------------------------------------------------------------

func (s *Service) requireShop(ctx context.Context, sellerID, shopID uuid.UUID) error {
	if _, err := s.shops.RequireOwned(ctx, sellerID, shopID); err != nil {
		return err
	}
	return nil
}

// ListForShop liste les codes d'une boutique du marchand.
func (s *Service) ListForShop(ctx context.Context, sellerID, shopID uuid.UUID, limit, offset int32) ([]Code, error) {
	if err := s.requireShop(ctx, sellerID, shopID); err != nil {
		return nil, err
	}
	return s.list(ctx, &shopID, false, limit, offset)
}

// CreateForShop crée un code pour une boutique du marchand, actif dès sa création.
func (s *Service) CreateForShop(ctx context.Context, sellerID, shopID uuid.UUID, in Input) (Code, error) {
	if err := s.requireShop(ctx, sellerID, shopID); err != nil {
		return Code{}, err
	}
	return s.create(ctx, in, shopID, sellerID)
}

// SellerAction suspend, reprend ou termine un code d'une boutique du marchand (sinon 404).
func (s *Service) SellerAction(ctx context.Context, sellerID, codeID uuid.UUID, action string) (Code, error) {
	c, err := s.get(ctx, codeID)
	if err != nil {
		return Code{}, err
	}
	if c.ShopID == nil || s.requireShop(ctx, sellerID, *c.ShopID) != nil {
		return Code{}, apperr.NotFound("promo_not_found", "Code promo introuvable.")
	}
	if c.Status == "suspended" && c.SuspensionReason != "" && action == "resume" {
		return Code{}, apperr.Forbidden("promo_suspended_by_admin", "Ce code a été suspendu par ivia.")
	}
	return s.setStatus(ctx, codeID, action, "")
}

// --- Admin ------------------------------------------------------------------------------------

// AdminList liste tous les codes (boutiques, IVI, bienvenue si demandé).
func (s *Service) AdminList(ctx context.Context, shopID *uuid.UUID, welcome bool, limit, offset int32) ([]Code, error) {
	return s.list(ctx, shopID, welcome, limit, offset)
}

// AdminCreate crée un code pour une boutique (boutique IVI), journalisé.
func (s *Service) AdminCreate(ctx context.Context, adminID uuid.UUID, in Input) (Code, error) {
	if in.ShopID == nil {
		return Code{}, apperr.Validation(map[string]string{"shop_id": "Choisissez la boutique."})
	}
	if _, err := s.shops.Get(ctx, *in.ShopID); err != nil {
		return Code{}, apperr.Validation(map[string]string{"shop_id": "Boutique inconnue."})
	}
	var out Code
	err := s.db.InTx(ctx, func(ctx context.Context) error {
		var err error
		if out, err = s.create(ctx, in, *in.ShopID, adminID); err != nil {
			return err
		}
		return s.admin.Record(ctx, admin.AuditEntry{
			AdminID: &adminID, Action: "promo_code.create", TargetType: "promo_code", TargetID: out.ID.String(),
			After: map[string]any{"code": out.Code, "shop_id": out.ShopID, "kind": out.Kind, "value": out.Value, "product_ids": in.ProductIDs},
		})
	})
	return out, err
}

// AdminAction suspend, reprend ou termine n'importe quel code, journalisé ; motif obligatoire
// pour suspendre le code d'un marchand.
func (s *Service) AdminAction(ctx context.Context, adminID, codeID uuid.UUID, action, reason string) (Code, error) {
	reason = validate.Clean(reason)
	if action == "suspend" && len([]rune(reason)) < 3 {
		return Code{}, apperr.Validation(map[string]string{"reason": "Indiquez le motif de la suspension."})
	}
	if len([]rune(reason)) > 300 {
		return Code{}, apperr.Validation(map[string]string{"reason": "300 caractères au plus."})
	}
	if action != "suspend" {
		reason = ""
	}
	var out Code
	err := s.db.InTx(ctx, func(ctx context.Context) error {
		before, err := s.get(ctx, codeID)
		if err != nil {
			return err
		}
		if out, err = s.setStatus(ctx, codeID, action, reason); err != nil {
			return err
		}
		return s.admin.Record(ctx, admin.AuditEntry{
			AdminID: &adminID, Action: "promo_code." + action, TargetType: "promo_code", TargetID: codeID.String(),
			Before: map[string]any{"status": before.Status}, After: map[string]any{"status": out.Status}, Reason: reason,
		})
	})
	return out, err
}

// Settings lit les réglages du coupon de bienvenue.
func (s *Service) Settings(ctx context.Context) (Settings, error) {
	r, err := store.New(s.db.Conn(ctx)).GetSettings(ctx)
	if err != nil {
		return Settings{}, fmt.Errorf("réglages des coupons : %w", err)
	}
	return Settings{r.WelcomeEnabled, r.WelcomeAmountXof, r.WelcomeMinOrderXof, r.WelcomeValidDays}, nil
}

// UpdateSettings modifie les réglages du coupon de bienvenue, journalisé.
func (s *Service) UpdateSettings(ctx context.Context, adminID uuid.UUID, in Settings) (Settings, error) {
	v := validate.New()
	v.Check(in.WelcomeAmountXOF >= 0 && in.WelcomeAmountXOF <= 100_000, "welcome_amount_xof", "Entre 0 et 100 000 F.")
	v.Check(!in.WelcomeEnabled || in.WelcomeAmountXOF >= 50, "welcome_amount_xof", "50 F au moins pour activer le coupon.")
	v.Check(in.WelcomeMinOrderXOF >= 0 && in.WelcomeMinOrderXOF <= 10_000_000, "welcome_min_order_xof", "Minimum invalide.")
	v.Check(in.WelcomeValidDays >= 1 && in.WelcomeValidDays <= 365, "welcome_valid_days", "Entre 1 et 365 jours.")
	if err := v.Err(); err != nil {
		return Settings{}, err
	}
	var out Settings
	err := s.db.InTx(ctx, func(ctx context.Context) error {
		before, err := s.Settings(ctx)
		if err != nil {
			return err
		}
		r, err := store.New(s.db.Conn(ctx)).UpdateSettings(ctx, store.UpdateSettingsParams{
			WelcomeEnabled: in.WelcomeEnabled, WelcomeAmountXof: in.WelcomeAmountXOF,
			WelcomeMinOrderXof: in.WelcomeMinOrderXOF, WelcomeValidDays: in.WelcomeValidDays, UpdatedBy: &adminID,
		})
		if err != nil {
			return fmt.Errorf("réglages des coupons : %w", err)
		}
		out = Settings{r.WelcomeEnabled, r.WelcomeAmountXof, r.WelcomeMinOrderXof, r.WelcomeValidDays}
		return s.admin.Record(ctx, admin.AuditEntry{
			AdminID: &adminID, Action: "coupon_settings.update", TargetType: "coupon_settings", TargetID: "welcome",
			Before: before, After: out,
		})
	})
	return out, err
}

// DiscountTotals donne les réductions confirmées sur [from, to) : à la charge d'ivia, des boutiques.
func (s *Service) DiscountTotals(ctx context.Context, from, to time.Time) (iviaXOF, shopsXOF int64, uses int32, err error) {
	r, err := store.New(s.db.Conn(ctx)).DiscountTotals(ctx, store.DiscountTotalsParams{FromTime: from, ToTime: to})
	if err != nil {
		return 0, 0, 0, fmt.Errorf("réductions : %w", err)
	}
	return r.IviaXof, r.ShopsXof, r.Uses, nil
}

// --- Acheteur ---------------------------------------------------------------------------------

// ListForUser liste les codes utilisables par un acheteur : codes publics en cours et coupons
// qui lui sont réservés (coupon de bienvenue créé à la première visite s'il y a droit).
func (s *Service) ListForUser(ctx context.Context, userID uuid.UUID) ([]Code, error) {
	if s.history != nil {
		if err := s.ensureWelcome(ctx, userID); err != nil {
			return nil, err
		}
	}
	rows, err := store.New(s.db.Conn(ctx)).ListUserCoupons(ctx, &userID)
	if err != nil {
		return nil, fmt.Errorf("coupons : %w", err)
	}
	out := make([]Code, 0, len(rows))
	for _, c := range rows {
		out = append(out, s.view(ctx, c, 0, 0))
	}
	return out, nil
}

// ensureWelcome crée le coupon de bienvenue d'un compte sans commande payée, s'il est activé.
func (s *Service) ensureWelcome(ctx context.Context, userID uuid.UUID) error {
	set, err := s.Settings(ctx)
	if err != nil || !set.WelcomeEnabled || set.WelcomeAmountXOF < 50 {
		return err
	}
	st := store.New(s.db.Conn(ctx))
	has, err := st.HasWelcome(ctx, &userID)
	if err != nil || has {
		return err
	}
	paid, err := s.history.HasPaidOrder(ctx, userID)
	if err != nil || paid {
		return err
	}
	ends := time.Now().AddDate(0, 0, int(set.WelcomeValidDays))
	for range 3 {
		_, err = st.CreateCode(ctx, store.CreateCodeParams{
			Code: randomCode("BIENVENUE-"), FundedBy: FundedByIvia, Kind: "fixed", Value: int32(set.WelcomeAmountXOF),
			MinOrderXof: set.WelcomeMinOrderXOF, StartsAt: time.Now(), EndsAt: &ends, MaxUsesPerUser: 1, MaxUses: ptr(int32(1)),
			Visibility: "private", ReservedFor: &userID, Welcome: true,
		})
		if database.IsUniqueViolation(err, "promo_codes_one_welcome_per_user") {
			return nil
		}
		if !database.IsUniqueViolation(err, "promo_codes_code_key") {
			break
		}
	}
	if err != nil {
		return fmt.Errorf("coupon de bienvenue : %w", err)
	}
	return nil
}

func ptr[T any](v T) *T { return &v }

const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

func randomCode(prefix string) string {
	b := make([]byte, 6)
	for i := range b {
		n, _ := rand.Int(rand.Reader, big.NewInt(int64(len(alphabet))))
		b[i] = alphabet[n.Int64()]
	}
	return prefix + string(b)
}

func formatXOF(v int64) string {
	s := fmt.Sprint(v)
	var out []byte
	for i := range s {
		if i > 0 && (len(s)-i)%3 == 0 {
			out = append(out, ' ')
		}
		out = append(out, s[i])
	}
	return string(out) + " F"
}

// failures compte les codes ratés par compte (10 par heure au plus).
type failures struct {
	mu   sync.Mutex
	seen map[uuid.UUID][]time.Time
}

const maxFailures = 10

func (f *failures) recent(id uuid.UUID, now time.Time) []time.Time {
	var keep []time.Time
	for _, t := range f.seen[id] {
		if now.Sub(t) < time.Hour {
			keep = append(keep, t)
		}
	}
	f.seen[id] = keep
	return keep
}

func (f *failures) blocked(id uuid.UUID) bool {
	f.mu.Lock()
	defer f.mu.Unlock()
	return len(f.recent(id, time.Now())) >= maxFailures
}

func (f *failures) add(id uuid.UUID) {
	f.mu.Lock()
	defer f.mu.Unlock()
	now := time.Now()
	f.seen[id] = append(f.recent(id, now), now)
}
