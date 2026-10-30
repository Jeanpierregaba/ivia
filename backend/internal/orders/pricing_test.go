package orders

import (
	"testing"

	"ivia/backend/internal/admin"
	"ivia/backend/internal/catalog"
)

func settings() admin.Settings {
	return admin.Settings{
		CommissionRateBP:    1000,
		MotorbikeBaseFeeXOF: 500, MotorbikePerKmXOF: 150,
		CarBaseFeeXOF: 1500, CarPerKmXOF: 300,
		DistanceCoefficientPct: 130,
	}
}

func TestDeliveryFee(t *testing.T) {
	cases := []struct {
		v    Vehicle
		m    int64
		want int64
	}{
		// 0 m : forfait seul.
		{VehicleMotorbike, 0, 500},
		// 1 000 m × 1,3 = 1 300 m → 500 + ceil(1,3 × 150 = 195) = 695 → 700.
		{VehicleMotorbike, 1000, 700},
		// 5 000 m × 1,3 = 6 500 m → 500 + 975 = 1 475 → 1 500.
		{VehicleMotorbike, 5000, 1500},
		// Voiture, 5 000 m → 1 500 + 1 950 = 3 450 → 3 450.
		{VehicleCar, 5000, 3450},
		// 1 m : ceil(1,3) = 2 m, ceil(2 × 150 / 1000) = 1 → 501 → 550.
		{VehicleMotorbike, 1, 550},
	}
	for _, c := range cases {
		if got := DeliveryFee(settings(), c.v, c.m); got != c.want {
			t.Errorf("DeliveryFee(%s, %d m) = %d, attendu %d", c.v, c.m, got, c.want)
		}
		if got := DeliveryFee(settings(), c.v, c.m); got%feeRounding != 0 {
			t.Errorf("frais non arrondis à 50 : %d", got)
		}
	}
}

func TestCommission(t *testing.T) {
	cases := []struct {
		subtotal int64
		bp       int32
		want     int64
	}{
		{10000, 1000, 1000},
		{12345, 1000, 1235}, // 1234,5 → 1235 (demi vers le haut)
		{12344, 1000, 1234},
		{999, 250, 25}, // 24,975 → 25
		{5000, 0, 0},
		{5000, 10000, 5000},
	}
	for _, c := range cases {
		if got := Commission(c.subtotal, c.bp); got != c.want {
			t.Errorf("Commission(%d, %d) = %d, attendu %d", c.subtotal, c.bp, got, c.want)
		}
	}
}

func TestCompatibleVehicles(t *testing.T) {
	if v := CompatibleVehicles(catalog.ParcelLarge); len(v) != 1 || v[0] != VehicleCar {
		t.Errorf("grand colis : %v, attendu [car]", v)
	}
	if v := CompatibleVehicles(catalog.ParcelSmall); len(v) != 2 || v[0] != VehicleMotorbike {
		t.Errorf("petit colis : %v", v)
	}
}
