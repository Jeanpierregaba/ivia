import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_ui/ivia_ui.dart';

/// Composants de l'app pharmacie, d'après les maquettes F00 à F23 (spec 031).
/// Les couleurs viennent de `IviaPharmacyColors`.
abstract final class P {
  static const green = IviaPharmacyColors.green;
  static const greenDeep = IviaPharmacyColors.greenDeep;
  static const softGreen = IviaPharmacyColors.greenSoft;
  static const page = IviaPharmacyColors.page;
  static const ink = IviaPharmacyColors.ink;
  static const label = IviaPharmacyColors.label;
  static const muted = IviaPharmacyColors.muted;
  static const line = IviaPharmacyColors.line;
  static const red = IviaPharmacyColors.red;
  static const softRed = IviaPharmacyColors.redSoft;
  static const danger = IviaPharmacyColors.danger;
  static const blue = IviaPharmacyColors.blue;
  static const softBlue = IviaPharmacyColors.blueSoft;
  static const yellow = IviaPharmacyColors.warning;
  static const softYellow = IviaPharmacyColors.warningSoft;

  /// Ancien nom de l'encre, pour les écrans pas encore refaits.
  static const navy = ink;

  /// Coins des cartes.
  static const radius = 20.0;

  /// Marges latérales des écrans.
  static const gutter = 18.0;
}

/// Styles de texte des maquettes (tailles en dp, Parkinsans).
abstract final class PText {
  static final heading = IviaTextStyles.title1;
  static final header = IviaTextStyles.title3.copyWith(fontSize: 18);
  static final cardTitle = IviaTextStyles.title3;
  static final body = IviaTextStyles.body;
  static final bodyMuted = IviaTextStyles.body.copyWith(color: P.muted);
  static final small = IviaTextStyles.caption.copyWith(color: P.muted);
  static final label = IviaTextStyles.bodyStrong.copyWith(color: P.label);
  static final pill = IviaTextStyles.caption.copyWith(
    fontWeight: FontWeight.w700,
  );
  static final button = IviaTextStyles.button.copyWith(fontSize: 17);
  static final figure = IviaTextStyles.title2;
}

class PCard extends StatelessWidget {
  const PCard({
    super.key,
    required this.child,
    this.onTap,
    this.color = Colors.white,
    this.border,
    this.padding,
  });
  final Widget child;
  final VoidCallback? onTap;
  final Color color;
  final Color? border;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => Material(
    color: color,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(P.radius),
      side: border == null
          ? BorderSide.none
          : BorderSide(color: border!, width: 2),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: padding ?? const EdgeInsets.all(16),
        child: child,
      ),
    ),
  );
}

/// Pastille : étape (« 1 sur 5 »), état (« Nouvelle »), étiquette.
class PPill extends StatelessWidget {
  const PPill(
    this.text, {
    super.key,
    this.bg = P.softGreen,
    this.fg = P.green,
    this.icon,
  });
  final String text;
  final Color bg, fg;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 26),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: ShapeDecoration(color: bg, shape: const StadiumBorder()),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          ExcludeSemantics(child: Icon(icon, size: 15, color: fg)),
          const SizedBox(width: 4),
        ],
        Flexible(
          child: Text(text, style: PText.pill.copyWith(color: fg)),
        ),
      ],
    ),
  );
}

/// Icône dans une tuile pâle aux coins arrondis.
class PIcon extends StatelessWidget {
  const PIcon(
    this.icon, {
    super.key,
    this.bg = P.softGreen,
    this.fg = P.green,
    this.size = 38,
  });
  final IconData icon;
  final Color bg, fg;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(size * .32),
    ),
    child: ExcludeSemantics(
      child: Icon(icon, color: fg, size: size * .52),
    ),
  );
}

/// Aspect d'un [PButton].
enum PButtonStyle {
  /// Vert plein (action principale).
  filled,

  /// Blanc bordé de gris (« Ignorer »).
  outline,

  /// Gris pâle (« Voir »).
  soft,

  /// Rouge foncé (« Confirmer l'annulation »).
  danger,
}

