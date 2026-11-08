import 'package:flutter/material.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../common/ui.dart';

// Éléments communs des écrans de mission (D11 à D16).

/// « #1042 » : fin de la référence de commande.
String shortRef(String reference) {
  final digits = RegExp(r'0*(\d+)$').firstMatch(reference)?.group(1);
  return digits == null ? reference : '#$digits';
}

/// Adresse et quartier (« Rue 248, Tokoin ») ; `null` : rien de connu.
String? placeAddress(MissionPlace place) {
  final parts = [
    place.addressText,
    if (place.neighborhood.isNotEmpty &&
        !place.addressText.contains(place.neighborhood))
      place.neighborhood,
  ].where((s) => s.isNotEmpty);
  return parts.isEmpty ? null : parts.join(' · ');
}

/// Bouton rond à icône (appel, itinéraire).
class RoundButton extends StatelessWidget {
  const RoundButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.bg,
    required this.fg,
    required this.onTap,
    this.size = 48,
  });
  final IconData icon;
  final String tooltip;
  final Color bg, fg;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    // Un nœud par bouton : rôle, libellé et action pour le lecteur d'écran.
    button: true,
    label: tooltip,
    onTap: onTap,
    excludeSemantics: true,
    child: Tooltip(
      message: tooltip,
      child: Material(
        color: bg,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox.square(
            dimension: size,
            child: Icon(icon, color: fg, size: 22),
          ),
        ),
      ),
    ),
  );
}

class MTag extends StatelessWidget {
  const MTag(this.text, {super.key, this.bg = D.page, this.fg = D.label});
  final String text;
  final Color bg, fg;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(IviaRadius.pill),
    ),
    child: Text(text, style: DText.pill.copyWith(color: fg, fontSize: 13)),
  );
}

/// En-tête des étapes en page (D12, D14) : titre centré, « 1 sur 2 ».
class StepHeader extends StatelessWidget {
  const StepHeader({super.key, required this.title, required this.step});
  final String title, step;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 48,
    child: Stack(
      alignment: Alignment.center,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 72),
          child: Semantics(
            header: true,
            child: Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DText.cardTitle.copyWith(fontSize: 18),
            ),
          ),
        ),
        Positioned(
          right: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(IviaRadius.pill),
            ),
            child: MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.3,
              child: Text(
                step,
                style: DText.pill.copyWith(color: D.blue, fontSize: 13),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

/// Case à cocher d'une ligne (toute la ligne est cliquable).
class CheckRow extends StatelessWidget {
  const CheckRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Semantics(
    checked: value,
    child: InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.all(4),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: value ? D.blue : Colors.white,
                  borderRadius: BorderRadius.circular(7),
                  border: value
                      ? null
                      : Border.all(color: IviaDriverColors.checkOff, width: 2),
                ),
                child: SizedBox.square(
                  dimension: 24,
                  child: value
                      ? const Icon(
                          Icons.check_rounded,
                          color: Colors.white,
                          size: 18,
                        )
                      : null,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(label, style: DText.body.copyWith(color: D.ink)),
            ),
          ],
        ),
      ),
    ),
  );
}
