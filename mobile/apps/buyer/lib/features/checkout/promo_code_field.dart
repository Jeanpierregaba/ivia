import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

/// Code choisi dans « Mes coupons » (« Utiliser ») : proposé tout seul à la
/// prochaine commande. Simple boîte, lue une fois par l'écran Commande.
final pendingCouponProvider = Provider<PendingCoupon>((ref) => PendingCoupon());

class PendingCoupon {
  String? _code;

  void set(String? code) => _code = code;

  /// Lit le code et l'oublie (une seule commande).
  String? take() {
    final c = _code;
    _code = null;
    return c;
  }
}

/// Champ « Code promo » de l'écran Commande : saisie, « Appliquer », puis le
/// code appliqué avec la réduction et « Retirer ». La raison d'un refus
/// s'affiche en clair sous le champ.
class PromoCodeField extends StatefulWidget {
  const PromoCodeField({
    super.key,
    required this.applied,
    required this.discountXof,
    required this.onApply,
    required this.onRemove,
    this.warning,
  });

  /// Code appliqué par le serveur ; `null` : aucun.
  final String? applied;
  final int discountXof;

  /// Vérifie le code ; rend le message d'erreur, ou `null` s'il est accepté.
  final Future<String?> Function(String code) onApply;
  final VoidCallback onRemove;

  /// Code retiré par le serveur (il ne s'applique plus).
  final String? warning;

  @override
  State<PromoCodeField> createState() => _PromoCodeFieldState();
}

class _PromoCodeFieldState extends State<PromoCodeField> {
  final _ctrl = TextEditingController();
  var _busy = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    final code = _ctrl.text.trim();
    if (code.isEmpty || _busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await widget.onApply(code);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
      if (error == null) _ctrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final applied = widget.applied;
    return AnimatedSize(
      duration: IviaMotion.medium,
      curve: IviaMotion.soft,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: IviaMotion.medium,
        switchInCurve: IviaMotion.soft,
        transitionBuilder: (child, a) => FadeTransition(
          opacity: a,
          child: ScaleTransition(
            scale: Tween(begin: 0.96, end: 1.0).animate(a),
            child: child,
          ),
        ),
        child: applied != null
            ? Container(
                key: ValueKey(applied),
                padding: const EdgeInsets.fromLTRB(
                  IviaSpacing.md,
                  IviaSpacing.sm,
                  IviaSpacing.xs,
                  IviaSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: IviaColors.successSoft,
                  borderRadius: BorderRadius.circular(IviaRadius.large),
                  border: Border.all(
                    color: IviaColors.success.withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.local_offer_rounded,
                      color: IviaColors.success,
                    ),
                    const SizedBox(width: IviaSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            applied,
                            style: t.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.6,
                            ),
                          ),
                          Text(
                            'Réduction de ${formatXof(widget.discountXof)}',
                            style: t.bodySmall?.copyWith(
                              color: IviaColors.success,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: widget.onRemove,
                      child: const Text('Retirer'),
                    ),
                  ],
                ),
              )
            : Column(
                key: const ValueKey('saisie'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _ctrl,
                          textCapitalization: TextCapitalization.characters,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _apply(),
                          decoration: const InputDecoration(
                            labelText: 'Code promo',
                            prefixIcon: Icon(Icons.local_offer_outlined),
                          ),
                        ),
                      ),
                      const SizedBox(width: IviaSpacing.sm),
                      FilledButton.tonal(
                        onPressed: _busy ? null : _apply,
                        child: _busy
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Appliquer'),
                      ),
                    ],
                  ),
                  if ((_error ?? widget.warning) case final msg?)
                    Padding(
                      padding: const EdgeInsets.only(top: IviaSpacing.xs),
                      child: Text(
                        msg,
                        style: t.bodySmall?.copyWith(color: IviaColors.error),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
