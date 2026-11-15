import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:url_launcher/url_launcher.dart';

// Publicité dans l'app acheteur (IVI et AWU-IVI d'abord) : fil lu une fois par
// session, visuels qui tournent au hasard, produits mis en avant qui reviennent
// dans les listes, statistiques anonymes. Réglages fixés par l'admin.

/// Fil publicitaire de la session. Erreur ou route absente : fil vide (la
/// publicité ne bloque jamais l'app).
final promoFeedProvider = FutureProvider<PromoFeed>((ref) async {
  try {
    return await ref.read(apiClientProvider).promoFeed();
  } on Exception {
    return const PromoFeed();
  }
}, retry: (_, _) => null);

/// Ouvre un lien dans le navigateur du téléphone (site officiel). `false` :
/// aucun navigateur n'a pu l'ouvrir.
typedef LinkOpener = Future<bool> Function(Uri uri);

final linkOpenerProvider = Provider<LinkOpener>(
  (ref) =>
      (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);

/// Hasard de la rotation (remplaçable dans les tests).
final promoRandomProvider = Provider<Random>((ref) => Random());

/// Statistiques publicitaires : regroupées puis envoyées par lots, sous un
/// identifiant de session tiré au hasard (aucun lien avec le compte).
class PromoTracker {
  PromoTracker(this._client, Random random)
    : sessionId = base64Url
          .encode([for (var i = 0; i < 18; i++) random.nextInt(256)])
          .replaceAll('=', '');

  final IviaApiClient _client;
  final String sessionId;
  final _pending = <PromoEvent>[];
  Timer? _timer;

  /// Produits ouverts ou commandés depuis une publicité (commande attribuée).
  final _fromAds = <String>{};

  static const _batch = 20;
  static const _delay = Duration(seconds: 10);

  void track(
    String kind, {
    PromoVisual? visual,
    String? productId,
    PromoPlacement? placement,
  }) {
    final product = productId ?? visual?.product?.id;
    if (product != null && kind.startsWith('click_')) _fromAds.add(product);
    _pending.add(
      PromoEvent(
        kind,
        visualId: visual?.id,
        productId: product,
        placement: placement,
      ),
    );
    if (_pending.length >= _batch) {
      unawaited(flush());
    } else {
      _timer ??= Timer(_delay, () => unawaited(flush()));
    }
  }

  /// Commande passée : « commande après clic » pour chaque produit venu d'une
  /// publicité.
  void orderPlaced(Iterable<String> productIds) {
    for (final id in productIds.where(_fromAds.contains)) {
      track('order', productId: id);
      _fromAds.remove(id);
    }
  }

  Future<void> flush() async {
    _timer?.cancel();
    _timer = null;
    if (_pending.isEmpty) return;
    final events = List.of(_pending.take(50));
    _pending.removeRange(0, events.length);
    try {
      await _client.sendPromoEvents(events, sessionId: sessionId);
    } on Exception {
      // Statistiques perdues plutôt que de gêner l'acheteur.
    }
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}

final promoTrackerProvider = Provider<PromoTracker>((ref) {
  final tracker = PromoTracker(
    ref.read(apiClientProvider),
    ref.read(promoRandomProvider),
  );
  ref.onDispose(tracker.dispose);
  return tracker;
});

/// Choisit un visuel selon la rotation fixée par l'admin, en évitant de
/// répéter [lastId] quand un autre est possible.
PromoVisual? pickVisual(
  List<PromoVisual> candidates,
  PromoRotation rotation,
  Random random, {
  String? lastId,
}) {
  if (candidates.isEmpty) return null;
  final pool = candidates.length > 1
      ? [
          for (final v in candidates)
            if (v.id != lastId) v,
        ]
      : candidates;
  switch (rotation) {
    case PromoRotation.priority:
      final sorted = List.of(pool)
        ..sort((a, b) => b.priority.compareTo(a.priority));
      return sorted.first;
    case PromoRotation.random:
      return pool[random.nextInt(pool.length)];
    case PromoRotation.weighted:
      final total = pool.fold(0, (s, v) => s + max(1, v.weight));
      var n = random.nextInt(total);
      for (final v in pool) {
        n -= max(1, v.weight);
        if (n < 0) return v;
      }
      return pool.last;
  }
}

/// Produits mis en avant, en cartes de liste.
List<ProductHit> featuredHits(PromoFeed feed) => [
  for (final p in feed.featured)
    if (p.available) ProductHit.fromProduct(p, shopName: 'Produit vedette'),
];

/// Glisse un produit mis en avant toutes les [every] cartes de [items]
/// (chacun une fois par liste), en commençant par [start] dans la liste des
/// vedettes : les produits IVI reviennent pendant toute la navigation.
List<ProductHit> interleaveFeatured(
  List<ProductHit> items,
  List<ProductHit> featured, {
  required int every,
  int start = 0,
}) {
  final present = {for (final i in items) i.id};
  final extra = [
    for (final f in featured)
      if (!present.contains(f.id)) f,
  ];
  if (extra.isEmpty || every < 2) return items;
  final out = <ProductHit>[];
  var k = start;
  for (var i = 0; i < items.length; i++) {
    if (i % every == 0 && k - start < extra.length) {
      out.add(extra[k++ % extra.length]);
    }
    out.add(items[i]);
  }
  return out;
}

/// [items] avec les produits mis en avant glissés selon les réglages
/// (publicité coupée : [items] tels quels).
List<ProductHit> withFeatured(WidgetRef ref, List<ProductHit> items) {
  final feed = ref.watch(promoFeedProvider).value;
  if (feed == null ||
      !feed.settings.enabled ||
      !feed.settings.bannersEnabled ||
      items.isEmpty) {
    return items;
  }
  return interleaveFeatured(
    items,
    featuredHits(feed),
    every: feed.settings.feedEvery,
  );
}
