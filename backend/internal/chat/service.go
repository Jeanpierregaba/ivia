// Package chat est la messagerie de la course (spec 037) : client ↔ livreur et livreur ↔ boutique.
// Elle s'ouvre quand un livreur a accepté la course et passe en lecture seule une fois la course
// terminée. Seuls les participants de la commande y ont accès (sinon 404). Les messages ne sont
// jamais écrits dans les journaux.
package chat

import (
	"context"
	"fmt"
	"net/http"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/google/uuid"

	"ivia/backend/internal/chat/store"
	"ivia/backend/internal/notifications"
	"ivia/backend/internal/orders"
	"ivia/backend/internal/platform/apperr"
	"ivia/backend/internal/platform/database"
	"ivia/backend/internal/platform/httpapi"
	"ivia/backend/internal/platform/identity"
	"ivia/backend/internal/platform/ratelimit"
	"ivia/backend/internal/platform/validate"
	"ivia/backend/internal/shops"
	"ivia/backend/internal/users"
)

// Fils de discussion d'une commande.
const (
	ThreadBuyerDriver = "buyer_driver"
	ThreadDriverShop  = "driver_shop"
)

// Rôles des participants.
const (
	RoleBuyer  = "buyer"
	RoleDriver = "driver"
	RoleSeller = "seller"
)

// Drivers donne le livreur d'une commande et si sa course est en cours.
type Drivers interface {
	ChatDriver(ctx context.Context, orderID uuid.UUID) (driverID *uuid.UUID, active bool, err error)
}

// Message est un message d'un fil.
type Message struct {
	ID         uuid.UUID `json:"id"`
	Mine       bool      `json:"mine"`
	SenderRole string    `json:"sender_role"`
	Body       string    `json:"body"`
	CreatedAt  time.Time `json:"created_at"`
}

// Thread est un fil vu par un participant.
type Thread struct {
	OrderID        uuid.UUID  `json:"order_id"`
	OrderReference string     `json:"order_reference"`
	Thread         string     `json:"thread"`
	CanSend        bool       `json:"can_send"`
	OtherName      string     `json:"other_name"`
	OtherRole      string     `json:"other_role"`
	OtherReadAt    *time.Time `json:"other_read_at"`
	Messages       []Message  `json:"messages"`
}

// Service gère la messagerie.
type Service struct {
	db      *database.DB
	orders  *orders.Service
	shops   *shops.Service
	users   *users.Service
	drivers Drivers
	notify  *notifications.Service
	limiter *ratelimit.Limiter
}

// NewService crée le service.
func NewService(db *database.DB, o *orders.Service, sh *shops.Service, u *users.Service, d Drivers, n *notifications.Service) *Service {
	// 30 messages par minute et par compte : une conversation, pas un envoi de masse.
	return &Service{db: db, orders: o, shops: sh, users: u, drivers: d, notify: n, limiter: ratelimit.New(30, time.Minute)}
}

var errNotFound = apperr.NotFound("chat_not_found", "Discussion introuvable.")

type party struct {
	reference        string
	buyer, owner     uuid.UUID
	driver           uuid.UUID
	active           bool
	other            uuid.UUID
	otherRole, appOf string
	otherApp         notifications.App
	thread           string
}

