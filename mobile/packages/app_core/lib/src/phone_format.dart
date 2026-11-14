import 'package:flutter/services.dart';

/// Numéro togolais saisi sans indicatif, affiché par paires : « 90 12 34 56 ».
/// Un numéro collé avec +228 ou 00228 garde ses 8 derniers chiffres.
class TogoPhoneFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = formatTogoPhone(newValue.text);
    // Curseur replacé après le même nombre de chiffres : on peut corriger un
    // chiffre au milieu du numéro.
    final cursor = newValue.selection.end.clamp(0, newValue.text.length);
    final digitsBefore = togoPhoneDigits(newValue.text.substring(0, cursor))
        .length;
    var offset = 0;
    for (var seen = 0; offset < text.length && seen < digitsBefore; offset++) {
      if (text[offset] != ' ') seen++;
    }
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: offset),
    );
  }
}

/// Les 8 chiffres du numéro, sans indicatif.
String togoPhoneDigits(String input) {
  var digits = input.replaceAll(RegExp(r'\D'), '');
  if (digits.length > 8 && digits.startsWith('00228')) {
    digits = digits.substring(5);
  } else if (digits.length > 8 && digits.startsWith('228')) {
    digits = digits.substring(3);
  }
  return digits.length > 8 ? digits.substring(0, 8) : digits;
}

String formatTogoPhone(String input) {
  final digits = togoPhoneDigits(input);
  final pairs = [
    for (var i = 0; i < digits.length; i += 2)
      digits.substring(i, i + 2 > digits.length ? digits.length : i + 2),
  ];
  return pairs.join(' ');
}

/// Mobile togolais : 8 chiffres commençant par 7 ou 9 (même règle que
/// l'API, qui reste seule juge).
bool isTogoMobile(String digits) => RegExp(r'^[79]\d{7}$').hasMatch(digits);

/// Numéro masqué par le serveur (« +22896••••78 ») mis en forme comme un
/// numéro saisi : « +228 96 •• •• 78 ». Rendu tel quel s'il n'a pas cette
/// forme.
String formatMaskedTogoPhone(String masked) {
  if (!masked.startsWith('+228') || masked.length != 12) return masked;
  final rest = masked.substring(4);
  return '+228 ${[for (var i = 0; i < 8; i += 2) rest.substring(i, i + 2)].join(' ')}';
}

/// Masque d'un numéro `+228XXXXXXXX` comme le serveur le rend
/// (`validate.MaskPhone`) : « +22896••••78 ». Sert à reconnaître la demande
/// d'un numéro saisi, sans jamais afficher ni garder ce numéro.
String maskTogoPhone(String e164) => e164.length < 6
    ? '••••'
    : '${e164.substring(0, 6)}••••${e164.substring(e164.length - 2)}';
