import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../payment/payment_logos.dart';
import '../payment/payment_providers.dart';

/// Paiement Mobile Money d'un déblocage ou d'une commande pharmacie : choix
/// de l'opérateur et du numéro, puis attente de la validation sur le
/// téléphone. Retourne le paiement réussi, ou `null`.
Future<MedPayment?> showMedPaySheet(
  BuildContext context, {
  required String title,
  required int amountXof,
  required Future<MedPayment?> Function(PaymentOperator op, String phone) start,
}) => showModalBottomSheet<MedPayment>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _PaySheet(title: title, amountXof: amountXof, start: start),
);

class _PaySheet extends ConsumerStatefulWidget {
  const _PaySheet({
    required this.title,
    required this.amountXof,
    required this.start,
  });

  final String title;
  final int amountXof;
  final Future<MedPayment?> Function(PaymentOperator op, String phone) start;

  @override
  ConsumerState<_PaySheet> createState() => _PaySheetState();
}

class _PaySheetState extends ConsumerState<_PaySheet> {
  var _op = PaymentOperator.flooz;
  final _phone = TextEditingController();
  MedPayment? _payment;
  String? _error;
  var _busy = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    final user = switch (ref.read(authControllerProvider)) {
      AuthSignedIn(:final user) => user,
      _ => null,
    };
    _phone.text = formatTogoPhone(user?.phone ?? '');
  }

  @override
  void dispose() {
    _poll?.cancel();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _pay() async {
    final digits = togoPhoneDigits(_phone.text);
    if (!isTogoMobile(digits)) {
      setState(() => _error = 'Numéro Mobile Money togolais attendu.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final p = await widget.start(_op, '+228$digits');
      if (!mounted) return;
      if (p == null || p.succeeded) {
        Navigator.pop(context, p);
        return;
      }
      setState(() => _payment = p);
      _poll = Timer.periodic(const Duration(seconds: 3), (_) => _refresh());
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refresh() async {
    final id = _payment?.id;
    if (id == null) return;
    try {
      final p = await ref.read(apiClientProvider).medPayment(id);
      if (!mounted) return;
      setState(() => _payment = p);
      if (p.succeeded) {
        _poll?.cancel();
        Navigator.pop(context, p);
      } else if (!p.pending) {
        _poll?.cancel();
        setState(() {
          _error = p.failureReason.isEmpty
              ? 'Paiement non abouti. Réessayez.'
              : p.failureReason;
          _payment = null;
        });
      }
    } on ApiException {
      // Réseau : nouvel essai au prochain tour.
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final waiting = _payment != null;
    final dev = ref.watch(devPaymentsProvider);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        IviaSpacing.screen,
        0,
        IviaSpacing.screen,
        IviaSpacing.screen + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.title, style: t.headlineSmall),
          const SizedBox(height: IviaSpacing.xs),
          Text(
            formatXof(widget.amountXof),
            style: t.headlineMedium?.copyWith(color: IviaColors.primary),
          ),
          const SizedBox(height: IviaSpacing.lg),
          if (waiting) ...[
            const Center(child: CircularProgressIndicator()),
            const SizedBox(height: IviaSpacing.lg),
            Text(
              _payment!.instructions.isNotEmpty
                  ? _payment!.instructions
                  : 'Validez le paiement sur votre téléphone '
                        '(${_op == PaymentOperator.flooz ? 'Flooz' : 'T-Money'}, '
                        '${_payment!.phoneMasked}).',
              textAlign: TextAlign.center,
            ),
            if (dev) ...[
              const SizedBox(height: IviaSpacing.lg),
              OutlinedButton(
                onPressed: () async {
                  await ref
                      .read(apiClientProvider)
                      .devSimulateMedPayment(_payment!.id);
                  await _refresh();
                },
                child: const Text('Simuler la validation'),
              ),
            ],
          ] else ...[
            for (final op in PaymentOperator.values)
              Padding(
                padding: const EdgeInsets.only(bottom: IviaSpacing.sm),
                child: ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(IviaRadius.large),
                    side: BorderSide(
                      color: _op == op ? IviaColors.primary : IviaColors.border,
                      width: _op == op ? 2 : 1,
                    ),
                  ),
                  leading: PaymentLogo.operator(op, size: 40),
                  title: Text(
                    op == PaymentOperator.flooz ? 'Flooz' : 'T-Money',
                  ),
                  subtitle: Text(operatorBrand(op)),
                  trailing: Icon(
                    _op == op
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: _op == op ? IviaColors.primary : IviaColors.border,
                  ),
                  onTap: () => setState(() => _op = op),
                ),
              ),
            const CardPaymentSoon(),
            const SizedBox(height: IviaSpacing.lg),
            TogoPhoneField(
              label: 'Numéro Mobile Money',
              controller: _phone,
              enabled: !_busy,
              errorText: _error,
            ),
            const SizedBox(height: IviaSpacing.xl),
            FilledButton(
              onPressed: _busy ? null : _pay,
              child: _busy
                  ? const ButtonProgress()
                  : Text('Payer ${formatXof(widget.amountXof)}'),
            ),
          ],
          if (waiting && _error != null)
            Text(_error!, style: const TextStyle(color: IviaColors.error)),
        ],
      ),
    );
  }
}
