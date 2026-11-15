part of 'client.dart';

// Tableau de bord du marchand (spec 042) : chiffres tirés des commandes payées.

/// Résumé d'une période.
class StatsTotals {
  StatsTotals.fromJson(Map<String, dynamic> j)
    : orders = _i(j['orders']),
      salesXof = _i(j['sales_xof']),
      avgBasketXof = _i(j['avg_basket_xof']),
      deliveries = _i(j['deliveries']),
      cancelled = _i(j['cancelled']),
      buyers = _i(j['buyers']);

  final int orders, salesXof, avgBasketXof, deliveries, cancelled, buyers;
}

/// Une journée de la période.
class StatsDay {
  StatsDay.fromJson(Map<String, dynamic> j)
    : date = DateTime.parse(j['date'] as String),
      orders = _i(j['orders']),
      salesXof = _i(j['sales_xof']);

  final DateTime date;
  final int orders, salesXof;
}

/// Un des produits les plus vendus.
class StatsProduct {
  StatsProduct.fromJson(Map<String, dynamic> j)
    : productId = j['product_id'] as String,
      name = j['name'] as String? ?? '',
      quantity = _i(j['quantity']),
      salesXof = _i(j['sales_xof']);

  final String productId, name;
  final int quantity, salesXof;
}

/// Tableau de bord d'une boutique.
class SellerStats {
  SellerStats.fromJson(Map<String, dynamic> j)
    : days = _i(j['days']),
      series = [for (final d in _list(j['series'])) StatsDay.fromJson(d)],
      totals = StatsTotals.fromJson(j['totals'] as Map<String, dynamic>),
      previous = StatsTotals.fromJson(j['previous'] as Map<String, dynamic>),
      hours = [for (final h in (j['hours'] as List? ?? const [])) _i(h)],
      topProducts = [
        for (final p in _list(j['top_products'])) StatsProduct.fromJson(p),
      ];

  final int days;
  final List<StatsDay> series;
  final StatsTotals totals, previous;

  /// Commandes par heure (0 h à 23 h).
  final List<int> hours;
  final List<StatsProduct> topProducts;
}

extension SellerStatsApi on IviaApiClient {
  /// Tableau de bord sur [days] jours (7 ou 30), aujourd'hui compris.
  Future<SellerStats> sellerStats(String shopId, {int days = 7}) async =>
      SellerStats.fromJson(
        await _send(
          'GET',
          '/v1/seller/shops/$shopId/stats',
          query: {'days': '$days'},
        ),
      );
}
