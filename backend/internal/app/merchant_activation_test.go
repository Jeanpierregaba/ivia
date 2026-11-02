package app_test

import (
	"net/http"
	"testing"
)

// Un marchand ne vend pas tant qu'un admin n'a pas vérifié sa pièce d'identité et publié sa boutique.
func TestMerchantMustBeValidatedByAdmin(t *testing.T) {
	requireApp(t)
	tok := login(t, uniqueEmail("marchand"))
	completeProfile(t, tok, "Akossiwa")
	lat, lng := zone()
	newShop := func(name string) string {
		t.Helper()
		return mustStatus(t, call(t, tok, "POST", "/v1/shops", map[string]any{
			"name": name, "phone": uniquePhone(), "address_text": "Rue du test",
			"location": map[string]float64{"lat": lat, "lng": lng}, "category_id": shopCategory(t),
		}), http.StatusCreated).str("id")
	}
	shopID := newShop("Chez Akossiwa")
	approve := func(id string) resp {
		t.Helper()
		return call(t, admin(t), "POST", "/v1/admin/shops/"+id+"/approve", map[string]any{})
	}

	// Boutique en attente : invisible des acheteurs, aucune pièce, publication refusée.
	mustStatus(t, call(t, "", "GET", "/v1/shops/"+shopID, nil), http.StatusNotFound)
	docs := mustStatus(t, call(t, tok, "GET", "/v1/seller/documents", nil), http.StatusOK)
	if items, _ := docs.Body["items"].([]any); len(items) != 0 {
		t.Fatalf("pièces au départ : %v", items)
	}
	if req, _ := docs.Body["required"].([]any); len(req) != 1 || req[0] != "id_card" {
		t.Fatalf("pièces obligatoires : %v", docs.Body["required"])
	}
	if r := approve(shopID); r.Status != http.StatusConflict || r.code() != "merchant_documents_missing" {
		t.Fatalf("publication sans pièce : %d %s", r.Status, r.code())
	}

	// Un registre du commerce seul ne suffit pas ; un type inconnu est refusé.
	uploadMerchantDocument(t, tok, "business_registration")
	if r := approve(shopID); r.code() != "merchant_documents_missing" {
		t.Fatalf("publication sans pièce d'identité : %d %s", r.Status, r.code())
	}
	key := uploadPrivatePDF(t, tok, "merchant_document")
	if r := call(t, tok, "POST", "/v1/seller/documents", map[string]string{"kind": "passport_scan", "object_key": key}); r.code() != "validation_failed" {
		t.Fatalf("type inconnu : %d %s", r.Status, r.code())
	}

	// Une clé délivrée à un autre utilisateur, ou pour un autre usage, est refusée.
	other := login(t, uniqueEmail("autre"))
	if r := call(t, other, "POST", "/v1/uploads", map[string]any{
		"purpose": "merchant_document", "content_type": "application/pdf", "size_bytes": 10,
	}); r.Status != http.StatusForbidden {
		t.Fatalf("envoi d'une pièce sans rôle marchand : %d", r.Status)
	}
	driverKey := uploadPrivatePDF(t, other, "driver_document")
	if r := call(t, tok, "POST", "/v1/seller/documents", map[string]string{"kind": "id_card", "object_key": driverKey}); r.code() != "validation_failed" {
		t.Fatalf("clé d'un autre utilisateur : %d %s", r.Status, r.code())
	}

	// Pièce d'identité déposée : la boutique est publiée et visible.
	added := uploadMerchantDocument(t, tok, "id_card")
	if items, _ := added.Body["items"].([]any); len(items) != 2 {
		t.Fatalf("pièces après dépôt : %v", items)
	}
	mustStatus(t, approve(shopID), http.StatusOK)
	mustStatus(t, call(t, "", "GET", "/v1/shops/"+shopID, nil), http.StatusOK)

	// L'admin consulte les pièces par lien temporaire ; le marchand voit ses pièces sans lien.
	adminView := mustStatus(t, call(t, admin(t), "GET", "/v1/admin/shops/"+shopID, nil), http.StatusOK)
	adminDocs, _ := adminView.Body["merchant_documents"].([]any)
	if len(adminDocs) != 2 {
		t.Fatalf("pièces vues par l'admin : %v", adminDocs)
	}
	for _, d := range adminDocs {
		if u, _ := d.(map[string]any)["url"].(string); u == "" {
			t.Fatalf("pièce sans lien pour l'admin : %v", d)
		}
	}
	ownerView := mustStatus(t, call(t, tok, "GET", "/v1/seller/shops/"+shopID, nil), http.StatusOK)
	ownerDocs, _ := ownerView.Body["merchant_documents"].([]any)
	if len(ownerDocs) != 2 {
		t.Fatalf("pièces vues par le marchand : %v", ownerDocs)
	}
	for _, d := range ownerDocs {
		if _, ok := d.(map[string]any)["url"]; ok {
			t.Fatalf("lien de lecture exposé au marchand : %v", d)
		}
	}

	// Les pièces valent pour la personne : sa deuxième boutique se publie sans nouveau dépôt.
	mustStatus(t, approve(newShop("Chez Akossiwa 2")), http.StatusOK)
}
