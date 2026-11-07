import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ivia_ui/ivia_ui.dart';

/// Langage visuel d'Ivia Business : un poste de pilotage, distinct de l'app
/// client. Panneau sombre, cartes plates à filet, barre fixe, une couleur par
/// secteur, le rouge réservé à l'urgence. Animations courtes et discrètes,
/// coupées si le téléphone demande de réduire les animations.
abstract final class Pro {
  static const ink = Color(0xFF0B1B33);
  static const ink2 = Color(0xFF172A4A);
  static const page = Color(0xFFF4F6FA);
  static const line = Color(0xFFE2E6EE);
  static const muted = Color(0xFF55627A);
  static const urgent = IviaColors.imperialRed;
  static const radius = 14.0;
  static const fast = Duration(milliseconds: 160);
  static const medium = Duration(milliseconds: 280);

  static const tabular = [FontFeature.tabularFigures()];

  static Color accent(String? sector) => switch (sector) {
    'restaurant' => const Color(0xFFB9500A),
    'real_estate' => const Color(0xFF0F766E),
    'artisan' => const Color(0xFF5B3FD6),
    _ => IviaColors.cobaltBlue,
  };

  static IconData icon(String? sector) => switch (sector) {
    'restaurant' => Icons.restaurant_rounded,
    'real_estate' => Icons.apartment_rounded,
    'artisan' => Icons.handyman_rounded,
    _ => Icons.storefront_rounded,
  };

  static bool still(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;
}

/// Transition de page : léger fondu et glissement.
class ProPageTransitions extends PageTransitionsBuilder {
  const ProPageTransitions();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0.04, 0),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}

/// Apparition en cascade : l'élément monte et se révèle selon son rang.
class Reveal extends StatefulWidget {
  const Reveal({super.key, this.index = 0, required this.child});
  final int index;
  final Widget child;

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: Pro.medium);
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(Duration(milliseconds: 40 * widget.index.clamp(0, 8)), () {
      if (mounted) _c.forward();
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
    if (Pro.still(context)) return widget.child;
    final curved = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, 0.06),
          end: Offset.zero,
        ).animate(curved),
        child: widget.child,
      ),
    );
  }
}

/// Chiffre qui monte jusqu'à sa valeur.
class CountUp extends StatelessWidget {
  const CountUp({
    super.key,
    required this.value,
    required this.format,
    this.style,
  });
  final int value;
  final String Function(int) format;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final s = style?.copyWith(fontFeatures: Pro.tabular);
    if (Pro.still(context)) return Text(format(value), style: s);
    return TweenAnimationBuilder<double>(
      tween: Tween(end: value.toDouble()),
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeOutCubic,
      builder: (_, v, _) => Text(format(v.round()), style: s),
    );
  }
}

/// Point vivant : statut en cours.
class PulseDot extends StatefulWidget {
  const PulseDot({super.key, required this.color, this.size = 8});
  final Color color;
  final double size;

  @override
  State<PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<PulseDot>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Pro.still(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: widget.size * 2.4,
    child: AnimatedBuilder(
      animation: _c,
      builder: (_, _) => Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: widget.size * (1 + 1.4 * _c.value),
            height: widget.size * (1 + 1.4 * _c.value),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.color.withValues(alpha: 0.35 * (1 - _c.value)),
            ),
          ),
          Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.color,
            ),
          ),
        ],
      ),
    ),
  );
}

/// Panneau de pilotage : fond sombre, trame discrète, filet de la couleur du
/// secteur. Colle au haut de l'écran.
class ProPanel extends StatelessWidget {
  const ProPanel({super.key, required this.child, required this.accent});
  final Widget child;
  final Color accent;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    decoration: BoxDecoration(
      color: Pro.ink,
      border: Border(bottom: BorderSide(color: accent, width: 3)),
    ),
    child: CustomPaint(
      painter: const _GridPainter(),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          child: child,
        ),
      ),
    ),
  );
}

class _GridPainter extends CustomPainter {
  const _GridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final dot = Paint()..color = Colors.white.withValues(alpha: 0.05);
    for (var x = 12.0; x < size.width; x += 22) {
      for (var y = 12.0; y < size.height; y += 22) {
        canvas.drawCircle(Offset(x, y), 1, dot);
      }
    }
  }

  @override
  bool shouldRepaint(_GridPainter oldDelegate) => false;
}