// resolve vérifie que l'utilisateur participe au fil et donne l'autre participant.
func (s *Service) resolve(ctx context.Context, userID uuid.UUID, role string, orderID uuid.UUID, thread string) (party, error) {
	o, err := s.orders.ForDelivery(ctx, orderID)
	if err != nil {
		return party{}, errNotFound
	}
	shop, err := s.shops.Get(ctx, o.ShopID)
	if err != nil {
		return party{}, err
	}
	driver, active, err := s.drivers.ChatDriver(ctx, orderID)
	if err != nil {
		return party{}, err
	}
	p := party{reference: o.Reference, buyer: o.BuyerID, owner: shop.OwnerID, active: active, thread: thread}
	switch {
	case role == RoleBuyer && thread == ThreadBuyerDriver && userID == o.BuyerID:
	case role == RoleSeller && thread == ThreadDriverShop && userID == shop.OwnerID:
	case role == RoleDriver && driver != nil && userID == *driver && (thread == ThreadBuyerDriver || thread == ThreadDriverShop):
	default:
		return party{}, errNotFound
	}
	if driver == nil {
		return party{}, apperr.Conflict("chat_unavailable", "La discussion s'ouvre dès qu'un livreur a accepté la course.")
	}
	p.driver = *driver
	switch {
	case role == RoleDriver && thread == ThreadBuyerDriver:
		p.other, p.otherRole, p.otherApp = o.BuyerID, RoleBuyer, notifications.AppBuyer
	case role == RoleDriver:
		p.other, p.otherRole, p.otherApp = shop.OwnerID, RoleSeller, notifications.AppSeller
	default:
		p.other, p.otherRole, p.otherApp = *driver, RoleDriver, notifications.AppDriver
	}
	return p, nil
}

func (s *Service) otherName(ctx context.Context, p party, orderID uuid.UUID) string {
	if p.otherRole == RoleSeller {
		if o, err := s.orders.ForDelivery(ctx, orderID); err == nil {
			if sh, err := s.shops.Get(ctx, o.ShopID); err == nil {
				return sh.Name
			}
		}
	}
	if c, err := s.users.Contact(ctx, p.other); err == nil && c.FirstName != "" {
		return c.FirstName
	}
	return map[string]string{RoleBuyer: "Client", RoleDriver: "Livreur", RoleSeller: "Boutique"}[p.otherRole]
}

// Get retourne le fil et le marque lu.
func (s *Service) Get(ctx context.Context, userID uuid.UUID, role string, orderID uuid.UUID, thread string) (Thread, error) {
	p, err := s.resolve(ctx, userID, role, orderID, thread)
	if err != nil {
		return Thread{}, err
	}
	q := store.New(s.db.Conn(ctx))
	rows, err := q.ListMessages(ctx, store.ListMessagesParams{OrderID: orderID, Thread: thread})
	if err != nil {
		return Thread{}, fmt.Errorf("messages : %w", err)
	}
	if err := q.MarkRead(ctx, store.MarkReadParams{OrderID: orderID, Thread: thread, UserID: userID}); err != nil {
		return Thread{}, fmt.Errorf("lecture : %w", err)
	}
	out := Thread{
		OrderID: orderID, OrderReference: p.reference, Thread: thread, CanSend: p.active,
		OtherName: s.otherName(ctx, p, orderID), OtherRole: p.otherRole, Messages: make([]Message, len(rows)),
	}
	if at, err := q.LastRead(ctx, store.LastReadParams{OrderID: orderID, Thread: thread, UserID: p.other}); err == nil {
		out.OtherReadAt = &at
	}
	for i, r := range rows {
		out.Messages[i] = Message{ID: r.ID, Mine: r.SenderID == userID, SenderRole: r.SenderRole, Body: r.Body, CreatedAt: r.CreatedAt}
	}
	// L'autre participant voit ses messages passer « lus ».
	_ = s.notify.Signal(ctx, p.other, p.otherApp, "chat_read", map[string]string{"order_id": orderID.String(), "thread": thread})
	return out, nil
}

