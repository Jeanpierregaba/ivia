package orders

// Status d'une commande (diagramme dans docs/ARCHITECTURE.md).
type Status string

const (
	StatusPendingPayment Status = "pending_payment"
	StatusExpired        Status = "expired"
	StatusAwaitingSeller Status = "awaiting_seller"
	StatusAccepted       Status = "accepted"
	StatusPreparing      Status = "preparing"
	StatusReadyForPickup Status = "ready_for_pickup"
	StatusAwaitingDriver Status = "awaiting_driver"
	StatusDriverAssigned Status = "driver_assigned"
	StatusPickedUp       Status = "picked_up"
	StatusDelivered      Status = "delivered"
	StatusDeliveryFailed Status = "delivery_failed"
	StatusReturnedToShop Status = "returned_to_shop"
	StatusCompleted      Status = "completed"
	StatusCancelled      Status = "cancelled"
	StatusRefunded       Status = "refunded"
)

// ActorType est l'auteur d'une transition.
type ActorType string

const (
	ActorBuyer  ActorType = "buyer"
	ActorSeller ActorType = "seller"
	ActorDriver ActorType = "driver"
	ActorAdmin  ActorType = "admin"
	// ActorSystem : tâches de fond et traitement des paiements confirmés par le prestataire.
	ActorSystem ActorType = "system"
)

// transitions liste, pour chaque statut, les statuts atteignables et qui peut déclencher le passage.
// C'est la seule source de vérité : toute transition absente est refusée.
var transitions = map[Status]map[Status][]ActorType{
	StatusPendingPayment: {
		StatusAwaitingSeller: {ActorSystem}, // paiement confirmé par webhook ou revérification
		StatusExpired:        {ActorSystem}, // délai de paiement dépassé
		StatusCancelled:      {ActorBuyer},  // l'acheteur renonce avant de payer
	},
	StatusExpired: {
		StatusAwaitingSeller: {ActorSystem}, // paiement tardif, stock encore disponible
		StatusCancelled:      {ActorSystem}, // paiement tardif, stock épuisé
	},
	StatusAwaitingSeller: {
		StatusAccepted:  {ActorSeller},
		StatusCancelled: {ActorSeller, ActorSystem, ActorBuyer, ActorAdmin}, // refus, délai, annulation
	},
	StatusAccepted: {
		StatusPreparing: {ActorSeller},
		StatusCancelled: {ActorAdmin},
	},
	StatusPreparing: {
		StatusReadyForPickup: {ActorSeller},
		StatusAwaitingDriver: {ActorSeller},
		StatusCancelled:      {ActorAdmin},
	},
	StatusReadyForPickup: {
		StatusCompleted: {ActorSeller}, // code de remise saisi par le marchand
		StatusCancelled: {ActorAdmin},
	},
	StatusAwaitingDriver: {
		StatusDriverAssigned: {ActorDriver},
		StatusCancelled:      {ActorAdmin},
	},
	StatusDriverAssigned: {
		StatusAwaitingDriver: {ActorDriver, ActorAdmin}, // désistement du livreur ou retrait par l'admin
		StatusPickedUp:       {ActorDriver},
	},
	StatusPickedUp: {
		StatusDelivered:      {ActorDriver}, // code de remise saisi par le livreur
		StatusDeliveryFailed: {ActorDriver},
	},
	StatusDeliveryFailed: {
		StatusReturnedToShop: {ActorSeller, ActorAdmin},
	},
	StatusCancelled: {
		StatusRefunded: {ActorAdmin},
	},
	StatusReturnedToShop: {
		StatusRefunded: {ActorAdmin},
	},
}

// CanTransition indique si actor peut faire passer une commande de from à to.
func CanTransition(from, to Status, actor ActorType) bool {
	for _, a := range transitions[from][to] {
		if a == actor {
			return true
		}
	}
	return false
}

// IsPaidStatus indique un statut où le paiement a été reçu et la commande est en cours.
func (s Status) IsPaidStatus() bool {
	switch s {
	case StatusAwaitingSeller, StatusAccepted, StatusPreparing, StatusReadyForPickup,
		StatusAwaitingDriver, StatusDriverAssigned, StatusPickedUp, StatusDelivered,
		StatusDeliveryFailed, StatusCompleted:
		return true
	}
	return false
}

// ShowsHandoverCode indique si l'acheteur doit voir son code de remise.
func (s Status) ShowsHandoverCode() bool {
	switch s {
	case StatusAwaitingSeller, StatusAccepted, StatusPreparing, StatusReadyForPickup,
		StatusAwaitingDriver, StatusDriverAssigned, StatusPickedUp:
		return true
	}
	return false
}

// releasesStock : statuts où le stock réservé est rendu.
func (s Status) releasesStock() bool {
	return s == StatusExpired || s == StatusCancelled || s == StatusReturnedToShop
}
