package app_test

import (
	"net/http"
	"slices"
	"testing"
	"time"

	"ivia/backend/internal/platform/storage"
)

// privateKeys liste les fichiers privés sous un préfixe (stockage local des tests).
func privateKeys(t *testing.T, prefix string) []string {
	t.Helper()
	objs, err := requireApp(t).LocalStore.List(ctx(), storage.Private, prefix)
	if err != nil {
		t.Fatal(err)
	}
	keys := make([]string, len(objs))
	for i, o := range objs {
		keys[i] = o.Key
	}
	return keys
}

// Un fichier envoyé mais jamais rattaché est supprimé après 24 h ; un fichier rattaché reste.
func TestOrphanPrivateDocumentsArePurged(t *testing.T) {
	a := requireApp(t)
	s := newSeller(t, 1) // pièce d'identité rattachée par newSeller
	orphanMerchant := uploadPrivatePDF(t, s.token, "merchant_document")
	driver := login(t, uniqueEmail("candidat"))
	orphanDriver := uploadPrivatePDF(t, driver, "driver_document")

	me := mustStatus(t, call(t, s.token, "GET", "/v1/me", nil), http.StatusOK).str("id")
	attached := ""
	for _, k := range privateKeys(t, "merchants/"+me+"/") {
		if k != orphanMerchant {
			attached = k
		}
	}

	// Trop récents : rien n'est supprimé.
	if _, err := a.Uploads.PurgeOrphans(ctx(), time.Now()); err != nil {
		t.Fatal(err)
	}
	for _, k := range []string{orphanMerchant, orphanDriver} {
		if !slices.Contains(privateKeys(t, k), k) {
			t.Fatalf("%s supprimé avant 24 h", k)
		}
	}

	// 25 h plus tard : les orphelins partent, les pièces rattachées restent.
	if _, err := a.Uploads.PurgeOrphans(ctx(), time.Now().Add(25*time.Hour)); err != nil {
		t.Fatal(err)
	}
	for _, k := range []string{orphanMerchant, orphanDriver} {
		if slices.Contains(privateKeys(t, k), k) {
			t.Fatalf("orphelin %s non supprimé", k)
		}
	}
	if attached == "" || !slices.Contains(privateKeys(t, attached), attached) {
		t.Fatalf("pièce rattachée supprimée ou introuvable (%q)", attached)
	}
}

// La suppression du compte efface tout le dossier privé, rattaché ou non (docs/SECURITY.md).
func TestAccountDeletionRemovesAllPrivateDocuments(t *testing.T) {
	requireApp(t)
	s := newSeller(t, 1)
	uploadPrivatePDF(t, s.token, "merchant_document") // jamais rattaché
	uploadPrivatePDF(t, s.token, "driver_document")   // document de livreur envoyé, sans candidature
	me := mustStatus(t, call(t, s.token, "GET", "/v1/me", nil), http.StatusOK).str("id")
	if n := len(privateKeys(t, "merchants/"+me+"/")); n != 2 {
		t.Fatalf("pièces du marchand avant suppression : %d, attendu 2", n)
	}

	mustStatus(t, call(t, s.token, "DELETE", "/v1/me", nil), http.StatusNoContent)
	if left := privateKeys(t, "merchants/"+me+"/"); len(left) != 0 {
		t.Fatalf("pièces du marchand restantes : %v", left)
	}
	if left := privateKeys(t, "drivers/"+me+"/"); len(left) != 0 {
		t.Fatalf("documents de livreur restants : %v", left)
	}
}
