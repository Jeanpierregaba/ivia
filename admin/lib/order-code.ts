// Code de commande alphanumérique (« K7P2-9QXA »), tiré du numéro par une permutation réversible
// (réseau de Feistel sur 40 bits) : mêmes valeurs que l'API (Go) et les apps (Dart).

const ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";
const KEYS = [0x3a5c1, 0x7e2b9, 0x1d4f7, 0x6b8e3];
const MASK = 0xfffff;

export function orderCode(number: number): string {
  let l = Math.floor(number / 0x100000) & MASK;
  let r = number & MASK;
  for (const k of KEYS) {
    const f = ((r * 0x5bd1 + k) ^ (r >> 7)) & MASK;
    [l, r] = [r, l ^ f];
  }
  let out = "";
  for (let i = 7; i >= 0; i--) {
    const chunk = i >= 4 ? (l >> ((i - 4) * 5)) & 31 : (r >> (i * 5)) & 31;
    out += ALPHABET[chunk];
    if (i === 4) out += "-";
  }
  return out;
}

/** Code à partir d'une référence « IV-000111 » ; vide sans numéro. */
export function orderCodeOfReference(reference: string): string {
  const m = /\d+/.exec(reference);
  return m ? orderCode(Number(m[0])) : "";
}
