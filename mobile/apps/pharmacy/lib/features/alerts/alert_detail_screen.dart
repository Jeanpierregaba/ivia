import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';

import '../../common/providers.dart';
import '../../common/ui.dart';
import '../push/push.dart';
import 'alert_logic.dart';
import 'incoming_alert_screen.dart';
import 'prescription_viewer.dart';
import 'response_screen.dart';

/// Détail d'une alerte (F11) : ordonnance, produits demandés, précision du
/// client ; « Ignorer » ou « Répondre ». Lire le détail marque l'alerte vue.
class AlertDetailScreen extends ConsumerStatefulWidget {
  const AlertDetailScreen({super.key, required this.alertId});
  final String alertId;

  @override
  ConsumerState<AlertDetailScreen> createState() => _AlertDetailScreenState();
}

class _AlertDetailScreenState extends ConsumerState<AlertDetailScreen> {
  InboxAlert? _alert;
  String? _error;
  var _busy = false;
  var _expired = false;

  @override
  void initState() {
    super.initState();
    _load();
    // L'alerte est à l'écran : la sonnerie s'arrête.
    ref.read(pushProvider).dismiss(widget.alertId);
    ref.read(incomingShownProvider.notifier).markShown(widget.alertId);
  }

  @override
  void dispose() {
    // Miniature de l'ordonnance : pas gardée après la fermeture.
    for (final p in _alert?.photos ?? const <InboxPhoto>[]) {
      if (p.url case final url?) NetworkImage(url).evict();
    }
    super.dispose();
  }

  /// Relu aussi quand le lien des photos (10 minutes) a expiré.
  Future<void> _load() async {
    try {
      final a = await ref
          .read(apiClientProvider)
          .pharmacyInboxItem(widget.alertId);
      if (!mounted) return;
      setState(() {
        _alert = a;
        _error = null;
        _expired = false;
      });
      ref.invalidate(inboxProvider);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  void _retry() {
    setState(() => _error = null);
    _load();
  }

  Future<void> _decline() async {
    setState(() => _busy = true);
    try {
      await ref.read(apiClientProvider).pharmacyDecline(widget.alertId);
      ref.invalidate(inboxProvider);
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        say(context, e.message);
      }
    }
  }

  Future<void> _respond() async {
    final sent = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ResponseScreen(alertId: widget.alertId),
      ),
    );
    if (sent == true && mounted) {
      Navigator.of(context).pop();
    } else {
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = _alert;
    final live =
        a != null &&
        !_expired &&
        a.status == 'pending' &&
        !a.unlocked &&
        a.searchEndsAt.isAfter(DateTime.now());
    return Scaffold(
      backgroundColor: P.page,
      body: SafeArea(
        child: Column(
          children: [
            PHeader(
              title: a == null ? 'Alerte' : 'Alerte de ${hhmm(a.receivedAt)}',
              trailing: a != null && live
                  ? PCountdownPill(
                      deadline: a.searchEndsAt,
                      onExpired: () => setState(() => _expired = true),
                    )
                  : null,
            ),
            Expanded(
              child: a == null
                  ? Center(
                      child: _error == null
                          ? const CircularProgressIndicator()
                          : Padding(
                              padding: const EdgeInsets.all(P.gutter),
                              child: PErrorRetry(
                                message: _error!,
                                onRetry: _retry,
                              ),
                            ),
                    )
                  : RefreshIndicator(
                      color: P.green,
                      onRefresh: _load,
                      child: _Details(
                        alert: a,
                        onReload: _load,
                        onPhotos: () => _alert?.photos,
                      ),
                    ),
            ),
            if (a != null)
              PBottomBar(
                children: live
                    ? [
                        PButton(
                          label: 'Ignorer',
                          style: PButtonStyle.outline,
                          busy: _busy,
                          onTap: a.responded ? null : _decline,
                        ),
                        PButton(
                          label: a.responded ? 'Modifier' : 'Répondre',
                          onTap: _busy ? null : _respond,
                        ),
                      ]
                    : [
                        PButton(
                          label: 'Retour',
                          style: PButtonStyle.outline,
                          onTap: () => Navigator.of(context).pop(),
                        ),
                      ],
              ),
          ],
        ),
      ),
    );
  }
}

class _Details extends StatelessWidget {
  const _Details({
    required this.alert,
    required this.onReload,
    required this.onPhotos,
  });

  /// Photos du détail relu (liens renouvelés).
  final List<InboxPhoto>? Function() onPhotos;
  final InboxAlert alert;
  final Future<void> Function() onReload;

  @override
  Widget build(BuildContext context) {
    final a = alert;
    final pages = a.photos.length;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(P.gutter, 4, P.gutter, 12),
      children: [
        if (!isOpenAlert(a, DateTime.now()) || a.unlocked)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: PCard(
              color: a.unlocked ? P.softGreen : P.softYellow,
              child: Text(
                a.unlocked
                    ? 'Le client a confirmé votre pharmacie : la commande est '
                          "dans l'onglet Commandes."
                    : a.responded
                    ? 'Réponse envoyée. Le client choisit sa pharmacie.'
                    : 'Alerte terminée : le délai est passé ou elle a été '
                          'ignorée.',
                style: PText.body,
              ),
            ),
          ),
        if (pages > 0) ...[
          Semantics(
            button: true,
            label:
                'Ordonnance, $pages page${pages > 1 ? 's' : ''}, toucher pour agrandir',
            excludeSemantics: true,
            child: PCard(
              padding: const EdgeInsets.all(10),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  fullscreenDialog: true,
                  builder: (_) => PrescriptionViewer(
                    photos: a.photos,
                    reload: () async {
                      await onReload();
                      return onPhotos();
                    },
                  ),
                ),
              ),
              child: Row(
                children: [
                  SizedBox.square(
                    dimension: 76,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: PrescriptionImage(
                            url: a.photos.first.url,
                            onExpired: onReload,
                          ),
                        ),
                        Positioned(
                          right: 6,
                          bottom: 6,
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.zoom_in,
                              size: 16,
                              color: P.ink,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Ordonnance · $pages page${pages > 1 ? 's' : ''}',
                          style: PText.cardTitle.copyWith(fontSize: 18),
                        ),
                        Text('Touchez pour agrandir', style: PText.bodyMuted),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (a.items.isNotEmpty || a.genericAccepted) ...[
          PCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (a.items.isNotEmpty) ...[
                  Text('Produits demandés', style: PText.label),
                  const SizedBox(height: 6),
                  for (final (i, item) in a.items.indexed) ...[
                    if (i > 0) const Divider(height: 1, color: P.line),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        children: [
                          const PIcon(Icons.medication),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(item.name, style: PText.cardTitle),
                                if (item.form.isNotEmpty)
                                  Text(item.form, style: PText.bodyMuted),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '×${item.quantity}',
                            semanticsLabel: 'quantité ${item.quantity}',
                            style: PText.cardTitle,
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
                if (a.genericAccepted) ...[
                  const SizedBox(height: 4),
                  const PPill('Générique accepté'),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (a.note.isNotEmpty) ...[
          PCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Précision du client', style: PText.label),
                const SizedBox(height: 4),
                Text('« ${a.note} »', style: PText.body.copyWith(fontSize: 17)),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ExcludeSemantics(
                child: Icon(Icons.visibility_off, size: 20, color: P.muted),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  "Client anonyme jusqu'à la confirmation · à "
                  '${formatDistance(a.distanceM)}',
                  style: PText.bodyMuted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
