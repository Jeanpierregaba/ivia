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

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"

	"ivia/backend/internal/admin"
	"ivia/backend/internal/auth"
	"ivia/backend/internal/business"
	"ivia/backend/internal/cart"
	"ivia/backend/internal/catalog"
	"ivia/backend/internal/delivery"
	"ivia/backend/internal/geo"
	"ivia/backend/internal/mapping"
	"ivia/backend/internal/notifications"
	"ivia/backend/internal/orders"
	"ivia/backend/internal/payments"
	"ivia/backend/internal/pharmacy"
	"ivia/backend/internal/platform/apperr"
	"ivia/backend/internal/platform/config"
	"ivia/backend/internal/platform/database"
	"ivia/backend/internal/platform/docs"
	"ivia/backend/internal/platform/errtrack"
	"ivia/backend/internal/platform/httpapi"
	"ivia/backend/internal/platform/jobs"
	"ivia/backend/internal/platform/storage"
	"ivia/backend/internal/promo"
	"ivia/backend/internal/properties"
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
	Promo         *promo.Service
	Pharmacy      *pharmacy.Service
	Properties    *properties.Service
	Business      *business.Service
	Mapping       *mapping.Service

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
	a.Auth = auth.NewService(db, a.Users, otpSender, logger, auth.Options{
		Secret: cfg.AuthSecret, SessionTTL: cfg.SessionTTL, GoogleClientIDs: cfg.GoogleClientIDs,
		PhoneChannels: a.phoneChannels(), PhoneCodesPerHour: cfg.PhoneCodesPerHour,
	})
	a.Auth.SetAuditor(a.Admin)
	a.Uploads = uploads.NewService(objectStore)
	a.Users.SetAvatars(a.Uploads)
	a.Notifications = notifications.NewService(db, enq, a.Users, push, logger)
	a.Auth.SetNotifier(authNotifier{a.Notifications})
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
	a.Promo = promo.NewService(db, a.Uploads, a.Catalog, a.Orders, a.Admin)
	a.Pharmacy = pharmacy.NewService(pharmacy.Deps{
		DB: db, Jobs: enq, Admin: a.Admin, Users: a.Users, Geo: a.Geo, Uploads: a.Uploads, Notify: a.Notifications,
		Payments: a.Payments, Delivery: a.Delivery, Logger: logger, Mail: a.buildEmailSender(),
	})

	a.Properties = properties.NewService(db, a.Uploads, a.Admin)
	if a.Mapping, err = mapping.New(db, a.Admin, logger, mapping.Config{
		Routing: cfg.GeoRoutingProvider, Geocoding: cfg.GeoGeocodingProvider, Places: cfg.GeoPlacesProvider,
		OSRMCar: cfg.OSRMURL, OSRMMoto: cfg.OSRMMotoURL, NominatimURL: cfg.NominatimURL,
		GooglePlacesKey: cfg.GooglePlacesAPIKey, RedisURL: cfg.RedisURL,
	}); err != nil {
		return nil, fmt.Errorf("carte : %w", err)
	}
	// Arrivée estimée du livreur chez la pharmacie (spec 032).
	a.Pharmacy.SetRouter(a.Mapping)
	a.Business = business.NewService(db, a.Shops, a.Users, a.Uploads, a.Admin, a.Notifications)

	// Suppression de compte : les modules qui bloquent, puis ceux qui effacent leurs données.
	a.Users.AddDeletionGuard(a.Orders)
	a.Users.AddDeletionGuard(a.Delivery)
	a.Users.AddDeletionGuard(a.Pharmacy)
	a.Users.AddDeletionHook(a.Auth)
	a.Users.AddDeletionHook(a.Orders)
	a.Users.AddDeletionHook(a.Delivery)
	a.Users.AddDeletionHook(a.Shops)
	a.Users.AddDeletionHook(a.Business)
	a.Users.AddDeletionHook(a.Mapping)
	a.Users.AddDeletionHook(a.Cart)
	a.Users.AddDeletionHook(a.Notifications)
	a.Users.AddDeletionHook(a.Pharmacy)

	reg := jobs.NewRegistry()
	a.Auth.RegisterJobs(reg)
	a.Notifications.RegisterJobs(reg)
	a.Orders.RegisterJobs(reg)
	a.Payments.RegisterJobs(reg)
	a.Delivery.RegisterJobs(reg)
	a.Pharmacy.RegisterJobs(reg)
	a.Mapping.RegisterJobs(reg)
	a.Uploads.RegisterJobs(reg, logger)
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
	promo.NewHandler(a.Promo).Register(rt)
	a.Properties.Register(rt)
	a.Business.Register(rt)
	a.Mapping.Register(rt, a.Delivery)
	var devPayments *payments.FakeProvider
	if a.Config.DevToolsEnabled() {
		devPayments = a.FakePayment
	}
	pharmacy.NewHandler(a.Pharmacy, devPayments).Register(rt)
	reports.NewHandler(a.Orders, a.Delivery, a.Payments, a.Shops, a.Users, a.Admin).Register(rt)

	if a.Config.Env != config.EnvProduction { // documentation interactive : local, test, staging
		rt.Raw(docs.PageRoute, http.HandlerFunc(docs.Page))
		rt.Raw(docs.SpecRoute, http.HandlerFunc(docs.Spec))
	}
	if a.Config.DevToolsEnabled() {
		if a.LocalStore != nil {
			rt.Raw("/dev/storage/", a.LocalStore.Handler())
		}
		rt.Auth("POST /v1/dev/medicine-alerts/{id}/auto-respond", a.devAutoRespond)
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

// buildEmailSender choisit l'envoi des e-mails d'information, comme celui des codes : Mailpit en
// local, Brevo en production.
func (a *App) buildEmailSender() notifications.EmailSender {
	cfg := a.Config
	switch cfg.OTPSender {
	case "brevo":
		return &notifications.BrevoEmail{APIKey: cfg.BrevoAPIKey, SenderEmail: cfg.BrevoSenderMail, SenderName: cfg.BrevoSenderName}
	case "smtp":
		return &notifications.SMTPEmail{Addr: cfg.SMTPAddr, From: cfg.SMTPFrom}
	}
	return &notifications.LogEmail{Logger: a.Logger}
}

// buildOTPSender assemble les expéditeurs de codes : e-mail (OTP_SENDER), WhatsApp
// (PHONE_OTP_SENDER) et SMS (SMS_SENDER). En local, chaque code est aussi gardé pour
// POST /v1/dev/otp.
func (a *App) buildOTPSender() (auth.OTPSender, error) {
	cfg := a.Config
	dev := func() *auth.LogSender {
		if a.DevOTP == nil {
			a.DevOTP = &auth.LogSender{Logger: a.Logger}
		}
		return a.DevOTP
	}
	var r auth.ChannelRouter
	switch cfg.OTPSender {
	case "brevo":
		r.Email = &auth.BrevoSender{APIKey: cfg.BrevoAPIKey, SenderEmail: cfg.BrevoSenderMail, SenderName: cfg.BrevoSenderName}
	case "log":
		r.Email = dev()
	case "smtp":
		// E-mail dans la boîte locale Mailpit, et code gardé pour POST /v1/dev/otp.
		r.Email = auth.TeeSender{&auth.SMTPSender{Addr: cfg.SMTPAddr, From: cfg.SMTPFrom}, dev()}
	default:
		return nil, fmt.Errorf("envoi OTP inconnu : %s", cfg.OTPSender)
	}
	switch cfg.PhoneOTPSender {
	case "whatsapp":
		r.WhatsApp = &auth.WhatsAppSender{PhoneNumberID: cfg.WhatsAppPhoneNumberID, AccessToken: cfg.WhatsAppAccessToken,
			Template: cfg.WhatsAppTemplate, Language: cfg.WhatsAppTemplateLang}
	case "log":
		r.WhatsApp = dev()
	}
	if cfg.SMSSender == "log" {
		r.SMS = dev()
	}
	return r, nil
}

// phoneChannels : canaux ouverts pour la connexion par numéro, WhatsApp d'abord.
func (a *App) phoneChannels() []auth.Channel {
	var out []auth.Channel
	if a.Config.PhoneOTPSender == "whatsapp" || a.Config.PhoneOTPSender == "log" {
		out = append(out, auth.ChannelWhatsApp)
	}
	// SMS toujours proposé dès que la connexion par numéro est ouverte : tant que le fournisseur
	// n'est pas branché (SMS_SENDER=none), l'envoi par SMS échoue et le code part par WhatsApp.
	if len(out) > 0 {
		out = append(out, auth.ChannelSMS)
	}
	return out
}

// authNotifier relie les alertes de sécurité du module auth aux notifications.
type authNotifier struct{ n *notifications.Service }

func (a authNotifier) NotifyAdmins(ctx context.Context, kind, title, body string, data map[string]string) error {
	return a.n.NotifyAdmins(ctx, kind, title, body, data)
}

func (a authNotifier) NotifyUser(ctx context.Context, userID uuid.UUID, app, kind, title, body string, data map[string]string) error {
	return a.n.Notify(ctx, notifications.Message{UserID: userID, App: notifications.App(app), Kind: kind, Title: title, Body: body, Data: data})
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
