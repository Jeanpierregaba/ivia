import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Carte Google Maps activée au build (`--dart-define=GOOGLE_MAPS=true`)
/// quand les clés sont configurées ; sinon, aperçu sans fond de carte.
const mapsEnabled = bool.fromEnvironment('GOOGLE_MAPS');

/// Sans carte, la position ne vient que de « Ma position » : un marchand qui
/// refuse la localisation serait bloqué. La carte est donc exigée en release.
void requireMapsInRelease() {
  if (kReleaseMode && !mapsEnabled) {
    throw StateError(
      'Carte absente : construire avec --dart-define=GOOGLE_MAPS=true et les '
      'clés Google Maps (AGENTS.md).',
    );
  }
}

final mapsEnabledProvider = Provider<bool>((ref) => mapsEnabled);
