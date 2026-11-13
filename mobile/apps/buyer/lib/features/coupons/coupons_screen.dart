import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../app/router.dart';
import '../checkout/promo_code_field.dart';
import '../pharmacy/med_ui.dart';

/// Codes utilisables par le client : publics en cours et coupons réservés.
final myCouponsProvider = FutureProvider.autoDispose<List<PromoCode>>(
  (ref) => ref.read(apiClientProvider).myCoupons(),
);

/// Profil › « Mes coupons » : un ticket par code, avec la réduction, la
/// boutique, le minimum et la date de fin. « Utiliser » ouvre la boutique et
/// le code est proposé tout seul à la commande.
class CouponsScreen extends ConsumerWidget {
  const CouponsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coupons = ref.watch(myCouponsProvider);
    final t = Theme.of(context).textTheme;
    return MedScaffold(
      top: const MedTopBar(title: 'Mes coupons'),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(myCouponsProvider.future),
        child: switch (coupons) {
          AsyncData(:final value) when value.isEmpty => ListView(
            padding: const EdgeInsets.all(IviaSpacing.xxl),
            children: [
              const SizedBox(height: IviaSpacing.xxl),
              const Icon(
                Icons.local_offer_outlined,
                size: 56,
                color: IviaColors.textMuted,
              ),
              const SizedBox(height: IviaSpacing.md),
              Text(
                'Aucun coupon pour le moment',
                textAlign: TextAlign.center,
                style: t.titleMedium,
              ),
              const SizedBox(height: IviaSpacing.xs),
              Text(
                'Les codes promo des boutiques et vos cadeaux ivia '
                's’afficheront ici.',
                textAlign: TextAlign.center,
                style: t.bodyMedium,
              ),
            ],
          ),
          AsyncData(:final value) => ListView.separated(
            padding: const EdgeInsets.fromLTRB(
              IviaSpacing.screen,
              IviaSpacing.md,
              IviaSpacing.screen,
              IviaSpacing.xxl,
            ),
            itemCount: value.length,
            separatorBuilder: (_, _) => const SizedBox(height: IviaSpacing.md),
            itemBuilder: (context, i) => IviaReveal(
              index: i,
              child: _CouponTicket(coupon: value[i]),
            ),
          ),
          AsyncError() => ListView(
            padding: const EdgeInsets.all(IviaSpacing.xxl),
            children: [
              Text(
                'Impossible de charger vos coupons.',
                textAlign: TextAlign.center,
                style: t.bodyLarge,
              ),
              const SizedBox(height: IviaSpacing.md),
              Center(
                child: TextButton(
                  onPressed: () => ref.invalidate(myCouponsProvider),
                  child: const Text('Réessayer'),
                ),
              ),
            ],
          ),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }
}

class _CouponTicket extends ConsumerWidget {
  const _CouponTicket({required this.coupon});

  final PromoCode coupon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final c = coupon;
    final color = c.welcome ? IviaColors.primary : IviaColors.secondary;
    final value = c.isPercent ? '-${c.value} %' : '-${formatXof(c.value)}';
    final details = [
      if (c.isPercent && c.maxDiscountXof != null)
        'Jusqu’à ${formatXof(c.maxDiscountXof!)}',
      if (c.minOrderXof > 0) 'Dès ${formatXof(c.minOrderXof)} d’achats',
      if (c.endsAt != null) 'Jusqu’au ${shortDate(c.endsAt!.toLocal())}',
    ];
    return Material(
      color: IviaColors.surface,
      borderRadius: BorderRadius.circular(IviaRadius.large),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 104,
              padding: const EdgeInsets.all(IviaSpacing.sm),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [color, Color.lerp(color, Colors.black, 0.25)!],
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    c.welcome
                        ? Icons.card_giftcard_rounded
                        : Icons.local_offer_rounded,
                    color: Colors.white,
                  ),
                  const SizedBox(height: IviaSpacing.xs),
                  FittedBox(
                    child: Text(
                      value,
                      style: t.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  IviaSpacing.md,
                  IviaSpacing.md,
                  IviaSpacing.sm,
                  IviaSpacing.sm,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.welcome ? 'Cadeau de bienvenue' : c.shopName,
                      style: t.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: c.code));
                        showMessage(
                          ScaffoldMessenger.of(context),
                          'Code ${c.code} copié.',
                        );
                      },
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            c.code,
                            style: t.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                              color: color,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(Icons.copy_rounded, size: 14, color: color),
                        ],
                      ),
                    ),
                    if (details.isNotEmpty) ...[
                      const SizedBox(height: IviaSpacing.xs),
                      Text(details.join(' · '), style: t.bodySmall),
                    ],
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () {
                          ref.read(pendingCouponProvider).set(c.code);
                          final shop = c.shopId;
                          context.go(
                            shop == null ? Routes.home : Routes.shop(shop),
                          );
                        },
                        child: const Text('Utiliser'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
