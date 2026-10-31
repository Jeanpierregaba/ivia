import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivia_buyer/features/auth/phone_format.dart';

void main() {
  test('numéro par paires, indicatif retiré', () {
    expect(formatTogoPhone('90123456'), '90 12 34 56');
    expect(formatTogoPhone('+228 90 12 34 56'), '90 12 34 56');
    expect(formatTogoPhone('0022870123456'), '70 12 34 56');
    expect(formatTogoPhone('901'), '90 1');
  });

  test('mobile togolais : 8 chiffres commençant par 7 ou 9', () {
    expect(isTogoMobile('90123456'), isTrue);
    expect(isTogoMobile('70123456'), isTrue);
    expect(isTogoMobile('22123456'), isFalse);
    expect(isTogoMobile('9012345'), isFalse);
  });

  test('correction au milieu : curseur gardé après le chiffre saisi', () {
    // « 90 12 34 56 », on remplace le 1 (position 3) par 5.
    final result = TogoPhoneFormatter().formatEditUpdate(
      const TextEditingValue(text: '90 12 34 56'),
      const TextEditingValue(
        text: '90 52 34 56',
        selection: TextSelection.collapsed(offset: 4),
      ),
    );
    expect(result.text, '90 52 34 56');
    expect(result.selection.baseOffset, 4);
  });
}
