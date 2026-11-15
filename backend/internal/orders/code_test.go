package orders

import "testing"

// Mêmes valeurs que les tests Dart (api_client) et TypeScript (back-office).
func TestCode(t *testing.T) {
	cases := map[int64]string{1: "HSWK-20E0", 111: "NTNJ-CKVW", 1042: "W8MB-QRCH", 1043: "F4D6-PHF8", 999999: "DC1D-KHHF"}
	for n, want := range cases {
		if got := Code(n); got != want {
			t.Errorf("Code(%d) = %s, attendu %s", n, got, want)
		}
	}
	seen := map[string]bool{}
	for n := int64(1); n <= 50000; n++ {
		c := Code(n)
		if seen[c] {
			t.Fatalf("code en double : %s", c)
		}
		seen[c] = true
	}
}
