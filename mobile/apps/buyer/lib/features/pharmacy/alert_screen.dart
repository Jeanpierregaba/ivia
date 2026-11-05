import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../app/router.dart';
import '../payment/payment_providers.dart';
import 'pay_sheet.dart';
import 'pharmacy_state.dart';

/// P04 à P07 : suivi d'une alerte. Compteurs (contactées, vues, réponses),
/// réponses classées par distance, déblocage d'une pharmacie, relance.
class AlertScreen extends ConsumerStatefulWidget {
  const AlertScreen({super.key, required this.alertId});

  final String alertId;

  @override
  ConsumerState<AlertScreen> createState() => _AlertScreenState();
}

class _AlertScreenState extends ConsumerState<AlertScreen> with LivePolling {
  var _busy = false;

  @override
  void initState() {
    super.initState();
    startPolling(() => ref.invalidate(medAlertProvider(widget.alertId)));
  }

  void _toast(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  Future<void> _unlock(MedAlert alert, MedResponse r) async {
    if (r.unlocked && r.reservationId != null) {
      context.push(Routes.medReservation(r.reservationId!));
      return;
    }
    String? reservationId;
    final paid = await showMedPaySheet(
      context,
      title: 'Voir la pharmacie n°${r.rank}',
      amountXof: alert.unlockFeeXof,
      start: (op, phone) async {
        final res = await ref
            .read(apiClientProvider)
            .unlockResponse(alert.id, r.id, operator: op, phone: phone);
        reservationId = res.reservationId ?? res.payment?.reservationId;
        return res.payment;
      },
    );
    if (!mounted) return;
    ref.invalidate(medAlertProvider(alert.id));
    // Paiement validé : la réservation est créée par le serveur.
    var id = reservationId ?? paid?.reservationId;
    if (id == null && (paid != null || reservationId != null)) {
      final fresh = await ref.read(apiClientProvider).medAlert(alert.id);
      id = fresh.responses
          .where((x) => x.id == r.id)
          .firstOrNull
          ?.reservationId;
    }
    if (id != null && mounted) context.push(Routes.medReservation(id));
  }

  Future<void> _relaunch(MedAlert alert) async {
    final radius = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(title: Text('Relancer avec un autre rayon')),
            for (final km in [2, 5, 10, 20])
              ListTile(
                leading: const Icon(Icons.radar),
                title: Text('$km km'),
                selected: km * 1000 == alert.radiusM,
                onTap: () => Navigator.pop(context, km * 1000),
              ),
          ],
        ),
      ),
    );
    if (radius == null) return;
    setState(() => _busy = true);
    try {
      final next = await ref
          .read(apiClientProvider)
          .relaunchAlert(alert.id, radius);
      ref.invalidate(myAlertsProvider);
      if (mounted) context.pushReplacement(Routes.medAlert(next.id));
    } on ApiException catch (e) {
      _toast(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel(MedAlert alert) async {
    setState(() => _busy = true);
    try {
      await ref.read(apiClientProvider).cancelAlert(alert.id);
      ref
        ..invalidate(medAlertProvider(alert.id))
        ..invalidate(myAlertsProvider);
    } on ApiException catch (e) {
      _toast(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(medAlertProvider(widget.alertId));
    final alert = async.value;
    return Scaffold(
      appBar: AppBar(title: const Text('Mon alerte')),
      body: SafeArea(
        child: alert == null
            ? Center(
                child: async.hasError
                    ? Text(
                        async.error is ApiException
                            ? (async.error as ApiException).message
                            : 'Alerte indisponible.',
                      )
                    : const CircularProgressIndicator(),
              )
            : _body(context, alert),
      ),
    );
  }

  Widget _body(BuildContext context, MedAlert alert) {
    final t = Theme.of(context).textTheme;
    final brand = IviaAppBrand.of(context);
    final remaining = alert.searchEndsAt.difference(
      ref.read(apiClientProvider).now(),
    );
    final responses = [...alert.responses]
      ..sort((a, b) => a.rank.compareTo(b.rank));
    final closed = !alert.searching;
    return ListView(
      padding: const EdgeInsets.all(IviaSpacing.screen),
      children: [
        Text(alert.title, style: t.headlineSmall),
        const SizedBox(height: IviaSpacing.xs),
        Text(
          [
            for (final i in alert.items) '${i.quantity} × ${i.name}',
            if (alert.photoCount > 0) '${alert.photoCount} photo(s)',
          ].join(' · '),
          style: t.bodyMedium?.copyWith(color: IviaColors.textSecondary),
        ),
        const SizedBox(height: IviaSpacing.lg),
        Container(
          padding: const EdgeInsets.all(IviaSpacing.lg),
          decoration: BoxDecoration(
            color: brand.accent,
            borderRadius: BorderRadius.circular(IviaRadius.large),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(switch (alert.status) {
                'searching' => 'Recherche en cours…',
                'answered' => 'Des pharmacies ont répondu',
                'no_response' => 'Aucune réponse',
                'unlocked' => 'Pharmacie débloquée',
                'fulfilled' => 'Alerte terminée',
                'cancelled' => 'Alerte annulée',
                _ => alert.status,
              }, style: t.titleLarge?.copyWith(color: Colors.white)),
              if (alert.searching && remaining > Duration.zero)
                Text(
                  'Réponses encore ${remaining.inMinutes + 1} min · rayon ${alert.radiusM ~/ 1000} km',
                  style: t.bodyMedium?.copyWith(color: Colors.white70),
                ),
              const SizedBox(height: IviaSpacing.lg),
              Row(
                children: [
                  _Counter(value: alert.notified, label: 'contactées'),
                  _Counter(value: alert.seen, label: 'ont vu'),
                  _Counter(value: alert.responded, label: 'ont répondu'),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: IviaSpacing.xl),
        if (responses.isEmpty)
          Text(
            alert.searching
                ? 'Les pharmacies regardent votre demande. Vous serez prévenu à chaque réponse.'
                : 'Aucune pharmacie n\'a répondu dans ce rayon.',
            style: t.bodyLarge,
          )
        else ...[
          Text(
            'Réponses, de la plus proche à la plus loin',
            style: t.titleMedium,
          ),
          const SizedBox(height: IviaSpacing.sm),
          for (final r in responses)
            _ResponseCard(
              response: r,
              fee: alert.unlockFeeXof,
              onUnlock: _busy ? null : () => _unlock(alert, r),
            ),
        ],
        const SizedBox(height: IviaSpacing.xl),
        if (closed && alert.status != 'unlocked' && alert.status != 'fulfilled')
          FilledButton.icon(
            onPressed: _busy ? null : () => _relaunch(alert),
            icon: const Icon(Icons.refresh),
            label: const Text('Relancer avec un autre rayon'),
          ),
        if (alert.searching && ref.watch(devPaymentsProvider))
          Padding(
            padding: const EdgeInsets.only(bottom: IviaSpacing.md),
            child: OutlinedButton.icon(
              onPressed: () async {
                await ref.read(apiClientProvider).devAutoRespond(alert.id);
                ref.invalidate(medAlertProvider(alert.id));
              },
              icon: const Icon(Icons.science_outlined),
              label: const Text('Simuler les réponses (démo)'),
            ),
          ),
        if (alert.searching)
          OutlinedButton(
            onPressed: _busy ? null : () => _cancel(alert),
            child: const Text('Annuler l\'alerte'),
          ),
      ],
    );
  }
}

class _Counter extends StatelessWidget {
  const _Counter({required this.value, required this.label});
  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$value',
            style: t.headlineMedium?.copyWith(color: Colors.white),
          ),
          Text(label, style: t.bodySmall?.copyWith(color: Colors.white70)),
        ],
      ),
    );
  }
}

class _ResponseCard extends StatelessWidget {
  const _ResponseCard({
    required this.response,
    required this.fee,
    required this.onUnlock,
  });

  final MedResponse response;
  final int fee;
  final VoidCallback? onUnlock;

  @override
  Widget build(BuildContext context) {
    final r = response;
    final t = Theme.of(context).textTheme;
    final name = r.unlocked && r.pharmacy != null
        ? r.pharmacy!.name
        : 'Pharmacie n°${r.rank}';
    return Card(
      margin: const EdgeInsets.only(bottom: IviaSpacing.md),
      child: Padding(
        padding: const EdgeInsets.all(IviaSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.local_pharmacy_outlined),
                const SizedBox(width: IviaSpacing.sm),
                Expanded(child: Text(name, style: t.titleMedium)),
                Text(formatDistance(r.distanceM), style: t.bodyMedium),
              ],
            ),
            const SizedBox(height: IviaSpacing.sm),
            Text(
              r.allAvailable
                  ? 'Tout est disponible'
                  : '${r.availableCount} sur ${r.lineCount} disponible(s)',
              style: t.bodyMedium?.copyWith(
                color: r.allAvailable
                    ? IviaColors.success
                    : IviaColors.textSecondary,
              ),
            ),
            for (final l in r.lines)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    Icon(
                      l.available ? Icons.check_circle : Icons.cancel_outlined,
                      size: 16,
                      color: l.available
                          ? IviaColors.success
                          : IviaColors.textMuted,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${l.quantity} × ${l.name}${l.prescriptionRequired ? ' · ordonnance' : ''}',
                      ),
                    ),
                    if (l.available) Text(formatXof(l.lineTotalXof)),
                  ],
                ),
              ),
            if (r.note.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: IviaSpacing.sm),
                child: Text('« ${r.note} »', style: t.bodySmall),
              ),
            const Divider(height: IviaSpacing.xl),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Total ${formatXof(r.totalXof)}',
                    style: t.titleMedium,
                  ),
                ),
                FilledButton(
                  onPressed: onUnlock,
                  child: Text(
                    r.unlocked
                        ? 'Voir ma réservation'
                        : 'Débloquer · ${formatXof(fee)}',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
