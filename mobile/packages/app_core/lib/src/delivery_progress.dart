import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_ui/ivia_ui.dart';

import 'chat_screen.dart';
import 'ivia_map.dart';
import 'providers.dart';
import 'realtime.dart';

/// Suivi d'une livraison pour le client et le marchand (spec 036) : livreur, étape de la course
/// (mise à jour dès que le livreur glisse), carte avec sa position en direct.
class DeliveryProgress extends ConsumerStatefulWidget {
  const DeliveryProgress({
    super.key,
    required this.orderId,
    required this.app,
    required this.load,
    this.customerView = true,
    this.chat,
  });

  /// Discussion avec le livreur (spec 037) ; `null` : pas de bouton.
  final ChatChannel? chat;

  final String orderId;

  /// App qui écoute les étapes (`buyer`, `seller`).
  final String app;
  final Future<OrderDelivery?> Function(IviaApiClient api, String orderId) load;

  /// Libellés côté client (« vers vous ») ; sinon côté boutique.
  final bool customerView;

  @override
  ConsumerState<DeliveryProgress> createState() => _DeliveryProgressState();
}

class _DeliveryProgressState extends ConsumerState<DeliveryProgress> {
  OrderDelivery? _delivery;
  StreamSubscription<RealtimeEvent>? _sub;
  Timer? _fallback;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
    _sub = ref.read(iviaRealtimeProvider(widget.app)).events.listen((e) {
      if (e.kind == RealtimeEvent.reconnected || e.orderId == widget.orderId) {
        unawaited(_reload());
      }
    });
    // Secours si la connexion temps réel ne passe pas.
    _fallback = Timer.periodic(const Duration(seconds: 30), (_) => _reload());
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    _fallback?.cancel();
    super.dispose();
  }

  Future<void> _reload() async {
    try {
      final d = await widget.load(ref.read(apiClientProvider), widget.orderId);
      if (mounted) setState(() => _delivery = d);
    } on ApiException {
      // Relu au prochain événement.
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _delivery;
    final t = Theme.of(context).textTheme;
    return AnimatedSize(
      duration: IviaMotion.slow,
      curve: IviaMotion.soft,
      alignment: Alignment.topCenter,
      child: d == null
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(bottom: IviaSpacing.lg),
              child: Material(
                color: IviaColors.surface,
                borderRadius: BorderRadius.circular(IviaRadius.large),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (d.step.moving)
                      LiveTrackingMap(orderId: widget.orderId, height: 190),
                    Padding(
                      padding: const EdgeInsets.all(IviaSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 22,
                                backgroundColor: IviaColors.secondarySoft,
                                child: Icon(
                                  d.vehicleType == 'car'
                                      ? Icons.directions_car_rounded
                                      : Icons.two_wheeler_rounded,
                                  color: IviaColors.secondary,
                                ),
                              ),
                              const SizedBox(width: IviaSpacing.md),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      d.driverFirstName.isEmpty
                                          ? 'Votre livreur'
                                          : d.driverFirstName,
                                      style: t.titleSmall,
                                    ),
                                    if (d.vehiclePlate.isNotEmpty)
                                      Text(d.vehiclePlate, style: t.bodySmall),
                                  ],
                                ),
                              ),
                              _LivePill(step: d.step),
                            ],
                          ),
                          const SizedBox(height: IviaSpacing.md),
                          _Steps(
                            step: d.step,
                            customerView: widget.customerView,
                          ),
                          if (widget.chat case final chat?) ...[
                            const SizedBox(height: IviaSpacing.sm),
                            OutlinedButton.icon(
                              onPressed: () => openChat(context, chat),
                              icon: const Icon(
                                Icons.chat_bubble_outline_rounded,
                                size: 18,
                              ),
                              label: Text(
                                d.driverFirstName.isEmpty
                                    ? 'Écrire au livreur'
                                    : 'Écrire à ${d.driverFirstName}',
                              ),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(46),
                                shape: const StadiumBorder(),
                                foregroundColor: const Color(0xFF128C7E),
                                side: const BorderSide(
                                  color: Color(0x55128C7E),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

/// Pastille « En direct » qui respire pendant que le livreur roule.
class _LivePill extends StatefulWidget {
  const _LivePill({required this.step});
  final DeliveryStep step;

  @override
  State<_LivePill> createState() => _LivePillState();
}

class _LivePillState extends State<_LivePill>
    with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final live = widget.step.moving;
    final color = live ? IviaColors.success : IviaColors.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(IviaRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FadeTransition(
            opacity: live
                ? Tween(begin: 0.35, end: 1.0).animate(_pulse)
                : const AlwaysStoppedAnimation(1),
            child: Icon(Icons.circle, size: 8, color: color),
          ),
          const SizedBox(width: 6),
          Text(
            live ? 'En direct' : widget.step.label,
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: color, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

/// Étapes de la course : faites, en cours (mise en avant), à venir.
class _Steps extends StatelessWidget {
  const _Steps({required this.step, required this.customerView});
  final DeliveryStep step;
  final bool customerView;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final steps = [
      (DeliveryStep.accepted, 'Livreur trouvé'),
      (DeliveryStep.headingToShop, 'En route vers la boutique'),
      (DeliveryStep.atShop, 'Arrivé à la boutique'),
      (
        DeliveryStep.headingToCustomer,
        customerView ? 'En route vers vous' : 'En route vers le client',
      ),
      (
        DeliveryStep.atCustomer,
        customerView ? 'Arrivé chez vous' : 'Arrivé chez le client',
      ),
      (DeliveryStep.delivered, 'Livrée'),
    ];
    final current = steps.indexWhere((s) => s.$1 == step);
    return Column(
      children: [
        for (final (i, (_, label)) in steps.indexed)
          AnimatedContainer(
            duration: IviaMotion.slow,
            curve: IviaMotion.soft,
            margin: const EdgeInsets.only(bottom: 2),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: i == current
                  ? IviaColors.secondarySoft
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(IviaRadius.button),
            ),
            child: Row(
              children: [
                AnimatedSwitcher(
                  duration: IviaMotion.medium,
                  child: Icon(
                    i < current ||
                            (i == current && step == DeliveryStep.delivered)
                        ? Icons.check_circle_rounded
                        : i == current
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                    key: ValueKey('$i-${i <= current}'),
                    size: 20,
                    color: i <= current
                        ? IviaColors.secondary
                        : IviaColors.border,
                  ),
                ),
                const SizedBox(width: IviaSpacing.sm),
                Expanded(
                  child: Text(
                    label,
                    style: (i == current ? t.titleSmall : t.bodyMedium)
                        ?.copyWith(
                          color: i <= current
                              ? IviaColors.text
                              : IviaColors.textMuted,
                        ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
