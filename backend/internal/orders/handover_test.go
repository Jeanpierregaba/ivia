package orders

import (
	"context"
	"io"
	"log/slog"
	"os"
	"testing"

	"github.com/google/uuid"

	"ivia/backend/internal/platform/apperr"
	"ivia/backend/internal/platform/database"
	"ivia/backend/internal/platform/testdb"
)

var testDB *database.DB

func TestMain(m *testing.M) { os.Exit(testdb.Main(m, &testDB)) }

// Régression : une requête qui a lu la commande avant que les essais n'atteignent 5 (lecture
// périmée, requêtes simultanées) ne doit jamais comparer le code. Le compteur fait foi en base.
func TestHandoverCodeCountsBeforeComparing(t *testing.T) {
	db := testdb.Require(t, testDB)
	ctx := context.Background()
	var userID, shopID, orderID uuid.UUID
	if err := db.Pool.QueryRow(ctx, "INSERT INTO users (email) VALUES ($1) RETURNING id", uuid.NewString()+"@example.tg").Scan(&userID); err != nil {
		t.Fatal(err)
	}
	if err := db.Pool.QueryRow(ctx, `INSERT INTO shops (owner_id, name, phone, address_text, location)
		VALUES ($1, 'Boutique', '+22890000000', 'Rue', ST_SetSRID(ST_MakePoint(1.2, 6.1), 4326)::geography) RETURNING id`, userID).Scan(&shopID); err != nil {
		t.Fatal(err)
	}
	if err := db.Pool.QueryRow(ctx, `INSERT INTO orders (buyer_id, shop_id, status, fulfillment, parcel_size, subtotal_xof, total_xof,
		commission_rate_bp, commission_xof, handover_code, handover_attempts, payment_deadline_at)
		VALUES ($1, $2, 'ready_for_pickup', 'pickup', 'small', 1000, 1000, 0, 0, '1234', 5, now()) RETURNING id`, userID, shopID).Scan(&orderID); err != nil {
		t.Fatal(err)
	}

	s := &Service{db: db, logger: slog.New(slog.NewTextHandler(io.Discard, nil))}
	stale := Order{ID: orderID, HandoverCode: "1234", HandoverAttempts: 0}
	if err := s.checkHandoverCode(ctx, stale, "1234"); !apperr.IsCode(err, "handover_locked") {
		t.Fatalf("code bloqué en base : %v, attendu handover_locked même avec le bon code", err)
	}
}
