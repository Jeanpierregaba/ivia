import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:ivia_ui/ivia_ui.dart';

/// Couleurs et mesures d'Ivia Driver (maquettes D00 à D19, spec 033). Les
/// maquettes sont dessinées à 720 px de large : 1 dp = 2 px.
abstract final class D {
  static const blue = IviaDriverColors.blue;
  static const blueSoft = IviaDriverColors.blueSoft;
  static const blueOnDark = IviaDriverColors.blueOnDark;
  static const navy = IviaDriverColors.navy;
  static const page = IviaDriverColors.page;
  static const ink = IviaDriverColors.ink;
  static const label = IviaDriverColors.label;
  static const muted = IviaDriverColors.muted;
  static const line = IviaDriverColors.line;
  static const outline = IviaDriverColors.outline;
  static const night = IviaDriverColors.night;
  static const nightTile = IviaDriverColors.nightTile;
  static const nightMuted = IviaDriverColors.nightMuted;
  static const red = IviaDriverColors.red;
  static const redSoft = IviaDriverColors.redSoft;
  static const green = IviaDriverColors.green;
  static const greenSoft = IviaDriverColors.greenSoft;

  /// Marges latérales des écrans (36 px).
  static const gutter = 18.0;

  /// Coins des cartes blanches (40 px) et des cartes sombres (48 px).
  static const radius = 20.0;
  static const radiusDark = 24.0;
}

/// Styles de texte des maquettes (tailles en dp, Parkinsans).
abstract final class DText {
  /// Grand titre de page (« Des missions près de vous. »).
  static final hero = IviaTextStyles.title1.copyWith(
    fontSize: 28,
    height: 1.16,
    fontWeight: FontWeight.w800,
    color: D.ink,
  );

  /// Titre d'écran (« Devenez livreur ivia », « Missions »).
  static final heading = IviaTextStyles.title1.copyWith(
    fontSize: 26,
    height: 1.15,
    fontWeight: FontWeight.w800,
    color: D.ink,
  );
  static final cardTitle = IviaTextStyles.title3.copyWith(color: D.ink);
  static final body = IviaTextStyles.body.copyWith(color: D.label);
  static final bodyMuted = IviaTextStyles.body.copyWith(color: D.muted);
  static final small = IviaTextStyles.caption.copyWith(color: D.muted);
  static final label = IviaTextStyles.bodyStrong.copyWith(color: D.label);

  /// Surtitre en capitales espacées (« NOUVELLE MISSION »).
  static final overline = IviaTextStyles.caption.copyWith(
    fontWeight: FontWeight.w800,
    letterSpacing: 1.2,
    color: D.blue,
  );

  /// Montant en grand (« 1 200 F »).
  static final amount = IviaTextStyles.title1.copyWith(
    fontSize: 30,
    height: 1.1,
    fontWeight: FontWeight.w800,
    color: D.ink,
  );
  static final button = IviaTextStyles.button.copyWith(fontSize: 17);
  static final pill = IviaTextStyles.caption.copyWith(
    fontWeight: FontWeight.w700,
  );
}

/// Carte blanche arrondie, sans ombre.
class DCard extends StatelessWidget {
  const DCard({
    super.key,
    required this.child,
    this.onTap,
    this.color = Colors.white,
    this.padding = const EdgeInsets.all(18),
    this.radius = D.radius,
  });
  final Widget child;
  final VoidCallback? onTap;
  final Color color;
  final EdgeInsetsGeometry padding;
  final double radius;

  /// Carte sombre (chiffres du jour, code de retrait, gains).
  const DCard.dark({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(18),
  }) : color = D.night,
       radius = D.radiusDark;

  @override
  Widget build(BuildContext context) => Material(
    color: color,
    borderRadius: BorderRadius.circular(radius),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(padding: padding, child: child),
    ),
  );
}

enum DButtonStyle { filled, outline, dark }

