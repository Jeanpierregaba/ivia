package orders

import (
	"context"
	"fmt"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/google/uuid"

	"ivia/backend/internal/orders/store"
)

// Données du tableau de bord du back-office (reports.Overview) propres aux commandes.

// Overview : compteurs des commandes en cours, codes bloqués et file de remboursement.
type Overview struct {
	Active         int64 `json:"active"`
	ToAccept       int64 `json:"to_accept"`
	WithoutDriver  int64 `json:"without_driver"`
	HandoverLocked int64 `json:"handover_locked"`
	Refunds        int64 `json:"refunds"`
	RefundsXOF     int64 `json:"refunds_xof"`
}

// Overview retourne les compteurs du moment.
func (s *Service) Overview(ctx context.Context) (Overview, error) {
	r, err := store.New(s.db.Conn(ctx)).OverviewCounts(ctx)
	if err != nil {
		return Overview{}, fmt.Errorf("compteurs des commandes : %w", err)
	}
	return Overview{
		Active: r.Active, ToAccept: r.ToAccept, WithoutDriver: r.WithoutDriver,
		HandoverLocked: r.HandoverLocked, Refunds: r.Refunds, RefundsXOF: r.RefundsXof,
	}, nil
}

// DayByMode : commandes payées un jour, par mode.
type DayByMode struct {
	Day      string `json:"day"`
	Delivery int64  `json:"delivery"`
	Pickup   int64  `json:"pickup"`
}

// PaidPerDayByMode retourne, pour chacun des `days` jours se terminant le jour de `end` (heure
// de Lomé), les commandes payées en livraison et en retrait (jours sans commande compris).
func (s *Service) PaidPerDayByMode(ctx context.Context, end time.Time, days int, loc *time.Location) ([]DayByMode, error) {
	last := time.Date(end.Year(), end.Month(), end.Day(), 0, 0, 0, 0, loc)
	first := last.AddDate(0, 0, -(days - 1))
	rows, err := store.New(s.db.Conn(ctx)).PaidPerDayByMode(ctx, store.PaidPerDayByModeParams{FromTime: first, ToTime: last.AddDate(0, 0, 1)})
	if err != nil {
		return nil, fmt.Errorf("commandes payées par jour : %w", err)
	}
	out := make([]DayByMode, days)
	index := make(map[string]int, days)
	for i := range out {
		d := first.AddDate(0, 0, i).Format(time.DateOnly)
		out[i].Day = d
		index[d] = i
	}
	for _, r := range rows {
		i, ok := index[r.Day.Format(time.DateOnly)]
		if !ok {
			continue
		}
		if r.Fulfillment == string(FulfillmentDelivery) {
			out[i].Delivery = r.N
		} else {
			out[i].Pickup = r.N
		}
	}
	return out, nil
}

// ActiveOrder est une ligne « Commandes en cours » du tableau de bord.
type ActiveOrder struct {
	ID             uuid.UUID `json:"id"`
	Number         int64     `json:"number"`
	Reference      string    `json:"reference"`
	ShopName       string    `json:"shop_name"`
	BuyerName      string    `json:"buyer_name"`
	Fulfillment    string    `json:"fulfillment"`
	TotalXOF       int64     `json:"total_xof"`
	Status         Status    `json:"status"`
	HandoverLocked bool      `json:"handover_locked"`
	// Since : dernier changement de statut.
	Since time.Time `json:"since"`
}

// Groupes des puces « Commandes en cours ».
var activeGroups = map[string][]Status{
	"":               {StatusAwaitingSeller, StatusAccepted, StatusPreparing, StatusReadyForPickup, StatusAwaitingDriver, StatusDriverAssigned, StatusPickedUp},
	"to_accept":      {StatusAwaitingSeller},
	"without_driver": {StatusAwaitingDriver},
	"locked":         {StatusReadyForPickup, StatusDriverAssigned, StatusPickedUp},
}

// ActiveGroupValid indique si le groupe est connu.
func ActiveGroupValid(group string) bool {
	_, ok := activeGroups[group]
	return ok
}

// ActiveOrders retourne les commandes en cours d'un groupe (toutes, à accepter, sans livreur,
// code bloqué), les plus récentes d'abord, avec boutique et acheteur (prénom et initiale).
func (s *Service) ActiveOrders(ctx context.Context, group string, limit int32) ([]ActiveOrder, error) {
	rows, err := store.New(s.db.Conn(ctx)).ActiveOrdersOverview(ctx, store.ActiveOrdersOverviewParams{
		Statuses: statusStrings(activeGroups[group]), LockedOnly: group == "locked", Lim: limit,
	})
	if err != nil {
		return nil, fmt.Errorf("commandes en cours : %w", err)
	}
	shopNames := map[uuid.UUID]string{}
	out := make([]ActiveOrder, len(rows))
	for i, r := range rows {
		name, ok := shopNames[r.ShopID]
		if !ok {
			if shop, err := s.shops.Get(ctx, r.ShopID); err == nil {
				name = shop.Name
			}
			shopNames[r.ShopID] = name
		}
		out[i] = ActiveOrder{
			ID: r.ID, Number: r.Number, Reference: Reference(r.Number), ShopName: name,
			BuyerName: s.shortName(ctx, r.BuyerID), Fulfillment: r.Fulfillment, TotalXOF: r.TotalXof,
			Status: Status(r.Status), HandoverLocked: r.HandoverAttempts >= MaxHandoverAttempts, Since: r.Since,
		}
	}
	return out, nil
}

// shortName : « Awa M. » (prénom et initiale du nom), « Compte supprimé » sinon.
func (s *Service) shortName(ctx context.Context, userID uuid.UUID) string {
	u, err := s.users.Get(ctx, userID)
	if err != nil {
		return "Compte supprimé"
	}
	name := strings.TrimSpace(u.FirstName)
	if r, _ := utf8.DecodeRuneInString(strings.TrimSpace(u.LastName)); r != utf8.RuneError {
		name += " " + strings.ToUpper(string(r)) + "."
	}
	if name == "" {
		return "Sans nom"
	}
	return name
}

func statusStrings(sts []Status) []string {
	out := make([]string, len(sts))
	for i, st := range sts {
		out[i] = string(st)
	}
	return out
}
