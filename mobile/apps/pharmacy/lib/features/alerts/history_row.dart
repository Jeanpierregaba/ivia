import 'package:flutter/material.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';

import '../../common/ui.dart';
import '../orders/order_screen.dart';
import 'alert_detail_screen.dart';

/// Ton d'une pastille d'état de l'historique (F21).
enum HistoryTone { green, red, blue, grey }

/// Une ligne de l'historique : alerte ou commande, avec sa pastille d'état.
class HistoryEntry {
  HistoryEntry({
    required this.at,
    required this.title,
    required this.subtitle,
    required this.status,
    required this.tone,
    required this.open,
  });

  final DateTime at;
  final String title, subtitle, status;
  final HistoryTone tone;
  final Widget Function() open;

  factory HistoryEntry.order(PharmacyOrder o) => HistoryEntry(
    at: o.completedAt ?? o.createdAt,
    title: '#${o.number}',
    subtitle:
        '${o.delivery ? 'Livraison' : 'Retrait'} · ${formatXof(o.itemsXof)}',
    status: orderStatusLabel(o),
    tone: switch (o.status) {
      'completed' || 'picked_up' => HistoryTone.green,
      'cancelled' || 'expired' => HistoryTone.grey,
      _ => HistoryTone.red,
    },
    open: () => OrderScreen(orderId: o.id),
  );

  factory HistoryEntry.alert(InboxAlert a) {
    final available = a.myLines.where((l) => l.available).length;
    final (status, tone, detail) = a.unlocked
        ? ('Confirmée', HistoryTone.green, 'Client confirmé')
        : a.responded
        ? (
            'Répondue',
            HistoryTone.blue,
            a.myLines.isEmpty
                ? 'Réponse envoyée'
                : '$available / ${a.myLines.length} disponible'
                      '${available > 1 ? 's' : ''}',
          )
        : a.status == 'declined'
        ? ('Ignorée', HistoryTone.grey, 'Ignorée')
        : ('Expirée', HistoryTone.grey, 'Non traitée');
    return HistoryEntry(
      at: a.receivedAt,
      title: a.title,
      subtitle: '$detail · ${hhmm(a.receivedAt)}',
      status: status,
      tone: tone,
      open: () => AlertDetailScreen(alertId: a.alertId),
    );
  }
}

/// Libellé court de l'état d'une commande, pour les listes.
String orderStatusLabel(PharmacyOrder o) => switch (o.status) {
  'reserved' when o.preparedAt != null => 'Prête',
  'reserved' => 'Mise de côté',
  'courier_search' => 'Livreur cherché',
  'awaiting_payment' => 'Paiement client',
  'courier_assigned' => 'Livreur en route',
  'picked_up' => 'Remise',
  'completed' => 'Remise',
  'expired' => 'Expirée',
  'cancelled' => 'Annulée',
  _ => o.status,
};

/// Jour d'une section : « Aujourd'hui », « Hier », sinon la date.
String dayLabel(DateTime at, DateTime now) {
  // Jours de Lomé, quel que soit le fuseau du téléphone.
  final d = lomeDay(at);
  final today = lomeDay(now);
  final days = today.difference(d).inDays;
  if (days == 0) return "Aujourd'hui";
  if (days == 1) return 'Hier';
  const months = [
    'janvier',
    'février',
    'mars',
    'avril',
    'mai',
    'juin',
    'juillet',
    'août',
    'septembre',
    'octobre',
    'novembre',
    'décembre',
  ];
  return '${d.day} ${months[d.month - 1]}';
}

/// Lignes groupées par jour, dans des cartes (F21).
class HistoryList extends StatelessWidget {
  const HistoryList({super.key, required this.entries});
  final List<HistoryEntry> entries;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final sorted = [...entries]..sort((a, b) => b.at.compareTo(a.at));
    final groups = <String, List<HistoryEntry>>{};
    for (final e in sorted) {
      groups.putIfAbsent(dayLabel(e.at, now), () => []).add(e);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final MapEntry(key: day, value: list) in groups.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 14, 0, 10),
            child: Semantics(
              header: true,
              child: Text(
                day.toUpperCase(),
                style: PText.label.copyWith(
                  fontSize: 13,
                  letterSpacing: 1.2,
                  color: P.muted,
                ),
              ),
            ),
          ),
          PCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (final (i, e) in list.indexed) ...[
                  if (i > 0) const Divider(height: 1, color: P.line),
                  HistoryRow(entry: e),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class HistoryRow extends StatelessWidget {
  const HistoryRow({super.key, required this.entry});
  final HistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final (bg, fg) = switch (e.tone) {
      HistoryTone.green => (P.softGreen, P.green),
      HistoryTone.red => (P.softRed, P.red),
      HistoryTone.blue => (P.softBlue, P.blue),
      HistoryTone.grey => (P.page, P.label),
    };
    return Semantics(
      button: true,
      label: '${e.title}, ${e.subtitle}, ${e.status}',
      excludeSemantics: true,
      child: InkWell(
        onTap: () =>
            Navigator.of(context)
                .push(MaterialPageRoute<void>(builder: (_) => e.open())),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e.title,
                      style: PText.cardTitle.copyWith(fontSize: 18),
                    ),
                    Text(e.subtitle, style: PText.bodyMuted),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Souple : en police très agrandie, le texte passe à la ligne.
              Flexible(
                child: PPill(e.status, bg: bg, fg: fg),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
