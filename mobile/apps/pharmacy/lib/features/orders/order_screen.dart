import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../common/providers.dart';
import '../../common/ui.dart';
import 'orders_tab.dart';

/// Réservation : produits, préparation, remise par code ou au livreur.
class OrderScreen extends ConsumerStatefulWidget {
  const OrderScreen({super.key, required this.orderId});
  final String orderId;

  @override
  ConsumerState<OrderScreen> createState() => _OrderScreenState();
}

class _OrderScreenState extends ConsumerState<OrderScreen> {
  PharmacyOrder? _o;
  final _code = TextEditingController();
  var _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final o = await ref.read(apiClientProvider).pharmacyOrder(widget.orderId);
    if (mounted) setState(() => _o = o);
  }

  Future<void> _do(
    Future<void> Function(IviaApiClient api) a,
    String done,
  ) async {
    setState(() => _busy = true);
    try {
      await a(ref.read(apiClientProvider));
      ref.invalidate(ordersProvider);
      ref.invalidate(earningsProvider);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(done)));
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final o = _o;
    return Scaffold(
      backgroundColor: P.page,
      appBar: AppBar(
        backgroundColor: P.page,
        title: Text(o == null ? 'Réservation' : 'Réservation ${o.number}'),
      ),
      body: o == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(IviaSpacing.screen),
              children: [
                PCard(
                  color: o.active ? P.green : P.navy,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        orderStatusLabel(o),
                        style: t.titleLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        '${o.buyerFirstName.isEmpty ? 'Patient' : o.buyerFirstName} · ${o.delivery ? 'livraison ivia' : 'retrait sur place'}'
                        '${o.expiresAt != null && o.active ? ' · mis de côté jusqu\'à ${hhmm(o.expiresAt!)}' : ''}',
                        style: t.bodyMedium?.copyWith(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                PCard(
                  child: Column(
                    children: [
                      for (final l in o.lines.where((l) => l.available))
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${l.quantity} × ${l.name}${l.prescriptionRequired ? ' · ordonnance' : ''}',
                                  style: t.bodyLarge,
                                ),
                              ),
                              Text(
                                formatXof(l.lineTotalXof),
                                style: t.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      const Divider(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              o.delivery
                                  ? 'Payé par le patient dans l\'app'
                                  : 'À encaisser au comptoir',
                              style: t.titleSmall,
                            ),
                          ),
                          Text(
                            formatXof(o.itemsXof),
                            style: t.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (o.prescriptionRequired) ...[
                  const SizedBox(height: 12),
                  PCard(
                    color: P.softYellow,
                    child: Text(
                      'Ordonnance exigée : vérifiez l\'original à la remise.',
                      style: t.bodyMedium,
                    ),
                  ),
                ],
                if (o.courier case final c?) ...[
                  const SizedBox(height: 12),
                  PCard(
                    child: Row(
                      children: [
                        const PIcon(
                          Icons.two_wheeler,
                          bg: P.softBlue,
                          fg: P.blue,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '${c.firstName} · livreur ivia${c.vehiclePlate.isEmpty ? '' : ' · ${c.vehiclePlate}'}',
                            style: t.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                if (o.active && o.preparedAt == null && o.status != 'picked_up')
                  PButton(
                    label: 'Commande prête',
                    icon: Icons.check,
                    busy: _busy,
                    onTap: () => _do(
                      (api) => api.pharmacyMarkPrepared(o.id),
                      'Le patient est prévenu.',
                    ),
                  ),
                if (o.active && !o.delivery && o.status == 'reserved') ...[
                  const SizedBox(height: 14),
                  PCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Remise au comptoir',
                          style: t.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          'Demandez le code à 4 chiffres affiché dans l\'app du patient.',
                          style: t.bodyMedium?.copyWith(color: P.muted),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _code,
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                          textAlign: TextAlign.center,
                          style: t.headlineMedium?.copyWith(
                            letterSpacing: 12,
                            fontWeight: FontWeight.w800,
                          ),
                          decoration: const InputDecoration(
                            counterText: '',
                            hintText: '• • • •',
                          ),
                        ),
                        const SizedBox(height: 10),
                        PButton(
                          label: 'Valider la remise',
                          color: P.navy,
                          busy: _busy,
                          onTap: () => _do(
                            (api) => api.pharmacyCompletePickup(
                              o.id,
                              _code.text.trim(),
                            ),
                            'Remise enregistrée.',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (o.active && o.status == 'reserved')
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => _do(
                            (api) => api.pharmacyCancelOrder(
                              o.id,
                              'Produit plus disponible',
                            ),
                            'Réservation annulée, patient remboursé.',
                          ),
                    child: const Text('Produit plus disponible : annuler'),
                  ),
              ],
            ),
    );
  }
}
