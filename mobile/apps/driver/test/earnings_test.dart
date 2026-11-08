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

  group('périodes (D18)', periodTests);
}

void periodTests() {
  // Dimanche 8 novembre 2026, 23 h 24 à Lomé.
  final now = DateTime.utc(2026, 11, 8, 23, 24);
  final missions = [
    // Semaine du 2 au 8 : vendredi 6 (deux), dimanche 8.
    _mission('a', DateTime.utc(2026, 11, 6, 10), 1000),
    _mission('b', DateTime.utc(2026, 11, 6, 18), 2000),
    _mission('c', DateTime.utc(2026, 11, 8, 9), 500),
    // Semaine précédente : lundi 26 octobre et dimanche 1er novembre.
    _mission('d', DateTime.utc(2026, 10, 26, 9), 1000),
    _mission('e', DateTime.utc(2026, 11, 1, 9), 1500),
    // Octobre, après le 8 : hors comparaison du mois.
    _mission('f', DateTime.utc(2026, 10, 20, 9), 9000),
    _mission('g', DateTime.utc(2026, 10, 3, 9), 2000),
  ];

  test('semaine : barres du lundi au dimanche, meilleur jour, variation', () {
    final s = summarize(missions, EarningsPeriod.week, now);
    expect(s.from, DateTime.utc(2026, 11, 2));
    expect(s.to, DateTime.utc(2026, 11, 8));
    expect(s.bars, [0, 0, 0, 0, 3000, 0, 500]);
    expect(s.barLabels, ['L', 'M', 'M', 'J', 'V', 'S', 'D']);
    expect(s.best, 4);
    expect(s.totals.earnedXof, 3500);
    expect(s.totals.deliveries, 3);
    // 3 500 contre 2 500 la semaine précédente : +40 %.
    expect(s.changePercent, 40);
    expect([for (final d in s.days) d.day.day], [8, 6]);
    expect(s.days.last.totals.deliveries, 2);
    expect(periodTitle(s, EarningsPeriod.week), 'DU 2 AU 8 NOVEMBRE');
    expect(dayTitle(s.days.last.day), 'Vendredi 6');
  });

  test('mois : tranches de 7 jours, comparaison au même jour du mois '
      'précédent', () {
    final s = summarize(missions, EarningsPeriod.month, now);
    expect(s.barLabels, ['1-7', '8-14', '15-21', '22-28', '29-30']);
    expect(s.bars, [4500, 500, 0, 0, 0]);
    expect(s.totals.earnedXof, 5000);
    // Du 1er au 8 octobre : 2 000 F ; du 1er au 8 novembre : 5 000 F.
    expect(s.changePercent, 150);
    expect(periodTitle(s, EarningsPeriod.month), 'NOVEMBRE 2026');
  });

  test('semaine à cheval sur deux mois ; rien avant : pas de variation', () {
    final s = summarize(
      [_mission('a', DateTime.utc(2026, 11, 3, 9), 700)],
      EarningsPeriod.week,
      DateTime.utc(2026, 11, 3, 12),
    );
    expect(periodTitle(s, EarningsPeriod.week), 'DU 2 AU 8 NOVEMBRE');
    expect(s.changePercent, isNull);
    final cross = summarize(
      const [],
      EarningsPeriod.week,
      DateTime.utc(2026, 11, 1),
    );
    expect(
      periodTitle(cross, EarningsPeriod.week),
      'DU 26 OCTOBRE AU 1ER NOVEMBRE',
    );
    expect(cross.best, isNull);
    expect(changeLabel(-8), '−8 %');
    expect(changeLabel(14), '+14 %');
  });
}
