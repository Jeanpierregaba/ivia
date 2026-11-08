import 'package:flutter/material.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../common/ui.dart';

// Illustrations de la présentation (maquettes D01 à D03, spec 033), à leur
// taille réelle (360 dp de large) et centrées dans la grande carte ; réduites
// seulement si la carte manque de place. Données fictives d'exemple.

/// Largeur du contenu d'une illustration (560 px sur les maquettes).
const _contentWidth = 280.0;

/// Grande carte colorée d'une page : prend la place restante, contenu centré.
class OnboardingCard extends StatelessWidget {
  const OnboardingCard({super.key, required this.color, required this.child});
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(32),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          // Texte agrandi ou petit écran : l'illustration rétrécit, sans
          // déborder (elle suit la taille de texte de la maquette).
          child: MediaQuery.withNoTextScaling(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: SizedBox(width: _contentWidth, child: child),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Page 1 : proposition de mission, « Vous êtes disponible ».
class MissionOfferIllustration extends StatelessWidget {
  const MissionOfferIllustration({super.key});

  @override
  Widget build(BuildContext context) => OnboardingCard(
    color: D.blue,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _WhiteCard(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'NOUVELLE MISSION',
                          style: DText.overline.copyWith(fontSize: 11),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '1 200 FCFA',
                          style: DText.amount.copyWith(fontSize: 23),
                        ),
                        const SizedBox(height: 2),
                        Text('Gain indicatif', style: DText.small),
                      ],
                    ),
                  ),
                  const _Countdown(seconds: 31),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Chez Afi → Bè Kpota',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DText.label.copyWith(
                        color: D.ink,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    '4,2 km',
                    style: DText.label.copyWith(
                      color: D.blue,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const _FakeButton('Accepter'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Tilted(
          degrees: 3,
          child: _CheckPill(label: 'Vous êtes disponible'),
        ),
      ],
    ),
  );
}

/// Page 2 : étapes de la mission et « Ouvrir l'itinéraire ».
class MissionStepsIllustration extends StatelessWidget {
  const MissionStepsIllustration({super.key});

  @override
  Widget build(BuildContext context) => const OnboardingCard(
    color: D.navy,
    child: _WhiteCard(
      padding: EdgeInsets.fromLTRB(18, 18, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DStep(
            title: 'Aller à la boutique',
            subtitle: 'Chez Afi · 800 m',
            state: DStepState.done,
          ),
          SizedBox(height: 20),
          DStep(
            title: 'Récupérer le colis',
            subtitle: 'Confirmez la récupération',
            state: DStepState.current,
          ),
          SizedBox(height: 20),
          DStep(
            title: 'Livrer le client',
            subtitle: 'Bè Kpota · 3,4 km',
            state: DStepState.todo,
          ),
          SizedBox(height: 20),
          _FakeButton("Ouvrir l'itinéraire"),
        ],
      ),
    ),
  );
}

/// Page 3 : code du client, « Mission terminée ».
class CustomerCodeIllustration extends StatelessWidget {
  const CustomerCodeIllustration({super.key});

  @override
  Widget build(BuildContext context) => OnboardingCard(
    color: D.blue,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _WhiteCard(
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Code du client', style: DText.label),
              const SizedBox(height: 10),
              const DCodeBoxes('4827', style: DCodeStyle.soft),
              const SizedBox(height: 12),
              Text(
                'Demandez le code à la remise du colis.',
                style: DText.small,
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        const Tilted(
          degrees: -3,
          child: _CheckPill(label: 'Mission terminée', dark: true),
        ),
      ],
    ),
  );
}

class _WhiteCard extends StatelessWidget {
  const _WhiteCard({required this.child, required this.padding});
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: padding,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
    ),
    child: child,
  );
}

/// Compte à rebours de la proposition (45 s ; ici figé à [seconds]).
class _Countdown extends StatelessWidget {
  const _Countdown({required this.seconds});
  final int seconds;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 60,
    child: Stack(
      alignment: Alignment.center,
      children: [
        SizedBox.expand(
          child: CircularProgressIndicator(
            value: seconds / 45,
            strokeWidth: 7,
            color: D.blue,
            backgroundColor: IviaDriverColors.blueRing,
          ),
        ),
        Text('$seconds', style: DText.cardTitle.copyWith(fontSize: 16)),
      ],
    ),
  );
}

class _FakeButton extends StatelessWidget {
  const _FakeButton(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    height: 46,
    alignment: Alignment.center,
    decoration: const ShapeDecoration(color: D.blue, shape: StadiumBorder()),
    child: Text(label, style: DText.button.copyWith(color: Colors.white)),
  );
}

/// Pastille « Vous êtes disponible » / « Mission terminée », avec coche.
class _CheckPill extends StatelessWidget {
  const _CheckPill({required this.label, this.dark = false});
  final String label;
  final bool dark;

  @override
  Widget build(BuildContext context) => Container(
    height: 50,
    padding: const EdgeInsets.fromLTRB(10, 0, 18, 0),
    decoration: ShapeDecoration(
      color: dark ? D.navy : Colors.white,
      shape: const StadiumBorder(),
      shadows: illustrationShadow,
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: const BoxDecoration(
            color: D.blue,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check, size: 16, color: Colors.white),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: DText.label.copyWith(
              color: dark ? Colors.white : D.ink,
              fontWeight: FontWeight.w700,
              fontSize: dark ? 14 : 15,
            ),
          ),
        ),
      ],
    ),
  );
}
