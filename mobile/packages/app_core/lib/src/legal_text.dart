import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:ivia_ui/ivia_ui.dart';

/// Morceau de [LegalText] : texte simple, ou lien vers un document légal.
class LegalPart {
  const LegalPart(this.text) : isLink = false;
  const LegalPart.link(this.text) : isLink = true;

  final String text;
  final bool isLink;
}

/// Texte avec liens vers les Conditions d'utilisation et la Politique de
/// confidentialité. Ces documents ne sont pas encore rédigés (TASKS.md) : un
/// lien affiche « Document disponible prochainement ».
class LegalText extends StatefulWidget {
  const LegalText({
    super.key,
    required this.parts,
    this.style,
    this.textAlign = TextAlign.start,
  });

  final List<LegalPart> parts;
  final TextStyle? style;
  final TextAlign textAlign;

  @override
  State<LegalText> createState() => _LegalTextState();
}

class _LegalTextState extends State<LegalText> {
  late final _recognizers = [
    for (final part in widget.parts)
      if (part.isLink) TapGestureRecognizer()..onTap = _showSoon else null,
  ];

  @override
  void dispose() {
    for (final r in _recognizers) {
      r?.dispose();
    }
    super.dispose();
  }

  void _showSoon() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('Document disponible prochainement.')),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          for (final (i, part) in widget.parts.indexed)
            TextSpan(
              text: part.text,
              recognizer: _recognizers[i],
              // Lien de l'app (Cornell ou Berkeley) : contraste de texte
              // courant.
              style: part.isLink
                  ? TextStyle(
                      color: IviaAppBrand.of(context).link,
                      fontWeight: FontWeight.w700,
                    )
                  : null,
            ),
        ],
      ),
      style: widget.style,
      textAlign: widget.textAlign,
    );
  }
}
