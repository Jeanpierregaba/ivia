package validate

import "testing"

func TestNormalizeTogoPhone(t *testing.T) {
	cases := map[string]string{
		"90123456":          "+22890123456",
		"+228 90 12 34 56":  "+22890123456",
		"00228-70-12-34-56": "+22870123456",
		"22899112233":       "+22899112233",
		"22 12 34 56":       "", // fixe : refusé
		"9012345":           "",
		"901234567":         "",
		"":                  "",
		"+33612345678":      "",
	}
	for in, want := range cases {
		got, ok := NormalizeTogoPhone(in)
		if got != want || ok != (want != "") {
			t.Errorf("NormalizeTogoPhone(%q) = %q, %v ; attendu %q", in, got, ok, want)
		}
	}
}

func TestNormalizeEmail(t *testing.T) {
	cases := map[string]string{
		" Ama.Kossi@Example.TG ": "ama.kossi@example.tg",
		"pas-un-email":           "",
		"a@b":                    "",
		"Ama <ama@example.tg>":   "",
		"a b@example.tg":         "",
	}
	for in, want := range cases {
		got, ok := NormalizeEmail(in)
		if got != want || ok != (want != "") {
			t.Errorf("NormalizeEmail(%q) = %q, %v ; attendu %q", in, got, ok, want)
		}
	}
}

func TestTextAndClean(t *testing.T) {
	e := New()
	e.Text("a", Clean("  \x00 Boutique Évé \x07 "), 2, 20)
	e.Text("b", "", 1, 10)
	e.Text("c", "ééééé", 1, 4)
	if _, bad := e["a"]; bad {
		t.Errorf("a ne devrait pas être en erreur : %v", e)
	}
	if e["b"] == "" || e["c"] == "" {
		t.Errorf("b et c devraient être en erreur : %v", e)
	}
	if Clean(" a\x00b ") != "ab" {
		t.Error("Clean doit retirer les caractères de contrôle")
	}
}

func TestMaskPhone(t *testing.T) {
	if got := MaskPhone("+22890123456"); got != "+22890••••56" {
		t.Errorf("MaskPhone = %q", got)
	}
}
