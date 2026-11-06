import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_ui/ivia_ui.dart';
import 'package:url_launcher/url_launcher.dart';

/// Composants des écrans pharmacie (maquettes P01 à P14).
abstract final class Med {
  static const navy = Color(0xFF111C33);
  static const page = Color(0xFFF1F2F4);
  static const softRed = Color(0xFFFDE8EA);
  static const softBlue = Color(0xFFE5EAF3);
  static const blue = Color(0xFF1F4E9C);
  static const softYellow = Color(0xFFFCEFD5);
  static const yellow = Color(0xFF8A5A00);
  static const muted = Color(0xFF6B7280);
  static const radius = 28.0;
}

/// Barre de titre : bouton rond, titre, élément à droite (étape, minutes…).
class MedTopBar extends StatelessWidget {
  const MedTopBar({
    super.key,
    required this.title,
    this.trailing,
    this.icon = Icons.arrow_back,
    this.onBack,
    this.centered = false,
  });

  final String title;
  final Widget? trailing;
  final IconData icon;
  final VoidCallback? onBack;
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final titleText = Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: centered ? TextAlign.center : TextAlign.start,
      style: t.titleLarge?.copyWith(
        fontWeight: FontWeight.w800,
        color: Med.navy,
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        IviaSpacing.screen,
        IviaSpacing.md,
        IviaSpacing.screen,
        IviaSpacing.md,
      ),
      child: Row(
        children: [
          MedRoundButton(icon: icon, onTap: onBack ?? () => _back(context)),
          const SizedBox(width: IviaSpacing.md),
          Expanded(child: titleText),
          const SizedBox(width: IviaSpacing.md),
          trailing ?? const SizedBox(width: 56),
        ],
      ),
    );
  }
}

/// Retour : écran précédent, sinon l'accueil (écran ouvert par un lien direct
/// ou remplacé).
void _back(BuildContext context) =>
    context.canPop() ? context.pop() : context.go('/home');

class MedRoundButton extends StatelessWidget {
  const MedRoundButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    shape: const CircleBorder(),
    child: InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: SizedBox.square(
        dimension: 56,
        child: Icon(icon, color: Med.navy, semanticLabel: tooltip),
      ),
    ),
  );
}

/// Pastille (« Étape 1 sur 3 », « 17 min »).
class MedPill extends StatelessWidget {
  const MedPill(
    this.text, {
    super.key,
    this.bg = Colors.white,
    this.fg = Med.navy,
  });

  factory MedPill.minutes(Duration left) => MedPill(
    '${left.inMinutes < 1 ? 1 : left.inMinutes} min',
    bg: Med.softRed,
    fg: IviaColors.primary,
  );

  final String text;
  final Color bg, fg;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(30),
    ),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelLarge
          ?.copyWith(color: fg, fontWeight: FontWeight.w800),
    ),
  );
}

/// Carte blanche arrondie.
class MedCard extends StatelessWidget {
  const MedCard({
    super.key,
    required this.child,
    this.border,
    this.padding,
    this.onTap,
  });

  final Widget child;
  final Color? border;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(Med.radius),
      side: border == null
          ? BorderSide.none
          : BorderSide(color: border!, width: 2),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: padding ?? const EdgeInsets.all(20),
        child: child,
      ),
    ),
  );
}

/// Pictogramme sur fond pâle.
class MedIconTile extends StatelessWidget {
  const MedIconTile(
    this.icon, {
    super.key,
    this.bg = Med.softBlue,
    this.fg = Med.navy,
    this.size = 52,
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
      borderRadius: BorderRadius.circular(size * .3),
    ),
    child: Icon(icon, color: fg, size: size * .48),
  );
}

/// Bouton principal du bas d'écran.
class MedBottomButton extends StatelessWidget {
  const MedBottomButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.busy = false,
    this.secondary,
  });

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool busy;
  final Widget? secondary;

  @override
  Widget build(BuildContext context) {
    final button = SizedBox(
      height: 64,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: IviaColors.primary,
          shape: const StadiumBorder(),
          textStyle: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        onPressed: busy ? null : onTap,
        child: busy
            ? const SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[Icon(icon), const SizedBox(width: 10)],
                  Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
                ],
              ),
      ),
    );
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          IviaSpacing.screen,
          IviaSpacing.sm,
          IviaSpacing.screen,
          IviaSpacing.lg,
        ),
        child: secondary == null
            ? button
            : Row(
                children: [
                  Expanded(child: secondary!),
                  const SizedBox(width: IviaSpacing.md),
                  Expanded(child: button),
                ],
              ),
      ),
    );
  }
}

