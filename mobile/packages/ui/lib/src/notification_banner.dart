import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'motion.dart';
import 'tokens.dart';

/// Ton d'une notification : couleur et icône par défaut.
enum IviaNoticeTone {
  success(Color(0xFF1E8E55), Icons.check_circle_rounded),
  error(IviaColors.imperialRed, Icons.error_rounded),
  info(IviaColors.berkeleyBlue, Icons.notifications_rounded);

  const IviaNoticeTone(this.color, this.icon);
  final Color color;
  final IconData icon;

  /// Ton déduit d'un message : un échec ou un refus en rouge, sinon un succès.
  static IviaNoticeTone of(String message) {
    final m = message.toLowerCase();
    const bad = [
      'impossible',
      'erreur',
      'échec',
      'echec',
      'pas de connexion',
      'vérifiez',
      'non actualis',
      'non chargé',
      'refus',
      'introuvable',
      'trop ',
      'ajoutez au moins',
      'indisponible',
      'expiré',
      'invalide',
      'déjà ',
    ];
    return bad.any(m.contains) ? IviaNoticeTone.error : IviaNoticeTone.success;
  }
}

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
  String? actionLabel,
  VoidCallback? onAction,
}) {
  final data = _Notice(
    title: title,
    body: body,
    icon: icon,
    color: color,
    onTap: onTap,
    visibleFor: visibleFor,
    actionLabel: actionLabel,
    onAction: onAction,
  );
  if (_IviaNotificationHostState._active case final host? when host.mounted) {
    host._show(data);
    return;
  }
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay != null) _showOn(overlay, data);
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
  final data = _Notice(
    title: title,
    body: body,
    icon: icon,
    color: color,
    onTap: onTap,
    visibleFor: visibleFor,
  );
  if (_IviaNotificationHostState._active case final host? when host.mounted) {
    host._show(data);
    return;
  }
  _showOn(overlay, data);
}

/// Message court (confirmation, erreur) en notification ; [tone] déduit du texte s'il est absent.
/// Sans hôte (tests d'un widget isolé), rien n'est affiché.
bool showIviaToast(
  String message, {
  IviaNoticeTone? tone,
  String? actionLabel,
  VoidCallback? onAction,
  Duration? visibleFor,
}) {
  final host = _IviaNotificationHostState._active;
  if (host == null || !host.mounted) return false;
  final t = tone ?? IviaNoticeTone.of(message);
  host._show(
    _Notice(
      title: message,
      icon: t.icon,
      color: t.color,
      compact: true,
      visibleFor: visibleFor ?? Duration(seconds: actionLabel == null ? 4 : 6),
      actionLabel: actionLabel,
      onAction: onAction,
    ),
  );
  return true;
}

OverlayEntry? _overlayEntry;

void _showOn(OverlayState overlay, _Notice data) {
  if (!overlay.mounted) return;
  if (_overlayEntry case final old? when old.mounted) old.remove();
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _NotificationBanner(
      data: data,
      onClosed: () {
        if (_overlayEntry == entry) _overlayEntry = null;
        if (entry.mounted) entry.remove();
      },
    ),
  );
  _overlayEntry = entry;
  overlay.insert(entry);
  unawaited(HapticFeedback.lightImpact());
}

class _Notice {
  _Notice({
    required this.title,
    this.body,
    required this.icon,
    required this.color,
    this.onTap,
    required this.visibleFor,
    this.actionLabel,
    this.onAction,
    this.compact = false,
  });

  final String title;
  final String? body;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final Duration visibleFor;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Message court : pas de « maintenant », texte sur deux lignes.
  final bool compact;
  final key = UniqueKey();
}

/// Couche des notifications de l'app, au-dessus de toutes les pages (feuilles et fenêtres
/// comprises). À placer une fois, dans le `builder` de l'app ([IviaResponsiveFrame] le fait).
class IviaNotificationHost extends StatefulWidget {
  const IviaNotificationHost({super.key, required this.child});
  final Widget child;

  @override
  State<IviaNotificationHost> createState() => _IviaNotificationHostState();
}

class _IviaNotificationHostState extends State<IviaNotificationHost> {
  static _IviaNotificationHostState? _active;
  _Notice? _current;

  @override
  void initState() {
    super.initState();
    _active = this;
  }

  @override
  void dispose() {
    if (_active == this) _active = null;
    super.dispose();
  }

  void _show(_Notice n) {
    setState(() => _current = n);
    unawaited(HapticFeedback.lightImpact());
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      widget.child,
      if (_current case final n?)
        _NotificationBanner(
          key: n.key,
          data: n,
          onClosed: () {
            if (mounted && _current == n) setState(() => _current = null);
          },
        ),
    ],
  );
}

