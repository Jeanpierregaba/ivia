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
    AreaPlace(:final name) => name,
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

/// Lieu cherché par son nom (« Grand Marché », « Université de Lomé ») :
/// ses coordonnées servent comme une position.
class AreaPlace extends AreaPosition {
  const AreaPlace(super.point, this.name);

  final String name;
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

  /// Choix lu au lancement : quartier ou lieu cherché ; `null` (rien de
  /// choisi, ou position du téléphone).
  final BuyerArea? initial;

  static Future<AreaStore> open() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return AreaStore._(prefs, initial: _parse(prefs.get(_key)));
    } on Exception {
      return AreaStore._(null, initial: null);
    }
  }

  /// `n|<id>|<nom>` ou `l|<lat>|<lng>|<nom>` ; toute autre valeur
  /// (position, donnée corrompue) : rien.
  static BuyerArea? _parse(Object? value) {
    if (value is! String) return null;
    final parts = value.split('|');
    if (value.startsWith('n|')) {
      if (parts.length != 3 || parts[1].isEmpty) return null;
      return AreaNeighborhood(parts[1], parts[2]);
    }
    if (value.startsWith('l|') && parts.length == 4) {
      final lat = double.tryParse(parts[1]), lng = double.tryParse(parts[2]);
      if (lat == null || lng == null) return null;
      return AreaPlace(GeoPoint(lat: lat, lng: lng), parts[3]);
    }
    return null;
  }

  /// Lieu choisi par son nom (pas la position du téléphone).
  Future<void> savePlace(AreaPlace area) => _write(
    'l|${area.point.lat}|${area.point.lng}|${area.name.replaceAll('|', ' ')}',
  );

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

  /// Numéro de la dernière demande : une réponse de position arrivée après
  /// un choix plus récent (quartier, nouvelle demande) est ignorée.
  var _request = 0;

  /// Dernière zone connue (position ou quartier), gardée si une nouvelle
  /// demande de position échoue.
  BuyerArea? _settled;

  /// Sans quartier gardé, l'app part en recherche de la position : aucune
  /// recherche n'est lancée sans zone en attendant.
  @override
  BuyerArea build() {
    final stored = ref.read(areaStoreProvider).initial;
    _settled = stored;
    return stored ?? const AreaLocating();
  }

  /// À l'ouverture de l'accueil : sans quartier choisi, la position est
  /// demandée une fois par ouverture de l'app.
  Future<void> ensure() async {
    if (_asked || state is AreaNeighborhood || state is AreaPlace) return;
    await locate();
  }

  /// « Utiliser ma position ». Échec : la zone connue est gardée (ou
  /// inconnue, avec la raison) ; renvoie la raison.
  Future<LocationFailure?> locate() async {
    _asked = true;
    final request = ++_request;
    state = const AreaLocating();
    LocationResult result;
    try {
      result = await ref.read(locationServiceProvider).current();
    } on Exception {
      result = const LocationResult.failed(LocationFailure.unavailable);
    }
    // Choix plus récent pendant l'attente : il prime.
    if (!ref.mounted || request != _request) return result.failure;
    if (result.point case final point?) {
      state = _settled = AreaPosition(point);
      await ref.read(areaStoreProvider).savePosition();
      return null;
    }
    state = _settled ?? AreaUnknown(result.failure);
    return result.failure;
  }

  /// Lieu trouvé par la recherche : ses coordonnées servent de zone.
  Future<void> choosePlace(GeoPoint point, String name) async {
    _request++;
    final area = AreaPlace(point, name);
    state = _settled = area;
    await ref.read(areaStoreProvider).savePlace(area);
  }

  Future<void> chooseNeighborhood(Choice neighborhood) async {
    _request++;
    final area = AreaNeighborhood(neighborhood.id, neighborhood.name);
    state = _settled = area;
    await ref.read(areaStoreProvider).saveNeighborhood(area);
  }
}

/// Explication d'une position manquante, pour l'acheteur.
String locationFailureMessage(LocationFailure failure) => switch (failure) {
  LocationFailure.serviceDisabled =>
    'La localisation de votre téléphone est désactivée.',
  LocationFailure.denied => 'Autorisez la localisation pour voir les boutiques et produits autour de vous.',
  LocationFailure.deniedForever =>
    'La localisation est bloquée pour ivia dans les réglages du téléphone.',
  LocationFailure.unavailable =>
    'Votre position est introuvable pour l’instant.',
};
