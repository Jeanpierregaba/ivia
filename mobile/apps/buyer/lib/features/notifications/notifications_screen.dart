import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../app/router.dart';
import 'notification_look.dart';
import 'notifications_state.dart';

/// Centre des notifications : regroupées par jour, non lues mises en avant,
/// glisser pour marquer comme lue, appui pour ouvrir la commande ou l'alerte.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  var _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      await ref.read(notificationsProvider.notifier).refresh();
      if (mounted && _failed) setState(() => _failed = false);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _open(AppNotification n) {
    ref.read(notificationsProvider.notifier).markRead(n.id);
    final d = n.data;
    final target = switch (d) {
      {'order_id': final id} => Routes.order(id),
      {'reservation_id': final id} => Routes.medReservation(id),
      {'alert_id': final id} => Routes.medAlert(id),
      _ => null,
    };
    if (target != null) context.push(target);
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(notificationsProvider);
    final unread = ref.watch(unreadNotificationsProvider);
    final t = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: IviaColors.background,
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          AnimatedSwitcher(
            duration: IviaMotion.medium,
            child: unread == 0
                ? const SizedBox.shrink()
                : TextButton(
                    onPressed: () =>
                        ref.read(notificationsProvider.notifier).markAllRead(),
                    child: const Text('Tout lire'),
                  ),
          ),
          const SizedBox(width: IviaSpacing.sm),
        ],
      ),
      body: IviaStateSwitcher(
        child: switch (items) {
          null when _failed => _Empty(
            key: const ValueKey('erreur'),
            icon: Icons.wifi_off_rounded,
            title: 'Notifications indisponibles',
            body: 'Vérifiez votre connexion, puis réessayez.',
            action: FilledButton(
              onPressed: _load,
              child: const Text('Réessayer'),
            ),
          ),
          null => const IviaListSkeleton(key: ValueKey('chargement')),
          [] => const _Empty(
            key: ValueKey('vide'),
            icon: Icons.notifications_none_rounded,
            title: 'Aucune notification',
            body: 'Paiements, commandes prêtes, réponses des pharmacies : tout arrivera ici.',
          ),
          final list => RefreshIndicator(
            key: const ValueKey('liste'),
            onRefresh: _load,
            child: IviaMaxWidth(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  IviaSpacing.screen,
                  IviaSpacing.sm,
                  IviaSpacing.screen,
                  IviaSpacing.xxl,
                ),
                children: [
                  for (final (i, entry) in _grouped(list).indexed)
                    switch (entry) {
                      String day => Padding(
                        padding: EdgeInsets.only(
                          top: i == 0 ? IviaSpacing.sm : IviaSpacing.xl,
                          bottom: IviaSpacing.sm,
                        ),
                        child: Text(
                          day,
                          style: t.titleSmall?.copyWith(
                            color: IviaColors.textSecondary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      AppNotification n => IviaReveal(
                        index: i,
                        child: _Tile(
                          key: ValueKey(n.id),
                          notification: n,
                          onTap: () => _open(n),
                          onRead: () => ref
                              .read(notificationsProvider.notifier)
                              .markRead(n.id),
                        ),
                      ),
                      _ => const SizedBox.shrink(),
                    },
                ],
              ),
            ),
          ),
        },
      ),
    );
  }

  /// Titres de jour suivis de leurs notifications.
  List<Object> _grouped(List<AppNotification> list) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    String label(DateTime d) {
      final l = d.toLocal();
      final day = DateTime(l.year, l.month, l.day);
      final diff = today.difference(day).inDays;
      if (diff <= 0) return "Aujourd'hui";
      if (diff == 1) return 'Hier';
      if (diff < 7) return 'Cette semaine';
      return 'Plus tôt';
    }

    final out = <Object>[];
    String? last;
    for (final n in list) {
      final l = label(n.createdAt);
      if (l != last) out.add(l);
      last = l;
      out.add(n);
    }
    return out;
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    super.key,
    required this.notification,
    required this.onTap,
    required this.onRead,
  });

  final AppNotification notification;
  final VoidCallback onTap, onRead;

  @override
  Widget build(BuildContext context) {
    final n = notification;
    final t = Theme.of(context).textTheme;
    final (icon, color) = notificationLook(n.kind);
    final card = AnimatedContainer(
      duration: IviaMotion.slow,
      curve: IviaMotion.standard,
      margin: const EdgeInsets.only(bottom: IviaSpacing.sm),
      decoration: BoxDecoration(
        color: n.read ? IviaColors.surface : color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(IviaRadius.large),
        border: Border.all(
          color: n.read ? IviaColors.border : color.withValues(alpha: 0.25),
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(IviaRadius.large),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(IviaSpacing.lg),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                const SizedBox(width: IviaSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              n.title,
                              style: t.titleSmall?.copyWith(
                                fontWeight: n.read
                                    ? FontWeight.w600
                                    : FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: IviaSpacing.sm),
                          Text(
                            timeOfDay(n.createdAt),
                            style: t.bodySmall?.copyWith(
                              color: IviaColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      if (n.body.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          n.body,
                          style: t.bodyMedium?.copyWith(
                            color: IviaColors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                AnimatedOpacity(
                  opacity: n.read ? 0 : 1,
                  duration: IviaMotion.medium,
                  child: Padding(
                    padding: const EdgeInsets.only(
                      left: IviaSpacing.sm,
                      top: 6,
                    ),
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (n.read) return card;
    // Glisser vers la gauche : marquée comme lue (la carte reste).
    return Dismissible(
      key: ValueKey('lire-${n.id}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        onRead();
        return false;
      },
      background: Container(
        margin: const EdgeInsets.only(bottom: IviaSpacing.sm),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: IviaSpacing.xl),
        decoration: BoxDecoration(
          color: IviaColors.success,
          borderRadius: BorderRadius.circular(IviaRadius.large),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.done_all_rounded, color: Colors.white),
            SizedBox(width: IviaSpacing.sm),
            Text(
              'Lue',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
      child: card,
    );
  }
}

/// État vide ou erreur : grande cloche qui rebondit à l'arrivée.
class _Empty extends StatelessWidget {
  const _Empty({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.action,
  });

  final IconData icon;
  final String title, body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(IviaSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 1100),
              curve: Curves.elasticOut,
              builder: (_, v, child) => Transform.translate(
                offset: Offset(0, -24 * (1 - v)),
                child: Transform.rotate(
                  angle: math.sin(v * math.pi * 3) * 0.15 * (1 - v),
                  child: child,
                ),
              ),
              child: Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: IviaColors.secondary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 48, color: IviaColors.secondary),
              ),
            ),
            const SizedBox(height: IviaSpacing.xl),
            Text(
              title,
              textAlign: TextAlign.center,
              style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: IviaSpacing.sm),
            Text(
              body,
              textAlign: TextAlign.center,
              style: t.bodyLarge?.copyWith(color: IviaColors.textSecondary),
            ),
            if (action != null) ...[
              const SizedBox(height: IviaSpacing.xl),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
