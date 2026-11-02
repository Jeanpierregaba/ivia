import 'package:flutter/material.dart';

import 'step_list.dart';
import 'tokens.dart';

/// Code de remise en très grand : 4 cases blanches, chiffres en Cornell,
/// sur le fond de couleur de l'en-tête. Lu « Code de remise : 4 8 2 7 ».
class IviaHandoverCode extends StatelessWidget {
  const IviaHandoverCode({super.key, required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.headlineLarge?.copyWith(
      color: IviaColors.primaryStrong,
      fontWeight: FontWeight.w800,
    );
    return Semantics(
      label: 'Code de remise : ${code.split('').join(' ')}',
      excludeSemantics: true,
      child: Row(
        children: [
          for (final (i, digit) in code.split('').indexed) ...[
            if (i > 0) const SizedBox(width: IviaSpacing.md),
            Expanded(
              child: Container(
                height: 72,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: IviaColors.surface,
                  borderRadius: BorderRadius.circular(IviaRadius.button),
                ),
                // Une ligne, même avec une police agrandie.
                child: FittedBox(child: Text(digit, style: style)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Étape de la frise d'une commande.
class IviaTimelineStep {
  const IviaTimelineStep({
    required this.title,
    required this.state,
    this.subtitle,
    this.time,
  });

  final String title;
  final String? subtitle;

  /// Heure déjà mise en forme (« 09:52 ») ; `null` pour une étape à venir.
  final String? time;
  final IviaStepState state;
}

/// Frise verticale : points reliés, pleins pour les étapes passées, cerclé
/// pour l'étape en cours, gris pour celles à venir.
class IviaTimeline extends StatelessWidget {
  const IviaTimeline({super.key, required this.steps, this.color});

  final List<IviaTimelineStep> steps;

  /// Couleur des étapes passées (par défaut, l'action de l'app).
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final active = color ?? Theme.of(context).colorScheme.primary;
    return Column(
      children: [
        for (final (i, step) in steps.indexed)
          _row(
            textTheme,
            active,
            step,
            next: i + 1 < steps.length ? steps[i + 1] : null,
          ),
      ],
    );
  }

  Widget _row(
    TextTheme textTheme,
    Color active,
    IviaTimelineStep step, {
    required IviaTimelineStep? next,
  }) {
    final last = next == null;
    final upcoming = step.state == IviaStepState.upcoming;
    final lineColor = !last && next.state != IviaStepState.upcoming
        ? active
        : IviaColors.border;
    final spoken = [
      step.title,
      ?step.subtitle,
      ?step.time,
      step.state.spoken,
    ].join(', ');
    return Semantics(
      label: spoken,
      excludeSemantics: true,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 24,
              child: Column(
                children: [
                  const SizedBox(height: 2),
                  _Dot(state: step.state, color: active),
                  if (!last)
                    Expanded(child: Container(width: 2, color: lineColor)),
                ],
              ),
            ),
            const SizedBox(width: IviaSpacing.md),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(bottom: last ? 0 : IviaSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      step.title,
                      style: textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: upcoming ? IviaColors.textMuted : null,
                      ),
                    ),
                    if (step.subtitle case final s?)
                      Text(s, style: textTheme.bodySmall),
                  ],
                ),
              ),
            ),
            if (step.time case final t?) ...[
              const SizedBox(width: IviaSpacing.sm),
              Text(t, style: textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.state, required this.color});

  final IviaStepState state;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 20,
    height: 20,
    decoration: ShapeDecoration(
      color: switch (state) {
        IviaStepState.done => color,
        IviaStepState.current => IviaColors.surface,
        IviaStepState.upcoming => IviaColors.surface,
      },
      shape: CircleBorder(
        side: BorderSide(
          color: state == IviaStepState.upcoming ? IviaColors.border : color,
          width: state == IviaStepState.current ? 6 : 2,
        ),
      ),
    ),
  );
}
