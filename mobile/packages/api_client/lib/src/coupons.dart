part of 'client.dart';

// Codes promo (spec 034) : « Mes coupons » de l'acheteur, codes de la boutique du marchand.

/// Code promo : pourcentage (avec plafond éventuel) ou montant fixe.
class PromoCode {
  PromoCode.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      code = j['code'] as String,
      shopId = j['shop_id'] as String?,
      shopName = j['shop_name'] as String? ?? '',
      fundedBy = j['funded_by'] as String? ?? 'shop',
      kind = j['kind'] as String? ?? 'fixed',
      value = _i(j['value']),
      maxDiscountXof = (j['max_discount_xof'] as num?)?.toInt(),
      minOrderXof = _i(j['min_order_xof']),
      startsAt = _d(j['starts_at']),
      endsAt = _d(j['ends_at']),
      maxUses = (j['max_uses'] as num?)?.toInt(),
      maxUsesPerUser = _i(j['max_uses_per_user']),
      visibility = j['visibility'] as String? ?? 'public',
      welcome = j['welcome'] as bool? ?? false,
      status = j['status'] as String? ?? 'active',
      state = j['state'] as String? ?? 'active',
      suspensionReason = j['suspension_reason'] as String? ?? '',
      usedCount = _i(j['used_count']),
      discountGivenXof = _i(j['discount_given_xof']);

  final String id, code, shopName, fundedBy, kind, visibility, status, state;
  final String suspensionReason;
  final String? shopId;
  final int value, minOrderXof, maxUsesPerUser, usedCount, discountGivenXof;
  final int? maxDiscountXof, maxUses;
  final DateTime? startsAt, endsAt;
  final bool welcome;

  bool get isPercent => kind == 'percent';

  /// Code suspendu par ivia (motif donné) : le marchand ne peut pas le reprendre.
  bool get suspendedByIvia =>
      status == 'suspended' && suspensionReason.isNotEmpty;
}

extension CouponsApi on IviaApiClient {
  /// Codes utilisables par l'acheteur : publics en cours et coupons réservés.
  Future<List<PromoCode>> myCoupons() async {
    final j = await _send('GET', '/v1/me/coupons');
    return [for (final i in _list(j['items'])) PromoCode.fromJson(i)];
  }

  /// Codes d'une boutique du marchand.
  Future<List<PromoCode>> sellerPromoCodes(String shopId) async {
    final j = await _send(
      'GET',
      '/v1/seller/shops/$shopId/promo-codes',
      query: {'limit': '100'},
    );
    return [for (final i in _list(j['items'])) PromoCode.fromJson(i)];
  }

  /// Crée un code (à la charge de la boutique), actif dès sa création.
  /// [code] vide : code généré.
  Future<PromoCode> createSellerPromoCode(
    String shopId, {
    String code = '',
    required String kind,
    required int value,
    int? maxDiscountXof,
    int minOrderXof = 0,
    DateTime? startsAt,
    DateTime? endsAt,
    int? maxUses,
    int maxUsesPerUser = 1,
    String visibility = 'public',
  }) async => PromoCode.fromJson(
    await _send(
      'POST',
      '/v1/seller/shops/$shopId/promo-codes',
      data: {
        'code': code,
        'kind': kind,
        'value': value,
        'max_discount_xof': ?maxDiscountXof,
        'min_order_xof': minOrderXof,
        'starts_at': ?startsAt?.toUtc().toIso8601String(),
        'ends_at': ?endsAt?.toUtc().toIso8601String(),
        'max_uses': ?maxUses,
        'max_uses_per_user': maxUsesPerUser,
        'visibility': visibility,
      },
    ),
  );

  /// `suspend`, `resume` ou `end`.
  Future<PromoCode> sellerPromoCodeAction(String id, String action) async =>
      PromoCode.fromJson(
        await _send('POST', '/v1/seller/promo-codes/$id/$action'),
      );
}
