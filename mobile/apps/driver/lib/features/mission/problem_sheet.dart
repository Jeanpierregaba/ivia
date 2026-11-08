import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../common/ui.dart';
import '../work/work_state.dart';
import 'mission_screen.dart' show MissionPhase;
import 'navigation.dart';

/// Assistance livreurs (numéro unique de l'app, à confirmer : TASKS.md).
const driverSupportPhone = '+22899309945';

/// « Signaler un problème » : ouvre D16.
class ProblemButton extends ConsumerWidget {
  const ProblemButton({super.key, required this.mission, required this.phase});
  final WorkMission mission;
  final MissionPhase phase;

  @override
  Widget build(BuildContext context, WidgetRef ref) => TextButton(
    onPressed: () => showProblemSheet(context, mission, phase),
    style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
    child: Text(
      'Signaler un problème',
      style: DText.button.copyWith(color: D.label, fontSize: 15),
    ),
  );
}

/// Un problème ? (D16) : situations selon l'étape, « Appeler le support ».
/// Seuls le désistement (avant le retrait) et « Client injoignable »
/// (commande de boutique) ont une suite côté serveur ; les autres situations
/// appellent le support (spec 033).
Future<void> showProblemSheet(
  BuildContext context,
  WorkMission mission,
  MissionPhase phase,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.white,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
  ),
  builder: (_) => _ProblemSheet(mission: mission, phase: phase),
);

class _ProblemSheet extends ConsumerWidget {
  const _ProblemSheet({required this.mission, required this.phase});
  final WorkMission mission;
  final MissionPhase phase;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final beforePickup =
        phase == MissionPhase.toPickup || phase == MissionPhase.atPickup;
    Future<void> support() => _callSupport(context, ref);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(D.gutter, 0, D.gutter, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text('Un problème ?', style: DText.heading),
            ),
            const SizedBox(height: 4),
            Text(
              'Choisissez la situation.',
              style: DText.bodyMuted.copyWith(fontSize: 15),
            ),
            const SizedBox(height: 8),
            if (beforePickup) ...[
              _Situation(
                icon: Icons.do_not_disturb_on_outlined,
                title: 'Je ne peux pas faire cette course',
                subtitle: 'La course repart vers un autre livreur',
                onTap: () => _withdraw(context, ref),
              ),
              if (phase == MissionPhase.atPickup)
                _Situation(
                  icon: Icons.broken_image_outlined,
                  title: 'Colis endommagé',
                  subtitle: 'Appel du support',
                  onTap: support,
                ),
            ] else ...[
              _Situation(
                icon: Icons.phone_disabled_rounded,
                title: 'Client injoignable',
                subtitle: mission.pharmacy
                    ? 'Appel du support'
                    : '10 min d\'attente et 2 appels requis',
                onTap: mission.pharmacy
                    ? support
                    : () => _unreachable(context, mission),
              ),
              _Situation(
                icon: Icons.wrong_location_outlined,
                title: 'Adresse introuvable',
                subtitle: 'Le support vous guide',
                onTap: support,
              ),
              if (phase == MissionPhase.atClient)
                _Situation(
                  icon: Icons.password_rounded,
                  title: 'Code refusé',
                  subtitle: "Le client n'a pas son code",
                  onTap: support,
                ),
            ],
            _Situation(
              icon: Icons.emergency_rounded,
              title: 'Accident ou urgence',
              subtitle: 'Appel immédiat du support',
              danger: true,
              last: true,
              onTap: support,
            ),
            const SizedBox(height: 12),
            DButton(
              label: 'Appeler le support',
              icon: Icons.support_agent_rounded,
              style: DButtonStyle.outline,
              onTap: support,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _withdraw(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    final error = await ref
        .read(workProvider.notifier)
        .run((api) => api.withdrawMission(mission, 'Empêchement du livreur'));
    if (error != null) messenger.showSnackBar(SnackBar(content: Text(error)));
  }

  Future<void> _unreachable(BuildContext context, WorkMission m) async {
    Navigator.of(context).pop();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (_) => _UnreachableSheet(mission: m),
    );
  }
}

Future<void> _callSupport(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  final ok = await ref.read(linkLauncherProvider)(
    Uri.parse('tel:$driverSupportPhone'),
  );
  if (!ok) {
    messenger.showSnackBar(
      const SnackBar(content: Text("Impossible de lancer l'appel.")),
    );
  }
}

class _Situation extends StatelessWidget {
  const _Situation({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.danger = false,
    this.last = false,
  });
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;
  final bool danger, last;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      border: last
          ? null
          : const Border(bottom: BorderSide(color: IviaDriverColors.line)),
    ),
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            DIconTile(
              icon,
              bg: danger ? D.redSoft : D.blueSoft,
              fg: danger ? D.red : D.blue,
              size: 40,
            ),
            const SizedBox(width: 14),
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
                  Text(subtitle, style: DText.bodyMuted.copyWith(fontSize: 13)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const ExcludeSemantics(
              child: Icon(Icons.chevron_right_rounded, color: D.label),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Client injoignable : appels passés, puis déclaration. Le serveur exige
/// 10 min d'attente chez le client et 2 appels ; son refus est affiché et
/// rien ne change.
class _UnreachableSheet extends ConsumerStatefulWidget {
  const _UnreachableSheet({required this.mission});
  final WorkMission mission;

  @override
  ConsumerState<_UnreachableSheet> createState() => _UnreachableSheetState();
}

class _UnreachableSheetState extends ConsumerState<_UnreachableSheet> {
  var _calls = 0, _busy = false;
  String? _error;

  Future<void> _declare() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(apiClientProvider)
          .failMission(widget.mission, 'Client injoignable', _calls);
      if (!mounted) return;
      Navigator.of(context).pop();
      await ref.read(workProvider.notifier).refresh();
    } on ApiException catch (e) {
      if (!mounted) return;
      final message = e.fields['call_attempts'] ?? e.message;
      setState(() => _error = message);
      announce(context, message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        D.gutter,
        22,
        D.gutter,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text('Client injoignable', style: DText.heading),
          ),
          const SizedBox(height: 6),
          Text(
            'Attendez 10 minutes chez le client et appelez-le au moins deux '
            'fois. Le colis retourne ensuite à la boutique.',
            style: DText.bodyMuted.copyWith(fontSize: 15),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Appels au client',
                  style: DText.cardTitle.copyWith(fontSize: 16),
                ),
              ),
              IconButton(
                tooltip: 'Un appel de moins',
                onPressed: _calls > 0 ? () => setState(() => _calls--) : null,
                icon: const Icon(Icons.remove_circle_outline_rounded),
              ),
              Semantics(
                liveRegion: true,
                child: Text(
                  '$_calls',
                  style: DText.amount.copyWith(fontSize: 22),
                ),
              ),
              IconButton(
                tooltip: 'Un appel de plus',
                onPressed: () => setState(() => _calls++),
                icon: const Icon(Icons.add_circle_outline_rounded),
              ),
            ],
          ),
          if (_error case final error?) ...[
            const SizedBox(height: 8),
            Text(error, style: DText.body.copyWith(color: IviaColors.error)),
          ],
          const SizedBox(height: 16),
          DButton(
            label: 'Déclarer le client injoignable',
            busy: _busy,
            onTap: _declare,
          ),
        ],
      ),
    ),
  );
}
