import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';

import '../../common/formats.dart';

/// Gains calculés dans l'app depuis l'historique des missions (spec 033,
/// arbitrage 5 : le serveur ne fournit pas de totaux). Jours de Lomé.

/// Profondeur de l'historique lu : assez pour « Mois » et sa comparaison.
const historyDays = 62;

/// Missions des [historyDays] derniers jours (boutique et pharmacie).
final missionHistoryProvider = FutureProvider.autoDispose<List<WorkMission>>((
  ref,
) {
  final since = lomeDay(DateTime.now())
      .subtract(const Duration(days: historyDays));
  return ref.read(apiClientProvider).workHistory(since: since);
});

/// Totaux d'une période : gains des missions livrées et leur nombre.
class Totals {
  const Totals(this.earnedXof, this.deliveries);
  final int earnedXof, deliveries;

  static const zero = Totals(0, 0);
}

/// Missions livrées dans [from, to[ (jours de Lomé).
Totals totalsBetween(List<WorkMission> missions, DateTime from, DateTime to) {
  var earned = 0, count = 0;
  for (final m in missions) {
    final at = m.deliveredAt;
    if (at == null) continue;
    final day = lomeDay(at);
    if (day.isBefore(from) || !day.isBefore(to)) continue;
    earned += m.feeXof;
    count++;
  }
  return Totals(earned, count);
}

/// Totaux du jour de Lomé de [now].
Totals today(List<WorkMission> missions, DateTime now) {
  final day = lomeDay(now);
  return totalsBetween(missions, day, day.add(const Duration(days: 1)));
}

/// Lundi (jour de Lomé) de la semaine de [now].
DateTime weekStart(DateTime now) {
  final day = lomeDay(now);
  return day.subtract(Duration(days: day.weekday - DateTime.monday));
}

/// Totaux de la semaine en cours (lundi à aujourd'hui inclus).
Totals thisWeek(List<WorkMission> missions, DateTime now) => totalsBetween(
  missions,
  weekStart(now),
  lomeDay(now).add(const Duration(days: 1)),
);
