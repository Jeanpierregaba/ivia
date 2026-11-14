import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:url_launcher/url_launcher.dart';

/// Lien d'appel : chiffres et « + » seulement (un numéro avec espaces ou
/// tirets donnerait un lien encodé que le téléphone ne compose pas).
Uri telUri(String phone) =>
    Uri(scheme: 'tel', path: phone.replaceAll(RegExp(r'[^\d+]'), ''));

/// Itinéraire dans l'application de navigation choisie (Profil). Liens
/// universels : l'app s'ouvre si elle est installée, sinon le navigateur.
/// Le lien ne contient que les coordonnées de la destination.
enum NavApp {
  google('google', 'Google Maps', 'Maps'),
  waze('waze', 'Waze', 'Waze'),
  apple('apple', 'Plans', 'Plans');

  const NavApp(this.code, this.label, this.shortLabel);
  final String code, label;

  /// Nom court des boutons (« Ouvrir dans Maps »).
  final String shortLabel;

  static NavApp parse(String? code) =>
      values.firstWhere((a) => a.code == code, orElse: () => google);

  Uri route(GeoPoint to) => switch (this) {
    google => Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      'destination': '${to.lat},${to.lng}',
      'travelmode': 'driving',
    }),
    waze => Uri.https('waze.com', '/ul', {
      'll': '${to.lat},${to.lng}',
      'navigate': 'yes',
    }),
    apple => Uri.https('maps.apple.com', '/', {
      'daddr': '${to.lat},${to.lng}',
      'dirflg': 'd',
    }),
  };
}

/// Ouvre un lien hors de l'app (navigation, appel) ; `false` : impossible.
/// Remplacé dans les tests.
final linkLauncherProvider = Provider<Future<bool> Function(Uri)>(
  (ref) =>
      (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);
