import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ivia_ui/ivia_ui.dart';

/// Charte d'Ivia Business (maquettes B00 à B25) : bleu nuit, cartes blanches
/// très arrondies, barre du bas en pilule flottante, rouge réservé à
/// l'urgence. Chaque interaction répond : enfoncement, ressort, retour
/// haptique, apparitions en cascade. Tout s'arrête si le téléphone demande
/// de réduire les animations.
abstract final class Biz {
  static const navy = IviaColors.berkeleyBlue;
  static const navy2 = Color(0xFF173E6E);
  static const page = IviaColors.background;
  static const line = IviaColors.border;
  static const muted = IviaColors.textMuted;
  static const red = IviaColors.imperialRed;
  static const green = Color(0xFF1E8E55);
  static const amber = Color(0xFFB7791F);
  static const blue = IviaColors.cobaltBlue;
  static const radius = 22.0;
  static const fast = Duration(milliseconds: 180);
  static const medium = Duration(milliseconds: 320);
  static const spring = Cubic(0.34, 1.56, 0.64, 1);
  static const tabular = [FontFeature.tabularFigures()];

  static const shadow = [
    BoxShadow(color: Color(0x0F0E2E54), blurRadius: 18, offset: Offset(0, 6)),
  ];

  static bool still(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  static void tick() => unawaited(HapticFeedback.selectionClick());
}

/// Zone qui s'enfonce légèrement sous le doigt (retour haptique au tap).
class BizPressable extends StatefulWidget {
  const BizPressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = 0.97,
  });
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;

  @override
  State<BizPressable> createState() => _BizPressableState();
}

class _BizPressableState extends State<BizPressable> {
  var _down = false;

  void _set(bool v) {
    if (_down != v && mounted) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.onTap != null || widget.onLongPress != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: active ? (_) => _set(true) : null,
      onTapUp: active ? (_) => _set(false) : null,
      onTapCancel: active ? () => _set(false) : null,
      onTap: widget.onTap == null
          ? null
          : () {
              Biz.tick();
              widget.onTap!();
            },
      onLongPress: widget.onLongPress == null
          ? null
          : () {
              _set(false);
              unawaited(HapticFeedback.mediumImpact());
              widget.onLongPress!();
            },
      child: AnimatedScale(
        scale: _down && !Biz.still(context) ? widget.scale : 1,
        duration: Biz.fast,
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}

/// Carte blanche arrondie, ombre douce ; filet coloré pour l'urgence.
class BizCard extends StatelessWidget {
  const BizCard({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.border,
    this.color = Colors.white,
    this.padding = const EdgeInsets.all(16),
    this.radius = Biz.radius,
  });
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Color? border;
  final Color color;
  final EdgeInsetsGeometry padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final box = AnimatedContainer(
      duration: Biz.medium,
      curve: Curves.easeOutCubic,
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
        border: border == null ? null : Border.all(color: border!, width: 2),
        boxShadow: Biz.shadow,
      ),
      child: child,
    );
    if (onTap == null && onLongPress == null) return box;
    return BizPressable(onTap: onTap, onLongPress: onLongPress, child: box);
  }
}

/// Pastille d'état (« En vente », « Brouillon »…).
class BizBadge extends StatelessWidget {
  const BizBadge(this.label, {super.key, required this.color, this.icon});
  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.11),
      borderRadius: BorderRadius.circular(99),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
        ],
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: color, fontWeight: FontWeight.w800),
          ),
        ),
      ],
    ),
  );
}

