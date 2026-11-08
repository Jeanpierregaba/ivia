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

/// Période de l'onglet Gains (D18).
enum EarningsPeriod { week, month }

/// Gains d'un jour de Lomé.
class DayTotals {
  const DayTotals(this.day, this.totals);
  final DateTime day;
  final Totals totals;
}

/// Résumé d'une période : total, barres, variation, jours livrés.
class PeriodSummary {
  const PeriodSummary({
    required this.from,
    required this.to,
    required this.totals,
    required this.bars,
    required this.barLabels,
    required this.barNames,
    required this.changePercent,
    required this.days,
  });

  /// Premier jour et dernier jour (inclus) de la période entière.
  final DateTime from, to;
  final Totals totals;

  /// Gains par jour (semaine) ou par tranche de 7 jours (mois).
  final List<int> bars;

  /// « L », « M »… ou « 1-7 », « 8-14 »… ; [barNames] : pour la lecture
  /// d'écran (« lundi », « du 1 au 7 »).
  final List<String> barLabels, barNames;

  /// Variation par rapport au même nombre de jours de la période
  /// précédente ; `null` si elle n'a aucune livraison.
  final int? changePercent;

  /// Jours avec au moins une livraison, du plus récent au plus ancien.
  final List<DayTotals> days;

  /// Barre la plus haute (mise en avant) ; `null` : aucune livraison.
  int? get best {
    var best = -1, max = 0;
    for (final (i, v) in bars.indexed) {
      if (v > max) (best, max) = (i, v);
    }
    return best < 0 ? null : best;
  }
}

const _weekLetters = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];
const weekdayNames = [
  'lundi',
  'mardi',
  'mercredi',
  'jeudi',
  'vendredi',
  'samedi',
  'dimanche',
];
const monthNames = [
  'janvier',
  'février',
  'mars',
  'avril',
  'mai',
  'juin',
  'juillet',
  'août',
  'septembre',
  'octobre',
  'novembre',
  'décembre',
];

/// « 1er », « 2 »…
String dayNumber(int day) => day == 1 ? '1er' : '$day';

DateTime _next(DateTime day) => day.add(const Duration(days: 1));

/// Semaine (lundi à dimanche) ou mois en cours, au jour de Lomé de [now].
PeriodSummary summarize(
  List<WorkMission> missions,
  EarningsPeriod period,
  DateTime now,
) {
  final today = lomeDay(now);
  final DateTime from, to, prevFrom, prevTo;
  final bars = <int>[];
  final labels = <String>[], names = <String>[];
  if (period == EarningsPeriod.week) {
    from = weekStart(now);
    to = from.add(const Duration(days: 6));
    for (var i = 0; i < 7; i++) {
      final day = from.add(Duration(days: i));
      bars.add(totalsBetween(missions, day, _next(day)).earnedXof);
      labels.add(_weekLetters[i]);
      names.add(weekdayNames[i]);
    }
    prevFrom = from.subtract(const Duration(days: 7));
    prevTo = today.subtract(const Duration(days: 7));
  } else {
    from = DateTime.utc(today.year, today.month);
    to = DateTime.utc(today.year, today.month + 1, 0);
    for (var start = 1; start <= to.day; start += 7) {
      final end = start + 6 > to.day ? to.day : start + 6;
      bars.add(
        totalsBetween(
          missions,
          DateTime.utc(today.year, today.month, start),
          DateTime.utc(today.year, today.month, end + 1),
        ).earnedXof,
      );
      labels.add('$start-$end');
      names.add('du ${dayNumber(start)} au $end');
    }
    prevFrom = DateTime.utc(today.year, today.month - 1);
    final prevLast = DateTime.utc(today.year, today.month, 0).day;
    prevTo = DateTime.utc(
      today.year,
      today.month - 1,
      today.day > prevLast ? prevLast : today.day,
    );
  }
  final totals = totalsBetween(missions, from, _next(to));
  final previous = totalsBetween(missions, prevFrom, _next(prevTo));
  final current = totalsBetween(missions, from, _next(today));
  final days = <DayTotals>[];
  for (
    var day = today;
    !day.isBefore(from);
    day = day.subtract(const Duration(days: 1))
  ) {
    final t = totalsBetween(missions, day, _next(day));
    if (t.deliveries > 0) days.add(DayTotals(day, t));
  }
  return PeriodSummary(
    from: from,
    to: to,
    totals: totals,
    bars: bars,
    barLabels: labels,
    barNames: names,
    changePercent: previous.earnedXof == 0
        ? null
        : ((current.earnedXof - previous.earnedXof) * 100 / previous.earnedXof)
              .round(),
    days: days,
  );
}

/// « DU 2 AU 8 NOVEMBRE », « DU 30 OCTOBRE AU 5 NOVEMBRE », « NOVEMBRE 2026 ».
String periodTitle(PeriodSummary s, EarningsPeriod period) {
  if (period == EarningsPeriod.month) {
    return '${monthNames[s.from.month - 1]} ${s.from.year}'.toUpperCase();
  }
  final sameMonth = s.from.month == s.to.month;
  final start = sameMonth
      ? dayNumber(s.from.day)
      : '${dayNumber(s.from.day)} ${monthNames[s.from.month - 1]}';
  return 'du $start au ${dayNumber(s.to.day)} ${monthNames[s.to.month - 1]}'
      .toUpperCase();
}

/// « Jeudi 6 ».
String dayTitle(DateTime day) {
  final name = weekdayNames[day.weekday - 1];
  return '${name[0].toUpperCase()}${name.substring(1)} ${dayNumber(day.day)}';
}

/// « +14 % », « −8 % », « 0 % ».
String changeLabel(int percent) => percent > 0
    ? '+$percent %'
    : percent < 0
    ? '−${-percent} %'
    : '0 %';
