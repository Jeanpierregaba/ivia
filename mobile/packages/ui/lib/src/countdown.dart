import 'dart:async';

import 'package:flutter/material.dart';

import 'tokens.dart';

/// Compte à rebours jusqu'à [deadline] (« 12:40 »), relu chaque seconde :
/// en `warning`, puis en `error` sous [urgentBelow] ; à zéro, « Délai
/// dépassé » et [onExpired] (une seule fois).
///
/// L'heure vient de [now] : l'app passe l'heure estimée du serveur, pour
/// qu'un téléphone mal réglé n'avance ni ne retarde un délai fixé par lui.
class IviaCountdown extends StatefulWidget {
  const IviaCountdown({
    super.key,
    required this.deadline,
    required this.now,
    this.onExpired,
    this.label,
    this.style,
    this.urgentBelow = const Duration(minutes: 3),
    this.expiredLabel = 'Délai dépassé',
  });

  final DateTime deadline;
  final DateTime Function() now;
  final VoidCallback? onExpired;

  /// Texte autour du temps restant (« Il vous reste 12:40 pour répondre ») ;
  /// le temps seul par défaut.
  final String Function(String remaining)? label;

  /// Style de base ; sa couleur est remplacée par celle de l'urgence.
  final TextStyle? style;
  final Duration urgentBelow;
  final String expiredLabel;

  /// « 12:40 », « 04:05 » : minutes et secondes restantes (arrondies
  /// au-dessus, pour ne jamais afficher 00:00 avant l'heure).
  static String format(Duration remaining) {
    final seconds = (remaining.inMilliseconds / 1000).ceil().clamp(0, 1 << 30);
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  State<IviaCountdown> createState() => _IviaCountdownState();
}

class _IviaCountdownState extends State<IviaCountdown> {
  Timer? _timer;
  var _expiredNotified = false;

  Duration get _remaining => widget.deadline.difference(widget.now());

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkExpired());
  }

  @override
  void didUpdateWidget(IviaCountdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.deadline != widget.deadline) _expiredNotified = false;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _tick() {
    if (!mounted) return;
    setState(() {});
    _checkExpired();
  }

  void _checkExpired() {
    if (!mounted || _expiredNotified || _remaining > Duration.zero) return;
    // App en arrière-plan (les minuteries tournent encore sur Android) :
    // rappel différé au retour au premier plan, à la seconde suivante.
    final state = WidgetsBinding.instance.lifecycleState;
    if (state != null && state != AppLifecycleState.resumed) return;
    _expiredNotified = true;
    widget.onExpired?.call();
  }

  @override
  Widget build(BuildContext context) {
    final remaining = _remaining;
    final expired = remaining <= Duration.zero;
    final color = expired || remaining < widget.urgentBelow
        ? IviaColors.error
        : IviaColors.warning;
    final clock = IviaCountdown.format(remaining);
    final text = expired
        ? widget.expiredLabel
        : widget.label?.call(clock) ?? clock;
    // Lecteur d'écran : à la minute près, sans les secondes qui défilent.
    final minutes = (remaining.inSeconds / 60).ceil();
    final spoken = expired
        ? widget.expiredLabel
        : widget.label?.call('$minutes min') ?? 'Il reste $minutes min';
    return Semantics(
      label: spoken,
      excludeSemantics: true,
      child: Text(
        text,
        style: (widget.style ?? DefaultTextStyle.of(context).style).copyWith(
          color: color,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}