/// Bouton pilule de 54 dp (108 px) ; désactivé : gris, texte atténué.
class DButton extends StatelessWidget {
  const DButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.style = DButtonStyle.filled,
    this.busy = false,
  });
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final DButtonStyle style;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, side) = switch (style) {
      DButtonStyle.filled => (D.blue, Colors.white, BorderSide.none),
      DButtonStyle.dark => (D.night, Colors.white, BorderSide.none),
      DButtonStyle.outline => (
        Colors.white,
        D.ink,
        const BorderSide(color: D.outline),
      ),
    };
    final enabled = onTap != null && !busy;
    return ConstrainedBox(
      constraints: const BoxConstraints(
        minHeight: 54,
        minWidth: double.infinity,
      ),
      child: TextButton(
        style: TextButton.styleFrom(
          backgroundColor: enabled || busy ? bg : IviaDriverColors.disabled,
          foregroundColor: fg,
          disabledForegroundColor: busy ? fg : D.muted,
          shape: StadiumBorder(side: enabled ? side : BorderSide.none),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          textStyle: DText.button,
        ),
        onPressed: enabled ? onTap : null,
        child: busy
            ? Semantics(
                label: 'Patientez',
                child: SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: fg),
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 20),
                    const SizedBox(width: 8),
                  ],
                  Flexible(child: Text(label, textAlign: TextAlign.center)),
                ],
              ),
      ),
    );
  }
}

/// Bouton rond blanc de 44 dp (retour, appel).
class DRound extends StatelessWidget {
  const DRound({
    super.key,
    required this.icon,
    required this.onTap,
    required this.tooltip,
    this.color = Colors.white,
    this.iconColor = D.ink,
    this.size = 44,
  });
  final IconData icon;
  final VoidCallback? onTap;
  final String tooltip;
  final Color color, iconColor;
  final double size;

  /// Retour à l'écran précédent.
  const DRound.back({super.key, required this.onTap})
    : icon = Icons.arrow_back,
      tooltip = 'Retour',
      color = Colors.white,
      iconColor = D.ink,
      size = 44;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    excludeFromSemantics: true,
    child: Semantics(
      button: true,
      label: tooltip,
      child: Material(
        color: color,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox.square(
            dimension: size,
            child: Icon(icon, color: iconColor, size: size * .5),
          ),
        ),
      ),
    ),
  );
}

/// Titre en deux couleurs (« Des missions **près de vous.** »).
class DTitle extends StatelessWidget {
  const DTitle(this.start, this.colored, {super.key, this.style});
  final String start, colored;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final base = style ?? DText.hero;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: '$start '),
          TextSpan(
            text: colored,
            style: base.copyWith(color: D.blue),
          ),
        ],
      ),
      style: base,
    );
  }
}

/// Icône sur un carré arrondi pâle (lignes de liste, en-têtes de carte).
class DIconTile extends StatelessWidget {
  const DIconTile(
    this.icon, {
    super.key,
    this.bg = D.blueSoft,
    this.fg = D.blue,
    this.size = 48,
    this.circle = false,
  });
  final IconData icon;
  final Color bg, fg;
  final double size;

  /// Pastille ronde (D09) au lieu du carré arrondi.
  final bool circle;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(circle ? size / 2 : size * .3),
      ),
      child: Icon(icon, color: fg, size: size * .5),
    ),
  );
}

/// Glissière « Glisser pour… » (60 dp) : l'action ne part qu'une fois le
/// bouton rond amené au bout ; relâché avant, il revient au départ. Un
/// lecteur d'écran l'active d'un toucher (pas de geste de glissement).
///
/// [onConfirmed] : la glissière reste au bout, avec une roue, jusqu'à la fin
/// de l'action, puis revient au départ (échec ou écran suivant).
class DSlide extends StatefulWidget {
  const DSlide({
    super.key,
    required this.label,
    required this.onConfirmed,
    this.dark = false,
  });
  final String label;

  /// `null` : glissière inactive (grisée).
  final Future<void> Function()? onConfirmed;

  /// Piste sombre et bouton bleu (étapes de mission, D11 à D13) ; sinon
  /// piste bleue et bouton blanc (passer en ligne, accepter).
  final bool dark;

  /// Part de la course à atteindre pour valider.
  static const threshold = .85;

  @override
  State<DSlide> createState() => _DSlideState();
}

class _DSlideState extends State<DSlide> {
  static const _height = 60.0;
  static const _knob = 48.0;
  static const _pad = 6.0;

  double _dx = 0;
  bool _busy = false;

