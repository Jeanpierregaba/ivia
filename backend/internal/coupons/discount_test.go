package coupons

import "testing"

func TestDiscount(t *testing.T) {
	cap5 := int64(500)
	cases := []struct {
		name     string
		kind     string
		value    int32
		max      *int64
		subtotal int64
		want     int64
	}{
		{"pourcentage", "percent", 10, nil, 5000, 500},
		{"pourcentage plafonné", "percent", 50, &cap5, 5000, 500},
		{"montant fixe", "fixed", 1000, nil, 5000, 1000},
		{"jamais plus que les produits", "fixed", 8000, nil, 5000, 5000},
		{"arrondi vers le bas", "percent", 15, nil, 999, 149},
	}
	for _, c := range cases {
		if got := Discount(c.kind, c.value, c.max, c.subtotal); got != c.want {
			t.Errorf("%s : %d, attendu %d", c.name, got, c.want)
		}
	}
}

func TestCapToMinTotal(t *testing.T) {
	if got := CapToMinTotal(5000, 5000); got != 4900 {
		t.Fatalf("100 F à payer au moins : %d", got)
	}
	if got := CapToMinTotal(500, 5000); got != 500 {
		t.Fatalf("réduction inchangée : %d", got)
	}
	if got := CapToMinTotal(500, 80); got != 0 {
		t.Fatalf("commande trop petite : %d", got)
	}
}

func TestNormalize(t *testing.T) {
	if got := Normalize("  promo 10 "); got != "PROMO10" {
		t.Fatalf("normalisation : %q", got)
	}
}
