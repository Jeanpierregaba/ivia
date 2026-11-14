import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'brand.dart';
import 'tokens.dart';
import 'typography.dart';

/// Saisie d'un code à N chiffres affiché en cases.
///
/// Un seul champ invisible porte la saisie : le collage d'un code entier,
/// l'effacement arrière et le remplissage automatique (`oneTimeCode`)
/// fonctionnent comme dans un champ ordinaire. Les cases ne font qu'afficher.
class IviaCodeInput extends StatefulWidget {
  const IviaCodeInput({
    super.key,
    required this.controller,
    this.focusNode,
    this.length = 6,
    this.hasError = false,
    this.enabled = true,
    this.autofocus = false,
    this.onCompleted,
    this.semanticLabel = 'Code à 6 chiffres',
    this.autofill = true,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final int length;

  /// Cases encadrées en rouge (code refusé).
  final bool hasError;
  final bool enabled;
  final bool autofocus;

  /// Appelé quand tous les chiffres sont saisis.
  final ValueChanged<String>? onCompleted;
  final String semanticLabel;

  /// Remplissage automatique d'un code reçu par SMS ou e-mail. Désactivé
  /// pour un code donné de vive voix (code de remise) : le téléphone
  /// proposerait un code reçu par le marchand.
  final bool autofill;

  @override
  State<IviaCodeInput> createState() => _IviaCodeInputState();
}

class _IviaCodeInputState extends State<IviaCodeInput> {
  FocusNode? _ownFocusNode;
  late String _text = widget.controller.text;

  FocusNode get _focusNode =>
      widget.focusNode ?? (_ownFocusNode ??= FocusNode());

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
    _focusNode.addListener(_rebuild);
  }

  @override
  void didUpdateWidget(IviaCodeInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onChanged);
      widget.controller.addListener(_onChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    _focusNode.removeListener(_rebuild);
    _ownFocusNode?.dispose();
    super.dispose();
  }

  void _rebuild() => setState(() {});

  // Le contrôleur notifie aussi les déplacements du curseur : on ne réagit
  // qu'aux changements du texte.
  void _onChanged() {
    final code = widget.controller.text;
    if (code == _text) return;
    setState(() => _text = code);
    if (code.length == widget.length) widget.onCompleted?.call(code);
  }

  @override
  Widget build(BuildContext context) {
    final code = widget.controller.text;
    final focused = _focusNode.hasFocus;
    return Stack(
      children: [
        ExcludeSemantics(
          child: Row(
            children: [
              for (var i = 0; i < widget.length; i++) ...[
                if (i > 0) const SizedBox(width: IviaSpacing.sm),
                Expanded(
                  child: _Box(
                    digit: i < code.length ? code[i] : null,
                    active:
                        focused && i == code.length.clamp(0, widget.length - 1),
                    hasError: widget.hasError,
                  ),
                ),
              ],
            ],
          ),
        ),
        // Champ réel, transparent, posé sur les cases.
        Positioned.fill(
          child: Semantics(
            label: widget.semanticLabel,
            child: TextField(
              controller: widget.controller,
              focusNode: _focusNode,
              enabled: widget.enabled,
              autofocus: widget.autofocus,
              keyboardType: TextInputType.number,
              autofillHints: widget.autofill
                  ? const [AutofillHints.oneTimeCode]
                  : null,
              enableIMEPersonalizedLearning: false,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(widget.length),
              ],
              showCursor: false,
              style: const TextStyle(color: Colors.transparent, fontSize: 1),
              decoration: const InputDecoration(
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                filled: false,
                contentPadding: EdgeInsets.zero,
                counterText: '',
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Box extends StatelessWidget {
  const _Box({
    required this.digit,
    required this.active,
    required this.hasError,
  });

  final String? digit;
  final bool active;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    final borderColor = hasError
        ? IviaColors.error
        : active
        ? IviaAppBrand.of(context).action
        : digit == null
        ? IviaColors.borderInput
        : IviaColors.surface;
    return Container(
      height: 60,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: IviaColors.surface,
        borderRadius: BorderRadius.circular(IviaRadius.button),
        border: Border.all(
          color: borderColor,
          width: active || hasError ? 2 : 1,
        ),
      ),
      child: Text(
        digit ?? '',
        style: IviaTextStyles.title2,
        // Au-delà de 150 %, un chiffre ne tient plus dans sa case.
        textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.5),
      ),
    );
  }
}
