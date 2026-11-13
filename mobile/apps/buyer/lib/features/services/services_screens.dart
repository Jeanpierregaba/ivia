import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/buyer_area.dart';
import '../../app/catalog_data.dart';
import '../../app/router.dart';
import '../home/shop_card.dart';
import '../pharmacy/med_ui.dart';

/// Restaurants : boutiques de la catégorie « Restauration », les plus proches d'abord.
final restaurantsProvider = FutureProvider.autoDispose<List<ShopHit>>((
  ref,
) async {
  final api = ref.read(apiClientProvider);
  final cats = await api.shopCategories();
  final resto = cats.where((c) => c.name == 'Restauration').firstOrNull;
  if (resto == null) return const [];
  final area = ref.watch(buyerAreaProvider);
  final base = area.apply(const SearchQuery(sort: SearchSort.distance));
  final page = await api.searchShops(
    SearchQuery(
      point: base.point,
      neighborhoodId: base.point == null ? null : base.neighborhoodId,
      shopCategoryId: resto.id,
      sort: base.point == null ? SearchSort.relevance : SearchSort.distance,
    ),
    limit: 30,
  );
  return page.items;
});

/// Biens immobiliers, filtrés par vente ou location.
final propertiesProvider = FutureProvider.autoDispose
    .family<List<Property>, String?>((ref, kind) {
      final area = ref.watch(buyerAreaProvider);
      return ref
          .read(apiClientProvider)
          .properties(near: area.point, kind: kind, limit: 30);
    });

final propertyProvider = FutureProvider.autoDispose.family<Property, String>(
  (ref, id) => ref.read(apiClientProvider).property(id),
);

String propertyPrice(Property p) =>
    p.forRent ? '${formatXof(p.priceXof)} / mois' : formatXof(p.priceXof);

