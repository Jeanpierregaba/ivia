package orders

// Groupes de statuts des onglets des apps (paramètre `group` des listes). Ils reprennent
// exactement la répartition des apps (mobile : OrderStatus.isActive côté acheteur, tabOf côté
// marchand), pour qu'une commande ancienne en cours ne manque jamais à « En cours ».

// SellerGroups : onglets de l'app marchand (commandes payées seulement).
var SellerGroups = map[string][]Status{
	"new": {StatusAwaitingSeller},
	"active": {
		StatusAccepted, StatusPreparing, StatusReadyForPickup,
		StatusAwaitingDriver, StatusDriverAssigned, StatusPickedUp,
	},
	"done": {
		StatusDelivered, StatusDeliveryFailed, StatusReturnedToShop,
		StatusCompleted, StatusCancelled, StatusRefunded,
	},
}

// BuyerGroups : onglets de l'app acheteur.
var BuyerGroups = map[string][]Status{
	"active": {
		StatusPendingPayment, StatusAwaitingSeller, StatusAccepted, StatusPreparing,
		StatusReadyForPickup, StatusAwaitingDriver, StatusDriverAssigned, StatusPickedUp,
	},
	"done": {
		StatusExpired, StatusDelivered, StatusDeliveryFailed, StatusReturnedToShop,
		StatusCompleted, StatusCancelled, StatusRefunded,
	},
}

// groupStatuses retourne les statuts d'un groupe ; nil (toutes les commandes) si group est vide.
func groupStatuses(groups map[string][]Status, group string) []string {
	if group == "" {
		return nil
	}
	sts := groups[group]
	out := make([]string, len(sts))
	for i, st := range sts {
		out[i] = string(st)
	}
	return out
}
