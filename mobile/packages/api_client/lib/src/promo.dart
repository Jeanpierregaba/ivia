import 'models.dart';

/// Réglages de diffusion de la publicité (schéma `PromoSettings`) : l'app
/// applique délai, intervalle, plafond par session et rotation. Par défaut
/// (fil illisible ou absent) : rien n'est diffusé.
class PromoSettings {
  const PromoSettings({
    this.enabled = false,
    this.bannersEnabled = false,
    this.modalEnabled = false,
    this.interstitialEnabled = false,
    this.firstDelay = const Duration(seconds: 20),
    this.minInterval = const Duration(seconds: 90),
    this.maxPerSession = 5,
    this.feedEvery = 6,
    this.rotation = PromoRotation.weighted,
    this.officialUrl = '',
  });

  factory PromoSettings.fromJson(Map<String, dynamic> json) => PromoSettings(
    enabled: json['enabled'] as bool? ?? false,
    bannersEnabled: json['banners_enabled'] as bool? ?? false,
    modalEnabled: json['modal_enabled'] as bool? ?? false,
    interstitialEnabled: json['interstitial_enabled'] as bool? ?? false,
    firstDelay: Duration(seconds: json['first_delay_seconds'] as int? ?? 20),
    minInterval: Duration(seconds: json['min_interval_seconds'] as int? ?? 90),
    maxPerSession: json['max_per_session'] as int? ?? 5,
    feedEvery: json['feed_every'] as int? ?? 6,
    rotation: PromoRotation.parse(json['rotation'] as String? ?? ''),
    officialUrl: json['official_url'] as String? ?? '',
  );

  final bool enabled;
  final bool bannersEnabled;
  final bool modalEnabled;
  final bool interstitialEnabled;
  final Duration firstDelay;
  final Duration minInterval;
  final int maxPerSession;

  /// Un produit mis en avant revient toutes les [feedEvery] cartes.
  final int feedEvery;
  final PromoRotation rotation;

  /// Site officiel de la marque (« Visiter le site officiel »).
  final String officialUrl;
}

enum PromoRotation {
  weighted('weighted'),
  random('random'),
  priority('priority');

  const PromoRotation(this.code);

  final String code;

  static PromoRotation parse(String code) =>
      values.where((r) => r.code == code).firstOrNull ?? weighted;
}

/// Emplacement d'un visuel dans l'app.
enum PromoPlacement {
  homeHero('home_hero'),
  homeFeed('home_feed'),
  catalogFeed('catalog_feed'),
  modal('modal'),
  interstitial('interstitial'),
  splash('splash');

  const PromoPlacement(this.code);

  final String code;

  static PromoPlacement? parse(String code) =>
      values.where((p) => p.code == code).firstOrNull;
}

/// Visuel publicitaire du fil (schéma `PromoFeedVisual`).
class PromoVisual {
  const PromoVisual({
    required this.id,
    required this.title,
    required this.imageUrl,
    required this.placements,
    this.kind = 'banner',
    this.subtitle = '',
    this.body = '',
    this.ctaLabel = '',
    this.externalUrl = '',
    this.priority = 0,
    this.weight = 1,
    this.product,
  });

  factory PromoVisual.fromJson(Map<String, dynamic> json) => PromoVisual(
    id: json['id'] as String,
    kind: json['kind'] as String? ?? 'banner',
    title: json['title'] as String? ?? '',
    subtitle: json['subtitle'] as String? ?? '',
    body: json['body'] as String? ?? '',
    imageUrl: json['image_url'] as String? ?? '',
    ctaLabel: json['cta_label'] as String? ?? '',
    externalUrl: json['external_url'] as String? ?? '',
    placements: [
      for (final p in json['placements'] as List? ?? const [])
        ?PromoPlacement.parse('$p'),
    ],
    priority: json['priority'] as int? ?? 0,
    weight: json['weight'] as int? ?? 1,
    product: switch (json['product']) {
      final Map<String, dynamic> p => Product.fromJson(p),
      _ => null,
    },
  );

  final String id;

  /// banner, modal, interstitial, welcome, monthly, poster.
  final String kind;
  final String title;
  final String subtitle;
  final String body;
  final String imageUrl;
  final String ctaLabel;
  final String externalUrl;
  final List<PromoPlacement> placements;
  final int priority;
  final int weight;

  /// Produit commandable depuis le visuel ; `null` : aucun ou plus en vente.
  final Product? product;
}

/// Fil publicitaire de l'app (schéma `PromoFeed`).
class PromoFeed {
  const PromoFeed({
    this.settings = const PromoSettings(),
    this.visuals = const [],
    this.featured = const [],
  });

  factory PromoFeed.fromJson(Map<String, dynamic> json) => PromoFeed(
    settings: PromoSettings.fromJson(
      json['settings'] as Map<String, dynamic>? ?? const {},
    ),
    visuals: [
      for (final v in json['visuals'] as List? ?? const [])
        PromoVisual.fromJson(v as Map<String, dynamic>),
    ],
    featured: [
      for (final p in json['featured'] as List? ?? const [])
        Product.fromJson(p as Map<String, dynamic>),
    ],
  );

  final PromoSettings settings;
  final List<PromoVisual> visuals;

  /// Produits mis en avant en vente, par rang.
  final List<Product> featured;

  /// Visuels d'un emplacement.
  List<PromoVisual> at(PromoPlacement placement) => [
    for (final v in visuals)
      if (v.placements.contains(placement)) v,
  ];
}

/// Événement publicitaire anonyme (schéma `PromoEvent`).
class PromoEvent {
  const PromoEvent(this.kind, {this.visualId, this.productId, this.placement});

  /// impression, dismiss, click_order, click_product, click_site, order.
  final String kind;
  final String? visualId;
  final String? productId;
  final PromoPlacement? placement;

  Map<String, dynamic> toJson() => {
    'kind': kind,
    'visual_id': ?visualId,
    'product_id': ?productId,
    'placement': ?placement?.code,
  };
}