  Future<void> _confirm(double max) async {
    final action = widget.onConfirmed;
    if (action == null || _busy) return;
    setState(() {
      _dx = max;
      _busy = true;
    });
    try {
      await action();
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _dx = 0;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onConfirmed != null;
    final track = !enabled
        ? IviaDriverColors.disabled
        : widget.dark
        ? D.night
        : D.blue;
    final knobColor = widget.dark ? D.blue : Colors.white;
    final arrowColor = widget.dark ? Colors.white : D.blue;
    final textColor = enabled ? Colors.white : D.muted;
    return LayoutBuilder(
      builder: (context, constraints) {
        final max = constraints.maxWidth - _knob - 2 * _pad;
        final dx = _dx.clamp(0.0, max);
        // Chevrons seulement si le libellé leur laisse la place.
        final labelStyle = DText.button.copyWith(
          color: textColor,
          fontSize: 15,
        );
        final painter = TextPainter(
          text: TextSpan(text: widget.label, style: labelStyle),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 1,
        )..layout();
        final labelWidth = painter.width;
        painter.dispose();
        final room = constraints.maxWidth - (_knob + 2 * _pad + 4) - 14;
        final chevrons = labelWidth <= room - 40;
        return Semantics(
          button: true,
          enabled: enabled && !_busy,
          label: widget.label,
          onTap: enabled ? () => _confirm(max) : null,
          excludeSemantics: true,
          child: Container(
            height: _height,
            decoration: BoxDecoration(
              color: track,
              borderRadius: BorderRadius.circular(IviaRadius.pill),
            ),
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                if (chevrons)
                  Positioned(
                    right: 16,
                    child: Row(
                      children: [
                        Icon(
                          Icons.chevron_right,
                          size: 20,
                          color: textColor.withValues(alpha: .35),
                        ),
                        Icon(
                          Icons.chevron_right,
                          size: 20,
                          color: textColor.withValues(alpha: .8),
                        ),
                      ],
                    ),
                  ),
                Positioned.fill(
                  left: _knob + 2 * _pad + 4,
                  right: chevrons ? 40 : 14,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: labelStyle,
                    ),
                  ),
                ),
                Positioned(
                  left: _pad + dx,
                  child: GestureDetector(
                    key: const Key('slide-knob'),
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragUpdate: !enabled || _busy
                        ? null
                        : (d) => setState(
                            () => _dx = (_dx + d.delta.dx).clamp(0.0, max),
                          ),
                    onHorizontalDragEnd: !enabled || _busy
                        ? null
                        : (_) {
                            if (_dx >= max * DSlide.threshold) {
                              _confirm(max);
                            } else {
                              setState(() => _dx = 0);
                            }
                          },
                    child: Container(
                      width: _knob,
                      height: _knob,
                      decoration: BoxDecoration(
                        color: enabled ? knobColor : Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: _busy
                          ? Padding(
                              padding: const EdgeInsets.all(13),
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: arrowColor,
                              ),
                            )
                          : Icon(
                              Icons.keyboard_double_arrow_right,
                              color: enabled ? arrowColor : D.muted,
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Onglet de la barre du bas.
class DTab {
  const DTab(this.label, this.icon, this.activeIcon);
  final String label;
  final IconData icon, activeIcon;
}

/// Barre du bas flottante, claire (arbitrage de la spec 033) : fond blanc,
/// onglet actif en pastille bleue avec son libellé, les autres en icône.
class DBottomNav extends StatelessWidget {
  const DBottomNav({
    super.key,
    required this.tabs,
    required this.index,
    required this.onSelect,
  });
  final List<DTab> tabs;
  final int index;
  final ValueChanged<int> onSelect;

  /// Les 4 onglets d'Ivia Driver.
  static const driverTabs = [
    DTab('Accueil', Icons.home_outlined, Icons.home_rounded),
    DTab('Missions', Icons.inventory_2_outlined, Icons.inventory_2),
    DTab('Gains', Icons.payments_outlined, Icons.payments),
    DTab('Profil', Icons.person_outline, Icons.person),
  ];

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    minimum: const EdgeInsets.only(bottom: 16),
    child: Center(
      heightFactor: 1,
      child: Container(
        key: const Key('bottom-nav'),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(IviaRadius.pill),
          boxShadow: const [
            BoxShadow(
              color: IviaDriverColors.shadow,
              blurRadius: 24,
              offset: Offset(0, 8),
            ),
          ],
        ),
        // Texte très agrandi : la barre rétrécit plutôt que de déborder.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (i, t) in tabs.indexed)
                _NavItem(tab: t, active: i == index, onTap: () => onSelect(i)),
            ],
          ),
        ),
      ),
    ),
  );
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.tab,
    required this.active,
    required this.onTap,
  });
  final DTab tab;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: active,
    label: tab.label,
    excludeSemantics: true,
    child: Material(
      color: active ? D.blue : Colors.transparent,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: AnimatedSize(
          duration: const Duration(milliseconds: 180),
          child: Container(
            height: 46,
            constraints: const BoxConstraints(minWidth: 54),
            padding: EdgeInsets.symmetric(horizontal: active ? 16 : 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  active ? tab.activeIcon : tab.icon,
                  size: 24,
                  color: active ? Colors.white : D.muted,
                ),
                if (active) ...[
                  const SizedBox(width: 8),
                  Text(
                    tab.label,
                    maxLines: 1,
                    style: DText.button.copyWith(
                      color: Colors.white,
                      fontSize: 15,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

enum DCodeStyle {
  /// Cases blanches cerclées de bleu (preuve de remise, D14).
  input,

  /// Cases sombres, chiffres blancs (code de retrait, D12).
  dark,

  /// Cases grises (présentation, D03).
  soft,
}

/// Code en cases, en affichage (lu d'un bloc par le lecteur d'écran).
class DCodeBoxes extends StatelessWidget {
  const DCodeBoxes(
    this.code, {
    super.key,
    this.length = 4,
    this.style = DCodeStyle.input,
    this.semanticLabel = 'Code',
  });
  final String code;
  final int length;
  final DCodeStyle style;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, border) = switch (style) {
      DCodeStyle.input => (Colors.white, D.ink, D.blue),
      DCodeStyle.dark => (D.nightTile, Colors.white, null),
      DCodeStyle.soft => (D.page, D.ink, null),
    };
    return Semantics(
      label: '$semanticLabel : ${code.split('').join(' ')}',
      excludeSemantics: true,
      child: Row(
        children: [
          for (var i = 0; i < length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            Expanded(
              child: Container(
                key: Key('code-box-$i'),
                constraints: const BoxConstraints(minHeight: 60),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(14),
                  border: border == null
                      ? null
                      : Border.all(color: border, width: 2.5),
                ),
                child: Text(
                  i < code.length ? code[i] : '',
                  style: DText.amount.copyWith(color: fg, fontSize: 30),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

enum DStepState { done, current, todo }

/// Étape d'une liste (« Aller à la boutique », « Dossier envoyé »).
class DStep extends StatelessWidget {
  const DStep({
    super.key,
    required this.title,
    required this.state,
    this.subtitle,
  });
  final String title;
  final String? subtitle;
  final DStepState state;

  @override
  Widget build(BuildContext context) {
    final state = switch (this.state) {
      DStepState.done => 'fait',
      DStepState.current => 'en cours',
      DStepState.todo => 'à venir',
    };
    return MergeSemantics(
      child: Semantics(
        value: state,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _StepDot(this.state),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: DText.cardTitle.copyWith(
                      color: this.state == DStepState.todo ? D.muted : D.ink,
                    ),
                  ),
                  if (subtitle case final s?) Text(s, style: DText.small),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepDot extends StatelessWidget {
  const _StepDot(this.state);
  final DStepState state;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: state == DStepState.done ? D.blue : Colors.white,
        border: state == DStepState.done
            ? null
            : Border.all(
                color: state == DStepState.current
                    ? D.blue
                    : IviaDriverColors.checkOff,
                width: 3,
              ),
      ),
      child: switch (state) {
        DStepState.done => const Icon(
          Icons.check,
          size: 16,
          color: Colors.white,
        ),
        DStepState.current => Center(
          child: Container(
            width: 10,
            height: 10,
            decoration: const BoxDecoration(
              color: D.blue,
              shape: BoxShape.circle,
            ),
          ),
        ),
        DStepState.todo => null,
      },
    ),
  );
}

/// Volet blanc posé sur la carte (D09 à D13), avec sa poignée.
class DSheet extends StatelessWidget {
  const DSheet({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
    ),
    padding: const EdgeInsets.fromLTRB(D.gutter, 10, D.gutter, 0),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 40,
            height: 5,
            decoration: BoxDecoration(
              color: D.outline,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
        const SizedBox(height: 16),
        child,
      ],
    ),
  );
}

/// Annonce un changement au lecteur d'écran (message après une glissière).
void announce(BuildContext context, String message) =>
    SemanticsService.sendAnnouncement(
      View.of(context),
      message,
      Directionality.of(context),
    );
