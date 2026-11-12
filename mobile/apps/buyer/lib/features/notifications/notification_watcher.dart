import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

/// Relève des notifications activée (désactivée par les tests d'écran).
final notificationWatchEnabledProvider = Provider<bool>((ref) => true);

/// Tant que l'app est ouverte, relit les notifications du compte et affiche les nouvelles en
/// bannière (paiement reçu, commande prête, annulation…). Complète le push du téléphone, et le
/// remplace dans un navigateur.
class NotificationWatcher extends ConsumerStatefulWidget {
  const NotificationWatcher({super.key, required this.child});

  final Widget child;

  static const interval = Duration(seconds: 20);

  @override
  ConsumerState<NotificationWatcher> createState() =>
      _NotificationWatcherState();
}

class _NotificationWatcherState extends ConsumerState<NotificationWatcher>
    with WidgetsBindingObserver {
  Timer? _timer;
  Set<String>? _known;
  var _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (ref.read(notificationWatchEnabledProvider)) {
      _timer = Timer.periodic(NotificationWatcher.interval, (_) => _poll());
      unawaited(_poll());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        ref.read(notificationWatchEnabledProvider)) {
      unawaited(_poll());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _poll() async {
    if (_busy || ref.read(authControllerProvider) is! AuthSignedIn) return;
    _busy = true;
    try {
      final items = await ref.read(apiClientProvider).notifications();
      if (!mounted) return;
      final known = _known;
      // Premier relevé : rien n'est annoncé, ces notifications existaient déjà.
      if (known != null) {
        for (final n in items.reversed) {
          if (!n.read && !known.contains(n.id)) {
            final (icon, color) = _look(n.kind);
            showIviaNotification(
              context,
              title: n.title,
              body: n.body.isEmpty ? null : n.body,
              icon: icon,
              color: color,
            );
          }
        }
      }
      _known = {...?known, for (final n in items) n.id};
    } catch (_) {
      // Réseau ou serveur indisponible : nouvel essai au prochain relevé.
    } finally {
      _busy = false;
    }
  }

  /// Icône et couleur selon le type de notification.
  (IconData, Color) _look(String kind) => switch (kind) {
    _ when kind.contains('cancel') || kind.contains('fail') => (
      Icons.cancel_outlined,
      IviaColors.error,
    ),
    _
        when kind.contains('paid') ||
            kind.contains('payment') ||
            kind.contains('refund') =>
      (Icons.payments_outlined, IviaColors.success),
    _ when kind.contains('ready') || kind.contains('delivered') => (
      Icons.check_circle_outline,
      IviaColors.success,
    ),
    _ when kind.contains('pharmacy') => (
      Icons.local_pharmacy_outlined,
      IviaColors.secondary,
    ),
    _ => (Icons.notifications_rounded, IviaColors.secondary),
  };

  @override
  Widget build(BuildContext context) => widget.child;
}
