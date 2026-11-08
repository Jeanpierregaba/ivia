import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../app/driver_dossier.dart';
import '../../common/formats.dart';
import '../../common/ui.dart';
import '../dossier/dossier_labels.dart';
import '../mission/navigation.dart';
import '../mission/problem_sheet.dart' show driverSupportPhone;
import '../work/work_state.dart';
import 'settings.dart';

/// Courses livrées depuis le début (tout l'historique, boutique et
/// pharmacie) : affichées à la place de la note (spec 033).
final deliveredCountProvider = FutureProvider.autoDispose<int>((ref) async {
  final all = await ref.read(apiClientProvider).workHistory();
  return all.where((m) => m.deliveredAt != null).length;
});

/// Applications de navigation proposées : Plans seulement sur iPhone.
List<NavApp> navAppsFor(TargetPlatform platform) => [
  NavApp.google,
  NavApp.waze,
  if (platform == TargetPlatform.iOS) NavApp.apple,
];

/// Profil (D19) : identité, véhicule, documents, zone de travail,
/// application de navigation, sonnerie des missions, aide, déconnexion.
/// Une activité validée ne se modifie plus dans l'app (le serveur la
/// verrouille) : « Modifier » explique comment passer par le support.
class ProfileTab extends ConsumerWidget {
  const ProfileTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = switch (ref.watch(authControllerProvider)) {
      AuthSignedIn(:final user) => user,
      _ => null,
    };
    final dossier = ref.watch(driverDossierProvider).value;
    final name = [
      user?.firstName,
      user?.lastName,
    ].whereType<String>().where((s) => s.isNotEmpty).join(' ');
    final count = ref.watch(deliveredCountProvider).value;
    final zone = ref.watch(workZoneNameProvider).value;
    final nav = ref.watch(navAppProvider).value ?? NavApp.google;
    final ring = ref.watch(missionRingProvider).value ?? true;
    final docs = dossier == null ? 0 : receivedKinds(dossier).length;

