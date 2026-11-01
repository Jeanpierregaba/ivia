import 'package:flutter/services.dart';

/// Espace fine insécable entre les milliers (« 4 500 »).
const _thousands = ' ';

/// Montant entier groupé par milliers : « 4 500 », « 100 000 000 ».
String groupDigits(int amount) {
  final digits = amount.abs().toString();
  final out = StringBuffer(amount < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(_thousands);
    out.write(digits[i]);
  }
  return out.toString();
}

/// Prix en FCFA tel qu'affiché : « 4 500 F » (espace insécable avant F).
String formatXof(int amount) => '${groupDigits(amount)} F';

/// Prix saisi (« 4 500 », « 4.500 ») lu en FCFA ; `null` : aucun chiffre.
int? parseXof(String input) {
  final digits = input.replaceAll(RegExp(r'\D'), '');
  return digits.isEmpty ? null : int.tryParse(digits);
}

/// Saisie d'un prix : chiffres seulement, groupés par milliers pendant la
/// frappe, [maxDigits] au plus.
class XofInputFormatter extends TextInputFormatter {
  XofInputFormatter({this.maxDigits = 9});

  final int maxDigits;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length > maxDigits) return oldValue;
    // Zéros de tête retirés : « 0 » seul reste possible.
    digits = digits.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    final text = digits.isEmpty ? '' : groupDigits(int.parse(digits));
    // Curseur replacé après le même nombre de chiffres.
    final cursor = newValue.selection.end.clamp(0, newValue.text.length);
    final before = newValue.text
        .substring(0, cursor)
        .replaceAll(RegExp(r'\D'), '')
        .length
        .clamp(0, digits.length);
    var offset = 0;
    for (var seen = 0; offset < text.length && seen < before; offset++) {
      if (text[offset] != _thousands) seen++;
    }
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: offset),
    );
  }
}

const _months = [
  'janv.',
  'févr.',
  'mars',
  'avr.',
  'mai',
  'juin',
  'juil.',
  'août',
  'sept.',
  'oct.',
  'nov.',
  'déc.',
];

/// Date courte à l'heure de Lomé (UTC toute l'année) : « aujourd'hui »,
/// « hier », « 24 oct. », ou « 24 oct. 2025 » pour une autre année.
String shortDate(DateTime date, {DateTime? now}) {
  final d = date.toUtc();
  final today = (now ?? DateTime.now()).toUtc();
  final day = DateTime.utc(d.year, d.month, d.day);
  final todayDay = DateTime.utc(today.year, today.month, today.day);
  final diff = todayDay.difference(day).inDays;
  if (diff == 0) return "aujourd'hui";
  if (diff == 1) return 'hier';
  final base = '${d.day} ${_months[d.month - 1]}';
  return d.year == today.year ? base : '$base ${d.year}';
}

/// [shortDate] précédé de « le » sauf pour aujourd'hui et hier :
/// « Retiré le 24 oct. », « Retiré aujourd'hui ».
String onDate(DateTime date, {DateTime? now}) {
  final s = shortDate(date, now: now);
  return s == "aujourd'hui" || s == 'hier' ? s : 'le $s';
}
