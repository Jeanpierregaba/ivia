import 'package:flutter/material.dart';
import 'package:ivia_ui/ivia_ui.dart';

/// Composants de l'app pharmacie : même langage visuel que l'acheteur,
/// accent vert pharmacie.
abstract final class P {
  static const navy = Color(0xFF111C33);
  static const page = Color(0xFFF1F2F4);
  static const green = IviaColors.success;
  static const softGreen = Color(0xFFE3F3EA);
  static const red = IviaColors.imperialRed;
  static const softRed = Color(0xFFFDE8EA);
  static const blue = Color(0xFF1F4E9C);
  static const softBlue = Color(0xFFE5EAF3);
  static const yellow = Color(0xFF8A5A00);
  static const softYellow = Color(0xFFFCEFD5);
  static const muted = Color(0xFF6B7280);
  static const radius = 28.0;
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
        padding: padding ?? const EdgeInsets.all(20),
        child: child,
      ),
    ),
  );
}

class PPill extends StatelessWidget {
  const PPill(this.text, {super.key, this.bg = P.softGreen, this.fg = P.green});
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

class PIcon extends StatelessWidget {
  const PIcon(
    this.icon, {
    super.key,
    this.bg = P.softGreen,
    this.fg = P.green,
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

class PButton extends StatelessWidget {
  const PButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.color = P.green,
    this.busy = false,
  });
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final Color color;
  final bool busy;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 60,
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
    style: Theme.of(context).textTheme.headlineMedium
        ?.copyWith(fontWeight: FontWeight.w800),
  );
}

String hhmm(DateTime d) {
  final l = d.toLocal();
  return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
}

void say(BuildContext context, String message) =>
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
