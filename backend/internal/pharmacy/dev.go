package pharmacy

import (
	"context"
	"fmt"

	"github.com/google/uuid"

	"ivia/backend/internal/pharmacy/store"
)

// Outils de démonstration locale (jamais exposés hors local : voir app.DevToolsEnabled).

// DemoPharmacy décrit une pharmacie de démonstration.
type DemoPharmacy struct {
	OwnerID           uuid.UUID
	Name, Phone, Addr string
	Lat, Lng          float64
}

// DevSeedPharmacy crée ou réactive une pharmacie validée, ouverte et de garde.
func (s *Service) DevSeedPharmacy(ctx context.Context, d DemoPharmacy) (uuid.UUID, error) {
	id, err := s.q(ctx).DevUpsertPharmacy(ctx, store.DevUpsertPharmacyParams{
		OwnerID: d.OwnerID, Name: d.Name, LicenseNumber: "DEMO-" + d.OwnerID.String()[:8], Phone: d.Phone,
		AddressText: d.Addr, Lat: d.Lat, Lng: d.Lng,
	})
	if err != nil {
		return uuid.Nil, fmt.Errorf("pharmacie de démonstration : %w", err)
	}
	return id, nil
}

// DevAutoRespond fait répondre les pharmacies de démonstration sollicitées : tous les produits
// disponibles, à un prix de démonstration. Les erreurs (déjà répondu, pas sollicitée) sont ignorées.
func (s *Service) DevAutoRespond(ctx context.Context, alertID uuid.UUID, owners []uuid.UUID) (int, error) {
	items, err := s.q(ctx).ListAlertItems(ctx, alertID)
	if err != nil {
		return 0, fmt.Errorf("produits de l'alerte : %w", err)
	}
	n := 0
	for i, owner := range owners {
		var lines []ResponseLineInput
		for j, it := range items {
			id := it.ID
			lines = append(lines, ResponseLineInput{
				AlertItemID: &id, Name: it.Name, Quantity: it.Quantity,
				UnitPriceXOF: int64(1500 + 500*((i+j)%5)), Available: i != 2 || j == 0,
			})
		}
		if len(lines) == 0 { // ordonnance en photo seulement
			lines = []ResponseLineInput{{Name: "Ordonnance complète", Quantity: 1, UnitPriceXOF: int64(6500 + 1000*i), Available: true}}
		}
		if _, err := s.Respond(ctx, owner, alertID, ResponseInput{Lines: lines, Note: "Disponible tout de suite."}); err == nil {
			n++
		}
	}
	return n, nil
}
