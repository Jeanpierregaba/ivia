/// Code de commande alphanumérique (« K7P2-9QXA »), tiré du numéro par une
/// permutation réversible (réseau de Feistel sur 40 bits) : unique pour chaque
/// numéro, impossible à deviner d'une commande à l'autre, et identique dans
/// l'API (Go), les apps et le back-office. Imprimé en code-barres (Code 128).
library;

const _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ'; // Crockford, sans I L O U
const _keys = [0x3A5C1, 0x7E2B9, 0x1D4F7, 0x6B8E3];
const _mask = 0xFFFFF; // 20 bits

int _round(int r, int k) => ((r * 0x5BD1 + k) ^ (r >> 7)) & _mask;

/// Code lisible d'une commande à partir de son numéro.
String orderCode(int number) {
  var l = (number >> 20) & _mask;
  var r = number & _mask;
  for (final k in _keys) {
    final next = l ^ _round(r, k);
    l = r;
    r = next;
  }
  final out = StringBuffer();
  for (var i = 7; i >= 0; i--) {
    final chunk = i >= 4 ? (l >> ((i - 4) * 5)) & 31 : (r >> (i * 5)) & 31;
    out.write(_alphabet[chunk]);
    if (i == 4) out.write('-');
  }
  return out.toString();
}

/// Code d'une commande à partir de sa référence (« IV-000111 ») ; vide si
/// elle ne contient pas de numéro.
String orderCodeOfReference(String reference) {
  final digits = RegExp(r'\d+').firstMatch(reference)?.group(0);
  return digits == null ? '' : orderCode(int.parse(digits));
}
