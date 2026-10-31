// Package app assemble l'application : services des modules, tâches de fond et routeur HTTP.
// Il est utilisé par le serveur (cmd/api), la ligne de commande d'administration (cmd/manage) et
// les tests de bout en bout.
package app

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"ivia/backend/internal/admin"
	"ivia/backend/internal/auth"
	"ivia/backend/internal/cart"
	"ivia/backend/internal/catalog"
	"ivia/backend/internal/delivery"
	"ivia/backend/internal/geo"
	"ivia/backend/internal/notifications"
	"ivia/backend/internal/orders"
	"ivia/backend/internal/payments"
	"ivia/backend/internal/platform/apperr"
	"ivia/backend/internal/platform/config"
	"ivia/backend/internal/platform/database"
	"ivia/backend/internal/platform/docs"
	"ivia/backend/internal/platform/errtrack"
	"ivia/backend/internal/platform/httpapi"
	"ivia/backend/internal/platform/jobs"
	"ivia/backend/internal/platform/storage"
	"ivia/backend/internal/reports"
	"ivia/backend/internal/search"
	"ivia/backend/internal/settlements"
	"ivia/backend/internal/shops"
	"ivia/backend/internal/stock"
	"ivia/backend/internal/uploads"
	"ivia/backend/internal/users"
)

// App regroupe les services assemblés.
type App struct {
	Config  config.Config
	Logger  *slog.Logger
	DB      *database.DB
	Queue   *jobs.Queue
	Handler http.Handler
	// Errors remonte les erreurs inattendues (Sentry si SENTRY_DSN, sinon rien).
	Errors errtrack.Reporter
	// Routes enregistrées (« MÉTHODE /chemin »).
	Routes []string

	Admin         *admin.Service
	Geo           *geo.Service
	Users         *users.Service
	Auth          *auth.Service
	Uploads       *uploads.Service
	Notifications *notifications.Service
	Shops         *shops.Service
	Stock         *stock.Service
	Catalog       *catalog.Service
	Cart          *cart.Service
	Orders        *orders.Service
	Payments      *payments.Service
	Delivery      *delivery.Service
	Settlements   *settlements.Service

	// Implémentations factices exposées en local et dans les tests (nil sinon).
	DevOTP      *auth.LogSender
	FakePayment *payments.FakeProvider
	LocalStore  *storage.Local
}

// Options ajuste l'assemblage (tests).
type Options struct {
	// PollInterval des tâches de fond (0 : valeur par défaut de River).
	PollInterval time.Duration
}

// New assemble l'application. Les migrations doivent avoir été appliquées.
func New(cfg config.Config, logger *slog.Logger, pool *pgxpool.Pool, opts Options) (*App, error) {
	a := &App{Config: cfg, Logger: logger, DB: database.New(pool), Errors: errtrack.Nop{}}
	enq := &jobs.Deferred{}
	if cfg.SentryDSN != "" {
		s, err := errtrack.NewSentry(cfg.SentryDSN, cfg.Env, cfg.Version)
		if err != nil {
			return nil, err
		}
		a.Errors = s
	}

	objectStore, err := a.buildStorage()
	if err != nil {
		return nil, err
	}
	otpSender, err := a.buildOTPSender()
	if err != nil {
		return nil, err
	}
	push, err := a.buildPush()
	if err != nil {
		return nil, err
	}
	provider, err := a.buildPaymentProvider()
	if err != nil {
		return nil, err
	}

	db := a.DB
	a.Admin = admin.NewService(db)
	a.Geo = geo.NewService(db, a.Admin)
	a.Users = users.NewService(db, a.Geo, a.Admin)
	a.Auth = auth.NewService(db, a.Users, otpSender, logger, auth.Options{Secret: cfg.AuthSecret, SessionTTL: cfg.SessionTTL})
	a.Uploads = uploads.NewService(objectStore)
	a.Notifications = notifications.NewService(db, enq, a.Users, push, logger)
	a.Shops = shops.NewService(db, a.Geo, a.Users, a.Uploads, a.Admin, a.Notifications)
	a.Stock = stock.NewService(db)
	a.Catalog = catalog.NewService(db, a.Shops, a.Stock, a.Uploads, a.Admin)
	a.Cart = cart.NewService(db, a.Catalog, a.Shops)
	a.Orders = orders.NewService(orders.Deps{
		DB: db, Jobs: enq, Admin: a.Admin, Users: a.Users, Geo: a.Geo, Shops: a.Shops, Catalog: a.Catalog,
		Stock: a.Stock, Cart: a.Cart, Notify: a.Notifications, Logger: logger,
	})
	a.Payments = payments.NewService(db, enq, provider, a.Orders, a.Admin, a.Notifications, logger)
	a.Delivery = delivery.NewService(delivery.Deps{
		DB: db, Jobs: enq, Admin: a.Admin, Users: a.Users, Geo: a.Geo, Shops: a.Shops, Orders: a.Orders,
		Uploads: a.Uploads, Notify: a.Notifications, Logger: logger,
	})
	a.Settlements = settlements.NewService(db, a.Orders, a.Shops, a.Admin, a.Notifications)

	// Suppression de compte : les modules qui bloquent, puis ceux qui effacent leurs données.
	a.Users.AddDeletionGuard(a.Orders)
	a.Users.AddDeletionGuard(a.Delivery)
	a.Users.AddDeletionHook(a.Auth)
	a.Users.AddDeletionHook(a.Orders)
	a.Users.AddDeletionHook(a.Delivery)
	a.Users.AddDeletionHook(a.Shops)
	a.Users.AddDeletionHook(a.Cart)
	a.Users.AddDeletionHook(a.Notifications)

	reg := jobs.NewRegistry()
	a.Auth.RegisterJobs(reg)
	a.Notifications.RegisterJobs(reg)
	a.Orders.RegisterJobs(reg)
	a.Payments.RegisterJobs(reg)
	a.Delivery.RegisterJobs(reg)
	if a.Queue, err = jobs.New(pool, reg, jobs.Options{RunWorkers: cfg.RunWorkers, PollInterval: opts.PollInterval, Logger: logger, Reporter: a.Errors}); err != nil {
		return nil, err
	}
	enq.Set(a.Queue)

	a.Handler, a.Routes = a.routes()
	return a, nil
}

