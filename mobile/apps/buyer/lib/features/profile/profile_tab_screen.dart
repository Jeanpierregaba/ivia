import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/router.dart';
import '../coupons/coupons_screen.dart';
import '../pharmacy/med_ui.dart';
import 'profile_settings.dart';

/// Profil : identité et photo, compte, paramètres, sécurité, aide.
class ProfileTabScreen extends ConsumerWidget {
  const ProfileTabScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final user = switch (ref.watch(authControllerProvider)) {
      AuthSignedIn(:final user) || AuthNeedsProfile(:final user) => user,
      _ => null,
    };
    void open(Widget page) =>
        Navigator.of(context)
            .push(MaterialPageRoute<void>(builder: (_) => page));
    return Container(
      color: Med.page,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            IviaSpacing.screen,
            IviaSpacing.lg,
            IviaSpacing.screen,
            120,
          ),
          children: [
            Text(
              'Mon profil',
              style: t.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: IviaSpacing.lg),
            _Header(user: user, onEdit: () => open(const PersonalInfoScreen())),
            const SizedBox(height: IviaSpacing.lg),
            Row(
              children: [
                _Shortcut(
                  icon: Icons.receipt_long_outlined,
                  label: 'Commandes',
                  onTap: () => context.go(Routes.orders),
                ),
                const SizedBox(width: 12),
                _Shortcut(
                  icon: Icons.add_box_outlined,
                  label: 'Pharmacie',
                  onTap: () => context.push(Routes.pharmacy),
                ),
                const SizedBox(width: 12),
                _Shortcut(
                  icon: Icons.shopping_bag_outlined,
                  label: 'Panier',
                  onTap: () => context.push(Routes.cart),
                ),
              ],
            ),
            _Section('Mon compte', [
              _Item(
                Icons.person_outline,
                'Informations personnelles',
                'Nom, prénom, e-mail',
                () => open(const PersonalInfoScreen()),
              ),
              _Item(
                Icons.place_outlined,
                'Mes adresses',
                'Maison, bureau…',
                () => open(const AddressesScreen()),
              ),
              _Item(
                Icons.local_offer_outlined,
                'Mes coupons',
                'Codes promo et cadeaux',
                () => open(const CouponsScreen()),
              ),
              _Item(
                Icons.receipt_outlined,
                'Mes factures',
                'Dans chaque commande payée',
                () => context.go(Routes.orders),
              ),
            ]),
            _Section('Paramètres', [
              _Item(
                Icons.notifications_none,
                'Notifications',
                'Commandes, pharmacie, promotions, son',
                () => open(const NotificationsSettingsScreen()),
              ),
              _Item(Icons.language, 'Langue', 'Français', null),
            ]),
            _Section('Sécurité', [
              _Item(
                Icons.phone_iphone,
                'Changer de numéro',
                user?.phone == null
                    ? 'Confirmé par un code'
                    : '+228 ${formatTogoPhone(user!.phone!)}',
                () => open(const ChangePhoneScreen()),
              ),
              _Item(
                Icons.devices_outlined,
                'Appareils connectés',
                'Voir et déconnecter vos appareils',
                () => open(const ConnectedDevicesScreen()),
              ),
              _Item(
                Icons.lock_outline,
                'Mot de passe',
                'Pas besoin : un code à usage unique à chaque connexion',
                () => _info(
                  context,
                  'Connexion sans mot de passe',
                  'Sur ivia, vous vous connectez avec votre numéro et un code reçu sur WhatsApp ou par SMS. '
                      'Aucun mot de passe à retenir ni à se faire voler. Pour changer d\'identifiant, changez de numéro.',
                ),
              ),
            ]),
            _Section('Aide', [
              _Item(
                Icons.chat_outlined,
                'Nous contacter',
                'WhatsApp, appel',
                () => _contact(context),
              ),
              _Item(
                Icons.help_outline,
                'Questions fréquentes',
                null,
                () => open(const FaqScreen()),
              ),
              _Item(
                Icons.description_outlined,
                'Conditions d\'utilisation',
                null,
                () => _info(
                  context,
                  'Conditions d\'utilisation',
                  'Document disponible prochainement.',
                ),
              ),
              _Item(
                Icons.privacy_tip_outlined,
                'Politique de confidentialité',
                null,
                () => _info(
                  context,
                  'Politique de confidentialité',
                  'Document disponible prochainement.',
                ),
              ),
              _Item(
                Icons.storefront_outlined,
                'Ouvrir une boutique',
                'Vendez sur Ivia Business',
                () => _info(
                  context,
                  'Ouvrir une boutique',
                  'Installez l\'app Ivia Business et connectez-vous avec le même compte. Vous créez votre boutique, '
                      'l\'équipe ivia la valide, puis vous ajoutez vos produits.',
                ),
              ),
            ]),
            _Section('', [
              _Item(
                Icons.logout,
                'Se déconnecter',
                null,
                () => ref.read(authControllerProvider.notifier).signOut(),
                danger: true,
              ),
              _Item(
                Icons.delete_outline,
                'Supprimer mon compte',
                'Définitif',
                () => _delete(context, ref),
                danger: true,
              ),
            ]),
            const SizedBox(height: IviaSpacing.lg),
            Center(
              child: Text(
                'ivia · version 1.0.0',
                style: t.bodySmall?.copyWith(color: Med.muted),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static void _info(BuildContext context, String title, String body) =>
      showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Compris'),
            ),
          ],
        ),
      );

  static const _supportPhone = String.fromEnvironment('IVIA_SUPPORT_PHONE');

  static void _contact(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Numéro du service client fourni au build (IVIA_SUPPORT_PHONE, ex. 22890000000).
          if (_supportPhone.isNotEmpty) ...[
            ListTile(
              leading: const Icon(Icons.chat_outlined),
              title: const Text('Écrire sur WhatsApp'),
              onTap: () => launchUrl(
                Uri.parse('https://wa.me/$_supportPhone'),
                mode: LaunchMode.externalApplication,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.call_outlined),
              title: const Text('Appeler le service client'),
              onTap: () => launchUrl(Uri.parse('tel:+$_supportPhone')),
            ),
          ],
          ListTile(
            leading: const Icon(Icons.mail_outline),
            title: const Text('support@ivia.tg'),
            onTap: () => launchUrl(Uri.parse('mailto:support@ivia.tg')),
          ),
        ],
      ),
    ),
  );

  static Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Supprimer votre compte ?'),
        content: const Text(
          'Vos informations, adresses et appareils sont effacés. Les factures restent conservées par les vendeurs '
          'comme la loi l\'exige. Cette action est définitive.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: IviaColors.error),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(apiClientProvider).deleteAccount();
      await ref.read(authControllerProvider.notifier).signOut();
    } on ApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }
}

