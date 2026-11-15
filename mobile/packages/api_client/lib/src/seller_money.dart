part of 'client.dart';

// App marchand : relevés de reversement (ventes livrées, commission, net reversé).

class SettlementLine {
  SettlementLine.fromJson(Map<String, dynamic> j)
    : orderId = j['order_id'] as String,
      reference = j['order_reference'] as String? ?? '',
      completedAt = DateTime.parse(j['completed_at'] as String),
      subtotalXof = _i(j['subtotal_xof']),
      commissionXof = _i(j['commission_xof']),
      netXof = _i(j['net_xof']);
  final String orderId, reference;
  final DateTime completedAt;
  final int subtotalXof, commissionXof, netXof;
}

/// Relevé d'une période : `pending` (à reverser) ou `settled` (reversé).
class Settlement {
  Settlement.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      shopName = j['shop_name'] as String? ?? '',
      periodStart = DateTime.parse(j['period_start'] as String),
      periodEnd = DateTime.parse(j['period_end'] as String),
      ordersCount = _i(j['orders_count']),
      grossXof = _i(j['gross_xof']),
      commissionXof = _i(j['commission_xof']),
      netXof = _i(j['net_xof']),
      status = j['status'] as String? ?? 'pending',
      settledAt = _d(j['settled_at']),
      reference = j['settlement_reference'] as String? ?? '',
      note = j['note'] as String? ?? '',
      lines = [for (final l in _list(j['lines'])) SettlementLine.fromJson(l)];

  final String id, shopName, status, reference, note;
  final DateTime periodStart, periodEnd;
  final DateTime? settledAt;
  final int ordersCount, grossXof, commissionXof, netXof;
  final List<SettlementLine> lines;

  bool get settled => status == 'settled';
}

extension SellerMoneyApi on IviaApiClient {
  Future<List<Settlement>> sellerSettlements(String shopId) async {
    final j = await _send(
      'GET',
      '/v1/seller/shops/$shopId/settlements',
      query: {'limit': '50'},
    );
    return [for (final i in _list(j['items'])) Settlement.fromJson(i)];
  }

  Future<Settlement> sellerSettlement(String id) async =>
      Settlement.fromJson(await _send('GET', '/v1/seller/settlements/$id'));
}
