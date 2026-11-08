import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../common/ui.dart';
import '../earnings/earnings_screen.dart';
import '../home/home_screen.dart';
import '../mission/mission_screen.dart';
import '../missions/missions_tab.dart';
import '../profile/profile_tab.dart';
import 'work_state.dart';

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
                const ProfileTab(),
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
