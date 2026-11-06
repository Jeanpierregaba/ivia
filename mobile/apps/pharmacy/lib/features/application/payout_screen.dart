import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../common/providers.dart';
import '../../common/ui.dart';

/// Compte de versement, avant l'envoi du dossier.
class PayoutScreen extends ConsumerStatefulWidget {
  const PayoutScreen({super.key});

  @override
  ConsumerState<PayoutScreen> createState() => _PayoutScreenState();
}

class _PayoutScreenState extends ConsumerState<PayoutScreen> {
  var _operator = 'flooz';
  final _phone = TextEditingController();
  late final _holder = TextEditingController(
    text: ref.read(pharmacyProfileProvider).value?.payoutHolder,
  );
  var _errors = <String, String>{};
  var _busy = false;

  @override
  void dispose() {
    _phone.dispose();
    _holder.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _errors = {};
    });
    final navigator = Navigator.of(context);
    try {
      await ref
          .read(apiClientProvider)
          .setPharmacyPayout(
            operator: _operator,
            phone: '+228${togoPhoneDigits(_phone.text)}',
            holder: _holder.text.trim(),
          );
      if (mounted) navigator.pop();
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _errors = e.fields);
        if (e.fields.isEmpty) say(context, e.message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: P.page,
      appBar: AppBar(
        backgroundColor: P.page,
        title: const Text('Compte de versement'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(IviaSpacing.screen),
        children: [
          Text(
            'Vos ventes livrées y sont versées. Le titulaire doit correspondre à la pièce d\'identité du dossier.',
            style: t.bodyMedium?.copyWith(color: P.muted),
          ),
          const SizedBox(height: 16),
          IviaFieldLabel(
            label: 'Opérateur',
            child: DropdownButtonFormField<String>(
              initialValue: _operator,
              items: const [
                DropdownMenuItem(
                  value: 'flooz',
                  child: Text('Moov Money (Flooz)'),
                ),
                DropdownMenuItem(value: 'tmoney', child: Text('Yas (T-Money)')),
              ],
              onChanged: (v) => setState(() => _operator = v ?? 'flooz'),
            ),
          ),
          const SizedBox(height: 14),
          TogoPhoneField(
            label: 'Numéro Mobile Money',
            controller: _phone,
            errorText: _errors['phone'],
          ),
          const SizedBox(height: 14),
          IviaFieldLabel(
            label: 'Titulaire du compte',
            child: TextField(
              controller: _holder,
              decoration: InputDecoration(errorText: _errors['holder']),
            ),
          ),
          const SizedBox(height: 20),
          PButton(label: 'Enregistrer', busy: _busy, onTap: _save),
        ],
      ),
    );
  }
}
