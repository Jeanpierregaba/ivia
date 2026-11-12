import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../common/ui.dart';
import '../earnings/earnings.dart';
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
  void initState() {
    super.initState();
    // Push réels (Firebase) : touchés, ils ramènent à l'accueil (proposition
    // ou mission en cours).
    unawaited(
      ref
          .read(iviaPushProvider('driver'))
          .start(
            onOpen: (_) {
              if (mounted) setState(() => _tab = 0);
            },
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // « Livraison terminée » (D15) passe avant une mission encore présente.
    final mission = ref.watch(
      workProvider.select((s) => s.delivered == null ? s.mission : null),
    );
    // Commande annulée pendant la mission : l'accueil affiche le message,
    // annoncé aussi au lecteur d'écran.
    // Proposition reçue sur un autre onglet : retour à l'Accueil, où elle
    // s'affiche (sinon elle sonnerait sans être visible).
    ref.listen(workProvider.select((s) => s.offer?.id), (previous, offer) {
      if (offer != null && offer != previous && _tab != 0) {
        setState(() => _tab = 0);
      }
    });
    ref.listen(workProvider.select((s) => s.error), (_, error) {
      if (error == WorkController.cancelledMessage) announce(context, error!);
    });
    return Scaffold(
      backgroundColor: D.page,
      // L'écran de mission reste monté sur les autres onglets : arrivée
      // gardée dans l'app (pharmacie), cases cochées et code saisi survivent
      // au changement d'onglet.
      body: IviaTabSwitcher(
        index: _tab,
        children: [
          if (mission != null)
            MissionScreen(key: ValueKey(mission.id), mission: mission)
          else
            const HomeTab(),
          MissionsTab(onOpenMission: () => setState(() => _tab = 0)),
          const EarningsTab(),
          const ProfileTab(),
        ],
      ),
      bottomNavigationBar: DBottomNav(
        tabs: DBottomNav.driverTabs,
        index: _tab,
        onSelect: (i) {
          // Missions et Gains : historique relu à chaque ouverture (missions
          // annulées, livrées ou retirées depuis la dernière lecture).
          if (i != _tab && (i == 1 || i == 2)) {
            ref.invalidate(missionHistoryProvider);
          }
          setState(() => _tab = i);
        },
      ),
    );
  }
}
