// Package ratings gère les avis (spec 035) : note du livreur après une livraison, par le client et,
// s'il le souhaite, par le marchand ; avis sur l'application. Le back-office les lit.
package ratings

import (
	"context"
	"fmt"
	"net/http"
	"slices"
	"time"

	"github.com/google/uuid"

	"ivia/backend/internal/orders"
	"ivia/backend/internal/platform/apperr"
	"ivia/backend/internal/platform/database"
	"ivia/backend/internal/platform/httpapi"
	"ivia/backend/internal/platform/identity"
	"ivia/backend/internal/platform/validate"
	"ivia/backend/internal/ratings/store"
	"ivia/backend/internal/users"
)

// Rôles de l'auteur d'une note.
const (
	RoleBuyer  = "buyer"
	RoleSeller = "seller"
)

// Tags proposés dans les apps (une note peut en porter plusieurs).
var allowedTags = []string{
	"rapide", "aimable", "soigneux", "ponctuel", "professionnel",
	"en_retard", "colis_abime", "impoli", "difficile_a_joindre",
}

// DriverOfOrder donne le livreur qui a livré une commande.
type DriverOfOrder interface {
	DeliveredBy(ctx context.Context, orderID uuid.UUID) (*uuid.UUID, error)
}

// Rating est la note d'une livraison.
type Rating struct {
	ID        uuid.UUID `json:"id"`
	OrderID   uuid.UUID `json:"order_id"`
	DriverID  uuid.UUID `json:"driver_id"`
	RaterRole string    `json:"rater_role"`
	Stars     int16     `json:"stars"`
	Tags      []string  `json:"tags"`
	Comment   string    `json:"comment"`
	CreatedAt time.Time `json:"created_at"`

	// Back-office seulement.
	DriverName     string `json:"driver_name,omitempty"`
	RaterName      string `json:"rater_name,omitempty"`
	OrderReference string `json:"order_reference,omitempty"`
}

// OrderRating est l'état de la note d'une commande pour son auteur.
type OrderRating struct {
	CanRate bool    `json:"can_rate"`
	Rating  *Rating `json:"rating"`
}

// Input décrit une note.
type Input struct {
	Stars   int16    `json:"stars"`
	Tags    []string `json:"tags"`
	Comment string   `json:"comment"`
}

// Feedback est un avis sur une application.
type Feedback struct {
	ID        uuid.UUID `json:"id"`
	App       string    `json:"app"`
	Stars     int16     `json:"stars"`
	Comment   string    `json:"comment"`
	CreatedAt time.Time `json:"created_at"`
	UserName  string    `json:"user_name,omitempty"`
}

// DriverScore est la moyenne d'un livreur.
type DriverScore struct {
	DriverID   uuid.UUID `json:"driver_id"`
	DriverName string    `json:"driver_name"`
	Average    float64   `json:"average"`
	Ratings    int32     `json:"ratings"`
	Low        int32     `json:"low"`
}

// AppScore est la moyenne d'une application.
type AppScore struct {
	App     string  `json:"app"`
	Average float64 `json:"average"`
	Ratings int32   `json:"ratings"`
}

// Service gère les avis.
type Service struct {
	db       *database.DB
	orders   *orders.Service
	users    *users.Service
	delivery DriverOfOrder
}

// NewService crée le service.
func NewService(db *database.DB, o *orders.Service, u *users.Service, d DriverOfOrder) *Service {
	return &Service{db: db, orders: o, users: u, delivery: d}
}

func toRating(r store.DeliveryRating) Rating {
	return Rating{
		ID: r.ID, OrderID: r.OrderID, DriverID: r.DriverID, RaterRole: r.RaterRole, Stars: r.Stars,
		Tags: r.Tags, Comment: r.Comment, CreatedAt: r.CreatedAt,
	}
}

// requireOrder vérifie que la commande est à l'auteur (acheteur) ou à sa boutique (marchand) ; 404 sinon.
func (s *Service) requireOrder(ctx context.Context, userID uuid.UUID, role string, orderID uuid.UUID) error {
	if role == RoleSeller {
		_, err := s.orders.GetForSeller(ctx, userID, orderID)
		return err
	}
	ok, err := s.orders.IsBuyerOf(ctx, userID, orderID)
	if err != nil {
		return err
	}
	if !ok {
		return apperr.NotFound("order_not_found", "Commande introuvable.")
	}
	return nil
}

// ForOrder dit si l'auteur peut noter la livraison et rend sa note si elle existe.
func (s *Service) ForOrder(ctx context.Context, userID uuid.UUID, role string, orderID uuid.UUID) (OrderRating, error) {
	if err := s.requireOrder(ctx, userID, role, orderID); err != nil {
		return OrderRating{}, err
	}
	r, err := store.New(s.db.Conn(ctx)).GetDeliveryRating(ctx, store.GetDeliveryRatingParams{OrderID: orderID, RaterRole: role})
	if err == nil {
		v := toRating(r)
		return OrderRating{Rating: &v}, nil
	}
	if !database.IsNoRows(err) {
		return OrderRating{}, fmt.Errorf("note : %w", err)
	}
	driver, err := s.delivery.DeliveredBy(ctx, orderID)
	if err != nil {
		return OrderRating{}, err
	}
	return OrderRating{CanRate: driver != nil}, nil
}

