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
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
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
