// Package notifications gère la liste des notifications de chaque app et leur envoi en push.
//
// Notify écrit la notification et crée la tâche d'envoi push dans la transaction en cours : si
// l'action métier est annulée, aucune notification n'est envoyée.
package notifications

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"time"

	"github.com/google/uuid"
	"github.com/riverqueue/river"

	"ivia/backend/internal/notifications/store"
	"ivia/backend/internal/platform/apperr"
	"ivia/backend/internal/platform/database"
	"ivia/backend/internal/platform/identity"
	"ivia/backend/internal/platform/jobs"
)

// App destinataire d'une notification.
type App string

const (
	AppBuyer  App = "buyer"
	AppSeller App = "seller"
	AppDriver App = "driver"
	AppAdmin  App = "admin"
	// AppPharmacy : app des pharmacies partenaires (module pharmacy).
	AppPharmacy App = "pharmacy"
)

// Message est une notification à envoyer.
type Message struct {
	UserID uuid.UUID
	App    App
	// Kind est un code stable (ex. order_paid) utilisé par les apps pour ouvrir le bon écran.
	Kind  string
	Title string
	Body  string
	// Data accompagne le push (ex. order_id). Uniquement des identifiants, jamais de donnée personnelle.
	Data map[string]string
}

// Notification est une notification de la liste d'une app.
type Notification struct {
	ID        uuid.UUID         `json:"id"`
	App       App               `json:"app"`
	Kind      string            `json:"kind"`
	Title     string            `json:"title"`
	Body      string            `json:"body"`
	Data      map[string]string `json:"data"`
	ReadAt    *time.Time        `json:"read_at"`
	CreatedAt time.Time         `json:"created_at"`
}

// PushSender envoie un push à un appareil (FCM en production, journal en local). sound : faux si
// la sonnerie des alertes est coupée sur ce téléphone (alerte urgente envoyée sans son sur iOS).
type PushSender interface {
	Send(ctx context.Context, token, title, body string, data map[string]string, sound bool) error
}

// Device : jeton push d'un appareil et son choix de sonnerie des alertes.
type Device struct {
	Token string
	Sound bool
}

// ErrInvalidToken : le jeton de l'appareil n'est plus valable (app désinstallée...).
var ErrInvalidToken = errors.New("jeton push invalide")

// Devices est ce dont le module a besoin du module users.
type Devices interface {
	PushDevices(ctx context.Context, userID uuid.UUID, app string) ([]Device, error)
	ForgetDeviceToken(ctx context.Context, token string) error
	UserIDsWithRole(ctx context.Context, role identity.Role) ([]uuid.UUID, error)
}

// Service gère les notifications.
type Service struct {
	db      *database.DB
	jobs    jobs.Enqueuer
	devices Devices
	push    PushSender
	logger  *slog.Logger
}

// NewService crée le service.
func NewService(db *database.DB, enq jobs.Enqueuer, devices Devices, push PushSender, logger *slog.Logger) *Service {
	return &Service{db: db, jobs: enq, devices: devices, push: push, logger: logger}
}

// Notify enregistre la notification et planifie son envoi push.
func (s *Service) Notify(ctx context.Context, m Message) error {
	data := m.Data
	if data == nil {
		data = map[string]string{}
	}
	raw, err := json.Marshal(data)
	if err != nil {
		return fmt.Errorf("notification : %w", err)
	}
	return s.db.InTx(ctx, func(ctx context.Context) error {
		id, err := store.New(s.db.Conn(ctx)).CreateNotification(ctx, store.CreateNotificationParams{
			UserID: m.UserID, App: string(m.App), Kind: m.Kind, Title: m.Title, Body: m.Body, Data: raw,
		})
		if err != nil {
			return fmt.Errorf("création de la notification : %w", err)
		}
		if m.App == AppAdmin {
			return nil // le back-office n'a pas de push : la liste suffit.
		}
		return s.jobs.Enqueue(ctx, SendPushArgs{NotificationID: id}, nil)
	})
}

// NotifyAdmins prévient tous les admins (alertes du back-office).
func (s *Service) NotifyAdmins(ctx context.Context, kind, title, body string, data map[string]string) error {
	ids, err := s.devices.UserIDsWithRole(ctx, identity.RoleAdmin)
	if err != nil {
		return err
	}
	for _, id := range ids {
		if err := s.Notify(ctx, Message{UserID: id, App: AppAdmin, Kind: kind, Title: title, Body: body, Data: data}); err != nil {
			return err
		}
	}
	return nil
}

// List retourne les notifications d'un utilisateur pour une app, avec le nombre de non lues.
func (s *Service) List(ctx context.Context, userID uuid.UUID, app App, limit, offset int32) ([]Notification, int64, error) {
	q := store.New(s.db.Conn(ctx))
	rows, err := q.ListNotifications(ctx, store.ListNotificationsParams{UserID: userID, App: string(app), Lim: limit, Off: offset})
	if err != nil {
		return nil, 0, fmt.Errorf("liste des notifications : %w", err)
	}
	unread, err := q.CountUnread(ctx, store.CountUnreadParams{UserID: userID, App: string(app)})
	if err != nil {
		return nil, 0, fmt.Errorf("décompte des notifications : %w", err)
	}
	out := make([]Notification, len(rows))
	for i, r := range rows {
		out[i] = toNotification(r)
	}
	return out, unread, nil
}

