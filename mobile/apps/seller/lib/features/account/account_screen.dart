import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../app/business_state.dart';
import '../../app/seller_shop.dart';
import '../business/business_screens.dart';
import 'revenue_screen.dart';

/// Compte : identité, boutique, revenus et relevés, sécurité, déconnexion.
class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final user = switch (ref.watch(authControllerProvider)) {
      AuthSignedIn(:final user) || AuthNeedsProfile(:final user) => user,
      _ => null,
    };
    final shop = ref.watch(sellerShopProvider).value;
    final pending = (ref.watch(settlementsProvider).value ?? const [])
        .where((s) => !s.settled)
        .fold<int>(0, (a, s) => a + s.netXof);
    final name = [
      user?.firstName,
      user?.lastName,
    ].whereType<String>().where((s) => s.isNotEmpty).join(' ');
    final shopLine = [
      shop?.categoryName,
      shop?.neighborhoodName,
    ].whereType<String>().where((s) => s.isNotEmpty).join(' · ');
    void open(Widget screen) => Navigator.of(
      context,
      rootNavigator: true,
    ).push(MaterialPageRoute<void>(builder: (_) => screen));
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(IviaSpacing.screen),
        children: [
          Semantics(
            header: true,
            child: Text('Compte', style: t.headlineLarge),
          ),
          const SizedBox(height: IviaSpacing.xl),
          _Card(
            child: Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: IviaColors.secondarySoft,
                  foregroundImage: shop?.logoUrl == null
                      ? null
                      : NetworkImage(shop!.logoUrl!),
                  child: Text(
                    (name.isEmpty ? '?' : name[0]).toUpperCase(),
                    style: t.titleLarge?.copyWith(
                      color: IviaColors.berkeleyBlue,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name.isEmpty ? 'Votre compte' : name,
                        style: t.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if ((user?.phone ?? '').isNotEmpty)
                        Text(
                          formatTogoPhone(user!.phone!),
                          style: t.bodyMedium?.copyWith(
                            color: IviaColors.textSecondary,
                          ),
                        ),
                      if (shop != null)
                        Text(
                          shopLine.isEmpty
                              ? shop.name
                              : '${shop.name} · $shopLine',
                          style: t.bodySmall?.copyWith(
                            color: IviaColors.textMuted,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: IviaSpacing.md),
          Material(
            color: IviaColors.berkeleyBlue,
            borderRadius: BorderRadius.circular(24),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => open(const RevenueScreen()),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    const Icon(
                      Icons.account_balance_wallet_outlined,
                      color: Colors.white,
                      size: 30,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Revenus et relevés',
                            style: t.titleMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            'À recevoir : ${formatXof(pending)}',
                            style: t.bodyMedium?.copyWith(
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: Colors.white),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: IviaSpacing.xl),
          _Section('Mon activité'),
          _Card(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _Item(
                  icon: Icons.swap_horiz,
                  title: 'Mes espaces',
                  onTap: ref.read(businessGateProvider.notifier).close,
                ),
                if (ref.watch(businessGateProvider).value?.opened
                    case final space?) ...[
                  const Divider(height: 1),
                  _Item(
                    icon: Icons.account_balance_outlined,
                    title: 'Compte de versement',
                    subtitle: space.payout?.phoneMasked,
                    onTap: () => open(PayoutScreen(space: space)),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: IviaSpacing.xl),
          _Section('Sécurité'),
          _Card(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _Item(
                  icon: Icons.phone_iphone,
                  title: 'Changer de numéro',
                  onTap: () => open(const ChangePhoneScreen()),
                ),
                const Divider(height: 1),
                _Item(
                  icon: Icons.devices_outlined,
                  title: 'Appareils connectés',
                  onTap: () => open(const ConnectedDevicesScreen()),
                ),
              ],
            ),
          ),
          const SizedBox(height: IviaSpacing.xl),
          _Section('Aide'),
          _Card(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _Item(
                  icon: Icons.percent,
                  title: 'Commission et reversements',
                  onTap: () => showModalBottomSheet<void>(
                    context: context,
                    showDragHandle: true,
                    builder: (c) => Padding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                      child: Text(
                        'ivia prélève sa commission sur chaque commande livrée. '
                        'Le reste vous est reversé sur votre Mobile Money à '
                        'chaque relevé ; le détail commande par commande est '
                        'dans « Revenus et relevés ».',
                        style: t.bodyLarge,
                      ),
                    ),
                  ),
                ),
                const Divider(height: 1),
                const _Item(
                  icon: Icons.mail_outline,
                  title: 'Écrire au support',
                  subtitle: 'support@ivia.tg',
                ),
              ],
            ),
          ),
          const SizedBox(height: IviaSpacing.xxl),
          AsyncButton.text(
            label: 'Se déconnecter',
            onPressed: ref.read(authControllerProvider.notifier).signOut,
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 8),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleSmall
          ?.copyWith(color: IviaColors.textMuted, fontWeight: FontWeight.w800),
    ),
  );
}

class _Item extends StatelessWidget {
  const _Item({
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
    leading: Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: IviaColors.secondarySoft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: IviaColors.berkeleyBlue, size: 22),
    ),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
    subtitle: subtitle == null ? null : Text(subtitle!),
    trailing: onTap == null ? null : const Icon(Icons.chevron_right),
    onTap: onTap,
  );
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => Material(
    color: IviaColors.surface,
    borderRadius: BorderRadius.circular(IviaRadius.large),
    clipBehavior: Clip.antiAlias,
    child: Padding(
      padding: padding ?? const EdgeInsets.all(IviaSpacing.lg),
      child: child,
    ),
  );
}
