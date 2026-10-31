import 'package:flutter/material.dart';

import 'button_progress.dart';

enum _Style { filled, outlined, text }

/// Bouton qui lance une action asynchrone : désactivé et indicateur affiché
/// pendant l'action, un seul envoi même en cas de double appui.
class AsyncButton extends StatefulWidget {
  const AsyncButton.filled({
    super.key,
    required this.label,
    required this.onPressed,
  }) : _style = _Style.filled;

  const AsyncButton.outlined({
    super.key,
    required this.label,
    required this.onPressed,
  }) : _style = _Style.outlined;

  const AsyncButton.text({
    super.key,
    required this.label,
    required this.onPressed,
  }) : _style = _Style.text;

  final String label;
  final Future<void> Function() onPressed;
  final _Style _style;

  @override
  State<AsyncButton> createState() => _AsyncButtonState();
}

class _AsyncButtonState extends State<AsyncButton> {
  var _busy = false;

  Future<void> _run() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onPressed();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final onPressed = _busy ? null : _run;
    final child = _busy ? const ButtonProgress() : Text(widget.label);
    return switch (widget._style) {
      _Style.filled => FilledButton(onPressed: onPressed, child: child),
      _Style.outlined => OutlinedButton(onPressed: onPressed, child: child),
      _Style.text => TextButton(onPressed: onPressed, child: child),
    };
  }
}
