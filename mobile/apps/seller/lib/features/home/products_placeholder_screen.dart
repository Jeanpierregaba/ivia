import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:ivia_ui/ivia_ui.dart';

/// Produits : écran provisoire, remplacé par le catalogue marchand
/// (fonctionnalité 005).
class ProductsPlaceholderScreen extends StatelessWidget {
  const ProductsPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(IviaSpacing.screen),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IviaBackButton(onPressed: () => context.pop()),
            ),
            const SizedBox(height: IviaSpacing.xxl),
            Semantics(
              header: true,
              child: Text('Mes produits', style: textTheme.headlineMedium),
            ),
            const SizedBox(height: IviaSpacing.sm),
            Text(
              'Bientôt : ajoutez vos produits en photo, avec le prix et le '
              'stock, pendant la validation de la boutique.',
              style: textTheme.bodyLarge?.copyWith(
                color: IviaColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
