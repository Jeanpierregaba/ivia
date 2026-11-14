/// Outils de test des écrans communs : faux service de position (règle 7
/// d'AGENTS.md).
library;

import 'dart:async';

import 'package:ivia_api_client/ivia_api_client.dart';

import 'src/location.dart';

/// Position simulée : autorisation [state] (accordée par défaut), réponse de
/// la fenêtre du système [onRequest], position [next] (ou [pending], ou
/// [error]).
class FakeLocationService implements LocationService {
  FakeLocationService({
    this.state = LocationAccess.granted,
    this.onRequest = LocationAccess.granted,
    this.next = const LocationResult.found(lome),
  });

  /// Centre de Lomé (Tokoin).
  static const lome = GeoPoint(lat: 6.1375, lng: 1.2123);

  LocationAccess state;

  /// État après la fenêtre du système ; [requestPending] la retient.
  LocationAccess onRequest;
  Completer<void>? requestPending;

  LocationResult next;

  /// Réponse retenue (GPS lent) ; `null` : immédiate.
  Completer<LocationResult>? pending;
  Exception? error;

  var calls = 0;
  var requests = 0;
  var settingsOpened = 0;

  @override
  Future<LocationAccess> access() async => state;

  @override
  Future<LocationAccess> request() async {
    requests++;
    if (requestPending case final p?) await p.future;
    return state = onRequest;
  }

  @override
  Future<LocationResult> current() async {
    calls++;
    if (error case final e?) throw e;
    switch (state) {
      case LocationAccess.askable:
        return const LocationResult.failed(LocationFailure.denied);
      case LocationAccess.deniedForever:
        return const LocationResult.failed(LocationFailure.deniedForever);
      case LocationAccess.granted:
        if (pending case final p?) return p.future;
        return next;
    }
  }

  @override
  Future<bool> openSettings() async {
    settingsOpened++;
    return true;
  }
}