/// Bandeau d'indicateurs du panneau, séparés par un filet.
class KpiStrip extends StatelessWidget {
  const KpiStrip({super.key, required this.items});
  final List<Kpi> items;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final valueStyle = t.titleLarge?.copyWith(
      color: Colors.white,
      fontWeight: FontWeight.w800,
    );
    // Grandes polices : trois colonnes étroites couperaient chaque libellé
    // sur plusieurs lignes ; une ligne par chiffre à la place.
    if (MediaQuery.textScalerOf(context).scale(10) > 13) {
      return Column(
        children: [
          for (final k in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      k.label,
                      style: t.bodySmall?.copyWith(color: Colors.white70),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: CountUp(
                        value: k.value,
                        format: k.format,
                        style: valueStyle,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
    }
    return IntrinsicHeight(
      child: Row(
        children: [
          for (final (i, k) in items.indexed) ...[
            if (i > 0)
              VerticalDivider(
                width: 25,
                thickness: 1,
                color: Colors.white.withValues(alpha: 0.14),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: CountUp(
                      value: k.value,
                      format: k.format,
                      style: valueStyle,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    k.label,
                    style: t.bodySmall?.copyWith(color: Colors.white70),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class Kpi {
  const Kpi(this.label, this.value, [this.format = _plain]);
  final String label;
  final int value;
  final String Function(int) format;
  static String _plain(int v) => '$v';
}

/// Carte plate à filet ; se creuse légèrement sous le doigt.
class ProCard extends StatefulWidget {
  const ProCard({
    super.key,
    required this.child,
    this.onTap,
    this.color = Colors.white,
    this.border,
    this.padding = const EdgeInsets.all(16),
  });
  final Widget child;
  final VoidCallback? onTap;
  final Color color;
  final Color? border;
  final EdgeInsetsGeometry padding;

  @override
  State<ProCard> createState() => _ProCardState();
}

class _ProCardState extends State<ProCard> {
  var _down = false;

  @override
  Widget build(BuildContext context) => AnimatedScale(
    scale: _down ? 0.985 : 1,
    duration: Pro.fast,
    child: Material(
      color: widget.color,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Pro.radius),
        side: BorderSide(color: widget.border ?? Pro.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onTap,
        onHighlightChanged: (v) => setState(() => _down = v),
        child: Padding(padding: widget.padding, child: widget.child),
      ),
    ),
  );
}

/// Étiquette rectangulaire.
class ProTag extends StatelessWidget {
  const ProTag(
    this.label, {
    super.key,
    required this.color,
    this.icon,
    this.solid = false,
  });
  final String label;
  final Color color;
  final IconData? icon;
  final bool solid;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: solid ? color : color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 13, color: solid ? Colors.white : color),
          const SizedBox(width: 4),
        ],
        // Grandes polices : l'étiquette rétrécit au lieu de déborder.
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: solid ? Colors.white : color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}

/// Bouton d'action, rectangulaire pour le distinguer de l'app client.
class ProButton extends StatefulWidget {
  const ProButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
    this.color = Pro.ink,
    this.outlined = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy, outlined;
  final Color color;

  @override
  State<ProButton> createState() => _ProButtonState();
}

class _ProButtonState extends State<ProButton> {
  var _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.busy;
    final fg = widget.outlined ? widget.color : Colors.white;
    final bg = widget.outlined
        ? Colors.white
        : enabled
        ? widget.color
        : widget.color.withValues(alpha: 0.4);
    return AnimatedScale(
      scale: _down ? 0.98 : 1,
      duration: Pro.fast,
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: widget.outlined
              ? const BorderSide(color: Pro.line)
              : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? widget.onPressed : null,
          onHighlightChanged: (v) => setState(() => _down = v),
          child: SizedBox(
            height: 52,
            child: Center(
              child: AnimatedSwitcher(
                duration: Pro.fast,
                child: widget.busy
                    ? SizedBox.square(
                        key: const ValueKey('busy'),
                        dimension: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: fg,
                        ),
                      )
                    : Row(
                        key: const ValueKey('label'),
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.icon != null) ...[
                            Icon(widget.icon, size: 18, color: fg),
                            const SizedBox(width: 8),
                          ],
                          Flexible(
                            child: Text(
                              widget.label,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(
                                    color: fg,
                                    fontWeight: FontWeight.w700,
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

/// Titre de section, action éventuelle à droite.
class ProSection extends StatelessWidget {
  const ProSection(this.title, {super.key, this.action, this.onAction});
  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 18, 2, 8),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        if (action != null) ...[
          const SizedBox(width: 8),
          // Grandes polices : l'action passe à la ligne au lieu de déborder.
          Flexible(
            child: GestureDetector(
              onTap: onAction,
              child: Text(
                action!,
                textAlign: TextAlign.end,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: IviaColors.cobaltBlue,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ],
    ),
  );
}

/// Page standard : barre sobre, contenu, action fixée en bas.
class ProPage extends StatelessWidget {
  const ProPage({
    super.key,
    required this.title,
    required this.children,
    this.bottom,
    this.actions,
    this.progress,
  });
  final String title;
  final List<Widget> children;
  final Widget? bottom;
  final List<Widget>? actions;

  /// Avancement du parcours (0 à 1) : filet animé sous la barre.
  final double? progress;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Pro.page,
    appBar: AppBar(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      title: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium
            ?.copyWith(fontWeight: FontWeight.w800),
      ),
      actions: actions,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(3),
        child: progress == null
            ? Container(height: 1, color: Pro.line)
            : TweenAnimationBuilder<double>(
                tween: Tween(end: progress),
                duration: Pro.medium,
                curve: Curves.easeOutCubic,
                builder: (_, v, _) => LinearProgressIndicator(
                  value: v,
                  minHeight: 3,
                  backgroundColor: Pro.line,
                  color: IviaColors.cobaltBlue,
                ),
              ),
      ),
    ),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        for (final (i, c) in children.indexed) Reveal(index: i, child: c),
      ],
    ),
    bottomNavigationBar: bottom == null
        ? null
        : Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Pro.line)),
            ),
            child: SafeArea(
              child: Padding(padding: const EdgeInsets.all(12), child: bottom),
            ),
          ),
  );
}

/// État vide, sans fausse donnée.
class ProEmpty extends StatelessWidget {
  const ProEmpty({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
  });
  final IconData icon;
  final String title, body;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ProCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 26),
      child: Column(
        children: [
          Icon(icon, size: 30, color: Pro.muted),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            body,
            textAlign: TextAlign.center,
            style: t.bodySmall?.copyWith(color: Pro.muted),
          ),
        ],
      ),
    );
  }
}

/// Barre de navigation fixe, bord à bord : un filet glisse sur l'onglet actif.
class ProDock extends StatelessWidget {
  const ProDock({
    super.key,
    required this.items,
    required this.current,
    required this.onSelected,
    required this.accent,
  });
  final List<ProDockItem> items;
  final int current;
  final ValueChanged<int> onSelected;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Pro.line)),
      ),
      child: SafeArea(
        child: SizedBox(
          height: 60,
          child: Stack(
            children: [
              AnimatedAlign(
                duration: Pro.medium,
                curve: Curves.easeOutCubic,
                alignment: Alignment(
                  items.length == 1 ? 0 : -1 + 2 * current / (items.length - 1),
                  -1,
                ),
                child: FractionallySizedBox(
                  widthFactor: 1 / items.length,
                  child: Center(
                    child: Container(
                      width: 34,
                      height: 3,
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(3),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Row(
                children: [
                  for (final (i, item) in items.indexed)
                    Expanded(
                      child: Semantics(
                        button: true,
                        selected: i == current,
                        label: item.badge > 0
                            ? '${item.label}, ${item.badgeLabel ?? item.badge}'
                            : item.label,
                        child: ExcludeSemantics(
                          child: InkWell(
                            onTap: () => onSelected(i),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Badge(
                                  isLabelVisible: item.badge > 0,
                                  backgroundColor: Pro.urgent,
                                  label: Text('${item.badge}'),
                                  child: AnimatedScale(
                                    scale: i == current ? 1.08 : 1,
                                    duration: Pro.fast,
                                    child: Icon(
                                      item.icon,
                                      size: 23,
                                      color: i == current ? accent : Pro.muted,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 3),
                                AnimatedDefaultTextStyle(
                                  duration: Pro.fast,
                                  style: (t.labelSmall ?? const TextStyle())
                                      .copyWith(
                                        color: i == current
                                            ? accent
                                            : Pro.muted,
                                        fontWeight: i == current
                                            ? FontWeight.w800
                                            : FontWeight.w500,
                                      ),
                                  // Hauteur fixe de la barre : libellé limité
                                  // à 130 % (annoncé en entier par le lecteur
                                  // d'écran), comme les barres d'onglets.
                                  child: Text(
                                    item.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textScaler: MediaQuery.textScalerOf(context)
                                        .clamp(maxScaleFactor: 1.3),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ProDockItem {
  const ProDockItem(this.icon, this.label, {this.badge = 0, this.badgeLabel});
  final IconData icon;
  final String label;
  final int badge;

  /// Pastille lue par le lecteur d'écran (« 2 nouvelles ») ; le nombre seul
  /// sinon.
  final String? badgeLabel;
}

/// Filtres à filet animé.
class ProFilter extends StatelessWidget {
  const ProFilter({
    super.key,
    required this.labels,
    required this.current,
    required this.onSelected,
    required this.accent,
  });
  final List<String> labels;
  final int current;
  final ValueChanged<int> onSelected;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Row(
      children: [
        for (final (i, l) in labels.indexed)
          Expanded(
            child: InkWell(
              onTap: () => onSelected(i),
              child: AnimatedContainer(
                duration: Pro.fast,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: i == current ? accent : Pro.line,
                      width: i == current ? 2.5 : 1,
                    ),
                  ),
                ),
                child: Text(
                  l,
                  textAlign: TextAlign.center,
                  style: t.labelLarge?.copyWith(
                    color: i == current ? accent : Pro.muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