    return ListView(
      padding: EdgeInsets.fromLTRB(
        D.gutter,
        MediaQuery.paddingOf(context).top + 14,
        D.gutter,
        24,
      ),
      children: [
        Row(
          children: [
            ExcludeSemantics(
              child: SizedBox.square(
                dimension: 64,
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    color: D.blue,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: MediaQuery.withNoTextScaling(
                      child: Text(
                        initials(name),
                        style: DText.heading.copyWith(
                          color: Colors.white,
                          fontSize: 24,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      name.isEmpty ? 'Ivia Driver' : name,
                      style: DText.heading.copyWith(fontSize: 28),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      if (count != null)
                        _Badge(
                          icon: Icons.inventory_2_rounded,
                          text: '$count course${count > 1 ? 's' : ''}',
                          bg: Colors.white,
                          fg: D.ink,
                          iconColor: D.blue,
                        ),
                      if (dossier?.review == DriverReview.approved)
                        const _Badge(
                          icon: Icons.verified_rounded,
                          text: 'Validé',
                          bg: D.greenSoft,
                          fg: D.green,
                          iconColor: D.green,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (dossier != null)
          _VehicleCard(
            dossier: dossier,
            onEdit: () => _sheet(context, const _LockedSheet()),
          ),
        const SizedBox(height: 12),
        _Group(
          children: [
            _Row(
              icon: Icons.description_outlined,
              title: 'Documents',
              subtitle: docs == 0
                  ? 'Aucun document'
                  : '$docs validé${docs > 1 ? 's' : ''}',
              onTap: dossier == null
                  ? null
                  : () => _sheet(context, _DocumentsSheet(dossier: dossier)),
            ),
            _Row(
              icon: Icons.location_on_outlined,
              title: 'Zone de travail',
              subtitle: zone ?? 'Non choisie',
              onTap: () => _sheet(context, const _LockedSheet()),
            ),
            _Row(
              icon: Icons.map_outlined,
              title: 'Application de navigation',
              subtitle: nav.label,
              onTap: () => _sheet(context, const _NavAppSheet()),
            ),
            MergeSemantics(
              child: _Row(
                icon: Icons.volume_up_outlined,
                title: 'Sonnerie des missions',
                trailing: Switch(
                  value: ring,
                  onChanged: (v) =>
                      ref.read(missionRingProvider.notifier).set(v),
                ),
                onTap: () => ref.read(missionRingProvider.notifier).set(!ring),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _Group(
          children: [
            _Row(
              icon: Icons.support_agent_rounded,
              title: 'Aide et support',
              subtitle: _phone(driverSupportPhone),
              onTap: () => _callSupport(context, ref),
            ),
            _Row(
              icon: Icons.devices_outlined,
              title: 'Appareils connectés',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ConnectedDevicesScreen(),
                ),
              ),
            ),
            _Row(
              icon: Icons.logout_rounded,
              title: 'Se déconnecter',
              danger: true,
              onTap: () => _signOut(context, ref),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final onMission = ref.read(workProvider).mission != null;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Se déconnecter ?'),
        content: Text(
          onMission
              ? 'Une mission est en cours : terminez-la avant de vous '
                    'déconnecter.'
              : 'Vous ne recevrez plus de propositions.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          if (!onMission)
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Se déconnecter'),
            ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final work = ref.read(workProvider.notifier);
    // En ligne : le serveur doit d'abord savoir que le livreur s'arrête,
    // sinon il resterait disponible pour des propositions.
    if (ref.read(workProvider).online) {
      await work.setOnline(false);
      if (ref.read(workProvider).online) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Impossible de passer hors ligne : vérifiez la connexion, '
              'puis réessayez.',
            ),
          ),
        );
        return;
      }
    }
    await ref.read(authControllerProvider.notifier).signOut();
  }
}

/// « +228 99 30 99 45 ».
String _phone(String e164) {
  final d = e164.replaceAll(RegExp(r'\D'), '');
  if (d.length != 11 || !d.startsWith('228')) return e164;
  final n = d.substring(3);
  return '+228 ${n.substring(0, 2)} ${n.substring(2, 4)} '
      '${n.substring(4, 6)} ${n.substring(6)}';
}

Future<void> _callSupport(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  final ok = await ref.read(linkLauncherProvider)(telUri(driverSupportPhone));
  if (!ok) {
    messenger.showSnackBar(
      const SnackBar(content: Text("Impossible de lancer l'appel.")),
    );
  }
}

Future<void> _sheet(BuildContext context, Widget child) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (_) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(D.gutter, 0, D.gutter, 16),
          child: child,
        ),
      ),
    );

class _Badge extends StatelessWidget {
  const _Badge({
    required this.icon,
    required this.text,
    required this.bg,
    required this.fg,
    required this.iconColor,
  });
  final IconData icon;
  final String text;
  final Color bg, fg, iconColor;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(IviaRadius.pill),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: iconColor),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            style: DText.pill.copyWith(color: fg, fontSize: 14),
          ),
        ),
      ],
    ),
  );
}

/// Carte sombre du véhicule : type, plaque, marque et modèle, « Modifier ».
class _VehicleCard extends StatelessWidget {
  const _VehicleCard({required this.dossier, required this.onEdit});
  final DriverDossier dossier;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final a = dossier.delivery;
    final type = a?.vehicleType ?? dossier.vehicleType;
    final plate = (a?.plate.isNotEmpty ?? false)
        ? a!.plate
        : dossier.vehiclePlate;
    final model = [a?.brand ?? '', a?.model ?? ''].where((s) => s.isNotEmpty);
    // Grande police : « Modifier » passe sous le véhicule.
    final big = MediaQuery.textScalerOf(context).scale(10) > 15;
    final edit = TextButton(
      onPressed: onEdit,
      style: TextButton.styleFrom(
        foregroundColor: D.blueOnDark,
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
      child: Text(
        'Modifier',
        style: DText.button.copyWith(color: D.blueOnDark, fontSize: 15),
      ),
    );
    final row = Row(
      children: [
        DIconTile(
          switch (type) {
            VehicleType.bicycle => Icons.pedal_bike_rounded,
            VehicleType.motorbike => Icons.two_wheeler_rounded,
            VehicleType.car => Icons.directions_car_rounded,
          },
          bg: D.blue,
          fg: Colors.white,
          size: 44,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: MergeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  vehicleLabel(type),
                  style: DText.cardTitle.copyWith(
                    color: Colors.white,
                    fontSize: 17,
                  ),
                ),
                Text(
                  [
                    // Espaces insécables : retour à la ligne entre la plaque
                    // et le modèle seulement.
                    if (plate.isNotEmpty) plate.replaceAll(' ', '\u00A0'),
                    if (model.isNotEmpty)
                      model.join(' ').replaceAll(' ', '\u00A0'),
                  ].join(' · '),
                  style: DText.body.copyWith(color: D.nightMuted, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
        if (!big) edit,
      ],
    );
    return DCard.dark(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      child: big
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [row, edit],
            )
          : row,
    );
  }
}

/// Carte blanche de lignes séparées par un trait.
class _Group extends StatelessWidget {
  const _Group({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => DCard(
    padding: EdgeInsets.zero,
    child: Column(
      children: [
        for (final (i, child) in children.indexed)
          DecoratedBox(
            decoration: BoxDecoration(
              border: i == children.length - 1
                  ? null
                  : const Border(bottom: BorderSide(color: D.line)),
            ),
            child: child,
          ),
      ],
    ),
  );
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.danger = false,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Row(
          children: [
            ExcludeSemantics(
              child: Icon(icon, color: danger ? D.red : D.blue, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: DText.cardTitle.copyWith(
                      fontSize: 16,
                      color: danger ? D.red : D.ink,
                    ),
                  ),
                  if (subtitle case final s?)
                    Text(s, style: DText.bodyMuted.copyWith(fontSize: 14)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            ?trailing ??
                (onTap == null || danger
                    ? null
                    : const ExcludeSemantics(
                        child: Icon(
                          Icons.chevron_right_rounded,
                          color: D.label,
                        ),
                      )),
          ],
        ),
      ),
    ),
  );
}

/// Véhicule et zone verrouillés après la validation (refus du serveur :
/// `application_locked`) : passer par le support.
class _LockedSheet extends ConsumerWidget {
  const _LockedSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Semantics(
        header: true,
        child: Text('Modifier mon activité', style: DText.heading),
      ),
      const SizedBox(height: 6),
      Text(
        'Votre activité est validée : pour changer de véhicule ou de zone '
        'de travail, contactez l\'équipe ivia.',
        style: DText.bodyMuted.copyWith(fontSize: 15),
      ),
      const SizedBox(height: 16),
      DButton(
        label: 'Appeler le support',
        icon: Icons.support_agent_rounded,
        onTap: () {
          Navigator.of(context).pop();
          _callSupport(context, ref);
        },
      ),
    ],
  );
}

/// Documents du dossier validé.
class _DocumentsSheet extends StatelessWidget {
  const _DocumentsSheet({required this.dossier});
  final DriverDossier dossier;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Semantics(header: true, child: Text('Documents', style: DText.heading)),
      const SizedBox(height: 8),
      for (final kind in receivedKinds(dossier))
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: MergeSemantics(
            child: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: D.green),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    documentLabel(kind),
                    style: DText.cardTitle.copyWith(fontSize: 16),
                  ),
                ),
                Text('Validé', style: DText.bodyMuted.copyWith(fontSize: 14)),
              ],
            ),
          ),
        ),
    ],
  );
}

/// Choix de l'application de navigation.
class _NavAppSheet extends ConsumerWidget {
  const _NavAppSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(navAppProvider).value ?? NavApp.google;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text('Application de navigation', style: DText.heading),
        ),
        const SizedBox(height: 4),
        Text(
          'Les itinéraires s\'ouvrent dans cette application.',
          style: DText.bodyMuted.copyWith(fontSize: 15),
        ),
        const SizedBox(height: 8),
        RadioGroup<NavApp>(
          groupValue: current,
          onChanged: (app) {
            if (app == null) return;
            ref.read(navAppProvider.notifier).set(app);
            Navigator.of(context).pop();
          },
          child: Column(
            children: [
              for (final app in navAppsFor(defaultTargetPlatform))
                RadioListTile<NavApp>(
                  value: app,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    app.label,
                    style: DText.cardTitle.copyWith(fontSize: 16),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