// Send envoie un message ; l'autre participant le reçoit en direct et par push.
func (s *Service) Send(ctx context.Context, userID uuid.UUID, role string, orderID uuid.UUID, thread, body string) (Message, error) {
	body = strings.TrimSpace(validate.Clean(body))
	if body == "" || utf8.RuneCountInString(body) > 1000 {
		return Message{}, apperr.Validation(map[string]string{"body": "Message de 1 à 1000 caractères."})
	}
	if ok, retry := s.limiter.Allow(userID.String()); !ok {
		return Message{}, apperr.TooManyRequests("rate_limited", "Trop de messages d'un coup. Patientez un instant.", retry)
	}
	p, err := s.resolve(ctx, userID, role, orderID, thread)
	if err != nil {
		return Message{}, err
	}
	if !p.active {
		return Message{}, apperr.Conflict("chat_closed", "La course est terminée : la discussion est fermée.")
	}
	var out Message
	err = s.db.InTx(ctx, func(ctx context.Context) error {
		r, err := store.New(s.db.Conn(ctx)).InsertMessage(ctx, store.InsertMessageParams{
			OrderID: orderID, Thread: thread, SenderID: userID, SenderRole: role, Body: body,
		})
		if err != nil {
			return fmt.Errorf("message : %w", err)
		}
		out = Message{ID: r.ID, Mine: true, SenderRole: role, Body: r.Body, CreatedAt: r.CreatedAt}
		sender := map[string]string{RoleBuyer: "du client", RoleDriver: "du livreur", RoleSeller: "de la boutique"}[role]
		if c, err := s.users.Contact(ctx, userID); err == nil && c.FirstName != "" && role != RoleSeller {
			sender = "de " + c.FirstName
		}
		preview := body
		if utf8.RuneCountInString(preview) > 120 {
			preview = string([]rune(preview)[:117]) + "…"
		}
		return s.notify.Notify(ctx, notifications.Message{
			UserID: p.other, App: p.otherApp, Kind: "chat_message",
			Title: "Message " + sender + " · " + p.reference, Body: preview,
			Data: map[string]string{"order_id": orderID.String(), "thread": thread, "from": role},
		})
	})
	return out, err
}

// --- HTTP -------------------------------------------------------------------------------------

// Register enregistre les routes.
func (s *Service) Register(rt *httpapi.Router) {
	rt.Roles("GET /v1/orders/{id}/chat", s.get(RoleBuyer, ThreadBuyerDriver), identity.RoleBuyer)
	rt.Roles("POST /v1/orders/{id}/chat", s.send(RoleBuyer, ThreadBuyerDriver), identity.RoleBuyer)
	rt.Roles("GET /v1/seller/orders/{id}/chat", s.get(RoleSeller, ThreadDriverShop), identity.RoleSeller)
	rt.Roles("POST /v1/seller/orders/{id}/chat", s.send(RoleSeller, ThreadDriverShop), identity.RoleSeller)
	rt.Roles("GET /v1/driver/orders/{id}/chat/{with}", s.get(RoleDriver, ""), identity.RoleDriver)
	rt.Roles("POST /v1/driver/orders/{id}/chat/{with}", s.send(RoleDriver, ""), identity.RoleDriver)
}

// threadOf : fil demandé ; pour le livreur, {with} = client ou shop.
func threadOf(r *http.Request, fixed string) (string, error) {
	if fixed != "" {
		return fixed, nil
	}
	switch r.PathValue("with") {
	case "client":
		return ThreadBuyerDriver, nil
	case "shop":
		return ThreadDriverShop, nil
	}
	return "", errNotFound
}

func (s *Service) get(role, fixed string) httpapi.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) error {
		id, err := httpapi.PathUUID(r, "id")
		if err != nil {
			return err
		}
		thread, err := threadOf(r, fixed)
		if err != nil {
			return err
		}
		t, err := s.Get(r.Context(), identity.MustFromContext(r.Context()).UserID, role, id, thread)
		if err != nil {
			return err
		}
		return httpapi.OK(w, t)
	}
}

func (s *Service) send(role, fixed string) httpapi.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) error {
		id, err := httpapi.PathUUID(r, "id")
		if err != nil {
			return err
		}
		thread, err := threadOf(r, fixed)
		if err != nil {
			return err
		}
		var in struct {
			Body string `json:"body"`
		}
		if err := httpapi.Decode(r, &in); err != nil {
			return err
		}
		m, err := s.Send(r.Context(), identity.MustFromContext(r.Context()).UserID, role, id, thread, in.Body)
		if err != nil {
			return err
		}
		return httpapi.Created(w, m)
	}
}