/// Bouton en pilule (plein ou à filet), avec état « en cours ».
class BizButton extends StatelessWidget {
  const BizButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
    this.color = Biz.navy,
    this.outlined = false,
    this.height = 54,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy, outlined;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    final fg = outlined ? color : Colors.white;
    final bg = outlined
        ? Colors.white
        : enabled || busy
        ? color
        : color.withValues(alpha: 0.38);
    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      onTap: enabled ? onPressed : null,
      child: BizPressable(
        onTap: enabled ? onPressed : null,
        child: AnimatedContainer(
          duration: Biz.fast,
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(height),
            border: outlined ? Border.all(color: Biz.line, width: 1.5) : null,
            boxShadow: outlined || !enabled
                ? null
                : [
                    BoxShadow(
                      color: color.withValues(alpha: 0.28),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
          ),
          child: Center(
            child: AnimatedSwitcher(
              duration: Biz.fast,
              child: busy
                  ? SizedBox.square(
                      key: const ValueKey('busy'),
                      dimension: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: fg,
                      ),
                    )
                  : Row(
                      key: const ValueKey('label'),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (icon != null) ...[
                          Icon(icon, size: 19, color: fg),
                          const SizedBox(width: 8),
                        ],
                        Flexible(
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(
                                  color: fg,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Bouton carré arrondi à filet (filtres, affichage, retour).
class BizIconButton extends StatelessWidget {
  const BizIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.active = false,
    this.badge = false,
    this.size = 48,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool active, badge;
  final double size;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Semantics(
      container: true,
      button: true,
      label: tooltip,
      selected: active,
      excludeSemantics: true,
      onTap: onPressed,
      child: BizPressable(
        onTap: onPressed,
        scale: 0.9,
        child: AnimatedContainer(
          duration: Biz.fast,
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: active ? Biz.navy : Colors.white,
            borderRadius: BorderRadius.circular(size * 0.32),
            border: Border.all(color: active ? Biz.navy : Biz.line),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(icon, size: 21, color: active ? Colors.white : Biz.navy),
              if (badge)
                Positioned(
                  top: size * 0.22,
                  right: size * 0.22,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Biz.red,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Puce de filtre à chevron (« Catégorie ▾ ») ; pleine quand un filtre est
/// posé.
class BizFilterChip extends StatelessWidget {
  const BizFilterChip({
    super.key,
    required this.label,
    required this.onTap,
    this.active = false,
    this.icon,
    this.count,
  });
  final String label;
  final VoidCallback onTap;
  final bool active;
  final IconData? icon;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final fg = active ? Colors.white : Biz.navy;
    return Semantics(
      container: true,
      button: true,
      selected: active,
      label: count == null ? label : '$label, $count',
      excludeSemantics: true,
      onTap: onTap,
      child: BizPressable(
        onTap: onTap,
        scale: 0.94,
        child: AnimatedContainer(
          duration: Biz.medium,
          curve: Curves.easeOutCubic,
          constraints: const BoxConstraints(minHeight: 42),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: active ? Biz.navy : Colors.white,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: active ? Biz.navy : Biz.line),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 17, color: fg),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.labelLarge?.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (count != null) ...[
                const SizedBox(width: 6),
                AnimatedContainer(
                  duration: Biz.medium,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: active
                        ? Colors.white.withValues(alpha: 0.18)
                        : Biz.page,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    '$count',
                    style: t.labelSmall?.copyWith(
                      color: fg,
                      fontWeight: FontWeight.w800,
                      fontFeatures: Biz.tabular,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Bloc gris qui scintille pendant un chargement.
class BizSkeleton extends StatefulWidget {
  const BizSkeleton({super.key, this.width, this.height = 14, this.radius = 8});
  final double? width;
  final double height;
  final double radius;

  @override
  State<BizSkeleton> createState() => _BizSkeletonState();
}

class _BizSkeletonState extends State<BizSkeleton>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Biz.still(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      unawaited(_c.repeat(reverse: true));
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: AnimatedBuilder(
      animation: _c,
      builder: (_, _) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: Color.lerp(
            const Color(0xFFE6E9EF),
            const Color(0xFFF2F4F8),
            _c.value,
          ),
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    ),
  );
}

/// État vide illustré : pastille d'icône, titre, texte, action.
class BizEmpty extends StatelessWidget {
  const BizEmpty({
    super.key,
    required this.icon,
    required this.title,
    this.body,
    this.action,
    this.color = Biz.blue,
  });
  final IconData icon;
  final String title;
  final String? body;
  final Widget? action;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      child: Column(
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: Biz.still(context) ? 1 : 0.6, end: 1),
            duration: const Duration(milliseconds: 600),
            curve: Biz.spring,
            builder: (_, s, child) => Transform.scale(scale: s, child: child),
            child: Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.09),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 38, color: color),
            ),
          ),
          const SizedBox(height: 16),
          Semantics(
            liveRegion: true,
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          if (body != null) ...[
            const SizedBox(height: 6),
            Text(
              body!,
              textAlign: TextAlign.center,
              style: t.bodyMedium?.copyWith(color: Biz.muted),
            ),
          ],
          if (action != null) ...[const SizedBox(height: 18), action!],
        ],
      ),
    );
  }
}

/// Feuille du bas Ivia Business : poignée, titre centré, croix de fermeture.
Future<T?> showBizSheet<T>(
  BuildContext context, {
  required String title,
  required WidgetBuilder builder,
  bool expand = false,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.white,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
  ),
  builder: (context) {
    final t = Theme.of(context).textTheme;
    final body = Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 10),
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Biz.line,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(56, 10, 8, 6),
            child: Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      title,
                      textAlign: TextAlign.center,
                      style: t.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Fermer',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Biz.line),
          if (expand)
            Expanded(child: builder(context))
          else
            Flexible(child: builder(context)),
        ],
      ),
    );
    return expand
        ? FractionallySizedBox(heightFactor: 0.92, child: body)
        : body;
  },
);

/// Apparition en cascade : l'élément monte, grandit un peu et se révèle.
class BizReveal extends StatefulWidget {
  const BizReveal({super.key, this.index = 0, required this.child});
  final int index;
  final Widget child;

  @override
  State<BizReveal> createState() => _BizRevealState();
}

class _BizRevealState extends State<BizReveal>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(Duration(milliseconds: 45 * widget.index.clamp(0, 10)), () {
      if (mounted) unawaited(_c.forward());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (Biz.still(context)) return widget.child;
    final curved = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, 0.08),
          end: Offset.zero,
        ).animate(curved),
        child: ScaleTransition(
          scale: Tween(begin: 0.98, end: 1.0).animate(curved),
          child: widget.child,
        ),
      ),
    );
  }
}

/// Barre du bas en pilule flottante : l'onglet actif s'étire en pastille
/// bleu nuit avec son nom ; bouton « + » au centre.
class BizDock extends StatelessWidget {
  const BizDock({
    super.key,
    required this.items,
    required this.current,
    required this.onSelected,
    required this.onCreate,
    this.creating = false,
  });

  /// Quatre onglets : deux à gauche du « + », deux à droite.
  final List<BizDockItem> items;
  final int current;
  final ValueChanged<int> onSelected;
  final VoidCallback onCreate;

  /// Menu de création ouvert : le « + » tourne en croix.
  final bool creating;

  @override
  Widget build(BuildContext context) {
    final half = items.length ~/ 2;
    Widget tab(int i) => Expanded(
      flex: i == current ? 13 : 8,
      child: _DockTab(
        item: items[i],
        selected: i == current,
        onTap: () {
          Biz.tick();
          onSelected(i);
        },
      ),
    );
    return Container(
      color: Biz.page,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
          child: Container(
            height: 70,
            padding: const EdgeInsets.symmetric(horizontal: 7),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(35),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x1F0E2E54),
                  blurRadius: 28,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: Row(
              children: [
                for (var i = 0; i < half; i++) tab(i),
                _CreateButton(onTap: onCreate, open: creating),
                for (var i = half; i < items.length; i++) tab(i),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class BizDockItem {
  const BizDockItem(this.icon, this.label, {this.badge = 0, this.badgeLabel});
  final IconData icon;
  final String label;
  final int badge;

  /// Pastille lue par le lecteur d'écran (« 2 nouvelles »).
  final String? badgeLabel;
}

class _DockTab extends StatelessWidget {
  const _DockTab({
    required this.item,
    required this.selected,
    required this.onTap,
  });
  final BizDockItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final fg = selected ? Colors.white : Biz.muted;
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      label: item.badge > 0
          ? '${item.label}, ${item.badgeLabel ?? item.badge}'
          : item.label,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Center(
            child: AnimatedContainer(
              duration: Biz.medium,
              curve: Curves.easeOutCubic,
              height: 54,
              padding: EdgeInsets.symmetric(horizontal: selected ? 12 : 0),
              decoration: BoxDecoration(
                color: selected ? Biz.navy : Colors.transparent,
                borderRadius: BorderRadius.circular(27),
              ),
              // Réduit plutôt que de déborder (petit écran, grande police).
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Badge(
                      isLabelVisible: item.badge > 0,
                      backgroundColor: Biz.red,
                      label: Text('${item.badge}'),
                      child: AnimatedScale(
                        scale: selected ? 1.06 : 1,
                        duration: Biz.medium,
                        curve: Biz.spring,
                        child: Icon(item.icon, size: 24, color: fg),
                      ),
                    ),
                    // Nom visible seulement sur l'onglet actif, qui s'étire.
                    AnimatedSize(
                      duration: Biz.medium,
                      curve: Curves.easeOutCubic,
                      child: selected
                          ? Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: Text(
                                item.label,
                                maxLines: 1,
                                textScaler: MediaQuery.textScalerOf(context)
                                    .clamp(maxScaleFactor: 1.2),
                                style: t.labelLarge?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            )
                          : const SizedBox.shrink(),
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

class _CreateButton extends StatelessWidget {
  const _CreateButton({required this.onTap, required this.open});
  final VoidCallback onTap;
  final bool open;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Créer',
    child: Semantics(
      container: true,
      button: true,
      label: 'Créer',
      excludeSemantics: true,
      onTap: onTap,
      child: BizPressable(
        onTap: onTap,
        scale: 0.88,
        child: Container(
          width: 58,
          height: 50,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFF3B4C), Biz.red],
            ),
            borderRadius: BorderRadius.circular(25),
            boxShadow: [
              BoxShadow(
                color: Biz.red.withValues(alpha: 0.38),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: AnimatedRotation(
            turns: open ? 0.125 : 0,
            duration: Biz.medium,
            curve: Biz.spring,
            child: const Icon(Icons.add_rounded, color: Colors.white, size: 30),
          ),
        ),
      ),
    ),
  );
}

/// Grand titre d'onglet, sous-titre et actions à droite.
class BizHeader extends StatelessWidget {
  const BizHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing = const [],
  });
  final String title;
  final String? subtitle;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: t.headlineLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: Biz.navy,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
              if (subtitle != null && subtitle!.isNotEmpty)
                AnimatedSwitcher(
                  duration: Biz.fast,
                  child: Text(
                    subtitle!,
                    key: ValueKey(subtitle),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: t.bodyMedium?.copyWith(color: Biz.muted),
                  ),
                ),
            ],
          ),
        ),
        for (final w in trailing) ...[const SizedBox(width: 8), w],
      ],
    );
  }
}
