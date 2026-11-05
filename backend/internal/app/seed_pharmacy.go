package app

import (
	"context"
	"fmt"
	"net/http"

	"github.com/google/uuid"

	"ivia/backend/internal/pharmacy"
	"ivia/backend/internal/platform/httpapi"
	"ivia/backend/internal/platform/identity"
)

// Pharmacies de démonstration (local uniquement) : validées, ouvertes et de garde autour de Tokoin,
// pour montrer le parcours « alerte médicament » sans l'app pharmacie.
var demoPharmacies = []struct {
	email, name, phone, addr string
	lat, lng                 float64
}{
	{"pharmacie.boulevard@ivia.local", "Pharmacie du Boulevard", "+22890000201", "Boulevard du 13 Janvier, Tokoin", 6.1495, 1.2165},
	{"pharmacie.bekpota@ivia.local", "Pharmacie Bè Kpota", "+22890000202", "Carrefour Bè Kpota", 6.1420, 1.2240},
	{"pharmacie.hopital@ivia.local", "Pharmacie Tokoin Hôpital", "+22890000203", "Face au CHU Sylvanus Olympio, Tokoin", 6.1530, 1.2110},
}

// seedDemoPharmacies crée les 3 pharmacies de démonstration (relançable sans doublon).
func (a *App) seedDemoPharmacies(ctx context.Context) (int, error) {
	n := 0
	for _, d := range demoPharmacies {
		u, _, err := a.Users.FindOrCreateByEmail(ctx, d.email)
		if err != nil {
			return n, err
		}
		if err := a.Users.GrantRole(ctx, u.ID, identity.RolePharmacist, nil); err != nil {
			return n, fmt.Errorf("rôle pharmacien : %w", err)
		}
		if _, err := a.Pharmacy.DevSeedPharmacy(ctx, pharmacy.DemoPharmacy{
			OwnerID: u.ID, Name: d.name, Phone: d.phone, Addr: d.addr, Lat: d.lat, Lng: d.lng,
		}); err != nil {
			return n, err
		}
		n++
	}
	return n, nil
}

// devAutoRespond : POST /v1/dev/medicine-alerts/{id}/auto-respond. Les pharmacies de
// démonstration sollicitées répondent à l'alerte (démonstration sans app pharmacie).
func (a *App) devAutoRespond(w http.ResponseWriter, r *http.Request) error {
	id, err := httpapi.PathUUID(r, "id")
	if err != nil {
		return err
	}
	owners := make([]uuid.UUID, 0, len(demoPharmacies))
	for _, d := range demoPharmacies {
		if u, err := a.Users.FindByEmail(r.Context(), d.email); err == nil {
			owners = append(owners, u.ID)
		}
	}
	n, err := a.Pharmacy.DevAutoRespond(r.Context(), id, owners)
	if err != nil {
		return err
	}
	return httpapi.OK(w, map[string]int{"responses": n})
}
