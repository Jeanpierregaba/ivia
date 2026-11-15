package orders

import (
	"fmt"
	"testing"
)

var allStatuses = []Status{
	StatusPendingPayment, StatusExpired, StatusAwaitingSeller, StatusAccepted, StatusPreparing,
	StatusReadyForPickup, StatusAwaitingDriver, StatusDriverAssigned, StatusPickedUp, StatusDelivered,
	StatusDeliveryFailed, StatusReturnedToShop, StatusCompleted, StatusCancelled, StatusRefunded,
}

var allActors = []ActorType{ActorBuyer, ActorSeller, ActorDriver, ActorAdmin, ActorSystem}

// expected est la spécification des transitions (docs/ARCHITECTURE.md), écrite indépendamment de
// la table du code : « départ → arrivée » → auteurs autorisés. Tout ce qui n'y figure pas est interdit.
var expected = map[string][]ActorType{
	"pending_payment → awaiting_seller":  {ActorSystem},
	"pending_payment → expired":          {ActorSystem},
	"pending_payment → cancelled":        {ActorBuyer},
	"expired → awaiting_seller":          {ActorSystem},
	"expired → cancelled":                {ActorSystem},
	"awaiting_seller → accepted":         {ActorSeller},
	"awaiting_seller → cancelled":        {ActorSeller, ActorSystem, ActorBuyer, ActorAdmin},
	"accepted → preparing":               {ActorSeller},
	"accepted → cancelled":               {ActorAdmin},
	"preparing → ready_for_pickup":       {ActorSeller},
	"preparing → awaiting_driver":        {ActorSeller},
	"preparing → cancelled":              {ActorAdmin},
	"ready_for_pickup → completed":       {ActorSeller},
	"ready_for_pickup → cancelled":       {ActorAdmin},
	"awaiting_driver → driver_assigned":  {ActorDriver},
	"awaiting_driver → cancelled":        {ActorAdmin},
	"driver_assigned → awaiting_driver":  {ActorDriver, ActorAdmin},
	"driver_assigned → picked_up":        {ActorDriver},
	"picked_up → delivered":              {ActorDriver},
	"picked_up → delivery_failed":        {ActorDriver},
	"delivery_failed → returned_to_shop": {ActorSeller, ActorAdmin},
	"cancelled → refunded":               {ActorAdmin},
	"returned_to_shop → refunded":        {ActorAdmin},
}

// TestStateMachineExhaustive vérifie les 15 × 15 × 5 combinaisons départ / arrivée / auteur.
func TestStateMachineExhaustive(t *testing.T) {
	checked := 0
	for _, from := range allStatuses {
		for _, to := range allStatuses {
			allowed := expected[fmt.Sprintf("%s → %s", from, to)]
			for _, actor := range allActors {
				want := false
				for _, a := range allowed {
					want = want || a == actor
				}
				if got := CanTransition(from, to, actor); got != want {
					t.Errorf("%s → %s par %s : permis=%v, attendu %v", from, to, actor, got, want)
				}
				checked++
			}
		}
	}
	if checked != 15*15*5 {
		t.Fatalf("%d combinaisons vérifiées", checked)
	}
	// Aucune transition du code ne doit être absente de la spécification.
	for from, tos := range transitions {
		for to := range tos {
			if _, ok := expected[fmt.Sprintf("%s → %s", from, to)]; !ok {
				t.Errorf("transition non spécifiée dans le code : %s → %s", from, to)
			}
		}
	}
}

func TestFinalStatusesHaveNoExit(t *testing.T) {
	for _, s := range []Status{StatusDelivered, StatusCompleted, StatusRefunded} {
		if len(transitions[s]) != 0 {
			t.Errorf("%s est un statut final : aucune transition ne doit en sortir", s)
		}
	}
}

func TestStockReleasingStatuses(t *testing.T) {
	for _, s := range allStatuses {
		want := s == StatusExpired || s == StatusCancelled || s == StatusReturnedToShop
		if s.releasesStock() != want {
			t.Errorf("%s : libère le stock = %v, attendu %v", s, s.releasesStock(), want)
		}
	}
}

func TestHandoverCodeVisibility(t *testing.T) {
	visible := map[Status]bool{
		StatusAwaitingSeller: true, StatusAccepted: true, StatusPreparing: true, StatusReadyForPickup: true,
		StatusAwaitingDriver: true, StatusDriverAssigned: true, StatusPickedUp: true,
	}
	for _, s := range allStatuses {
		if s.ShowsHandoverCode() != visible[s] {
			t.Errorf("%s : code visible = %v, attendu %v", s, s.ShowsHandoverCode(), visible[s])
		}
	}
}
