import 'package:flutter/material.dart';
import 'package:ivia_ui/ivia_ui.dart';

// Illustrations de la présentation livreur, dessinées d'après les maquettes
// du 2026-10-31 sur le plan de 324 × 421 dp d'OnboardingArtboard.
// Données fictives d'exemple.

/// Page 1 : proposition de mission, « Vous êtes disponible ».
class MissionOfferIllustration extends StatelessWidget {
  const MissionOfferIllustration({super.key});

  @override
  Widget build(BuildContext context) {
    return OnboardingArtboard(
      child: IllustrationCard(
        color: IviaColors.cobaltBlue,
        child: Stack(
          children: [
            Positioned(
              left: 22,
              top: 74,
              width: 280,
              child: _WhiteCard(
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
                                style: IviaTextStyles.overline.copyWith(
                                  color: IviaColors.cobaltBlue,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text('1 200 FCFA', style: IviaTextStyles.title1),
                              Text(
                                'Gain indicatif',
                                style: IviaTextStyles.caption.copyWith(
                                  color: IviaColors.textMuted,
                                ),
                              ),
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
                            style: IviaTextStyles.bodyStrong,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          '4,2 km',
                          style: IviaTextStyles.bodyStrong.copyWith(
                            color: IviaColors.cobaltBlue,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const _FakeButton(label: 'Accepter'),
                  ],
                ),
              ),
            ),
            const Positioned(
              left: 22,
              top: 282,
              child: Tilted(
                degrees: 3,
                child: CheckPill(
                  label: 'Vous êtes disponible',
                  checkColor: IviaColors.cobaltBlue,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Page 2 : étapes de la mission et « Ouvrir l'itinéraire ».
class MissionStepsIllustration extends StatelessWidget {
  const MissionStepsIllustration({super.key});

  @override
  Widget build(BuildContext context) {
    return const OnboardingArtboard(
      child: IllustrationCard(
        color: IviaColors.berkeleyBlue,
        child: Padding(
          padding: EdgeInsets.fromLTRB(22, 93, 22, 0),
          child: Align(
            alignment: Alignment.topCenter,
            child: IviaStepList(
              steps: [
                IviaStep(
                  title: 'Aller à la boutique',
                  subtitle: 'Chez Afi · 800 m',
                  state: IviaStepState.done,
                ),
                IviaStep(
                  title: 'Récupérer le colis',
                  subtitle: 'Confirmez la récupération',
                  state: IviaStepState.current,
                ),
                IviaStep(
                  title: 'Livrer le client',
                  subtitle: 'Bè Kpota · 3,4 km',
                  state: IviaStepState.upcoming,
                ),
              ],
              footer: _FakeButton(label: "Ouvrir l'itinéraire"),
            ),
          ),
        ),
      ),
    );
  }
}

/// Page 3 : code du client, « Mission terminée ».
class CustomerCodeIllustration extends StatelessWidget {
  const CustomerCodeIllustration({super.key});

  @override
  Widget build(BuildContext context) {
    return OnboardingArtboard(
      child: IllustrationCard(
        color: IviaColors.cobaltBlue,
        child: Stack(
          children: [
            Positioned(
              left: 22,
              top: 96,
              width: 280,
              child: _WhiteCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Code du client',
                      style: IviaTextStyles.bodyStrong.copyWith(
                        color: IviaColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        for (final (i, digit) in '4827'.split('').indexed) ...[
                          if (i > 0) const SizedBox(width: 8),
                          Expanded(
                            child: Container(
                              height: 54,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: IviaColors.background,
                                borderRadius: BorderRadius.circular(
                                  IviaRadius.button,
                                ),
                              ),
                              child: Text(digit, style: IviaTextStyles.title1),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Demandez le code à la remise du colis.',
                      style: IviaTextStyles.caption.copyWith(
                        color: IviaColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Positioned(
              left: 118,
              top: 282,
              child: Tilted(
                degrees: -3,
                child: CheckPill(
                  label: 'Mission terminée',
                  checkColor: IviaColors.cobaltBlue,
                  dark: true,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WhiteCard extends StatelessWidget {
  const _WhiteCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: IviaColors.surface,
        borderRadius: BorderRadius.circular(IviaRadius.large),
      ),
      child: child,
    );
  }
}

/// Compte à rebours de la proposition (45 s ; ici figé à [seconds]).
class _Countdown extends StatelessWidget {
  const _Countdown({required this.seconds});

  final int seconds;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 60,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox.expand(
            child: CircularProgressIndicator(
              value: seconds / 45,
              strokeWidth: 7,
              color: IviaColors.cobaltBlue,
              backgroundColor: IviaColors.secondarySoft,
            ),
          ),
          Text('$seconds', style: IviaTextStyles.title3),
        ],
      ),
    );
  }
}

class _FakeButton extends StatelessWidget {
  const _FakeButton({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      alignment: Alignment.center,
      decoration: const ShapeDecoration(
        color: IviaColors.cobaltBlue,
        shape: StadiumBorder(),
      ),
      child: Text(
        label,
        style: IviaTextStyles.bodyStrong.copyWith(color: Colors.white),
      ),
    );
  }
}
