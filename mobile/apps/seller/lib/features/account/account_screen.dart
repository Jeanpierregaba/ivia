import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../app/router.dart';
import '../../app/seller_shop.dart';

/// Compte : identité du compte, boutique, déconnexion. Le profil complet
/// arrive avec la fonctionnalité 002.
class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final user = switch (ref.watch(authControllerProvider)) {
      AuthSignedIn(:final user) || AuthNeedsProfile(:final user) => user,
      _ => null,
    };
    final shop = ref.watch(sellerShopProvider).value;
    final name = [
      user?.firstName,
      user?.lastName,
    ].whereType<String>().where((s) => s.isNotEmpty).join(' ');
    final shopLine = [
      shop?.categoryName,
      shop?.neighborhoodName,
    ].whereType<String>().where((s) => s.isNotEmpty).join(' · ');
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(IviaSpacing.screen),
        children: [
          Semantics(
            header: true,
            child: Text('Compte', style: textTheme.headlineLarge),
          ),
          const SizedBox(height: IviaSpacing.xxl),
          _Card(
            title: name.isEmpty ? 'Votre compte' : name,
            subtitle: user?.email ?? '',
          ),
          if (shop != null) ...[
            const SizedBox(height: IviaSpacing.md),
            _Card(title: shop.name, subtitle: shopLine),
          ],
          const SizedBox(height: IviaSpacing.xxxl),
          OutlinedButton(
            onPressed: () => context.push(Routes.accountPassword),
            child: const Text('Changer le mot de passe'),
          ),
          const SizedBox(height: IviaSpacing.sm),
          AsyncButton.text(
            label: 'Se déconnecter',
            onPressed: ref.read(authControllerProvider.notifier).signOut,
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(IviaSpacing.lg),
      decoration: BoxDecoration(
        color: IviaColors.surface,
        borderRadius: BorderRadius.circular(IviaRadius.large),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: textTheme.titleMedium),
          if (subtitle.isNotEmpty)
            Text(
              subtitle,
              style: textTheme.bodyMedium?.copyWith(
                color: IviaColors.textSecondary,
              ),
            ),
        ],
      ),
    );
  }
}