/// Bouton en pilule, 54 dp. Désactivé : gris, texte atténué.
class PButton extends StatelessWidget {
  const PButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.style = PButtonStyle.filled,
    this.busy = false,
    this.height = 54,
  });
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final PButtonStyle style;
  final bool busy;
  final double height;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, side) = switch (style) {
      PButtonStyle.filled => (P.green, Colors.white, BorderSide.none),
      PButtonStyle.danger => (P.danger, Colors.white, BorderSide.none),
      PButtonStyle.soft => (P.page, P.ink, BorderSide.none),
      PButtonStyle.outline => (
        Colors.white,
        P.ink,
        const BorderSide(color: IviaPharmacyColors.outline),
      ),
    };
    final enabled = onTap != null && !busy;
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: height, minWidth: double.infinity),
      child: TextButton(
        style: TextButton.styleFrom(
          backgroundColor: enabled || busy ? bg : IviaPharmacyColors.disabled,
          foregroundColor: fg,
          disabledForegroundColor: busy ? fg : P.muted,
          shape: StadiumBorder(side: enabled ? side : BorderSide.none),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          textStyle: PText.button,
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

/// Titre de page avec une partie colorée.
class PTitle extends StatelessWidget {
  const PTitle(this.start, this.colored, {super.key});
  final String start, colored;

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      text: start,
      children: [
        TextSpan(
          text: colored,
          style: const TextStyle(color: P.green),
        ),
      ],
    ),
    style: PText.heading,
  );
}

/// Retour rond et blanc (44 dp dessinés, 48 dp à toucher).
class PBackButton extends StatelessWidget {
  const PBackButton({super.key, this.onPressed, this.icon = Icons.arrow_back});

  /// `null` : revient à l'écran précédent.
  final VoidCallback? onPressed;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: icon == Icons.close ? 'Fermer' : 'Retour',
    excludeSemantics: true,
    child: SizedBox.square(
      dimension: 48,
      child: Center(
        child: Material(
          color: Colors.white,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed ?? () => Navigator.of(context).maybePop(),
            child: SizedBox.square(
              dimension: 44,
              child: Icon(icon, color: P.ink, size: 22),
            ),
          ),
        ),
      ),
    ),
  );
}

/// En-tête : retour, titre centré, pastille éventuelle à droite.
class PHeader extends StatelessWidget {
  const PHeader({
    super.key,
    required this.title,
    this.trailing,
    this.onBack,
    this.showBack = true,
  });
  final String title;
  final Widget? trailing;
  final VoidCallback? onBack;
  final bool showBack;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(P.gutter - 2, 8, P.gutter, 8),
    child: Row(
      children: [
        if (showBack)
          PBackButton(onPressed: onBack)
        else
          const SizedBox(width: 48),
        const SizedBox(width: 8),
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: PText.header,
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Pastille bornée : le titre garde la place, même en police à 200 %.
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 48, maxWidth: 110),
          child: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.5,
            child: Align(
              alignment: Alignment.centerRight,
              widthFactor: 1,
              child: trailing,
            ),
          ),
        ),
      ],
    ),
  );
}

/// Pastille blanche d'étape (« 1 sur 5 »).
class PStepPill extends StatelessWidget {
  const PStepPill({super.key, required this.step, required this.of});
  final int step, of;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Étape $step sur $of',
    excludeSemantics: true,
    child: PPill('$step sur $of', bg: Colors.white),
  );
}

/// Boutons fixés en bas de l'écran, au-dessus de la barre du système.
/// Côte à côte (le dernier, l'action principale, plus large) ; empilés,
/// l'action principale en haut, quand le texte est très agrandi.
class PBottomBar extends StatelessWidget {
  const PBottomBar({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final stacked = MediaQuery.textScalerOf(context).scale(10) > 13;
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(P.gutter, 8, P.gutter, 10),
        child: children.length == 1
            ? children.single
            : stacked
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final (i, c) in children.reversed.indexed) ...[
                    if (i > 0) const SizedBox(height: 8),
                    c,
                  ],
                ],
              )
            : Row(
                children: [
                  for (final (i, c) in children.indexed) ...[
                    if (i > 0) const SizedBox(width: 8),
                    Expanded(flex: i == children.length - 1 ? 3 : 2, child: c),
                  ],
                ],
              ),
      ),
    );
  }
}

