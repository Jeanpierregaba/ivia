package search

import "testing"

func TestPrefixQuery(t *testing.T) {
	for in, want := range map[string]string{
		"pag":                    "pag:*",
		"Robe  Pag":              "robe & pag:*",
		"l'huile":                "huile:*",
		"pagne & | ! ( ) :* <->": "pagne:*",
		"riz 5 kg":               "riz & 5 & kg:*",
		"un deux trois quatre cinq six sept huit neuf": "deux & trois & quatre & cinq & six & sept & huit & neuf:*",
	} {
		got := prefixQuery(in)
		if got == nil || *got != want {
			t.Errorf("prefixQuery(%q) = %v, attendu %q", in, got, want)
		}
	}
	for _, in := range []string{"", "  ", "%_\\", "l' d'"} {
		if got := prefixQuery(in); got != nil {
			t.Errorf("prefixQuery(%q) = %q, attendu nil", in, *got)
		}
	}
}

func TestLikeTextEscapesWildcards(t *testing.T) {
	in := `100% coton_bio\`
	if got := *likeText(&in); got != `100\% coton\_bio\` {
		t.Fatalf("likeText = %q", got)
	}
	if likeText(nil) != nil {
		t.Fatal("likeText(nil) doit rester nil")
	}
}
