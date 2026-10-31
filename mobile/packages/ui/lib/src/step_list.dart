import 'package:flutter/material.dart';

import 'brand.dart';
import 'tokens.dart';

/// État d'une étape de [IviaStepList].
enum IviaStepState {
  done('terminé'),
  current('en cours'),
  upcoming('à venir');

  const IviaStepState(this.spoken);

  /// Lu par le lecteur d'écran après le titre de l'étape.
  final String spoken;
}

/// Une étape : titre, précision éventuelle, état.
class IviaStep {
  const IviaStep({required this.title, this.subtitle, required this.state});

  final String title;
  final String? subtitle;
  final IviaStepState state;
}

/// Liste d'étapes dans une carte blanche (ex. validation de la boutique) :
/// coche pour les étapes faites, anneau pour l'étape en cours, cercle vide
/// et texte atténué pour les suivantes.
class IviaStepList extends StatelessWidget {
  const IviaStepList({super.key, required this.steps});

  final List<IviaStep> steps;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final action = IviaAppBrand.of(context).action;
    return Container(
      padding: const EdgeInsets.all(IviaSpacing.xl),
      decoration: BoxDecoration(
        color: IviaColors.surface,
        borderRadius: BorderRadius.circular(IviaRadius.large),
      ),
      child: Column(
        children: [
          for (final (i, step) in steps.indexed) ...[
            if (i > 0) const SizedBox(height: IviaSpacing.lg),
            MergeSemantics(
              child: Semantics(
                value: step.state.spoken,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ExcludeSemantics(child: _Marker(step.state, action)),
                    const SizedBox(width: IviaSpacing.lg),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 3),
                          Text(
                            step.title,
                            style: textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: step.state == IviaStepState.upcoming
                                  ? IviaColors.textMuted
                                  : IviaColors.text,
                            ),
                          ),
                          if (step.subtitle case final subtitle?)
                            Text(subtitle, style: textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Marker extends StatelessWidget {
  const _Marker(this.state, this.action);

  final IviaStepState state;
  final Color action;

  static const _size = 28.0;

  @override
  Widget build(BuildContext context) {
    return switch (state) {
      IviaStepState.done => Container(
        width: _size,
        height: _size,
        decoration: const BoxDecoration(
          color: IviaColors.cobaltBlue,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.check, size: 18, color: Colors.white),
      ),
      IviaStepState.current => Container(
        width: _size,
        height: _size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: action, width: 3),
        ),
        child: Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: action, shape: BoxShape.circle),
        ),
      ),
      IviaStepState.upcoming => Container(
        width: _size,
        height: _size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: IviaColors.borderInput, width: 2),
        ),
      ),
    };
  }
}
