import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivia_app_core/ivia_app_core.dart';

/// Espaces typographiques remplacés par des espaces simples, pour lire les
/// attentes.
String plain(String s) => s.replaceAll(' ', ' ').replaceAll(' ', ' ');

void main() {
  test('prix groupés par milliers, espace insécable avant F', () {
    expect(plain(formatXof(450)), '450 F');
    expect(plain(formatXof(4500)), '4 500 F');
    expect(plain(formatXof(100000000)), '100 000 000 F');
    expect(formatXof(4500), contains(' F'));
  });

  test('prix saisi : séparateurs ignorés, vide refusé', () {
    expect(parseXof('4 500'), 4500);
    expect(parseXof('4.500'), 4500);
    expect(parseXof('4 500'), 4500);
    expect(parseXof(''), isNull);
    expect(parseXof('abc'), isNull);
  });

  group('saisie du prix', () {
    final formatter = XofInputFormatter();
    TextEditingValue type(String old, String text, [int? cursor]) =>
        formatter.formatEditUpdate(
          TextEditingValue(text: old),
          TextEditingValue(
            text: text,
            selection: TextSelection.collapsed(offset: cursor ?? text.length),
          ),
        );

    test('groupée pendant la frappe, curseur en fin', () {
      final v = type('450', '4500');
      expect(plain(v.text), '4 500');
      expect(v.selection.end, v.text.length);
    });

    test('lettres et zéros de tête retirés', () {
      expect(plain(type('', '0012a5').text), '125');
      expect(type('', '0').text, '0');
    });

    test('au-delà de 9 chiffres : frappe ignorée', () {
      final v = type('100 000 000', '1000000000');
      expect(plain(v.text), '100 000 000');
    });

    test('correction au milieu : curseur après le même chiffre', () {
      // « 4 500 » → insertion de 2 après le 4 : « 42 500 ».
      final v = type('4 500', '42 500', 2);
      expect(plain(v.text), '42 500');
      expect(v.selection.end, 2);
    });
  });

  group('dates courtes', () {
    final now = DateTime.utc(2026, 10, 31, 15);

    test("aujourd'hui, hier, puis jour et mois", () {
      expect(shortDate(DateTime.utc(2026, 10, 31, 1), now: now), "aujourd'hui");
      expect(shortDate(DateTime.utc(2026, 10, 30, 23), now: now), 'hier');
      expect(shortDate(DateTime.utc(2026, 10, 24), now: now), '24 oct.');
      expect(shortDate(DateTime.utc(2026, 2, 1), now: now), '1 févr.');
      expect(shortDate(DateTime.utc(2025, 12, 9), now: now), '9 déc. 2025');
    });

    test('heure de Lomé (UTC) même pour une date locale', () {
      final local = DateTime.utc(2026, 10, 24, 23, 30).toLocal();
      expect(shortDate(local, now: now), '24 oct.');
    });

    test('« le » devant une date, pas devant aujourd\'hui ni hier', () {
      expect(onDate(DateTime.utc(2026, 10, 24), now: now), 'le 24 oct.');
      expect(onDate(DateTime.utc(2026, 10, 31), now: now), "aujourd'hui");
    });
  });

  test('distances : mètres sous 1 km, puis kilomètres à la virgule', () {
    expect(plain(formatDistance(3)), '10 m');
    expect(plain(formatDistance(347)), '350 m');
    expect(plain(formatDistance(994)), '990 m');
    expect(plain(formatDistance(996)), '1 km', reason: 'jamais « 1000 m »');
    expect(plain(formatDistance(1150)), '1,2 km');
    expect(plain(formatDistance(2000)), '2 km');
    expect(plain(formatDistance(9960)), '10 km');
    expect(plain(formatDistance(12400)), '12 km');
    expect(formatDistance(350), contains('\u00A0'));
  });
}
