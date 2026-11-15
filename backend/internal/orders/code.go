package orders

// Code de commande alphanumérique (« K7P2-9QXA »), tiré du numéro par une permutation réversible
// (réseau de Feistel sur 40 bits) : unique pour chaque numéro, et identique dans les apps (Dart) et
// le back-office (TypeScript). Imprimé en code-barres (Code 128) sur le reçu et les écrans.

const codeAlphabet = "0123456789ABCDEFGHJKMNPQRSTVWXYZ" // Crockford, sans I L O U

var codeKeys = [4]int64{0x3A5C1, 0x7E2B9, 0x1D4F7, 0x6B8E3}

const codeMask = 0xFFFFF // 20 bits

// Code retourne le code lisible d'une commande.
func Code(number int64) string {
	l, r := (number>>20)&codeMask, number&codeMask
	for _, k := range codeKeys {
		l, r = r, l^(((r*0x5BD1+k)^(r>>7))&codeMask)
	}
	out := make([]byte, 0, 9)
	for i := 7; i >= 0; i-- {
		var chunk int64
		if i >= 4 {
			chunk = (l >> ((i - 4) * 5)) & 31
		} else {
			chunk = (r >> (i * 5)) & 31
		}
		out = append(out, codeAlphabet[chunk])
		if i == 4 {
			out = append(out, '-')
		}
	}
	return string(out)
}
