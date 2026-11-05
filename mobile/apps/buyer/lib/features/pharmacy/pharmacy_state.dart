import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';

import '../../app/buyer_area.dart';

/// Centre approximatif des quartiers de Lomé : position de recherche des
/// pharmacies quand l'acheteur a choisi un quartier plutôt que le GPS.
const _neighborhoodCenters = {
  'Bè': GeoPoint(lat: 6.1430, lng: 1.2370),
  'Tokoin': GeoPoint(lat: 6.1480, lng: 1.2150),
  'Adidogomé': GeoPoint(lat: 6.1750, lng: 1.1600),
  'Agoè': GeoPoint(lat: 6.2350, lng: 1.2050),
  'Nyékonakpoè': GeoPoint(lat: 6.1300, lng: 1.2050),
  'Kodjoviakopé': GeoPoint(lat: 6.1260, lng: 1.1980),
  'Hédzranawoé': GeoPoint(lat: 6.1630, lng: 1.2400),
  'Baguida': GeoPoint(lat: 6.1600, lng: 1.3200),
  'Djidjolé': GeoPoint(lat: 6.1600, lng: 1.1950),
  'Amoutiévé': GeoPoint(lat: 6.1330, lng: 1.2250),
  'Avédji': GeoPoint(lat: 6.1850, lng: 1.1850),
  'Kégué': GeoPoint(lat: 6.1700, lng: 1.2600),
};

GeoPoint? _areaPoint(BuyerArea area) => switch (area) {
  AreaNeighborhood(:final name) => area.point ?? _neighborhoodCenters[name],
  _ => area.point,
};

/// Pharmacies de garde autour de l'acheteur (accueil A01).
final onDutyPharmaciesProvider =
    FutureProvider.autoDispose<List<OnDutyPharmacy>>((ref) async {
      final point = _areaPoint(ref.watch(buyerAreaProvider));
      if (point == null) return const [];
      return ref.read(apiClientProvider).onDutyPharmacies(point, limit: 3);
    });

/// Alertes de l'acheteur, la plus récente d'abord.
final myAlertsProvider = FutureProvider.autoDispose<List<MedAlert>>(
  (ref) => ref.read(apiClientProvider).myAlerts(),
);

final medAlertProvider = FutureProvider.autoDispose.family<MedAlert, String>(
  (ref, id) => ref.read(apiClientProvider).medAlert(id),
);

final medReservationProvider = FutureProvider.autoDispose
    .family<MedReservation, String>(
      (ref, id) => ref.read(apiClientProvider).medReservation(id),
    );

/// Position de l'alerte : celle de la zone de l'accueil, sinon le GPS.
Future<GeoPoint?> alertPosition(WidgetRef ref) async {
  final point = _areaPoint(ref.read(buyerAreaProvider));
  if (point != null) return point;
  try {
    // Navigateur : la demande d'autorisation peut rester sans réponse.
    return (await ref
            .read(locationServiceProvider)
            .current()
            .timeout(const Duration(seconds: 8)))
        .point;
  } on TimeoutException {
    return null;
  }
}

/// Relit un provider toutes les [every] tant que l'écran est ouvert et que
/// [active] le demande (suivi en direct).
mixin LivePolling<T extends StatefulWidget> on State<T> {
  Timer? _poll;

  void startPolling(
    VoidCallback refresh, {
    Duration every = const Duration(seconds: 4),
  }) {
    _poll?.cancel();
    _poll = Timer.periodic(every, (_) => refresh());
  }

  void stopPolling() => _poll?.cancel();

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }
}

/// Libellés des statuts de réservation (P08 à P14).
String reservationStatusLabel(MedReservation r) => switch (r.status) {
  'reserved' when r.delivery => 'Livraison choisie',
  'reserved' => 'Mis de côté pour vous',
  'courier_search' => 'Recherche d\'un livreur ivia',
  'awaiting_payment' => 'Livreur trouvé : à vous de payer',
  'courier_assigned' => 'Le livreur va chercher votre commande',
  'picked_up' => 'Le livreur arrive',
  'completed' => 'Remis',
  'expired' => 'Mise de côté expirée',
  'cancelled' => 'Annulée',
  _ => r.status,
};
