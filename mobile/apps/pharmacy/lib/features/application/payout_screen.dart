import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../common/providers.dart';
import '../../common/ui.dart';

/// Compte de versement : étape 5 du dossier ([step]), qui envoie le dossier
/// pour validation, ou écran seul (depuis le relevé), qui l'enregistre.
class PayoutScreen extends ConsumerStatefulWidget {
  const PayoutScreen({super.key, this.step, this.onBack});

  /// Étape du dossier (« 5 sur 5 ») ; `null` hors du dossier.
  final int? step;
  final VoidCallback? onBack;

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

  bool get _inDossier => widget.step != null;

  @override
  void initState() {
    super.initState();
    for (final c in [_phone, _holder]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _phone.dispose();
    _holder.dispose();
    super.dispose();
  }

  bool get _filled =>
      togoPhoneDigits(_phone.text).length == 8 &&
      _holder.text.trim().isNotEmpty;

  /// Enregistre le compte saisi (s'il y en a un), puis envoie le dossier.
  Future<void> _save(PharmacyProfile? p) async {
    setState(() {
      _busy = true;
      _errors = {};
    });
    final api = ref.read(apiClientProvider);
    final navigator = Navigator.of(context);
    try {
      if (_filled) {
        await api.setPharmacyPayout(
          operator: _operator,
          phone: '+228${togoPhoneDigits(_phone.text)}',
          holder: _holder.text.trim(),
        );
      }
      if (_inDossier) await api.submitPharmacy();
      ref.invalidate(pharmacyProfileProvider);
      if (!_inDossier && mounted) navigator.pop();
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
    final p = ref.watch(pharmacyProfileProvider).value;
    final step = widget.step;
    final hasPayout = p?.hasPayout ?? false;
    final ready = _inDossier
        ? (p?.missingDocuments.isEmpty ?? false) && (hasPayout || _filled)
        : _filled;
    return Scaffold(
      backgroundColor: P.page,
      body: SafeArea(
        child: Column(
          children: [
            PHeader(
              title: 'Compte de versement',
              trailing: step == null ? null : PStepPill(step: step, of: 5),
              onBack: widget.onBack,
            ),
            Expanded(
              child: PFormTheme(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(P.gutter, 8, P.gutter, 8),
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        'Où recevoir vos ventes ?',
                        style: PText.heading,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Les commandes livrées, payées dans l\'app, y sont versées. '
                      'Le titulaire doit correspondre à la pièce d\'identité du '
                      'dossier.',
                      style: PText.bodyMuted,
                    ),
                    const SizedBox(height: 18),
                    if (hasPayout) ...[
                      PCard(
                        child: Row(
                          children: [
                            const PIcon(Icons.account_balance_wallet_outlined),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Compte enregistré',
                                    style: PText.cardTitle.copyWith(
                                      fontSize: 16,
                                    ),
                                  ),
                                  Text(
                                    '${p!.payoutMasked} · ${p.payoutHolder}',
                                    style: PText.small,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Pour le changer, saisissez le nouveau compte.',
                        style: PText.small,
                      ),
                      const SizedBox(height: 10),
                    ],
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: IviaFieldLabel(
                        label: 'Opérateur',
                        child: DropdownButtonFormField<String>(
                          initialValue: _operator,
                          items: const [
                            DropdownMenuItem(
                              value: 'flooz',
                              child: Text('Moov Money (Flooz)'),
                            ),
                            DropdownMenuItem(
                              value: 'tmoney',
                              child: Text('Yas (T-Money)'),
                            ),
                          ],
                          onChanged: _busy
                              ? null
                              : (v) => setState(() => _operator = v ?? 'flooz'),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: TogoPhoneField(
                        label: 'Numéro Mobile Money',
                        controller: _phone,
                        enabled: !_busy,
                        errorText: _errors['phone'],
                      ),
                    ),
                    IviaFieldLabel(
                      label: 'Titulaire du compte',
                      child: TextField(
                        controller: _holder,
                        enabled: !_busy,
                        textCapitalization: TextCapitalization.words,
                        decoration: InputDecoration(
                          errorText: _errors['holder'],
                          errorMaxLines: 3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            PBottomBar(
              children: [
                PButton(
                  label: _inDossier ? 'Envoyer pour validation' : 'Enregistrer',
                  busy: _busy,
                  onTap: ready ? () => _save(p) : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
