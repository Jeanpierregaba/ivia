import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

/// Profil : identité, ouverture d'une boutique, déconnexion. Adresses,
/// informations personnelles et suppression du compte arrivent avec la 002.
class ProfileTabScreen extends ConsumerWidget {
  const ProfileTabScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final user = switch (ref.watch(authControllerProvider)) {
      AuthSignedIn(:final user) || AuthNeedsProfile(:final user) => user,
      _ => null,
    };
    final name = [
      user?.firstName,
      user?.lastName,
    ].whereType<String>().where((s) => s.isNotEmpty).join(' ');
    final initials = [user?.firstName, user?.lastName]
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .map((s) => s.characters.first.toUpperCase())
        .join();
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(IviaSpacing.screen),
        children: [
          Row(
            children: [
              ExcludeSemantics(
                child: CircleAvatar(
                  radius: 32,
                  backgroundColor: IviaAppBrand.of(context).action,
                  child: Text(
                    initials.isEmpty ? '?' : initials,
                    style: textTheme.titleLarge?.copyWith(color: Colors.white),
                  ),
                ),
              ),
              const SizedBox(width: IviaSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        name.isEmpty ? 'Mon profil' : name,
                        style: textTheme.headlineSmall,
                      ),
                    ),
                    if (user?.phone case final phone?)
                      Text(
                        '+228 ${formatTogoPhone(phone)}',
                        style: textTheme.bodyMedium,
                      )
                    else if (user?.email case final email?)
                      Text(email, style: textTheme.bodyMedium),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: IviaSpacing.xxl),
          _Card(
            children: [
              _Row(
                title: 'Ouvrir une boutique',
                subtitle: 'Vendez sur ivia Marchand',
                onTap: () => showModalBottomSheet<void>(
                  context: context,
                  showDragHandle: true,
                  builder: (context) => const _SellerInfo(),
                ),
              ),
            ],
          ),
          const SizedBox(height: IviaSpacing.lg),
          _Card(
            children: [
              _Row(
                title: 'Changer de numéro',
                subtitle: 'Confirmé par un code',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ChangePhoneScreen(),
                  ),
                ),
              ),
              _Row(
                title: 'Appareils connectés',
                subtitle: 'Voir et déconnecter vos appareils',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ConnectedDevicesScreen(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: IviaSpacing.lg),
          _Card(
            children: [
              _Row(
                title: 'Se déconnecter',
                onTap: () =>
                    ref.read(authControllerProvider.notifier).signOut(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SellerInfo extends StatelessWidget {
  const _SellerInfo();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          IviaSpacing.screen,
          0,
          IviaSpacing.screen,
          IviaSpacing.screen,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                'Ouvrir une boutique',
                style: textTheme.headlineSmall,
              ),
            ),
            const SizedBox(height: IviaSpacing.sm),
            Text(
              'Installez l’app ivia Marchand et connectez-vous avec le même '
              'compte. Vous créez votre '
              'boutique, l’équipe ivia la valide, puis vous ajoutez vos '
              'produits.',
              style: textTheme.bodyLarge?.copyWith(
                color: IviaColors.textSecondary,
              ),
            ),
            const SizedBox(height: IviaSpacing.xl),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Compris'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: IviaColors.surface,
      borderRadius: BorderRadius.circular(IviaRadius.large),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.title, required this.onTap, this.subtitle});

  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: IviaSpacing.lg,
            vertical: IviaSpacing.md,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: textTheme.titleMedium),
                    if (subtitle case final s?)
                      Text(s, style: textTheme.bodyMedium),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: IviaColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