class MedOutlineButton extends StatelessWidget {
  const MedOutlineButton({super.key, required this.label, required this.onTap});
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 64,
    child: OutlinedButton(
      style: OutlinedButton.styleFrom(
        shape: const StadiumBorder(),
        backgroundColor: Colors.white,
        foregroundColor: Med.navy,
        side: const BorderSide(color: Color(0xFFD5D8DE), width: 1.5),
        textStyle: Theme.of(context).textTheme.titleMedium
            ?.copyWith(fontWeight: FontWeight.w800),
      ),
      onPressed: onTap,
      child: Text(label),
    ),
  );
}

/// Code de remise en 4 cases.
class MedCodeBoxes extends StatelessWidget {
  const MedCodeBoxes(this.code, {super.key, this.color = Med.navy});
  final String code;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (final (i, d) in code.split('').indexed) ...[
        if (i > 0) const SizedBox(width: 12),
        Expanded(
          child: Container(
            height: 78,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              d,
              style: Theme.of(context).textTheme.displaySmall
                  ?.copyWith(color: color, fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ],
    ],
  );
}

/// Photo jointe (octets locaux ou lien signé).
class MedPhoto extends StatelessWidget {
  const MedPhoto({super.key, this.bytes, this.url, this.radius = 16});
  final Uint8List? bytes;
  final String? url;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(color: const Color(0xFFE3E5E9));
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: bytes != null
          ? Image.memory(bytes!, fit: BoxFit.cover)
          : url != null
          ? Image.network(
              url!,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => placeholder,
            )
          : placeholder,
    );
  }
}

/// Carte OpenStreetMap avec des repères (pharmacies, client).
class MedMap extends StatelessWidget {
  const MedMap({
    super.key,
    required this.center,
    this.markers = const [],
    this.zoom = 14.5,
    this.me,
  });

  final GeoPoint center;
  final List<GeoPoint> markers;
  final GeoPoint? me;
  final double zoom;

  @override
  Widget build(BuildContext context) => IviaMap(
    center: center,
    zoom: zoom,
    markers: [
      for (final (i, m) in markers.indexed)
        IviaMapMarker(
          id: 'p$i',
          point: m,
          color: Med.navy,
          icon: Icons.add_box_outlined,
        ),
      if (me != null)
        IviaMapMarker(
          id: 'me',
          point: me!,
          color: IviaColors.primary,
          icon: Icons.person_pin_circle,
        ),
    ],
  );
}

/// Itinéraire dans l'application de cartes du téléphone.
Future<void> openDirections(GeoPoint to) => launchUrl(
  Uri.parse(
    'https://www.google.com/maps/dir/?api=1&destination=${to.lat},${to.lng}',
  ),
  mode: LaunchMode.externalApplication,
);

Future<void> callNumber(String phone) => launchUrl(Uri.parse('tel:$phone'));

String hhmm(DateTime d) {
  final l = d.toLocal();
  return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
}

String agoLabel(DateTime d, DateTime now) {
  final m = now.difference(d).inMinutes;
  return m < 1 ? "à l'instant" : 'il y a $m min';
}

/// Fond de page des écrans pharmacie.
class MedScaffold extends ConsumerWidget {
  const MedScaffold({
    super.key,
    required this.top,
    required this.body,
    this.bottom,
    this.background = Med.page,
  });

  final Widget top;
  final Widget body;
  final Widget? bottom;
  final Color background;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    backgroundColor: background,
    body: SafeArea(
      bottom: false,
      child: Column(
        children: [
          top,
          Expanded(child: body),
        ],
      ),
    ),
    // Bas d'écran à la hauteur de son contenu, jamais de tout l'écran.
    bottomNavigationBar: bottom == null
        ? null
        : Column(mainAxisSize: MainAxisSize.min, children: [bottom!]),
  );
}
