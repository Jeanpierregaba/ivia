import 'package:flutter_test/flutter_test.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_driver/features/earnings/earnings.dart';

// Spec 033 : gains calculés depuis l'historique, jours de Lomé (UTC).

WorkMission _mission(String id, DateTime? deliveredAt, int fee) =>
    WorkMission.shop({
      'id': id,
      'order_reference': '#$id',
      'status': deliveredAt == null ? 'failed' : 'delivered',
      'fee_xof': fee,
      'items_count': 1,
      'parcel_size': 'small',
      'shop': {'name': 'Chez Afi'},
      'customer': null,
      'assigned_at': (deliveredAt ?? DateTime.utc(2026, 11, 8))
          .toIso8601String(),
      'delivered_at': deliveredAt?.toIso8601String(),
    });

void main() {
  // Dimanche 8 novembre 2026, 23 h 24 à Lomé.
  final now = DateTime.utc(2026, 11, 8, 23, 24);
  final missions = [
    _mission('a', DateTime.utc(2026, 11, 8, 23, 58), 1200),
    _mission('b', DateTime.utc(2026, 11, 8, 0, 5), 700),
    // Samedi soir à Lomé, minuit passé ailleurs : samedi.
    _mission('c', DateTime.utc(2026, 11, 7, 23, 50), 1000),
    // Lundi de la semaine précédente : hors semaine.
    _mission('d', DateTime.utc(2026, 11, 1, 12), 900),
    // Pas livrée : jamais comptée.
    _mission('e', null, 5000),
  ];

  test('jour de Lomé', () {
    final t = today(missions, now);
    expect(t.earnedXof, 1900);
    expect(t.deliveries, 2);
  });

  test('semaine du lundi à aujourd\'hui', () {
    expect(weekStart(now), DateTime.utc(2026, 11, 2));
    final w = thisWeek(missions, now);
    expect(w.earnedXof, 2900);
    expect(w.deliveries, 3);
  });

  test('aucune mission : zéro', () {
    expect(today(const [], now).earnedXof, 0);
    expect(thisWeek(const [], now).deliveries, 0);
  });
}
