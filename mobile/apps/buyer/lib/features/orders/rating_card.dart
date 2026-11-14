import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Note de la livraison d'une commande (peut-on noter, note donnée).
final orderRatingProvider = FutureProvider.autoDispose
    .family<OrderRating, String>(
      (ref, id) => ref.read(apiClientProvider).orderRating(id),
    );

/// Commandes déjà proposées à la note pendant cette session (la feuille
/// s'ouvre seule une fois).
final _prompted = <String>{};

const _appFeedbackKey = 'ivia.app_feedback_asked';

/// Carte « Comment s'est passée la livraison ? » d'une commande livrée :
/// étoiles qui ouvrent la feuille d'avis ; la feuille s'ouvre seule la
/// première fois. Après une bonne note, l'avis sur l'app est demandé une fois.
class DeliveryRatingCard extends ConsumerStatefulWidget {
  const DeliveryRatingCard({super.key, required this.orderId});

  final String orderId;

  @override
  ConsumerState<DeliveryRatingCard> createState() => _DeliveryRatingCardState();
}

class _DeliveryRatingCardState extends ConsumerState<DeliveryRatingCard> {
  Future<void> _rate() async {
    final client = ref.read(apiClientProvider);
    var stars = 0;
    final ok = await showRatingSheet(
      context,
      title: 'Comment s’est passée la livraison ?',
      subtitle: 'Votre note aide ivia à garder les meilleurs livreurs.',
      leading: const CircleAvatar(
        radius: 30,
        backgroundColor: IviaColors.secondarySoft,
        child: Icon(
          Icons.delivery_dining_rounded,
          color: IviaColors.secondary,
          size: 32,
        ),
      ),
      praiseTags: driverPraiseTags,
      issueTags: driverIssueTags,
      onSubmit: (r) async {
        try {
          await client.rateOrder(
            widget.orderId,
            stars: r.stars,
            tags: r.tags,
            comment: r.comment,
          );
          stars = r.stars;
          return null;
        } on ApiException catch (e) {
          return e.message;
        }
      },
    );
    if (!mounted || !ok) return;
    ref.invalidate(orderRatingProvider(widget.orderId));
    if (stars >= 4) await _askAppFeedback();
  }

  /// « Et ivia, vous aimez ? » : demandé une seule fois.
  Future<void> _askAppFeedback() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_appFeedbackKey) ?? false) return;
    await prefs.setBool(_appFeedbackKey, true);
    if (!mounted) return;
    final client = ref.read(apiClientProvider);
    await showRatingSheet(
      context,
      title: 'Et ivia, vous aimez ?',
      subtitle: 'Dites-nous ce que vous pensez de l’application.',
      leading: const IviaLogoTile(size: 56),
      commentHint: 'Une idée, une remarque ? (facultatif)',
      onSubmit: (r) async {
        try {
          await client.sendAppFeedback(
            app: 'buyer',
            stars: r.stars,
            comment: r.comment,
          );
          return null;
        } on ApiException catch (e) {
          return e.message;
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final state = ref.watch(orderRatingProvider(widget.orderId)).value;
    if (state == null || (!state.canRate && state.rating == null)) {
      return const SizedBox.shrink();
    }
    if (state.canRate && _prompted.add(widget.orderId)) {
      Future.delayed(const Duration(milliseconds: 700), () {
        if (mounted) unawaited(_rate());
      });
    }
    final given = state.rating;
    return IviaReveal(
      index: 0,
      child: Material(
        color: IviaColors.surface,
        borderRadius: BorderRadius.circular(IviaRadius.large),
        child: InkWell(
          borderRadius: BorderRadius.circular(IviaRadius.large),
          onTap: given == null ? _rate : null,
          child: Padding(
            padding: const EdgeInsets.all(IviaSpacing.md),
            child: Row(
              children: [
                const Icon(
                  Icons.delivery_dining_rounded,
                  color: IviaColors.secondary,
                ),
                const SizedBox(width: IviaSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        given == null
                            ? 'Notez votre livraison'
                            : 'Merci pour votre note !',
                        style: t.titleSmall,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          for (var i = 1; i <= 5; i++)
                            Icon(
                              i <= (given?.stars ?? 0)
                                  ? Icons.star_rounded
                                  : Icons.star_outline_rounded,
                              size: 22,
                              color: i <= (given?.stars ?? 0)
                                  ? const Color(0xFFF5B301)
                                  : IviaColors.textMuted,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (given == null)
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: IviaColors.textMuted,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
