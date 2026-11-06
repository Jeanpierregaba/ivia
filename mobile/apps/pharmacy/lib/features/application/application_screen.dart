import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../common/providers.dart';
import '../../common/ui.dart';
import '../push/push.dart';
import 'application_flow.dart';

/// Inscription : le statut du dossier décide de l'écran. Brouillon,
/// compléments ou refus : les 5 étapes ; envoyé ou suspendu : l'attente.
class ApplicationScreen extends ConsumerWidget {
  const ApplicationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(pharmacyProfileProvider).value;
    if (profile == null || profile.editable) {
      return ApplicationFlow(profile: profile);
    }
    return _Waiting(profile: profile);
  }
}

class _Frame extends ConsumerWidget {
  const _Frame({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    backgroundColor: P.page,
    body: SafeArea(
      child: RefreshIndicator(
        onRefresh: () async => ref.invalidate(pharmacyProfileProvider),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(IviaSpacing.screen),
          children: [
            Row(
              children: [
                const IviaLogoTile(size: 48, color: P.green),
                const Spacer(),
                TextButton(
                  onPressed: () => signOutPharmacy(ref),
                  child: const Text('Se déconnecter'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    ),
  );
}

/// Dossier envoyé ou pharmacie suspendue : aucune alerte reçue.
class _Waiting extends ConsumerWidget {
  const _Waiting({required this.profile});
  final PharmacyProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final p = profile;
    return _Frame(
      children: [
        if (p.suspended)
          const PTitle('Pharmacie ', 'suspendue')
        else
          const PTitle('Dossier en ', 'vérification'),
        const SizedBox(height: 8),
        Text(
          p.suspended
              ? 'Votre pharmacie ne reçoit plus d\'alertes. Contactez l\'équipe ivia.'
              : 'L\'équipe ivia vérifie votre autorisation, votre identité et votre position. Vous ne recevez aucune alerte avant la validation.',
          style: t.bodyLarge?.copyWith(color: P.muted),
        ),
        const SizedBox(height: 20),
        PCard(
          child: Row(
            children: [
              const PIcon(Icons.local_pharmacy),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.name,
                      style: t.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      p.addressText,
                      style: t.bodyMedium?.copyWith(color: P.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: () => ref.invalidate(pharmacyProfileProvider),
          icon: const Icon(Icons.refresh),
          label: const Text('Actualiser le statut'),
        ),
      ],
    );
  }
}