/// Liste des restaurants.
class RestaurantsScreen extends ConsumerWidget {
  const RestaurantsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(restaurantsProvider);
    return MedScaffold(
      top: const MedTopBar(title: 'Restaurants'),
      body: items.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) =>
            const Center(child: Text('Restaurants indisponibles.')),
        data: (list) => list.isEmpty
            ? const Center(
                child: Text('Aucun restaurant autour de vous pour l\'instant.'),
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(
                  IviaSpacing.screen,
                  0,
                  IviaSpacing.screen,
                  IviaSpacing.xxl,
                ),
                itemCount: list.length,
                separatorBuilder: (_, _) => const SizedBox(height: 14),
                itemBuilder: (context, i) {
                  final s = list[i];
                  return SizedBox(
                    height: 230,
                    child: ShopCard(
                      name: s.name,
                      logoUrl: s.logoUrl,
                      place: neighborhoodName(ref, s.neighborhoodId),
                      distance: s.distanceM == null
                          ? null
                          : formatDistance(s.distanceM!),
                      acceptingOrders: s.acceptingOrders,
                      onTap: () => context.push(Routes.shop(s.id)),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

/// Carte d'un bien (A01 : photo, « À vendre » / « À louer », favori, prix).
class PropertyCard extends StatelessWidget {
  const PropertyCard({super.key, required this.property, this.width});
  final Property property;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final p = property;
    return SizedBox(
      width: width,
      child: MedCard(
        padding: const EdgeInsets.all(10),
        onTap: () => context.push(Routes.property(p.id)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1.5,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  MedPhoto(url: p.photoUrls.firstOrNull, radius: 20),
                  Positioned(
                    left: 10,
                    top: 10,
                    child: MedPill(
                      p.forRent ? 'À louer' : 'À vendre',
                      bg: p.forRent ? Med.navy : IviaColors.primary,
                      fg: Colors.white,
                    ),
                  ),
                  const Positioned(
                    right: 10,
                    top: 10,
                    child: CircleAvatar(
                      radius: 18,
                      backgroundColor: Colors.white,
                      child: Icon(
                        Icons.favorite_border,
                        size: 20,
                        color: Med.navy,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 12, 6, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  Text(
                    [
                      p.neighborhood,
                      if (p.bedrooms > 0) '${p.bedrooms} ch.',
                      if (p.surfaceM2 > 0) '${p.surfaceM2} m²',
                    ].join(' · '),
                    style: t.bodyMedium?.copyWith(color: Med.muted),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    propertyPrice(p),
                    style: t.titleMedium?.copyWith(
                      color: IviaColors.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Biens immobiliers : tous, à vendre, à louer.
class PropertiesScreen extends ConsumerStatefulWidget {
  const PropertiesScreen({super.key});

  @override
  ConsumerState<PropertiesScreen> createState() => _PropertiesScreenState();
}

class _PropertiesScreenState extends ConsumerState<PropertiesScreen> {
  String? _kind;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final items = ref.watch(propertiesProvider(_kind));
    return MedScaffold(
      top: const MedTopBar(title: 'Immobilier'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          IviaSpacing.screen,
          0,
          IviaSpacing.screen,
          IviaSpacing.xxl,
        ),
        children: [
          Row(
            children: [
              for (final (i, (label, kind)) in [
                ('Tous', null),
                ('À vendre', 'sale'),
                ('À louer', 'rent'),
              ].indexed) ...[
                if (i > 0) const SizedBox(width: 10),
                ChoiceChip(
                  label: Text(label),
                  selected: _kind == kind,
                  showCheckmark: false,
                  selectedColor: Med.navy,
                  backgroundColor: Colors.white,
                  side: BorderSide.none,
                  shape: const StadiumBorder(),
                  labelStyle: t.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: _kind == kind ? Colors.white : Med.navy,
                  ),
                  onSelected: (_) => setState(() => _kind = kind),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          ...items.when(
            loading: () => [const Center(child: CircularProgressIndicator())],
            error: (_, _) => [const Text('Annonces indisponibles.')],
            data: (list) => [
              if (list.isEmpty) const Text('Aucune annonce pour l\'instant.'),
              for (final p in list)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: PropertyCard(property: p),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Fiche d'un bien : photos, prix, caractéristiques, carte, contact.
class PropertyScreen extends ConsumerWidget {
  const PropertyScreen({super.key, required this.propertyId});
  final String propertyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final async = ref.watch(propertyProvider(propertyId));
    final p = async.value;
    if (p == null) {
      return MedScaffold(
        top: const MedTopBar(title: 'Annonce'),
        body: Center(
          child: async.hasError
              ? const Text('Annonce indisponible.')
              : const CircularProgressIndicator(),
        ),
      );
    }
    final digits = p.contactPhone.replaceAll('+', '');
    return MedScaffold(
      top: MedTopBar(title: p.forRent ? 'À louer' : 'À vendre'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          IviaSpacing.screen,
          0,
          IviaSpacing.screen,
          IviaSpacing.xxl,
        ),
        children: [
          AspectRatio(
            aspectRatio: 1.35,
            child: MedPhoto(url: p.photoUrls.firstOrNull, radius: Med.radius),
          ),
          const SizedBox(height: 16),
          Text(
            p.title,
            style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            [
              p.neighborhood,
              p.addressText,
            ].where((s) => s.isNotEmpty).join(' · '),
            style: t.bodyLarge?.copyWith(color: Med.muted),
          ),
          const SizedBox(height: 10),
          Text(
            propertyPrice(p),
            style: t.headlineSmall?.copyWith(
              color: IviaColors.primary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              for (final (i, (icon, label)) in [
                (
                  Icons.bed_outlined,
                  p.bedrooms > 0
                      ? '${p.bedrooms} chambre${p.bedrooms > 1 ? 's' : ''}'
                      : 'Studio',
                ),
                (
                  Icons.square_foot,
                  p.surfaceM2 > 0 ? '${p.surfaceM2} m²' : '—',
                ),
                (
                  Icons.home_work_outlined,
                  switch (p.propertyType) {
                    'villa' => 'Villa',
                    'apartment' => 'Appartement',
                    'land' => 'Terrain',
                    'office' => 'Bureau',
                    'room' => 'Chambre',
                    _ => 'Maison',
                  },
                ),
              ].indexed) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(
                  child: MedCard(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Column(
                      children: [
                        Icon(icon, color: Med.navy),
                        const SizedBox(height: 4),
                        Text(
                          label,
                          style: t.labelLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          MedCard(child: Text(p.description, style: t.bodyLarge)),
          const SizedBox(height: 16),
          SizedBox(
            height: 180,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Med.radius),
              child: MedMap(
                center: p.location,
                markers: [p.location],
                zoom: 15,
              ),
            ),
          ),
          const SizedBox(height: 16),
          MedCard(
            child: Row(
              children: [
                const MedIconTile(
                  Icons.real_estate_agent_outlined,
                  bg: Med.softRed,
                  fg: IviaColors.primary,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.contactName.isEmpty ? 'Annonceur' : p.contactName,
                        style: t.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        '+228 ${formatTogoPhone(p.contactPhone)}',
                        style: t.bodyMedium?.copyWith(color: Med.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottom: MedBottomButton(
        label: 'Appeler',
        icon: Icons.call_outlined,
        onTap: () => callNumber(p.contactPhone),
        secondary: MedOutlineButton(
          label: 'WhatsApp',
          leading: const IviaWhatsAppLogo(size: 26),
          onTap: () => launchUrl(
            Uri.parse(
              'https://wa.me/$digits?text=${Uri.encodeComponent('Bonjour, je suis intéressé(e) par « ${p.title} » vu sur ivia.')}',
            ),
            mode: LaunchMode.externalApplication,
          ),
        ),
      ),
    );
  }
}