// Rate note la livraison d'une commande livrée, une fois par rôle.
func (s *Service) Rate(ctx context.Context, userID uuid.UUID, role string, orderID uuid.UUID, in Input) (Rating, error) {
	v := validate.New()
	v.Check(in.Stars >= 1 && in.Stars <= 5, "stars", "Note de 1 à 5 étoiles.")
	in.Comment = validate.Clean(in.Comment)
	v.Check(len([]rune(in.Comment)) <= 500, "comment", "500 caractères au plus.")
	tags := []string{}
	for _, t := range in.Tags {
		if slices.Contains(allowedTags, t) && !slices.Contains(tags, t) {
			tags = append(tags, t)
		}
	}
	if err := v.Err(); err != nil {
		return Rating{}, err
	}
	if err := s.requireOrder(ctx, userID, role, orderID); err != nil {
		return Rating{}, err
	}
	driver, err := s.delivery.DeliveredBy(ctx, orderID)
	if err != nil {
		return Rating{}, err
	}
	if driver == nil {
		return Rating{}, apperr.Conflict("rating_not_available", "Vous pourrez noter le livreur une fois la commande livrée.")
	}
	r, err := store.New(s.db.Conn(ctx)).InsertDeliveryRating(ctx, store.InsertDeliveryRatingParams{
		OrderID: orderID, DriverID: *driver, RaterID: userID, RaterRole: role, Stars: in.Stars, Tags: tags, Comment: in.Comment,
	})
	if database.IsUniqueViolation(err, "delivery_ratings_order_id_rater_role_key") {
		return Rating{}, apperr.Conflict("already_rated", "Vous avez déjà noté cette livraison.")
	}
	if err != nil {
		return Rating{}, fmt.Errorf("note : %w", err)
	}
	return toRating(r), nil
}

// AppFeedback enregistre un avis sur une application.
func (s *Service) AppFeedback(ctx context.Context, userID uuid.UUID, app string, stars int16, comment string) (Feedback, error) {
	v := validate.New()
	v.Check(slices.Contains([]string{"buyer", "seller", "driver", "pharmacy"}, app), "app", "Application inconnue.")
	v.Check(stars >= 1 && stars <= 5, "stars", "Note de 1 à 5 étoiles.")
	comment = validate.Clean(comment)
	v.Check(len([]rune(comment)) <= 1000, "comment", "1000 caractères au plus.")
	if err := v.Err(); err != nil {
		return Feedback{}, err
	}
	r, err := store.New(s.db.Conn(ctx)).InsertAppFeedback(ctx, store.InsertAppFeedbackParams{UserID: userID, App: app, Stars: stars, Comment: comment})
	if err != nil {
		return Feedback{}, fmt.Errorf("avis : %w", err)
	}
	return Feedback{ID: r.ID, App: r.App, Stars: r.Stars, Comment: r.Comment, CreatedAt: r.CreatedAt}, nil
}

func (s *Service) name(ctx context.Context, id uuid.UUID) string {
	c, err := s.users.Contact(ctx, id)
	if err != nil {
		return ""
	}
	return c.FirstName
}

// AdminRatings liste les notes de livraison (d'un livreur si demandé).
func (s *Service) AdminRatings(ctx context.Context, driverID *uuid.UUID, limit, offset int32) ([]Rating, error) {
	rows, err := store.New(s.db.Conn(ctx)).ListDeliveryRatings(ctx, store.ListDeliveryRatingsParams{DriverID: driverID, Lim: limit, Off: offset})
	if err != nil {
		return nil, fmt.Errorf("notes : %w", err)
	}
	out := make([]Rating, len(rows))
	for i, r := range rows {
		out[i] = toRating(r)
		out[i].DriverName = s.name(ctx, r.DriverID)
		out[i].RaterName = s.name(ctx, r.RaterID)
		if o, err := s.orders.AdminGet(ctx, r.OrderID); err == nil {
			out[i].OrderReference = o.Reference
		}
	}
	return out, nil
}

// AdminFeedback liste les avis sur les applications.
func (s *Service) AdminFeedback(ctx context.Context, limit, offset int32) ([]Feedback, error) {
	rows, err := store.New(s.db.Conn(ctx)).ListAppFeedback(ctx, store.ListAppFeedbackParams{Lim: limit, Off: offset})
	if err != nil {
		return nil, fmt.Errorf("avis : %w", err)
	}
	out := make([]Feedback, len(rows))
	for i, r := range rows {
		out[i] = Feedback{ID: r.ID, App: r.App, Stars: r.Stars, Comment: r.Comment, CreatedAt: r.CreatedAt, UserName: s.name(ctx, r.UserID)}
	}
	return out, nil
}

