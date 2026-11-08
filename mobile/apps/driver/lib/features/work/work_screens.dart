import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../app/driver_dossier.dart';
import '../../common/ui.dart';
import '../earnings/earnings_screen.dart';
import '../home/home_screen.dart';
import '../mission/mission_screen.dart';
import '../missions/missions_tab.dart';
import 'work_state.dart';
import 'work_ui.dart';

/// App livreur validé (spec 033) : Accueil, Missions, Gains, Profil, avec la
/// barre du bas claire. Une mission en cours remplace l'Accueil.
class DriverShell extends ConsumerStatefulWidget {
  const DriverShell({super.key});

  @override
  ConsumerState<DriverShell> createState() => _DriverShellState();
}

class _DriverShellState extends ConsumerState<DriverShell> {
  var _tab = 0;

  @override
  Widget build(BuildContext context) {
    final mission = ref.watch(workProvider.select((s) => s.mission));
    return Scaffold(
      backgroundColor: D.page,
      body: mission != null && _tab == 0
          ? MissionScreen(mission: mission)
          : IndexedStack(
              index: _tab,
              children: [
                const HomeTab(),
                MissionsTab(onOpenMission: () => setState(() => _tab = 0)),
                const EarningsTab(),
                const _ProfileTab(),
              ],
            ),
      bottomNavigationBar: DBottomNav(
        tabs: DBottomNav.driverTabs,
        index: _tab,
        onSelect: (i) => setState(() => _tab = i),
      ),
    );
  }
}

class _ProfileTab extends ConsumerWidget {
  const _ProfileTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final user = switch (ref.watch(authControllerProvider)) {
      AuthSignedIn(:final user) => user,
      _ => null,
    };
    final dossier = ref.watch(driverDossierProvider).value;
    final name = [
      user?.firstName,
      user?.lastName,
    ].whereType<String>().where((s) => s.isNotEmpty).join(' ');
    void open(Widget p) =>
        Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => p));
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(IviaSpacing.screen),
        children: [
          Text(
            'Mon profil',
            style: t.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: W.navy,
              borderRadius: BorderRadius.circular(W.radius),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 34,
                  backgroundColor: W.accent,
                  foregroundImage: user?.avatarUrl == null
                      ? null
                      : NetworkImage(user!.avatarUrl!),
                  child: Text(
                    name.isEmpty ? '?' : name[0],
                    style: t.headlineSmall?.copyWith(color: Colors.white),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name.isEmpty ? 'Livreur ivia' : name,
                        style: t.titleLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const WPill(
                        'Livreur validé',
                        bg: Color(0x33FFFFFF),
                        fg: Colors.white,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          WCard(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                ListTile(
                  leading: const WIcon(Icons.two_wheeler, size: 42),
                  title: const Text('Véhicule'),
                  subtitle: Text(
                    dossier == null
                        ? '—'
                        : '${dossier.vehicleType.name} · ${dossier.vehiclePlate}',
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const WIcon(Icons.devices_outlined, size: 42),
                  title: const Text('Appareils connectés'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => open(const ConnectedDevicesScreen()),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const WIcon(Icons.support_agent, size: 42),
                  title: const Text('Assistance livreurs'),
                  subtitle: const Text('+228 99 30 99 45'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          WCard(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: ListTile(
              leading: const WIcon(
                Icons.logout,
                bg: W.softRed,
                fg: W.red,
                size: 42,
              ),
              title: const Text(
                'Se déconnecter',
                style: TextStyle(color: W.red, fontWeight: FontWeight.w800),
              ),
              onTap: () async {
                await ref.read(workProvider.notifier).setOnline(false);
                await ref.read(authControllerProvider.notifier).signOut();
              },
            ),
          ),
        ],
      ),
    );
  }
}
