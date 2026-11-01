import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Zone où l'acheteur cherche : la position du téléphone, ou un quartier.
sealed class BuyerArea {
  const BuyerArea();

  /// Paramètres de zone d'une recherche (`point` ou `neighborhoodId`).
  SearchQuery apply(SearchQuery query) => switch (this) {
    AreaPosition(:final point) => query.copyWith(
      point: () => point,
      neighborhoodId: () => null,
    ),
    AreaNeighborhood(:final id) => query.copyWith(
      point: () => null,
      radiusM: () => null,
      neighborhoodId: () => id,
    ),
    _ => query.copyWith(
      point: () => null,
      radiusM: () => null,
      neighborhoodId: () => null,
    ),
  };

  /// Libellé de l'en-tête de l'accueil (« Ma position », « Tokoin »).
  String get label => switch (this) {
    AreaPosition() => 'Ma position',
    AreaNeighborhood(:final name) => name,
    AreaLocating() => 'Localisation…',
    AreaUnknown() => 'Choisir un quartier',
  };

  GeoPoint? get point => switch (this) {
    AreaPosition(:final point) => point,
    _ => null,
  };
}

/// Ni position ni quartier ; [failure] : pourquoi la position manque.
class AreaUnknown extends BuyerArea {
  const AreaUnknown([this.failure]);

  final LocationFailure? failure;
}

/// Position en cours de lecture.
class AreaLocating extends BuyerArea {
  const AreaLocating();
}

class AreaPosition extends BuyerArea {
  const AreaPosition(this.point);

  @override
  final GeoPoint point;
}

class AreaNeighborhood extends BuyerArea {
  const AreaNeighborhood(this.id, this.name);

  final String id;
  final String name;
}

/// Choix de zone gardé sur le téléphone : le quartier (identifiant et nom),
/// ou la position du téléphone. La position elle-même n'est jamais gardée.
class AreaStore {
  AreaStore._(this._prefs, {required this.initial});

  static const _key = 'buyer_area';

  final SharedPreferences? _prefs;

  /// Choix lu au lancement : `null` (rien de choisi, ou position).
  final AreaNeighborhood? initial;

  static Future<AreaStore> open() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return AreaStore._(prefs, initial: _parse(prefs.get(_key)));
    } on Exception {
      return AreaStore._(null, initial: null);
    }
  }

  /// `n|<id>|<nom>` ; toute autre valeur (position, donnée corrompue) : rien.
  static AreaNeighborhood? _parse(Object? value) {
    if (value is! String || !value.startsWith('n|')) return null;
    final parts = value.split('|');
    if (parts.length != 3 || parts[1].isEmpty) return null;
    return AreaNeighborhood(parts[1], parts[2]);
  }

  Future<void> saveNeighborhood(AreaNeighborhood area) =>
      _write('n|${area.id}|${area.name.replaceAll('|', ' ')}');

  Future<void> savePosition() => _write('position');

  /// Un échec d'écriture est ignoré : le choix sera redemandé.
  Future<void> _write(String value) async {
    try {
      await _prefs?.setString(_key, value);
    } on Exception {
      // Rien à faire : la zone reste choisie pour cette session.
    }
  }
}

/// Fourni par `main()` une fois le stockage ouvert.
final areaStoreProvider = Provider<AreaStore>(
  (ref) => throw UnimplementedError('areaStoreProvider non fourni'),
);

/// Zone de recherche de l'acheteur.
final buyerAreaProvider = NotifierProvider<BuyerAreaController, BuyerArea>(
  BuyerAreaController.new,
);

class BuyerAreaController extends Notifier<BuyerArea> {
  /// Position déjà demandée pendant cette ouverture de l'app.
  var _asked = false;

  /// Sans quartier gardé, l'app part en recherche de la position : aucune
  /// recherche n'est lancée sans zone en attendant.
  @override
  BuyerArea build() =>
      ref.read(areaStoreProvider).initial ?? const AreaLocating();

  /// À l'ouverture de l'accueil : sans quartier choisi, la position est
  /// demandée une fois par ouverture de l'app.
  Future<void> ensure() async {
    if (_asked || state is AreaNeighborhood) return;
    await locate();
  }

  /// « Utiliser ma position ». Échec : la zone précédente est gardée (ou
  /// inconnue, avec la raison) ; renvoie la raison.
  Future<LocationFailure?> locate() async {
    _asked = true;
    final previous = state;
    state = const AreaLocating();
    LocationResult result;
    try {
      result = await ref.read(locationServiceProvider).current();
    } on Exception {
      result = const LocationResult.failed(LocationFailure.unavailable);
    }
    if (!ref.mounted) return result.failure;
    if (result.point case final point?) {
      state = AreaPosition(point);
      await ref.read(areaStoreProvider).savePosition();
      return null;
    }
    state = previous is AreaNeighborhood
        ? previous
        : AreaUnknown(result.failure);
    return result.failure;
  }

  Future<void> chooseNeighborhood(Choice neighborhood) async {
    final area = AreaNeighborhood(neighborhood.id, neighborhood.name);
    state = area;
    await ref.read(areaStoreProvider).saveNeighborhood(area);
  }
}

/// Explication d'une position manquante, pour l'acheteur.
String locationFailureMessage(LocationFailure failure) => switch (failure) {
  LocationFailure.serviceDisabled =>
    'La localisation est désactivée. Choisissez votre quartier.',
  LocationFailure.denied || LocationFailure.deniedForever =>
    'Position non autorisée. Choisissez votre quartier.',
  LocationFailure.unavailable =>
    'Position introuvable pour l’instant. Choisissez votre quartier.',
};
