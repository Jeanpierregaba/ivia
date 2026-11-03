package app_test

import (
	"net/http"
	"net/url"
	"slices"
	"testing"
)

// La recherche part pendant la frappe : le début du dernier mot suffit ; les jokers de LIKE tapés
// par l'acheteur sont cherchés tels quels.
func TestSearchMatchesWordPrefixAndEscapesWildcards(t *testing.T) {
	requireApp(t)
	s := newSeller(t, 5)
	pagne := mustStatus(t, call(t, s.token, "POST", "/v1/seller/shops/"+s.shopID+"/products", map[string]any{
		"category_id": category(t), "name": "Pagne wax hollandais", "price_xof": 12000,
		"parcel_size": "small", "stock_mode": "untracked",
	}), http.StatusCreated).str("id")
	near := "&lat=" + ftoa(s.lat) + "&lng=" + ftoa(s.lng) + "&radius_m=2000"

	ids := func(path string) []string {
		t.Helper()
		var out []string
		for _, it := range mustStatus(t, call(t, "", "GET", path, nil), http.StatusOK).Body["items"].([]any) {
			out = append(out, it.(map[string]any)["id"].(string))
		}
		return out
	}
	for _, q := range []string{"pag", "Pagn", "pagne wa", "wax holl", "pâg"} {
		if !slices.Contains(ids("/v1/search/products?q="+url.QueryEscape(q)+near), pagne) {
			t.Errorf("« %s » ne trouve pas « Pagne wax hollandais »", q)
		}
	}
	if slices.Contains(ids("/v1/search/products?q=robe"+near), pagne) {
		t.Error("« robe » ne doit pas trouver le pagne")
	}
	// Syntaxe plein texte tapée par l'acheteur : ni erreur, ni résultat inventé.
	ids("/v1/search/products?q=" + url.QueryEscape("pag & | ! ( :* <->") + near)

	if !slices.Contains(ids("/v1/search/shops?q=boutique"+near), s.shopID) {
		t.Fatal("« boutique » doit trouver la boutique de test")
	}
	for _, q := range []string{"%", "_", "%%", `\`} {
		if got := ids("/v1/search/shops?q=" + url.QueryEscape(q) + near); slices.Contains(got, s.shopID) {
			t.Errorf("« %s » ne doit pas trouver toutes les boutiques (%d résultats)", q, len(got))
		}
	}
}
