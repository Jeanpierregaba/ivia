import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../app/router.dart';
import '../../app/seller_shop.dart';
import 'order_screen.dart';
import 'orders_providers.dart';

/// Message d'un code bloqué (5 essais), comme le serveur.
const handoverLockedMessage =
    "Trop d'essais : le code est bloqué. Contactez l'équipe ivia.";

/// « Code de remise » : le marchand saisit le code à 4 chiffres que
/// l'acheteur lui donne au retrait. Le code ne vit que dans le champ, vidé
/// après chaque essai ; il n'est ni gardé ni journalisé.
class HandoverScreen extends ConsumerStatefulWidget {
  const HandoverScreen({super.key, required this.orderId});

  final String orderId;

  @override
  ConsumerState<HandoverScreen> createState() => _HandoverScreenState();
}

class _HandoverScreenState extends ConsumerState<HandoverScreen> {
  final _code = TextEditingController();
  var _busy = false;
  var _locked = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _code.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  SellerOrderController get _order =>
      ref.read(sellerOrderProvider(widget.orderId).notifier);

  Future<void> _submit() async {
    final code = _code.text;
    if (_busy || code.length != 4) return;
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    // Vidé dès l'envoi : le code ne reste pas à l'écran.
    _code.clear();
    try {
      final order = await ref
          .read(apiClientProvider)
          .handOverOrder(widget.orderId, code);
      if (!mounted) return;
      _order.set(order);
      showMessage(messenger, 'Commande remise.');
      if (router.canPop()) {
        router.pop();
      } else {
        router.go(Routes.order(widget.orderId));
      }
      return;
    } on ApiException catch (e) {
      String error;
      switch (e.code) {
        case _ when e.isNetwork:
          error = 'Pas de connexion. Réessayez.';
        case 'handover_locked':
          _locked = true;
          error = e.message;
        case 'order_not_found':
          showMessage(messenger, orderNotFoundMessage);
          router.go(Routes.orders);
          return;
        case 'shop_suspended' || 'shop_not_found':
          error = e.message;
          await ref.read(sellerShopProvider.notifier).refresh();
        default:
          error = e.message;
      }
      if (mounted) setState(() => _error = error);
      // Essais comptés ou statut changé : le détail se met à jour.
      if (!e.isNetwork) await _order.refresh().catchError((Object _) {});
    } on Exception {
      if (mounted) {
        setState(() => _error = 'Une erreur est survenue. Réessayez.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final order = ref.watch(sellerOrderProvider(widget.orderId)).value;
    final locked = _locked || (order?.isHandoverLocked ?? false);
    final buyer = order?.buyerFirstName ?? '';
    final error = _error ?? (locked ? handoverLockedMessage : null);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(IviaSpacing.screen),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IviaBackButton(
                      onPressed: _busy ? null : () => context.pop(),
                    ),
                  ),
                  const SizedBox(height: IviaSpacing.lg),
                  Semantics(
                    header: true,
                    child: Text(
                      'Code de remise',
                      style: textTheme.headlineMedium,
                    ),
                  ),
                  const SizedBox(height: IviaSpacing.sm),
                  Text(
                    buyer.isEmpty
                        ? "Demandez à l'acheteur son code à 4 chiffres."
                        : 'Demandez à $buyer son code à 4 chiffres.',
                    style: textTheme.bodyLarge?.copyWith(
                      color: IviaColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: IviaSpacing.xxl),
                  if (!locked)
                    IviaCodeInput(
                      controller: _code,
                      length: 4,
                      autofocus: true,
                      enabled: !_busy,
                      hasError: _error != null,
                      semanticLabel: 'Code de remise à 4 chiffres',
                    ),
                  if (error != null) ...[
                    const SizedBox(height: IviaSpacing.md),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        error,
                        style: textTheme.bodyMedium?.copyWith(
                          color: IviaColors.error,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // En bas, au-dessus du clavier : toujours visible.
            if (!locked)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  IviaSpacing.screen,
                  IviaSpacing.sm,
                  IviaSpacing.screen,
                  IviaSpacing.lg,
                ),
                child: FilledButton(
                  onPressed: _busy || _code.text.length != 4 ? null : _submit,
                  child: _busy
                      ? const ButtonProgress()
                      : const Text('Remettre la commande'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
