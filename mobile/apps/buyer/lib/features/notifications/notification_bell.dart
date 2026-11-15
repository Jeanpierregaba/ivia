import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../app/router.dart';
import 'notifications_state.dart';

/// Cloche de l'accueil : pastille du nombre de notifications non lues, et la
/// cloche se balance quand une nouvelle arrive.
class NotificationBell extends ConsumerStatefulWidget {
  const NotificationBell({super.key});

  @override
  ConsumerState<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends ConsumerState<NotificationBell>
    with SingleTickerProviderStateMixin {
  late final _ring = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void dispose() {
    _ring.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final count = ref.watch(unreadNotificationsProvider);
    ref.listen(unreadNotificationsProvider, (before, now) {
      if (now > (before ?? 0) && !IviaMotion.reduced(context)) {
        _ring.forward(from: 0);
      }
    });
    void open() => context.push(Routes.notifications);
    return Semantics(
      button: true,
      label: count == 0
          ? 'Notifications'
          : 'Notifications, $count non lue${count > 1 ? 's' : ''}',
      excludeSemantics: true,
      onTap: open,
      child: Tooltip(
        message: 'Notifications',
        child: IviaPressable(
          child: Material(
            color: IviaColors.surface,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: open,
              child: SizedBox.square(
                dimension: 60,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    AnimatedBuilder(
                      animation: _ring,
                      builder: (context, child) {
                        // Balancement amorti, pivot en haut de la cloche.
                        final t = _ring.value;
                        final angle =
                            math.sin(t * math.pi * 6) * 0.45 * (1 - t);
                        return Transform.rotate(
                          angle: angle,
                          alignment: Alignment.topCenter,
                          child: child,
                        );
                      },
                      child: Icon(
                        count > 0
                            ? Icons.notifications_active_outlined
                            : Icons.notifications_none_rounded,
                        color: const Color(0xFF111C33),
                        size: 28,
                      ),
                    ),
                    Positioned(
                      right: 2,
                      top: 2,
                      child: AnimatedScale(
                        scale: count > 0 ? 1 : 0,
                        duration: IviaMotion.of(context, IviaMotion.slow),
                        curve: Curves.elasticOut,
                        child: Container(
                          constraints: const BoxConstraints(
                            minWidth: 24,
                            minHeight: 24,
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: IviaColors.imperialRed,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: AnimatedSwitcher(
                            duration: IviaMotion.of(context, IviaMotion.medium),
                            transitionBuilder: (child, a) => ScaleTransition(
                              scale: CurvedAnimation(
                                parent: a,
                                curve: Curves.easeOutBack,
                              ),
                              child: child,
                            ),
                            child: Text(
                              count > 99 ? '99+' : '$count',
                              key: ValueKey(count),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
