part of 'client.dart';

// Avis (spec 035) : note du livreur après une livraison, avis sur l'application.

/// Note d'une livraison.
class DeliveryRating {
  DeliveryRating.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      stars = _i(j['stars']),
      tags = [for (final t in j['tags'] as List? ?? const []) t as String],
      comment = j['comment'] as String? ?? '',
      createdAt = _d(j['created_at']);

  final String id, comment;
  final int stars;
  final List<String> tags;
  final DateTime? createdAt;
}

/// État de la note d'une commande : peut-on noter, note déjà donnée.
class OrderRating {
  OrderRating.fromJson(Map<String, dynamic> j)
    : canRate = j['can_rate'] as bool? ?? false,
      rating = switch (j['rating']) {
        final Map<String, dynamic> r => DeliveryRating.fromJson(r),
        _ => null,
      };

  final bool canRate;
  final DeliveryRating? rating;
}

extension RatingsApi on IviaApiClient {
  /// Note de la livraison d'une commande de l'acheteur.
  Future<OrderRating> orderRating(String orderId) async =>
      OrderRating.fromJson(await _send('GET', '/v1/orders/$orderId/rating'));

  /// Note le livreur d'une commande livrée (une fois).
  Future<DeliveryRating> rateOrder(
    String orderId, {
    required int stars,
    List<String> tags = const [],
    String comment = '',
  }) async => DeliveryRating.fromJson(
    await _send(
      'POST',
      '/v1/orders/$orderId/rating',
      data: {'stars': stars, 'tags': tags, 'comment': comment},
    ),
  );

  /// Note du livreur par le marchand.
  Future<OrderRating> sellerDriverRating(String orderId) async =>
      OrderRating.fromJson(
        await _send('GET', '/v1/seller/orders/$orderId/driver-rating'),
      );

  Future<DeliveryRating> rateDriverAsSeller(
    String orderId, {
    required int stars,
    List<String> tags = const [],
    String comment = '',
  }) async => DeliveryRating.fromJson(
    await _send(
      'POST',
      '/v1/seller/orders/$orderId/driver-rating',
      data: {'stars': stars, 'tags': tags, 'comment': comment},
    ),
  );

  /// Avis sur l'application (`buyer`, `seller`, `driver`, `pharmacy`).
  Future<void> sendAppFeedback({
    required String app,
    required int stars,
    String comment = '',
  }) => _send(
    'POST',
    '/v1/me/app-feedback',
    data: {'app': app, 'stars': stars, 'comment': comment},
  );

  /// Note moyenne du livreur connecté.
  Future<({double average, int ratings})> myDriverRating() async {
    final j = await _send('GET', '/v1/driver/rating');
    return (
      average: (j['average'] as num?)?.toDouble() ?? 0,
      ratings: _i(j['ratings']),
    );
  }
}
