import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'motion.dart';
import 'tokens.dart';

/// Notification affichée dans l'app : bannière qui descend du haut de l'écran, comme une
/// notification du téléphone, puis repart seule après quelques secondes (ou d'un glissement vers
/// le haut). Une seule à la fois.
void showIviaNotification(
  BuildContext context, {
  required String title,
  String? body,
  IconData icon = Icons.notifications_rounded,
  Color color = IviaColors.secondary,
  VoidCallback? onTap,
  Duration visibleFor = const Duration(seconds: 4),
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  showIviaNotificationOn(
    overlay,
    title: title,
    body: body,
    icon: icon,
    color: color,
    onTap: onTap,
    visibleFor: visibleFor,
  );
}

/// Même bannière sur une couche lue avant une attente (`Overlay.of(context, rootOverlay: true)`) :
/// elle s'affiche même si l'écran a été quitté entre-temps.
void showIviaNotificationOn(
  OverlayState overlay, {
  required String title,
  String? body,
  IconData icon = Icons.notifications_rounded,
  Color color = IviaColors.secondary,
  VoidCallback? onTap,
  Duration visibleFor = const Duration(seconds: 4),
}) {
  if (!overlay.mounted) return;
  _current?.remove();
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _NotificationBanner(
      title: title,
      body: body,
      icon: icon,
      color: color,
      onTap: onTap,
      visibleFor: visibleFor,
      onClosed: () {
        if (_current == entry) _current = null;
        if (entry.mounted) entry.remove();
      },
    ),
  );
  _current = entry;
  overlay.insert(entry);
  HapticFeedback.lightImpact();
}

OverlayEntry? _current;

class _NotificationBanner extends StatefulWidget {
  const _NotificationBanner({
    required this.title,
    required this.body,
    required this.icon,
    required this.color,
    required this.onTap,
    required this.visibleFor,
    required this.onClosed,
  });

  final String title;
  final String? body;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final Duration visibleFor;
  final VoidCallback onClosed;

  @override
  State<_NotificationBanner> createState() => _NotificationBannerState();
}

class _NotificationBannerState extends State<_NotificationBanner>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
    reverseDuration: const Duration(milliseconds: 260),
  );
  Timer? _timer;
  var _closing = false;

  @override
  void initState() {
    super.initState();
    _c.forward();
    _timer = Timer(widget.visibleFor, _close);
  }

  Future<void> _close() async {
    if (_closing || !mounted) return;
    _closing = true;
    _timer?.cancel();
    await _c.reverse();
    widget.onClosed();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final reduced = IviaMotion.reduced(context);
    final slide = CurvedAnimation(
      parent: _c,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeInCubic,
    );
    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      child: SafeArea(
        bottom: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                IviaSpacing.md,
                IviaSpacing.sm,
                IviaSpacing.md,
                0,
              ),
              child: FadeTransition(
                opacity: _c,
                child: SlideTransition(
                  position: Tween(
                    begin: reduced ? Offset.zero : const Offset(0, -1.2),
                    end: Offset.zero,
                  ).animate(slide),
                  child: GestureDetector(
                    onTap: () {
                      widget.onTap?.call();
                      _close();
                    },
                    onVerticalDragEnd: (d) {
                      if ((d.primaryVelocity ?? 0) < -100) _close();
                    },
                    child: Semantics(
                      liveRegion: true,
                      child: Material(
                        color: IviaColors.surface,
                        elevation: 10,
                        shadowColor: const Color(0x330E2E54),
                        borderRadius: BorderRadius.circular(20),
                        child: Padding(
                          padding: const EdgeInsets.all(IviaSpacing.md),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: widget.color.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  widget.icon,
                                  color: widget.color,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: IviaSpacing.md),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            widget.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: t.titleSmall?.copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: IviaSpacing.sm),
                                        Text(
                                          'maintenant',
                                          style: t.labelSmall?.copyWith(
                                            color: IviaColors.textMuted,
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (widget.body case final body?) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        body,
                                        maxLines: 3,
                                        overflow: TextOverflow.ellipsis,
                                        style: t.bodyMedium?.copyWith(
                                          color: IviaColors.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