/// Avatar (photo ou initiales).
class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, required this.user, this.radius = 40});
  final User? user;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final initials = [user?.firstName, user?.lastName]
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .map((s) => s.characters.first.toUpperCase())
        .join();
    final url = user?.avatarUrl;
    return CircleAvatar(
      radius: radius,
      backgroundColor: IviaColors.primary,
      foregroundImage: url == null ? null : NetworkImage(url),
      child: Text(
        initials.isEmpty ? '?' : initials,
        style: Theme.of(context).textTheme.headlineSmall
            ?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _Header extends ConsumerStatefulWidget {
  const _Header({required this.user, required this.onEdit});
  final User? user;
  final VoidCallback onEdit;

  @override
  ConsumerState<_Header> createState() => _HeaderState();
}

class _HeaderState extends ConsumerState<_Header> {
  var _busy = false;

  Future<void> _photo() async {
    final source = await showModalBottomSheet<PhotoSource>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Prendre une photo'),
              onTap: () => Navigator.pop(c, PhotoSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choisir dans la galerie'),
              onTap: () => Navigator.pop(c, PhotoSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    final bytes = await ref
        .read(photoPickerProvider)
        .pick(source: source, maxSide: 600);
    if (bytes == null) return;
    setState(() => _busy = true);
    try {
      final api = ref.read(apiClientProvider);
      final prepared = await api.prepareUpload(
        purpose: 'avatar',
        contentType: 'image/jpeg',
        sizeBytes: bytes.length,
      );
      await api.upload(prepared, bytes);
      final user = await api.updateMe(avatarKey: prepared.objectKey);
      await ref.read(authControllerProvider.notifier).profileUpdated(user);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final u = widget.user;
    final name = [
      u?.firstName,
      u?.lastName,
    ].whereType<String>().where((s) => s.isNotEmpty).join(' ');
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Med.navy,
        borderRadius: BorderRadius.circular(Med.radius),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: _busy ? null : _photo,
            child: Stack(
              children: [
                UserAvatar(user: u, radius: 38),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: _busy
                        ? const SizedBox.square(
                            dimension: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(
                            Icons.photo_camera,
                            size: 14,
                            color: Med.navy,
                          ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.isEmpty ? 'Mon profil' : name,
                  style: t.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (u?.phone case final p?)
                  Text(
                    '+228 ${formatTogoPhone(p)}',
                    style: t.bodyMedium?.copyWith(color: Colors.white70),
                  ),
                if (u?.email case final e?)
                  Text(e, style: t.bodySmall?.copyWith(color: Colors.white70)),
              ],
            ),
          ),
          IconButton.filledTonal(
            tooltip: 'Modifier',
            onPressed: widget.onEdit,
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
    );
  }
}

class _Shortcut extends StatelessWidget {
  const _Shortcut({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Expanded(
    child: MedCard(
      padding: const EdgeInsets.symmetric(vertical: 16),
      onTap: onTap,
      child: Column(
        children: [
          MedIconTile(icon, bg: Med.softRed, fg: IviaColors.primary, size: 46),
          const SizedBox(height: 8),
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    ),
  );
}

class _Item {
  const _Item(
    this.icon,
    this.title,
    this.subtitle,
    this.onTap, {
    this.danger = false,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool danger;
}

class _Section extends StatelessWidget {
  const _Section(this.title, this.items);
  final String title;
  final List<_Item> items;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: IviaSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Text(
                title.toUpperCase(),
                style: t.labelMedium?.copyWith(
                  color: Med.muted,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          MedCard(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                for (final (i, it) in items.indexed) ...[
                  if (i > 0) const Divider(height: 1, indent: 72),
                  ListTile(
                    leading: MedIconTile(
                      it.icon,
                      size: 42,
                      bg: it.danger ? Med.softRed : Med.softBlue,
                      fg: it.danger ? IviaColors.primary : Med.navy,
                    ),
                    title: Text(
                      it.title,
                      style: t.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: it.danger ? IviaColors.primary : Med.navy,
                      ),
                    ),
                    subtitle: it.subtitle == null
                        ? null
                        : Text(
                            it.subtitle!,
                            style: t.bodySmall?.copyWith(color: Med.muted),
                          ),
                    trailing: it.onTap == null
                        ? null
                        : const Icon(Icons.chevron_right, color: Med.muted),
                    onTap: it.onTap,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Informations personnelles (prénom, nom).
class PersonalInfoScreen extends ConsumerStatefulWidget {
  const PersonalInfoScreen({super.key});

  @override
  ConsumerState<PersonalInfoScreen> createState() => _PersonalInfoScreenState();
}

class _PersonalInfoScreenState extends ConsumerState<PersonalInfoScreen> {
  final _first = TextEditingController();
  final _last = TextEditingController();
  Map<String, String> _errors = {};
  var _busy = false;

  @override
  void initState() {
    super.initState();
    if (ref.read(authControllerProvider) case AuthSignedIn(:final user)) {
      _first.text = user.firstName;
      _last.text = user.lastName;
    }
  }

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _errors = {};
    });
    try {
      final user = await ref
          .read(apiClientProvider)
          .updateMe(firstName: _first.text.trim(), lastName: _last.text.trim());
      await ref.read(authControllerProvider.notifier).profileUpdated(user);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Profil mis à jour.')));
        Navigator.of(context).pop();
      }
    } on ApiException catch (e) {
      setState(
        () => _errors = e.fields.isEmpty ? {'first_name': e.message} : e.fields,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = switch (ref.watch(authControllerProvider)) {
      AuthSignedIn(:final user) => user,
      _ => null,
    };
    return MedScaffold(
      top: const MedTopBar(title: 'Informations personnelles'),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: IviaSpacing.screen),
        children: [
          Center(child: UserAvatar(user: user, radius: 48)),
          const SizedBox(height: 24),
          IviaFieldLabel(
            label: 'Prénom',
            child: TextField(
              controller: _first,
              decoration: InputDecoration(errorText: _errors['first_name']),
            ),
          ),
          const SizedBox(height: 16),
          IviaFieldLabel(
            label: 'Nom',
            child: TextField(
              controller: _last,
              decoration: InputDecoration(errorText: _errors['last_name']),
            ),
          ),
          const SizedBox(height: 16),
          IviaFieldLabel(
            label: 'Téléphone',
            child: TextField(
              enabled: false,
              controller: TextEditingController(
                text: user?.phone == null
                    ? ''
                    : '+228 ${formatTogoPhone(user!.phone!)}',
              ),
              decoration: const InputDecoration(
                helperText:
                    'Changez-le depuis Profil › Sécurité › Changer de numéro.',
              ),
            ),
          ),
        ],
      ),
      bottom: MedBottomButton(label: 'Enregistrer', busy: _busy, onTap: _save),
    );
  }
}

/// Carnet d'adresses de livraison.
class AddressesScreen extends ConsumerStatefulWidget {
  const AddressesScreen({super.key});

  @override
  ConsumerState<AddressesScreen> createState() => _AddressesScreenState();
}

class _AddressesScreenState extends ConsumerState<AddressesScreen> {
  late Future<List<BuyerAddress>> _list = ref
      .read(apiClientProvider)
      .addresses();

  void _reload() =>
      setState(() => _list = ref.read(apiClientProvider).addresses());

  Future<void> _add() async {
    final label = TextEditingController(text: 'Maison');
    final text = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Nouvelle adresse'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: label,
              decoration: const InputDecoration(
                labelText: 'Nom (Maison, Bureau…)',
              ),
            ),
            TextField(
              controller: text,
              decoration: const InputDecoration(
                labelText: 'Repère (rue, portail…)',
              ),
            ),
            const SizedBox(height: 8),
            const Text('Vous placerez ensuite le point sur la carte.'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Ajouter'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final picked = await Navigator.of(context).push<PickedPlace>(
      MaterialPageRoute(
        builder: (_) => const PlacePickerScreen(title: 'Placer l\'adresse'),
      ),
    );
    if (picked == null || !mounted) return;
    final p = picked.point;
    try {
      await ref
          .read(apiClientProvider)
          .createAddress(
            label: label.text.trim().isEmpty ? 'Maison' : label.text.trim(),
            addressText: text.text.trim().isEmpty
                ? picked.label
                : text.text.trim(),
            location: p,
          );
      _reload();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return MedScaffold(
      top: const MedTopBar(title: 'Mes adresses'),
      body: FutureBuilder<List<BuyerAddress>>(
        future: _list,
        builder: (context, snap) {
          final items = snap.data;
          if (items == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (items.isEmpty) {
            return Center(
              child: Text('Aucune adresse enregistrée.', style: t.bodyLarge),
            );
          }
          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: IviaSpacing.screen),
            children: [
              for (final a in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: MedCard(
                    child: Row(
                      children: [
                        const MedIconTile(
                          Icons.place_outlined,
                          bg: Med.softRed,
                          fg: IviaColors.primary,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                a.label,
                                style: t.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                a.addressText,
                                style: t.bodyMedium?.copyWith(color: Med.muted),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Supprimer',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            await ref
                                .read(apiClientProvider)
                                .deleteAddress(a.id);
                            _reload();
                          },
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
      bottom: MedBottomButton(
        label: 'Ajouter une adresse',
        icon: Icons.add,
        onTap: _add,
      ),
    );
  }
}

/// Notifications : catégories, son et vibration.
class NotificationsSettingsScreen extends ConsumerWidget {
  const NotificationsSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final prefs =
        ref.watch(notificationPrefsProvider).value ?? const NotificationPrefs();
    final save = ref.read(notificationPrefsProvider.notifier).save;
    Widget toggle(
      String title,
      String sub,
      bool v,
      NotificationPrefs Function(bool) next,
    ) => SwitchListTile(
      title: Text(
        title,
        style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800),
      ),
      subtitle: Text(sub),
      value: v,
      activeTrackColor: IviaColors.primary,
      onChanged: (x) => save(next(x)),
    );
    return MedScaffold(
      top: const MedTopBar(title: 'Notifications'),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: IviaSpacing.screen),
        children: [
          MedCard(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                toggle(
                  'Commandes',
                  'Paiement, préparation, livraison',
                  prefs.orders,
                  (x) => prefs.copyWith(orders: x),
                ),
                const Divider(height: 1),
                toggle(
                  'Pharmacie',
                  'Réponses des pharmacies, livreur',
                  prefs.pharmacy,
                  (x) => prefs.copyWith(pharmacy: x),
                ),
                const Divider(height: 1),
                toggle(
                  'Promotions',
                  'Offres et nouveautés',
                  prefs.promos,
                  (x) => prefs.copyWith(promos: x),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'SON',
            style: t.labelMedium?.copyWith(
              color: Med.muted,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          MedCard(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                for (final e in notificationSounds.entries)
                  ListTile(
                    leading: Icon(
                      prefs.sound == e.key
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      color: prefs.sound == e.key
                          ? IviaColors.primary
                          : Med.muted,
                    ),
                    title: Text(e.value),
                    trailing: e.key == 'silent'
                        ? null
                        : IconButton(
                            tooltip: 'Écouter',
                            icon: const Icon(Icons.play_circle_outline),
                            onPressed: () =>
                                SystemSound.play(SystemSoundType.alert),
                          ),
                    onTap: () => save(prefs.copyWith(sound: e.key)),
                  ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('Vibration'),
                  value: prefs.vibrate,
                  activeTrackColor: IviaColors.primary,
                  onChanged: (x) => save(prefs.copyWith(vibrate: x)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Questions fréquentes.
class FaqScreen extends StatelessWidget {
  const FaqScreen({super.key});

  static const _faq = [
    (
      'Comment payer ?',
      'Par Flooz (Moov Money) ou T-Money (Mixx by Yas). Vous validez sur votre téléphone avec votre code secret. La carte bancaire arrive bientôt.',
    ),
    (
      'Combien coûte la livraison ?',
      'Le prix dépend de la distance et s\'affiche avant de commander. Le retrait en boutique est gratuit.',
    ),
    (
      'Comment fonctionne l\'alerte médicament ?',
      'Vous indiquez vos médicaments, les pharmacies de garde proches répondent, et vous ne payez que pour débloquer celle que vous choisissez.',
    ),
    (
      'Comment annuler une commande ?',
      'Depuis le suivi de la commande, tant que la boutique ne l\'a pas acceptée. Un paiement déjà fait est remboursé.',
    ),
    (
      'Où trouver ma facture ?',
      'Dans le suivi de chaque commande payée : « Voir le reçu », puis « Télécharger » ou « Partager ».',
    ),
  ];

  @override
  Widget build(BuildContext context) => MedScaffold(
    top: const MedTopBar(title: 'Questions fréquentes'),
    body: ListView(
      padding: const EdgeInsets.symmetric(horizontal: IviaSpacing.screen),
      children: [
        for (final (q, a) in _faq)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: MedCard(
              padding: EdgeInsets.zero,
              child: ExpansionTile(
                shape: const Border(),
                title: Text(
                  q,
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [Text(a)],
              ),
            ),
          ),
      ],
    ),
  );
}