/// Gestionnaire des messages de l'app : chaque `showSnackBar` (texte, action éventuelle) devient
/// une notification en haut de l'écran, au lieu du bandeau du bas.
class IviaMessenger extends ScaffoldMessenger {
  const IviaMessenger({super.key, required super.child});

  @override
  ScaffoldMessengerState createState() => _IviaMessengerState();
}

class _IviaMessengerState extends ScaffoldMessengerState {
  @override
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showSnackBar(
    SnackBar snackBar, {
    AnimationStyle? snackBarAnimationStyle,
  }) {
    final text = switch (snackBar.content) {
      final Text t => t.data ?? t.textSpan?.toPlainText(),
      _ => null,
    };
    final action = snackBar.action;
    if (text == null ||
        !showIviaToast(
          text,
          actionLabel: action?.label,
          onAction: action?.onPressed,
        )) {
      return super.showSnackBar(
        snackBar,
        snackBarAnimationStyle: snackBarAnimationStyle,
      );
    }
    // Bandeau du bas remplacé : un bandeau vide et invisible garde le contrat de l'API.
    return super.showSnackBar(
      const SnackBar(
        content: SizedBox.shrink(),
        duration: Duration(milliseconds: 1),
        backgroundColor: Colors.transparent,
        elevation: 0,
        padding: EdgeInsets.zero,
      ),
      snackBarAnimationStyle: AnimationStyle.noAnimation,
    );
  }
}

class _NotificationBanner extends StatefulWidget {
  const _NotificationBanner({
    super.key,
    required this.data,
    required this.onClosed,
  });

  final _Notice data;
  final VoidCallback onClosed;

  @override
  State<_NotificationBanner> createState() => _NotificationBannerState();
}

class _NotificationBannerState extends State<_NotificationBanner>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 460),
    reverseDuration: const Duration(milliseconds: 260),
  );

  Timer? _timer;
  var _closing = false;

  @override
  void initState() {
    super.initState();
    unawaited(_c.forward());
    _timer = Timer(widget.data.visibleFor, _close);
  }

  Future<void> _close() async {
    if (_closing || !mounted) return;
    _closing = true;
    _timer?.cancel();
    await _c.reverse();
    if (mounted) widget.onClosed();
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
    final d = widget.data;
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
                      d.onTap?.call();
                      _close();
                    },
                    onVerticalDragEnd: (e) {
                      if ((e.primaryVelocity ?? 0) < -100) _close();
                    },
                    child: Semantics(
                      liveRegion: true,
                      container: true,
                      child: Material(
                        color: Colors.white,
                        elevation: 14,
                        shadowColor: const Color(0x400E2E54),
                        borderRadius: BorderRadius.circular(22),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                12,
                                12,
                                12,
                                10,
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 42,
                                    height: 42,
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: [
                                          Color.lerp(
                                            d.color,
                                            Colors.white,
                                            0.25,
                                          )!,
                                          d.color,
                                        ],
                                      ),
                                      borderRadius: BorderRadius.circular(14),
                                      boxShadow: [
                                        BoxShadow(
                                          color: d.color.withValues(alpha: 0.3),
                                          blurRadius: 10,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: Icon(
                                      d.icon,
                                      color: Colors.white,
                                      size: 22,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          d.title,
                                          maxLines: d.compact ? 3 : 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: t.titleSmall?.copyWith(
                                            fontWeight: FontWeight.w700,
                                            color: IviaColors.text,
                                          ),
                                        ),
                                        if (d.body case final body?) ...[
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
                                  if (d.actionLabel case final label?) ...[
                                    const SizedBox(width: 8),
                                    TextButton(
                                      onPressed: () {
                                        d.onAction?.call();
                                        _close();
                                      },
                                      style: TextButton.styleFrom(
                                        backgroundColor: d.color.withValues(
                                          alpha: 0.1,
                                        ),
                                        foregroundColor: d.color,
                                        shape: const StadiumBorder(),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                        ),
                                        textStyle: t.labelLarge?.copyWith(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      child: Text(label),
                                    ),
                                  ] else if (!d.compact) ...[
                                    const SizedBox(width: 8),
                                    Text(
                                      'maintenant',
                                      style: t.labelSmall?.copyWith(
                                        color: IviaColors.textMuted,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            // Liseré de la couleur du message.
                            Container(
                              height: 3,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    d.color,
                                    d.color.withValues(alpha: 0.15),
                                  ],
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
            ),
          ),
        ),
      ),
    );
  }
}
