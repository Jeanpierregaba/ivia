import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';
import 'package:url_launcher/url_launcher.dart';

/// Composants de l'app livreur, même langage visuel que l'app acheteur
/// (cartes blanches arrondies, en-têtes bleu nuit), accent cobalt.
abstract final class W {
  static const navy = Color(0xFF111C33);
  static const page = Color(0xFFF1F2F4);
  static const accent = IviaColors.cobaltBlue;
  static const soft = Color(0xFFE5EAF3);
  static const green = Color(0xFF1E7A4C);
  static const softGreen = Color(0xFFE3F3EA);
  static const red = IviaColors.imperialRed;
  static const softRed = Color(0xFFFDE8EA);
  static const muted = Color(0xFF6B7280);
  static const radius = 28.0;
}

class WTopBar extends StatelessWidget {
  const WTopBar({
    super.key,
    required this.title,
    this.trailing,
    this.back = true,
  });
  final String title;
  final Widget? trailing;
  final bool back;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      IviaSpacing.screen,
      IviaSpacing.md,
      IviaSpacing.screen,
      IviaSpacing.md,
    ),
    child: Row(
      children: [
        if (back) ...[
          WRound(
            icon: Icons.arrow_back,
            onTap: () => context.canPop() ? context.pop() : context.go('/home'),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w800, color: W.navy),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

class WRound extends StatelessWidget {
  const WRound({
    super.key,
    required this.icon,
    required this.onTap,
    this.dark = false,
  });
  final IconData icon;
  final VoidCallback? onTap;
  final bool dark;

  @override
  Widget build(BuildContext context) => Material(
    color: dark ? W.navy : Colors.white,
    shape: const CircleBorder(),
    child: InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: SizedBox.square(
        dimension: 54,
        child: Icon(icon, color: dark ? Colors.white : W.navy),
      ),
    ),
  );
}

class WPill extends StatelessWidget {
  const WPill(this.text, {super.key, this.bg = W.soft, this.fg = W.accent});
  final String text;
  final Color bg, fg;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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

class WCard extends StatelessWidget {
  const WCard({
    super.key,
    required this.child,
    this.onTap,
    this.color = Colors.white,
    this.padding,
    this.border,
  });
  final Widget child;
  final VoidCallback? onTap;
  final Color color;
  final EdgeInsetsGeometry? padding;
  final Color? border;

  @override
  Widget build(BuildContext context) => Material(
    color: color,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(W.radius),
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

class WIcon extends StatelessWidget {
  const WIcon(
    this.icon, {
    super.key,
    this.bg = W.soft,
    this.fg = W.accent,
    this.size = 50,
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
    child: Icon(icon, color: fg, size: size * .5),
  );
}

class WButton extends StatelessWidget {
  const WButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.color = W.accent,
    this.busy = false,
  });
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final Color color;
  final bool busy;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 62,
    width: double.infinity,
    child: FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: color,
        shape: const StadiumBorder(),
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
                Text(
                  label,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
    ),
  );
}

/// Carte avec les points de la course.
class WMap extends StatelessWidget {
  const WMap({super.key, required this.points, this.zoom = 13.5});
  final List<(GeoPoint, IconData, Color)> points;
  final double zoom;

  @override
  Widget build(BuildContext context) {
    final center = points.isEmpty
        ? const GeoPoint(lat: 6.1480, lng: 1.2150)
        : points.first.$1;
    return IviaMap(
      center: center,
      zoom: zoom,
      markers: [
        for (final (i, (p, icon, color)) in points.indexed)
          IviaMapMarker(id: 'p$i', point: p, color: color, icon: icon),
      ],
    );
  }
}

Future<void> call(String phone) => launchUrl(Uri.parse('tel:$phone'));

String hhmm(DateTime d) {
  final l = d.toLocal();
  return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
}
