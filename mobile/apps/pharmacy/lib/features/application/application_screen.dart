import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../common/providers.dart';
import 'application_flow.dart';
import 'review_screen.dart';

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
    return ReviewScreen(profile: profile);
  }
}
