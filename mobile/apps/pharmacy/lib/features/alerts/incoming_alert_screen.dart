import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../common/providers.dart';
import '../../common/ui.dart';
import 'alert_logic.dart';

/// Chemin de l'alerte entrante (F10) et du détail (F11).
String incomingAlertPath(String id) => '/home/incoming/$id';
String alertDetailPath(String id) => '/home/alert/$id';

/// Alertes déjà montrées en plein écran sur ce lancement : une alerte ne
/// s'ouvre qu'une fois, qu'elle arrive par le push ou par la relecture.
final incomingShownProvider = NotifierProvider<IncomingShown, Set<String>>(
  IncomingShown.new,
);

class IncomingShown extends Notifier<Set<String>> {
  @override
  Set<String> build() => {};

  /// `true` si l'alerte n'avait pas encore été montrée.
  bool markShown(String id) {
    if (state.contains(id)) return false;
    state = {...state, id};
    return true;
  }
}

/// Alerte entrante (F10) : plein écran vert foncé, « Voir l'alerte » ouvre le
/// détail, « Ignorer » refuse l'alerte. Ouverte depuis le push ou quand une
/// alerte arrive app ouverte.
class IncomingAlertScreen extends ConsumerStatefulWidget {
  const IncomingAlertScreen({super.key, required this.alertId});
  final String alertId;

  @override
  ConsumerState<IncomingAlertScreen> createState() =>
      _IncomingAlertScreenState();
}

class _IncomingAlertScreenState extends ConsumerState<IncomingAlertScreen> {
  var _busy = false;
  var _expired = false;

  /// Relecture de la boîte en cours : une alerte arrivée par le push n'est
  /// peut-être pas encore dans la liste.
  var _refreshing = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      ref.read(incomingShownProvider.notifier).markShown(widget.alertId);
      ref.invalidate(inboxProvider);
      try {
        await ref.read(inboxProvider.future);
      } on Object {
        // Réseau : l'écran dit ce qu'il sait.
      }
      if (mounted) setState(() => _refreshing = false);
    });
  }

  void _close() => context.canPop() ? context.pop() : context.go('/home');

  Future<void> _ignore() async {
    setState(() => _busy = true);
    try {
      await ref.read(apiClientProvider).pharmacyDecline(widget.alertId);
      ref.invalidate(inboxProvider);
      if (mounted) _close();
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        say(context, e.message);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final inbox = ref.watch(inboxProvider);
    final alert = inbox.value
        ?.where((a) => a.alertId == widget.alertId)
        .firstOrNull;
    final live =
        alert != null && !_expired && isOpenAlert(alert, DateTime.now());
    final Widget content;
    if (alert == null && (_refreshing || inbox.isLoading)) {
      content = const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    } else {
      content = _Body(
        alert: alert,
        live: live,
        busy: _busy,
        onExpired: () => setState(() => _expired = true),
        onView: () => context.pushReplacement(alertDetailPath(widget.alertId)),
        onIgnore: _ignore,
        onClose: _close,
      );
    }
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: P.greenDeep,
        body: SafeArea(child: content),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.alert,
    required this.live,
    required this.busy,
    required this.onExpired,
    required this.onView,
    required this.onIgnore,
    required this.onClose,
  });

  final InboxAlert? alert;
  final bool live, busy;
  final VoidCallback onExpired, onView, onIgnore, onClose;

  @override
  Widget build(BuildContext context) {
    final a = alert;
    final n = a?.items.length ?? 0;
    final title = a == null
        ? 'Alerte terminée'
        : n == 0
        ? 'Ordonnance en photo'
        : '$n produit${n > 1 ? 's' : ''} demandé${n > 1 ? 's' : ''}';
    final detail = a == null
        ? null
        : [
            'Client à ${formatDistance(a.distanceM)}',
            if (a.photoCount > 0 && n > 0) 'ordonnance jointe',
          ].join(' · ');
    const muted = IviaPharmacyColors.onGreenMuted;
    return Column(
      children: [
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: P.gutter),
              child: Column(
                children: [
                  const ExcludeSemantics(child: _Bell()),
                  const SizedBox(height: 30),
                  Text(
                    'ALERTE MÉDICAMENT',
                    textAlign: TextAlign.center,
                    style: IviaTextStyles.overline.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: muted,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Semantics(
                    header: true,
                    liveRegion: true,
                    child: Text(
                      title,
                      textAlign: TextAlign.center,
                      style: PText.heading.copyWith(
                        color: Colors.white,
                        fontSize: 30,
                      ),
                    ),
                  ),
                  if (detail != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      detail,
                      textAlign: TextAlign.center,
                      style: PText.body.copyWith(color: muted, fontSize: 16),
                    ),
                  ],
                  const SizedBox(height: 22),
                  if (a != null && live)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 5,
                      ),
                      decoration: const ShapeDecoration(
                        color: Colors.white,
                        shape: StadiumBorder(),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const ExcludeSemantics(
                            child: Icon(Icons.timer, size: 16, color: P.red),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: IviaCountdown(
                              deadline: a.searchEndsAt,
                              now: DateTime.now,
                              color: P.red,
                              onExpired: onExpired,
                              expiredLabel: 'Terminée',
                              label: (r) => '$r pour répondre',
                              style: PText.pill.copyWith(fontSize: 14),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Text(
                      a == null
                          ? "Cette alerte n'est plus disponible."
                          : 'Alerte terminée : le délai est passé ou une '
                                'réponse a déjà été envoyée.',
                      textAlign: TextAlign.center,
                      style: PText.body.copyWith(color: muted),
                    ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(P.gutter, 8, P.gutter, 12),
          child: Column(
            children: [
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: busy ? null : (live ? onView : onClose),
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: P.greenDeep,
                    disabledBackgroundColor: Colors.white70,
                    minimumSize: const Size.fromHeight(54),
                    shape: const StadiumBorder(),
                    textStyle: PText.button,
                  ),
                  child: Text(live ? "Voir l'alerte" : 'Fermer'),
                ),
              ),
              if (live) ...[
                const SizedBox(height: 6),
                TextButton(
                  onPressed: busy ? null : onIgnore,
                  style: TextButton.styleFrom(
                    foregroundColor: muted,
                    minimumSize: const Size(120, 48),
                    textStyle: PText.button,
                  ),
                  child: busy
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Ignorer'),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Cloche rouge dans trois cercles.
class _Bell extends StatelessWidget {
  const _Bell();

  @override
  Widget build(BuildContext context) => Container(
    width: 180,
    height: 180,
    alignment: Alignment.center,
    decoration: const BoxDecoration(
      color: IviaPharmacyColors.ringOuter,
      shape: BoxShape.circle,
    ),
    child: Container(
      width: 128,
      height: 128,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: IviaPharmacyColors.ringInner,
        shape: BoxShape.circle,
      ),
      child: Container(
        width: 92,
        height: 92,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.notifications_active, size: 40, color: P.red),
      ),
    ),
  );
}
