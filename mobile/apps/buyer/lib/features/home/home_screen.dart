import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

/// Accueil : salutation ; recherche et sections à la tâche 6 de la spec 007.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final firstName = switch (ref.watch(authControllerProvider)) {
      AuthSignedIn(:final user) => user.firstName,
      _ => '',
    };
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(IviaSpacing.screen),
        children: [
          Text(
            firstName.isEmpty ? 'Bonjour,' : 'Bonjour $firstName,',
            style: Theme.of(context).textTheme.headlineLarge,
          ),
        ],
      ),
    );
  }
}