func (a *App) routes() (http.Handler, []string) {
	rt := httpapi.NewRouter(httpapi.Options{
		Logger: a.Logger, DB: a.DB.Pool, Auth: a.Auth, TrustProxyHeaders: a.Config.TrustProxyHeaders,
		Reporter: a.Errors,
	})
	auth.NewHandler(a.Auth).Register(rt)
	users.NewHandler(a.Users).Register(rt)
	admin.NewHandler(a.Admin).Register(rt)
	geo.NewHandler(a.Geo).Register(rt)
	a.Uploads.Register(rt)
	notifications.NewHandler(a.Notifications).Register(rt)
	shops.NewHandler(a.Shops).Register(rt)
	catalog.NewHandler(a.Catalog).Register(rt)
	search.NewService(a.DB, a.Uploads).Register(rt)
	cart.NewHandler(a.Cart).Register(rt)
	orders.NewHandler(a.Orders).Register(rt)
	payments.NewHandler(a.Payments, a.Logger, a.Config.DevToolsEnabled()).Register(rt)
	delivery.NewHandler(a.Delivery).Register(rt)
	settlements.NewHandler(a.Settlements).Register(rt)
	reports.NewHandler(a.Orders, a.Delivery, a.Payments).Register(rt)

	if a.Config.Env != config.EnvProduction { // documentation interactive : local, test, staging
		rt.Raw(docs.PageRoute, http.HandlerFunc(docs.Page))
		rt.Raw(docs.SpecRoute, http.HandlerFunc(docs.Spec))
	}
	if a.Config.DevToolsEnabled() {
		if a.LocalStore != nil {
			rt.Raw("/dev/storage/", a.LocalStore.Handler())
		}
		if a.DevOTP != nil {
			// Dernier code envoyé à une adresse : automatisation des tests des apps en local.
			// POST : l'adresse ne doit jamais apparaître dans une URL.
			rt.Public("POST /v1/dev/otp", func(w http.ResponseWriter, r *http.Request) error {
				var in struct {
					Recipient string `json:"recipient"`
				}
				if err := httpapi.Decode(r, &in); err != nil {
					return err
				}
				code, ok := a.DevOTP.LastCode(in.Recipient)
				if !ok {
					return apperr.NotFound("otp_not_found", "Aucun code envoyé à ce destinataire.")
				}
				return httpapi.OK(w, map[string]string{"code": code})
			})
		}
	}
	return rt.Handler(), rt.Patterns()
}

func (a *App) buildStorage() (storage.ObjectStore, error) {
	switch a.Config.Storage {
	case "r2":
		return storage.NewR2(storage.R2Config{
			AccountID: a.Config.R2AccountID, AccessKeyID: a.Config.R2AccessKeyID, SecretAccessKey: a.Config.R2SecretAccessKey,
			PublicBucket: a.Config.R2PublicBucket, PrivateBucket: a.Config.R2PrivateBucket, PublicBaseURL: a.Config.R2PublicBaseURL,
		}), nil
	case "local":
		a.LocalStore = storage.NewLocal(a.Config.LocalStorageDir, a.Config.PublicBaseURL, a.Config.AuthSecret)
		return a.LocalStore, nil
	}
	return nil, fmt.Errorf("stockage inconnu : %s", a.Config.Storage)
}

func (a *App) buildOTPSender() (auth.OTPSender, error) {
	switch a.Config.OTPSender {
	case "brevo":
		return &auth.BrevoSender{APIKey: a.Config.BrevoAPIKey, SenderEmail: a.Config.BrevoSenderMail, SenderName: a.Config.BrevoSenderName}, nil
	case "log":
		a.DevOTP = &auth.LogSender{Logger: a.Logger}
		return a.DevOTP, nil
	}
	return nil, fmt.Errorf("envoi OTP inconnu : %s", a.Config.OTPSender)
}

func (a *App) buildPush() (notifications.PushSender, error) {
	switch a.Config.PushSender {
	case "fcm":
		return notifications.NewFCMFromFile(a.Config.FCMCredentialsFile)
	case "log":
		return notifications.LogPush{Logger: a.Logger}, nil
	}
	return nil, fmt.Errorf("envoi push inconnu : %s", a.Config.PushSender)
}

func (a *App) buildPaymentProvider() (payments.Provider, error) {
	switch a.Config.PaymentProvider {
	case "fake":
		secret := []byte(a.Config.PaymentWebhookSecret)
		if len(secret) == 0 {
			secret = a.Config.AuthSecret
		}
		a.FakePayment = payments.NewFakeProvider(secret)
		return a.FakePayment, nil
	}
	return nil, errors.New("prestataire de paiement inconnu : " + a.Config.PaymentProvider)
}

// Start démarre les tâches de fond.
func (a *App) Start(ctx context.Context) error { return a.Queue.Start(ctx) }

// Stop arrête les tâches de fond en laissant finir celles en cours (dans la limite de ctx), puis
// envoie les erreurs en attente.
func (a *App) Stop(ctx context.Context) error {
	err := a.Queue.Stop(ctx)
	a.Errors.Flush(2 * time.Second)
	return err
}
