package orders

import (
	"ivia/backend/internal/admin"
	"ivia/backend/internal/catalog"
)

// Vehicle est la catégorie de véhicule d'une livraison.
type Vehicle string

const (
	VehicleMotorbike Vehicle = "motorbike"
	VehicleCar       Vehicle = "car"
)

// MaxDeliveryDistanceM : au-delà, la livraison n'est pas proposée (Grand Lomé).
const MaxDeliveryDistanceM = 40_000

// feeRounding : les frais sont arrondis au multiple supérieur de 50 FCFA.
const feeRounding = 50

// CompatibleVehicles retourne les véhicules qui peuvent transporter un colis de cette taille,
// du moins cher au plus cher. Un grand colis ne part qu'en voiture.
func CompatibleVehicles(size catalog.ParcelSize) []Vehicle {
	if size == catalog.ParcelLarge {
		return []Vehicle{VehicleCar}
	}
	return []Vehicle{VehicleMotorbike, VehicleCar}
}

// DeliveryFee calcule les frais de livraison : forfait + prix au km du véhicule, sur la distance
// à vol d'oiseau multipliée par le coefficient réglable, arrondis au multiple supérieur de 50 FCFA.
// Tout est calculé en entiers (pas de nombre à virgule pour l'argent).
func DeliveryFee(s admin.Settings, v Vehicle, straightLineM int64) int64 {
	base, perKm := s.MotorbikeBaseFeeXOF, s.MotorbikePerKmXOF
	if v == VehicleCar {
		base, perKm = s.CarBaseFeeXOF, s.CarPerKmXOF
	}
	effectiveM := ceilDiv(straightLineM*int64(s.DistanceCoefficientPct), 100)
	fee := base + ceilDiv(effectiveM*perKm, 1000)
	return ceilDiv(fee, feeRounding) * feeRounding
}

// Commission calcule la commission de la plateforme sur le montant des produits (arrondi au FCFA
// le plus proche, les demis vers le haut). rateBP est en points de base (1000 = 10 %).
func Commission(subtotalXOF int64, rateBP int32) int64 {
	return (subtotalXOF*int64(rateBP) + 5000) / 10000
}

func ceilDiv(a, b int64) int64 {
	if a <= 0 {
		return 0
	}
	return (a + b - 1) / b
}
