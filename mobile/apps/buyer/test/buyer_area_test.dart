import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_buyer/app/buyer_area.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _lome = GeoPoint(lat: 6.1375, lng: 1.2123);

class _FakeLocation implements LocationService {
  LocationResult next = const LocationResult.found(_lome);
  var calls = 0;

  @override
  Future<LocationResult> current() async {
    calls++;
    return next;
  }
}

void main() {
  late _FakeLocation location;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    location = _FakeLocation();
  });

  Future<ProviderContainer> container() async {
    final store = await AreaStore.open();
    return ProviderContainer.test(
      overrides: [
        areaStoreProvider.overrideWithValue(store),
        locationServiceProvider.overrideWithValue(location),
      ],
    );
  }

  test('rien de choisi : position demandée une fois par ouverture', () async {
    final c = await container();
    expect(c.read(buyerAreaProvider), isA<AreaUnknown>());
    await c.read(buyerAreaProvider.notifier).ensure();
    await c.read(buyerAreaProvider.notifier).ensure();
    expect(location.calls, 1);
    expect(c.read(buyerAreaProvider).point, _lome);
    expect(c.read(buyerAreaProvider).label, 'Ma position');
    // La position n'est jamais gardée, seulement le choix.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.get('buyer_area'), 'position');
  });

  test('position refusée : zone inconnue, raison et message', () async {
    location.next = const LocationResult.failed(LocationFailure.denied);
    final c = await container();
    final failure = await c.read(buyerAreaProvider.notifier).locate();
    expect(failure, LocationFailure.denied);
    final area = c.read(buyerAreaProvider);
    expect(area, isA<AreaUnknown>());
    expect((area as AreaUnknown).failure, LocationFailure.denied);
    expect(
      locationFailureMessage(LocationFailure.denied),
      contains('Choisissez votre quartier'),
    );
  });

  test(
    'quartier choisi : retrouvé au lancement, position non demandée',
    () async {
      final c = await container();
      await c
          .read(buyerAreaProvider.notifier)
          .chooseNeighborhood(const Choice(id: 'n1', name: 'Tokoin'));
      expect(c.read(buyerAreaProvider).label, 'Tokoin');

      final relaunch = await container();
      final area = relaunch.read(buyerAreaProvider);
      expect(area, isA<AreaNeighborhood>());
      expect((area as AreaNeighborhood).id, 'n1');
      await relaunch.read(buyerAreaProvider.notifier).ensure();
      expect(location.calls, 0);
    },
  );

  test('« Utiliser ma position » en échec : le quartier reste', () async {
    final c = await container();
    await c
        .read(buyerAreaProvider.notifier)
        .chooseNeighborhood(const Choice(id: 'n1', name: 'Tokoin'));
    location.next = const LocationResult.failed(LocationFailure.unavailable);
    await c.read(buyerAreaProvider.notifier).locate();
    expect(c.read(buyerAreaProvider).label, 'Tokoin');
  });

  test('donnée gardée illisible : rien de choisi', () async {
    SharedPreferences.setMockInitialValues({'buyer_area': 42});
    expect((await AreaStore.open()).initial, isNull);
    SharedPreferences.setMockInitialValues({'buyer_area': 'n||'});
    expect((await AreaStore.open()).initial, isNull);
  });

  test('zone traduite en paramètres de recherche', () {
    const query = SearchQuery(text: 'riz', radiusM: 2000, neighborhoodId: 'x');
    final byPosition = const AreaPosition(_lome).apply(query);
    expect(byPosition.point, _lome);
    expect(byPosition.radiusM, 2000);
    expect(byPosition.neighborhoodId, isNull);

    final byNeighborhood = const AreaNeighborhood(
      'n1',
      'Tokoin',
    ).apply(query.copyWith(point: () => _lome));
    expect(byNeighborhood.point, isNull);
    expect(byNeighborhood.radiusM, isNull);
    expect(byNeighborhood.neighborhoodId, 'n1');

    final none = const AreaUnknown().apply(query);
    expect(none.neighborhoodId, isNull);
    expect(none.radiusM, isNull);
  });
}
