import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivia_ui/ivia_ui.dart';

/// Ratio de contraste WCAG 2.2 entre deux couleurs opaques.
double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final (light, dark) = la > lb ? (la, lb) : (lb, la);
  return (light + 0.05) / (dark + 0.05);
}

/// Garde-fou : si une couleur de la charte change, les usages permis dans
/// docs/DESIGN.md (tableau « Contrastes ») doivent être revus.
void main() {
  const white = Color(0xFFFFFFFF);

  test('texte courant lisible (AA, 4,5:1)', () {
    const pairs = {
      'text sur background': (IviaColors.text, IviaColors.background),
      'textSecondary sur background': (
        IviaColors.textSecondary,
        IviaColors.background,
      ),
      'textMuted sur background': (IviaColors.textMuted, IviaColors.background),
      'error sur background': (IviaColors.error, IviaColors.background),
      'success sur surface': (IviaColors.success, IviaColors.surface),
      'warning sur background': (IviaColors.warning, IviaColors.background),
      'blanc sur Cornell': (white, IviaColors.cornellRed),
      'blanc sur Cobalt': (white, IviaColors.cobaltBlue),
      'blanc sur Berkeley': (white, IviaColors.berkeleyBlue),
      'text sur primarySoft': (IviaColors.text, IviaColors.primarySoft),
      'Cornell sur primarySoft': (
        IviaColors.primaryStrong,
        IviaColors.primarySoft,
      ),
      'Berkeley sur secondarySoft': (
        IviaColors.tertiary,
        IviaColors.secondarySoft,
      ),
      'Cornell sur surface': (IviaColors.primaryStrong, IviaColors.surface),
    };
    pairs.forEach((name, pair) {
      expect(
        contrast(pair.$1, pair.$2),
        greaterThanOrEqualTo(4.5),
        reason: name,
      );
    });
  });

  test('contour des champs visible (3:1)', () {
    expect(
      contrast(IviaColors.borderInput, IviaColors.surface),
      greaterThanOrEqualTo(3),
    );
    expect(
      contrast(IviaColors.borderInput, IviaColors.background),
      greaterThanOrEqualTo(3),
    );
  });

  test('pictogrammes et indicateurs des apps visibles (3:1)', () {
    for (final brand in [
      IviaAppBrand.buyer,
      IviaAppBrand.seller,
      IviaAppBrand.driver,
    ]) {
      expect(contrast(brand.accent, brand.accentSoft), greaterThanOrEqualTo(3));
      expect(
        contrast(brand.accent, IviaColors.surface),
        greaterThanOrEqualTo(3),
      );
    }
  });

  test('couleurs d\'action des apps lisibles (AA, 4,5:1)', () {
    for (final brand in [
      IviaAppBrand.buyer,
      IviaAppBrand.seller,
      IviaAppBrand.driver,
    ]) {
      // Liens : texte courant sur le fond d'écran et sur blanc.
      expect(
        contrast(brand.link, IviaColors.background),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrast(brand.link, IviaColors.surface),
        greaterThanOrEqualTo(4.5),
      );
    }
    // Marchand : blanc sur les boutons Berkeley, titres Cobalt sur le fond.
    expect(
      contrast(white, IviaAppBrand.seller.action),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      contrast(IviaAppBrand.seller.highlight, IviaColors.background),
      greaterThanOrEqualTo(4.5),
    );
  });

  test(
    'écart connu : blanc sur Imperial Red réservé aux boutons et titres',
    () {
      final ratio = contrast(white, IviaColors.imperialRed);
      expect(ratio, greaterThanOrEqualTo(3));
      expect(ratio, lessThan(4.5));
    },
  );
}
