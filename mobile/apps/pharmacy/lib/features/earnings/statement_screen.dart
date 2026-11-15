import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../common/providers.dart';
import '../../common/ui.dart';
import '../alerts/history_row.dart';
import '../application/payout_screen.dart';

/// Relevé (F22) : solde à recevoir, commandes livrées payées dans l'app,
/// compte de versement.
class StatementScreen extends ConsumerWidget {
  const StatementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final earningsValue = ref.watch(earningsProvider);
    final e = earningsValue.value;
    final orders = ref.watch(ordersProvider).value ?? const <PharmacyOrder>[];
    final p = ref.watch(pharmacyProfileProvider).value;
    final delivered =
        orders.where((o) => o.delivery && o.status == 'completed').toList()
          ..sort(
            (a, b) => (b.completedAt ?? b.createdAt).compareTo(
              a.completedAt ?? a.createdAt,
            ),
          );
    final noCommission = delivered.every((o) => o.dueXof >= o.itemsXof);
    final error = errorOf(earningsValue);
    return Scaffold(
      backgroundColor: P.page,
      body: SafeArea(
        child: Column(
          children: [
            const PHeader(title: 'Relevé'),
            Expanded(
              child: RefreshIndicator(
                color: P.green,
                onRefresh: () async {
                  ref
                    ..invalidate(earningsProvider)
                    ..invalidate(ordersProvider);
                },
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(P.gutter, 4, P.gutter, 24),
                  children: [
                    if (error != null) ...[
                      PErrorRetry(message: error),
                      const SizedBox(height: 12),
                    ],
                    Container(
                      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                      decoration: BoxDecoration(
                        color: P.green,
                        borderRadius: BorderRadius.circular(28),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'À recevoir',
                            style: PText.body.copyWith(
                              fontSize: 16,
                              color: IviaPharmacyColors.onGreenMuted,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            formatXof(e?.balanceXof ?? 0),
                            style: IviaTextStyles.display.copyWith(
                              color: Colors.white,
                              fontSize: 40,
                              height: 1.15,
                            ),
                          ),
                          if (noCommission) ...[
                            const SizedBox(height: 12),
                            const PPill(
                              '0 % de commission',
                              bg: Colors.white,
                              fg: P.green,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      "Seules les commandes livrées payées dans l'app "
                      'apparaissent ici. Les retraits sont payés au comptoir.',
                      style: PText.bodyMuted.copyWith(fontSize: 16),
                    ),
                    if ((e?.paidOutXof ?? 0) > 0) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Déjà versé : ${formatXof(e!.paidOutXof)}',
                        style: PText.bodyMuted,
                      ),
                    ],
                    const SizedBox(height: 14),
                    if (delivered.isEmpty)
                      const PEmpty(
                        icon: Icons.receipt_long_outlined,
                        text: 'Aucune commande livrée pour le moment.',
                      )
                    else
                      PCard(
                        padding: EdgeInsets.zero,
                        child: Column(
                          children: [
                            for (final (i, o) in delivered.indexed) ...[
                              if (i > 0)
                                const Divider(height: 1, color: P.line),
                              Padding(
                                padding: const EdgeInsets.all(14),
                                child: MergeSemantics(
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              '#${o.number}',
                                              style: PText.cardTitle.copyWith(
                                                fontSize: 18,
                                              ),
                                            ),
                                            Text(
                                              '${dayLabel(o.completedAt ?? o.createdAt, DateTime.now())}'
                                              ' · Livraison',
                                              style: PText.bodyMuted,
                                            ),
                                          ],
                                        ),
                                      ),
                                      Text(
                                        formatXof(o.dueXof),
                                        style: PText.cardTitle.copyWith(
                                          fontSize: 18,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    const SizedBox(height: 12),
                    Semantics(
                      button: true,
                      child: PCard(
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const PayoutScreen(),
                          ),
                        ),
                        child: Row(
                          children: [
                            const PIcon(Icons.account_balance_wallet, size: 40),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Compte de versement',
                                    style: PText.cardTitle,
                                  ),
                                  Text(
                                    p?.payoutMasked ?? 'À renseigner',
                                    style: PText.bodyMuted,
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right, color: P.muted),
                          ],
                        ),
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
