import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../common/providers.dart';
import '../../common/ui.dart';
import 'alert_detail_screen.dart';

class InboxTab extends ConsumerWidget {
  const InboxTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final items = ref.watch(inboxProvider).value ?? const <InboxAlert>[];
    final profile = ref.watch(pharmacyProfileProvider).value;
    final now = DateTime.now();
    final open = items
        .where((a) => a.searchEndsAt.isAfter(now) && a.status != 'declined')
        .toList();
    final past = items.where((a) => !open.contains(a)).toList();
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(inboxProvider),
      child: ListView(
        padding: const EdgeInsets.all(IviaSpacing.screen),
        children: [
          Text(
            profile?.name ?? 'Pharmacie',
            style: t.bodyLarge?.copyWith(color: P.muted),
          ),
          const PTitle('Alertes ', 'médicament'),
          const SizedBox(height: 12),
          if (profile != null &&
              !profile.isOpen &&
              !profile.onDuty &&
              !profile.open24h)
            PCard(
              color: P.softYellow,
              child: Text(
                'Vous êtes fermé : vous ne recevez pas d\'alertes. Ouvrez la pharmacie dans l\'onglet Officine.',
                style: t.bodyMedium,
              ),
            ),
          const SizedBox(height: 8),
          if (open.isEmpty)
            PCard(
              child: Row(
                children: [
                  const PIcon(Icons.notifications_none),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      'Aucune alerte en cours. Les nouvelles alertes apparaissent ici en direct.',
                      style: t.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          for (final a in open)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _AlertTile(alert: a),
            ),
          if (past.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Terminées',
              style: t.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: P.muted,
              ),
            ),
            const SizedBox(height: 8),
            for (final a in past.take(20))
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _AlertTile(alert: a),
              ),
          ],
        ],
      ),
    );
  }
}

class _AlertTile extends StatelessWidget {
  const _AlertTile({required this.alert});
  final InboxAlert alert;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final a = alert;
    final left = a.searchEndsAt.difference(DateTime.now());
    final live = left > Duration.zero && a.status != 'declined';
    final (label, bg, fg) = a.unlocked
        ? ('Débloquée', P.softGreen, P.green)
        : a.responded
        ? ('Répondu · ${formatXof(a.myTotalXof)}', P.softBlue, P.blue)
        : a.status == 'declined'
        ? ('Refusée', P.page, P.muted)
        : live
        ? ('À répondre · ${left.inMinutes + 1} min', P.softRed, P.red)
        : ('Expirée', P.page, P.muted);
    return PCard(
      border: live && !a.responded ? P.red : null,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => AlertDetailScreen(alertId: a.alertId),
        ),
      ),
      child: Row(
        children: [
          PIcon(
            a.photoCount > 0
                ? Icons.description_outlined
                : Icons.medication_outlined,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  a.title,
                  style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
                Text(
                  [
                    if (a.items.isNotEmpty)
                      '${a.items.length} produit${a.items.length > 1 ? 's' : ''}',
                    if (a.photoCount > 0)
                      '${a.photoCount} photo${a.photoCount > 1 ? 's' : ''}',
                    formatDistance(a.distanceM),
                    'reçue à ${hhmm(a.receivedAt)}',
                  ].join(' · '),
                  style: t.bodySmall?.copyWith(color: P.muted),
                ),
                const SizedBox(height: 6),
                PPill(label, bg: bg, fg: fg),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: P.muted),
        ],
      ),
    );
  }
}