// MarkRead marque une notification de l'utilisateur comme lue.
func (s *Service) MarkRead(ctx context.Context, userID, id uuid.UUID) error {
	n, err := store.New(s.db.Conn(ctx)).MarkRead(ctx, store.MarkReadParams{ID: id, UserID: userID})
	if err != nil {
		return fmt.Errorf("lecture de la notification : %w", err)
	}
	if n == 0 {
		return apperr.NotFound("notification_not_found", "Notification introuvable.")
	}
	return nil
}

// MarkAllRead marque toutes les notifications d'une app comme lues.
func (s *Service) MarkAllRead(ctx context.Context, userID uuid.UUID, app App) error {
	if err := store.New(s.db.Conn(ctx)).MarkAllRead(ctx, store.MarkAllReadParams{UserID: userID, App: string(app)}); err != nil {
		return fmt.Errorf("lecture des notifications : %w", err)
	}
	return nil
}

// Delete supprime une notification du compte ; celle d'un autre compte est introuvable.
func (s *Service) Delete(ctx context.Context, userID, id uuid.UUID) error {
	n, err := store.New(s.db.Conn(ctx)).DeleteNotification(ctx, store.DeleteNotificationParams{ID: id, UserID: userID})
	if err != nil {
		return fmt.Errorf("suppression de la notification : %w", err)
	}
	if n == 0 {
		return apperr.NotFound("notification_not_found", "Notification introuvable.")
	}
	return nil
}

// DeleteAll supprime toutes les notifications d'une app du compte.
func (s *Service) DeleteAll(ctx context.Context, userID uuid.UUID, app App) error {
	if err := store.New(s.db.Conn(ctx)).DeleteAppNotifications(ctx, store.DeleteAppNotificationsParams{UserID: userID, App: string(app)}); err != nil {
		return fmt.Errorf("suppression des notifications : %w", err)
	}
	return nil
}

// OnAccountDeleted supprime les notifications du compte (users.DeletionHook) : elles peuvent
// contenir des informations personnelles.
func (s *Service) OnAccountDeleted(ctx context.Context, userID uuid.UUID) error {
	if err := store.New(s.db.Conn(ctx)).DeleteUserNotifications(ctx, userID); err != nil {
		return fmt.Errorf("suppression des notifications : %w", err)
	}
	return nil
}

func (s *Service) sendPush(ctx context.Context, id uuid.UUID) error {
	q := store.New(s.db.Conn(ctx))
	n, err := q.GetNotification(ctx, id)
	if database.IsNoRows(err) {
		return nil // compte supprimé entre-temps
	}
	if err != nil {
		return fmt.Errorf("lecture de la notification : %w", err)
	}
	if n.PushSentAt != nil {
		return nil // déjà envoyée (tâche rejouée)
	}
	tokens, err := s.devices.PushDevices(ctx, n.UserID, n.App)
	if err != nil {
		return err
	}
	data := map[string]string{}
	_ = json.Unmarshal(n.Data, &data)
	data["notification_id"] = n.ID.String()
	data["kind"] = n.Kind

	var failed error
	for _, d := range tokens {
		err := s.push.Send(ctx, d.Token, n.Title, n.Body, data, d.Sound)
		switch {
		case errors.Is(err, ErrInvalidToken):
			if err := s.devices.ForgetDeviceToken(ctx, d.Token); err != nil {
				return err
			}
		case err != nil:
			failed = err
		}
	}
	if failed != nil && len(tokens) == 1 {
		return fmt.Errorf("envoi push : %w", failed) // River réessaiera
	}
	if failed != nil {
		s.logger.Warn("push partiellement envoyé", "notification_id", n.ID, "err", failed)
	}
	return q.MarkPushSent(ctx, n.ID)
}

func toNotification(r store.Notification) Notification {
	data := map[string]string{}
	_ = json.Unmarshal(r.Data, &data)
	return Notification{
		ID: r.ID, App: App(r.App), Kind: r.Kind, Title: r.Title, Body: r.Body, Data: data,
		ReadAt: r.ReadAt, CreatedAt: r.CreatedAt,
	}
}

// SendPushArgs : envoi push d'une notification.
type SendPushArgs struct {
	NotificationID uuid.UUID `json:"notification_id"`
}

// Kind implémente river.JobArgs.
func (SendPushArgs) Kind() string { return "notifications.send_push" }

// InsertOpts : un push trop vieux n'a plus d'intérêt, on limite les essais.
func (SendPushArgs) InsertOpts() river.InsertOpts { return river.InsertOpts{MaxAttempts: 5} }

type sendPushWorker struct {
	river.WorkerDefaults[SendPushArgs]
	svc *Service
}

func (w *sendPushWorker) Work(ctx context.Context, job *river.Job[SendPushArgs]) error {
	return w.svc.sendPush(ctx, job.Args.NotificationID)
}

// RegisterJobs déclare les tâches de fond du module.
func (s *Service) RegisterJobs(reg *jobs.Registry) {
	river.AddWorker(reg.Workers, &sendPushWorker{svc: s})
}