/// Compte à rebours rouge en pastille ; « Terminée » à zéro.
class PCountdownPill extends StatelessWidget {
  const PCountdownPill({
    super.key,
    required this.deadline,
    this.onExpired,
    this.suffix,
    this.now = DateTime.now,
  });
  final DateTime deadline;
  final VoidCallback? onExpired;

  /// Texte après le temps (« pour répondre »).
  final String? suffix;
  final DateTime Function() now;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 26),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: const ShapeDecoration(color: P.softRed, shape: StadiumBorder()),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const ExcludeSemantics(
          child: Icon(Icons.timer, size: 15, color: P.red),
        ),
        const SizedBox(width: 4),
        Flexible(
          child: IviaCountdown(
            deadline: deadline,
            now: now,
            onExpired: onExpired,
            color: P.red,
            expiredLabel: 'Terminée',
            label: suffix == null ? null : (r) => '$r $suffix',
            style: PText.pill.copyWith(fontSize: 14),
          ),
        ),
      ],
    ),
  );
}

/// Case à cocher des maquettes (22 dp, coins de 6 dp) et son libellé.
class PCheckRow extends StatelessWidget {
  const PCheckRow({
    super.key,
    required this.value,
    required this.onChanged,
    required this.label,
  });
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String label;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: Semantics(
      checked: value,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onChanged == null ? null : () => onChanged!(!value),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: value ? P.green : Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  border: value
                      ? null
                      : Border.all(
                          color: IviaPharmacyColors.checkOff,
                          width: 2,
                        ),
                ),
                child: value
                    ? const Icon(Icons.check, size: 16, color: Colors.white)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(label, style: PText.body)),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Interrupteur des maquettes : piste de 50 × 30 dp, pastille blanche.
class PSwitch extends StatelessWidget {
  const PSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.label,
    this.onColor = P.green,
  });
  final bool value;
  final ValueChanged<bool>? onChanged;

  /// Libellé pour le lecteur d'écran, si la ligne n'en donne pas.
  final String? label;
  final Color onColor;

  @override
  Widget build(BuildContext context) => Semantics(
    toggled: value,
    enabled: onChanged != null,
    label: label,
    child: GestureDetector(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      child: SizedBox(
        width: 54,
        height: 48,
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 50,
            height: 30,
            padding: const EdgeInsets.all(3),
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            decoration: ShapeDecoration(
              color: onChanged == null
                  ? IviaPharmacyColors.disabled
                  : value
                  ? onColor
                  : IviaPharmacyColors.checkOff,
              shape: const StadiumBorder(),
            ),
            child: Container(
              width: 24,
              height: 24,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// État vide d'une liste.
class PEmpty extends StatelessWidget {
  const PEmpty({super.key, required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => PCard(
    child: Row(
      children: [
        PIcon(icon, bg: P.page, fg: P.muted),
        const SizedBox(width: 14),
        Expanded(child: Text(text, style: PText.bodyMuted)),
      ],
    ),
  );
}

/// Liste illisible (réseau) : le message de l'API, puis « Tirer pour
/// réessayer ».
class PErrorRetry extends StatelessWidget {
  const PErrorRetry({super.key, required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => PCard(
    color: P.softRed,
    child: Row(
      children: [
        const ExcludeSemantics(child: Icon(Icons.wifi_off, color: P.danger)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message, style: PText.body.copyWith(color: P.danger)),
              Text('Tirer pour réessayer', style: PText.small),
            ],
          ),
        ),
      ],
    ),
  );
}

/// Message de l'erreur d'une liste ; `null` si elle a été lue.
String? errorOf(AsyncValue<Object?> value) => switch (value.error) {
  null => null,
  final ApiException e => e.message,
  _ => 'Connexion impossible. Vérifiez votre réseau.',
};

String hhmm(DateTime d) {
  final l = d.toLocal();
  return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
}

void say(BuildContext context, String message) =>
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