// Scores donne la moyenne des livreurs les plus notés et celle de chaque application.
func (s *Service) Scores(ctx context.Context) ([]DriverScore, []AppScore, error) {
	st := store.New(s.db.Conn(ctx))
	rows, err := st.DriverAverages(ctx)
	if err != nil {
		return nil, nil, fmt.Errorf("moyennes : %w", err)
	}
	drivers := make([]DriverScore, len(rows))
	for i, r := range rows {
		drivers[i] = DriverScore{DriverID: r.DriverID, DriverName: s.name(ctx, r.DriverID), Average: r.Average, Ratings: r.Ratings, Low: r.Low}
	}
	apps, err := st.AppAverages(ctx)
	if err != nil {
		return nil, nil, fmt.Errorf("moyennes : %w", err)
	}
	out := make([]AppScore, len(apps))
	for i, a := range apps {
		out[i] = AppScore{App: a.App, Average: a.Average, Ratings: a.Ratings}
	}
	return drivers, out, nil
}

// DriverScore donne la moyenne d'un livreur (fiche du back-office, app livreur).
func (s *Service) DriverScore(ctx context.Context, driverID uuid.UUID) (float64, int32, error) {
	r, err := store.New(s.db.Conn(ctx)).DriverAverage(ctx, driverID)
	if err != nil {
		return 0, 0, fmt.Errorf("moyenne : %w", err)
	}
	return r.Average, r.Ratings, nil
}

// --- HTTP -------------------------------------------------------------------------------------

// Register enregistre les routes.
func (s *Service) Register(rt *httpapi.Router) {
	rt.Roles("GET /v1/orders/{id}/rating", s.getFor(RoleBuyer), identity.RoleBuyer)
	rt.Roles("POST /v1/orders/{id}/rating", s.rateFor(RoleBuyer), identity.RoleBuyer)
	rt.Roles("GET /v1/seller/orders/{id}/driver-rating", s.getFor(RoleSeller), identity.RoleSeller)
	rt.Roles("POST /v1/seller/orders/{id}/driver-rating", s.rateFor(RoleSeller), identity.RoleSeller)
	rt.Auth("POST /v1/me/app-feedback", s.feedback)
	rt.Roles("GET /v1/driver/rating", s.driverOwn, identity.RoleDriver)
	rt.Roles("GET /v1/admin/ratings", s.adminRatings, identity.RoleAdmin)
	rt.Roles("GET /v1/admin/app-feedback", s.adminFeedback, identity.RoleAdmin)
	rt.Roles("GET /v1/admin/rating-scores", s.adminScores, identity.RoleAdmin)
}

func who(r *http.Request) uuid.UUID { return identity.MustFromContext(r.Context()).UserID }

func (s *Service) getFor(role string) httpapi.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) error {
		id, err := httpapi.PathUUID(r, "id")
		if err != nil {
			return err
		}
		out, err := s.ForOrder(r.Context(), who(r), role, id)
		if err != nil {
			return err
		}
		return httpapi.OK(w, out)
	}
}

func (s *Service) rateFor(role string) httpapi.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) error {
		id, err := httpapi.PathUUID(r, "id")
		if err != nil {
			return err
		}
		var in Input
		if err := httpapi.Decode(r, &in); err != nil {
			return err
		}
		out, err := s.Rate(r.Context(), who(r), role, id, in)
		if err != nil {
			return err
		}
		return httpapi.Created(w, out)
	}
}

func (s *Service) feedback(w http.ResponseWriter, r *http.Request) error {
	var in struct {
		App     string `json:"app"`
		Stars   int16  `json:"stars"`
		Comment string `json:"comment"`
	}
	if err := httpapi.Decode(r, &in); err != nil {
		return err
	}
	out, err := s.AppFeedback(r.Context(), who(r), in.App, in.Stars, in.Comment)
	if err != nil {
		return err
	}
	return httpapi.Created(w, out)
}

func (s *Service) driverOwn(w http.ResponseWriter, r *http.Request) error {
	avg, n, err := s.DriverScore(r.Context(), who(r))
	if err != nil {
		return err
	}
	return httpapi.OK(w, map[string]any{"average": avg, "ratings": n})
}

func (s *Service) adminRatings(w http.ResponseWriter, r *http.Request) error {
	q := httpapi.NewQuery(r)
	page := q.Page()
	driver := q.UUID("driver_id")
	if err := q.Err(); err != nil {
		return err
	}
	items, err := s.AdminRatings(r.Context(), driver, page.FetchLimit(), int32(page.Offset))
	if err != nil {
		return err
	}
	return httpapi.OK(w, httpapi.NewList(items, page))
}

func (s *Service) adminFeedback(w http.ResponseWriter, r *http.Request) error {
	q := httpapi.NewQuery(r)
	page := q.Page()
	if err := q.Err(); err != nil {
		return err
	}
	items, err := s.AdminFeedback(r.Context(), page.FetchLimit(), int32(page.Offset))
	if err != nil {
		return err
	}
	return httpapi.OK(w, httpapi.NewList(items, page))
}

func (s *Service) adminScores(w http.ResponseWriter, r *http.Request) error {
	drivers, apps, err := s.Scores(r.Context())
	if err != nil {
		return err
	}
	return httpapi.OK(w, map[string]any{"drivers": drivers, "apps": apps})
}
