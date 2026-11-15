import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../common/providers.dart';
import '../../common/ui.dart';
import '../planning/planning_screen.dart';
import '../push/push.dart';

/// Dossier envoyé (F08) ou pharmacie suspendue : aucune alerte reçue. Tirer
/// vers le bas relit le statut ; la validation arrive aussi par push.
class ReviewScreen extends ConsumerWidget {
  const ReviewScreen({super.key, required this.profile});
  final PharmacyProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = profile;
    final suspended = p.suspended;
    return Scaffold(
      backgroundColor: P.page,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 4, 6, 0),
                child: TextButton(
                  onPressed: () => signOutPharmacy(ref),
                  style: TextButton.styleFrom(foregroundColor: P.muted),
                  child: const Text('Se déconnecter'),
                ),
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                color: P.green,
                onRefresh: () async => ref.invalidate(pharmacyProfileProvider),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(P.gutter, 12, P.gutter, 8),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        width: 76,
                        height: 76,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: suspended
                            ? const Icon(
                                Icons.pause_circle_outline,
                                size: 44,
                                color: P.danger,
                              )
                            : const SizedBox.square(
                                dimension: 40,
                                child: CircularProgressIndicator(
                                  value: 0.75,
                                  strokeWidth: 5,
                                  color: P.green,
                                  backgroundColor: P.softGreen,
                                  semanticsLabel: 'Validation en cours',
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    Semantics(
                      header: true,
                      child: Text(
                        suspended
                            ? 'Votre pharmacie est suspendue'
                            : 'Votre pharmacie est en cours de validation',
                        style: PText.heading,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      suspended
                          ? "Elle ne reçoit plus d'alertes pour le moment. "
                                "Contactez l'équipe ivia pour en savoir plus."
                          : "L'équipe ivia vérifie votre autorisation "
                                "d'exercice. Vous recevrez une notification et "
                                'un e-mail.',
                      style: PText.body.copyWith(fontSize: 16, color: P.label),
                    ),
                    const SizedBox(height: 22),
                    IviaStepList(
                      doneColor: P.green,
                      upcomingColor: IviaPharmacyColors.checkOff,
                      steps: [
                        const IviaStep(
                          title: 'Compte créé',
                          state: IviaStepState.done,
                        ),
                        IviaStep(
                          title: 'Dossier envoyé',
                          subtitle: p.name,
                          state: IviaStepState.done,
                        ),
                        IviaStep(
                          title: 'Vérification par ivia',
                          subtitle: suspended ? 'Faite' : 'En cours',
                          state: suspended
                              ? IviaStepState.done
                              : IviaStepState.current,
                        ),
                        IviaStep(
                          title: 'Réception des alertes',
                          subtitle: suspended
                              ? 'Suspendue'
                              : 'Dès la validation',
                          state: IviaStepState.upcoming,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            PBottomBar(
              children: [
                PButton(
                  label: 'Préparer mon planning de garde',
                  style: PButtonStyle.outline,
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const PlanningScreen(),
                      ),
                    );
                    ref.invalidate(shiftsProvider);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
