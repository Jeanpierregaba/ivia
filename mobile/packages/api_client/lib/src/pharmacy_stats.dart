part of 'client.dart';

// Tableau de bord de la pharmacie (spec 042).

/// Résumé d'une période.
class PharmacyStatsTotals {
  PharmacyStatsTotals.fromJson(Map<String, dynamic> j)
    : received = _i(j['received']),
      responded = _i(j['responded']),
      responseRate = _i(j['response_rate']),
      avgResponseMin = _i(j['avg_response_min']),
      reservations = _i(j['reservations']),
      completed = _i(j['completed']),
      salesXof = _i(j['sales_xof']);

  final int received, responded, responseRate, avgResponseMin;
  final int reservations, completed, salesXof;
}

/// Une journée de la période.
class PharmacyStatsDay {
  PharmacyStatsDay.fromJson(Map<String, dynamic> j)
    : date = DateTime.parse(j['date'] as String),
      received = _i(j['received']),
      responded = _i(j['responded']),
      reservations = _i(j['reservations']),
      salesXof = _i(j['sales_xof']);

  final DateTime date;
  final int received, responded, reservations, salesXof;
}

/// Tableau de bord sur 7 ou 30 jours.
class PharmacyStats {
  PharmacyStats.fromJson(Map<String, dynamic> j)
    : days = _i(j['days']),
      series = [
        for (final d in _list(j['series'])) PharmacyStatsDay.fromJson(d),
      ],
      totals = PharmacyStatsTotals.fromJson(
        j['totals'] as Map<String, dynamic>,
      ),
      previous = PharmacyStatsTotals.fromJson(
        j['previous'] as Map<String, dynamic>,
      ),
      hours = [for (final h in (j['hours'] as List? ?? const [])) _i(h)],
      topMedicines = [
        for (final m in _list(j['top_medicines']))
          (
            name: m['name'] as String? ?? '',
            responses: _i(m['responses']),
            reservations: _i(m['reservations']),
          ),
      ];

  final int days;
  final List<PharmacyStatsDay> series;
  final PharmacyStatsTotals totals, previous;
  final List<int> hours;
  final List<({String name, int responses, int reservations})> topMedicines;
}

extension PharmacyStatsApi on IviaApiClient {
  Future<PharmacyStats> pharmacyStats({int days = 7}) async =>
      PharmacyStats.fromJson(
        await _send('GET', '/v1/pharmacy/stats', query: {'days': '$days'}),
      );
}
