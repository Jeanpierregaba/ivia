import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../app/driver_dossier.dart';
import '../../common/formats.dart';
import '../../common/ui.dart';
import '../earnings/earnings.dart';
import '../mission/eta.dart';
import '../mission/mission_ui.dart';
import '../work/work_state.dart';

/// Onglet d'une mission dans D17.
enum MissionGroup { active, done, cancelled }

/// Statuts d'une mission en cours (boutique et pharmacie).
const _activeStatuses = {
  'assigned',
  'at_shop',
  'picked_up',
  'at_customer',
  'returning',
};

/// En cours, terminée (livrée) ou annulée (annulée, désistement, non livrée).
MissionGroup missionGroup(WorkMission m) {
  if (m.deliveredAt != null || m.status == 'delivered') {
    return MissionGroup.done;
  }
  // `returning` : non livrée, le colis repart à la boutique (en cours).
  if (_activeStatuses.contains(m.status)) return MissionGroup.active;
  return MissionGroup.cancelled;
}

/// Recherche par numéro de commande (« 1042 », « #1042 », « IV-001042 »).
bool matchesQuery(WorkMission m, String query) {
  final q = query.trim().toLowerCase().replaceAll('#', '');
  if (q.isEmpty) return true;
  final ref = m.reference.toLowerCase();
  return ref.contains(q) || shortRef(m.reference).contains(q);
}

/// Missions (D17) : en-tête sombre et recherche par numéro, onglets
/// « En cours · n », « Terminées », « Annulées », une carte par mission.
/// Missions des [historyDays] derniers jours ; la mission en cours vient de
/// l'état du travail (relu toutes les 4 s). La cloche des maquettes est
/// masquée : l'app n'a pas de notifications (spec 033).
class MissionsTab extends ConsumerStatefulWidget {
  const MissionsTab({super.key, required this.onOpenMission});

  /// Ouvre l'écran de la mission en cours (onglet Accueil).
  final VoidCallback onOpenMission;

  @override
  ConsumerState<MissionsTab> createState() => _MissionsTabState();
}

class _MissionsTabState extends ConsumerState<MissionsTab> {
  final _search = TextEditingController();
  var _group = MissionGroup.active;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(missionHistoryProvider);
    final current = ref.watch(workProvider.select((s) => s.mission));
    final all = <WorkMission>[
      ?current,
      for (final m in history.value ?? const <WorkMission>[])
        if (m.id != current?.id) m,
    ];
    final byGroup = {
      for (final g in MissionGroup.values)
        g: [
          for (final m in all)
            if (missionGroup(m) == g) m,
        ],
    };
    final query = _search.text;
    final shown = [
      for (final m in byGroup[_group]!)
        if (matchesQuery(m, query)) m,
    ];
    final loading = history.isLoading && !history.hasValue;
    final failed = history.hasError && !history.hasValue;

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(missionHistoryProvider);
        await ref.read(missionHistoryProvider.future).catchError((_) {
          return const <WorkMission>[];
        });
      },
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          D.gutter,
          MediaQuery.paddingOf(context).top + 6,
          D.gutter,
          24,
        ),
        children: [
          _Header(controller: _search, onChanged: (_) => setState(() {})),
          const SizedBox(height: 12),
          _Tabs(
            group: _group,
            activeCount: byGroup[MissionGroup.active]!.length,
            onSelect: (g) => setState(() => _group = g),
          ),
          const SizedBox(height: 12),
          if (loading && _group != MissionGroup.active)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (failed && _group != MissionGroup.active)
            _Empty(
              icon: Icons.cloud_off_rounded,
              text: 'Impossible de charger les missions.',
              action: 'Réessayer',
              onAction: () => ref.invalidate(missionHistoryProvider),
            )
          else if (shown.isEmpty)
            _Empty(
              icon: Icons.inventory_2_outlined,
              text: query.trim().isNotEmpty
                  ? 'Aucune commande ne correspond à « ${query.trim()} ».'
                  : switch (_group) {
                      MissionGroup.active => 'Aucune mission en cours.',
                      MissionGroup.done =>
                        'Aucune mission terminée ces deux derniers mois.',
                      MissionGroup.cancelled => 'Aucune mission annulée.',
                    },
            )
          else
            for (final m in shown)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: MissionCard(
                  mission: m,
                  onTap: missionGroup(m) == MissionGroup.active
                      ? widget.onOpenMission
                      : () => _showDetails(context, m),
                ),
              ),
        ],
      ),
    );
  }

  Future<void> _showDetails(BuildContext context, WorkMission m) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        builder: (_) => _MissionDetails(mission: m),
      );
}

class _Header extends StatelessWidget {
  const _Header({required this.controller, required this.onChanged});
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: D.night,
      borderRadius: BorderRadius.circular(34),
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(18, 26, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              'Missions',
              style: DText.hero.copyWith(color: Colors.white, fontSize: 34),
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: controller,
            onChanged: onChanged,
            textInputAction: TextInputAction.search,
            style: DText.body.copyWith(color: Colors.white, fontSize: 16),
            cursorColor: Colors.white,
            decoration: InputDecoration(
              hintText: 'Rechercher une commande',
              hintStyle: DText.body.copyWith(color: D.nightMuted, fontSize: 16),
              prefixIcon: const Padding(
                padding: EdgeInsetsDirectional.only(start: 16, end: 8),
                child: Icon(Icons.search_rounded, color: D.nightMuted),
              ),
              suffixIcon: controller.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Effacer la recherche',
                      icon: const Icon(
                        Icons.close_rounded,
                        color: D.nightMuted,
                      ),
                      onPressed: () {
                        controller.clear();
                        onChanged('');
                      },
                    ),
              filled: true,
              fillColor: D.nightTile,
              contentPadding: const EdgeInsets.symmetric(vertical: 16),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(IviaRadius.pill),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(IviaRadius.pill),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(IviaRadius.pill),
                borderSide: const BorderSide(color: D.blueOnDark),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Onglets en pilules : l'onglet actif est bleu.
class _Tabs extends StatelessWidget {
  const _Tabs({
    required this.group,
    required this.activeCount,
    required this.onSelect,
  });
  final MissionGroup group;
  final int activeCount;
  final ValueChanged<MissionGroup> onSelect;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(IviaRadius.pill),
    ),
    child: Padding(
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          for (final (g, label) in [
            (MissionGroup.active, 'En cours · $activeCount'),
            (MissionGroup.done, 'Terminées'),
            (MissionGroup.cancelled, 'Annulées'),
          ])
            Expanded(
              child: Semantics(
                button: true,
                selected: g == group,
                child: Material(
                  color: g == group ? D.blue : Colors.transparent,
                  borderRadius: BorderRadius.circular(IviaRadius.pill),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => onSelect(g),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 40),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 10,
                        ),
                        child: Center(
                          child: Text(
                            label,
                            textAlign: TextAlign.center,
                            style: DText.button.copyWith(
                              fontSize: 15,
                              color: g == group ? Colors.white : D.label,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

/// Carte d'une mission : n°, retrait → livraison, statut, gain, heures.
class MissionCard extends ConsumerWidget {
  const MissionCard({super.key, required this.mission, required this.onTap});
  final WorkMission mission;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = mission;
    final group = missionGroup(m);
    final (tag, tagBg, tagFg) = statusTag(m);
    final area = m.client?.neighborhood ?? '';
    final facts = group == MissionGroup.active
        ? _activeFacts(ref, m)
        : _pastFacts(m, DateTime.now());
    // Grande police : le statut passe sous le numéro.
    final bigText = MediaQuery.textScalerOf(context).scale(10) > 15;
    return DCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MergeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    DIconTile(
                      m.pharmacy
                          ? Icons.local_pharmacy_rounded
                          : Icons.inventory_2_rounded,
                      size: 42,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            m.reference.isEmpty
                                ? 'Course'
                                : shortRef(m.reference),
                            style: DText.cardTitle.copyWith(fontSize: 17),
                          ),
                          if (m.pickup.name.isNotEmpty)
                            _Route(from: m.pickup.name, to: area),
                        ],
                      ),
                    ),
                    if (!bigText) ...[
                      const SizedBox(width: 8),
                      MTag(tag, bg: tagBg, fg: tagFg),
                    ],
                  ],
                ),
                if (bigText) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: MTag(tag, bg: tagBg, fg: tagFg),
                  ),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        formatXof(m.feeXof),
                        style: DText.amount.copyWith(
                          fontSize: 24,
                          color: group == MissionGroup.cancelled
                              ? D.muted
                              : D.ink,
                          decoration: group == MissionGroup.cancelled
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                    ),
                    const ExcludeSemantics(
                      child: Icon(Icons.chevron_right_rounded, color: D.label),
                    ),
                  ],
                ),
                if (facts.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    child: Divider(height: 1, color: D.line),
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final (label, value) in facts)
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                label,
                                style: DText.bodyMuted.copyWith(fontSize: 13),
                              ),
                              Text(
                                value,
                                style: DText.cardTitle.copyWith(fontSize: 15),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// En cours : retrait (fait ou à venir) et arrivée prévue, estimée depuis
  /// la position du livreur (vol d'oiseau, vitesse du véhicule).
  List<(String, String)> _activeFacts(WidgetRef ref, WorkMission m) {
    final here = ref.watch(herePositionProvider).value;
    final vehicle =
        ref.watch(driverDossierProvider).value?.vehicleType ??
        VehicleType.motorbike;
    final now = ref.read(apiClientProvider).now();
    String? eta(GeoPoint? to) => here == null || to == null
        ? null
        : hhmm(arrivalAt(now, straightMeters(here, to), vehicle));
    final picked = m.pickedUpAt;
    if (picked == null) {
      final at = eta(m.pickup.location);
      return [
        ('Acceptée', hhmm(m.assignedAt)),
        if (at != null) ('Retrait prévu', at),
      ];
    }
    final at = eta(m.client?.location);
    return [('Retrait', hhmm(picked)), if (at != null) ('Arrivée prévue', at)];
  }
}

/// « Chez Afi → Bè Kpota » (flèche dessinée : absente de la police).
class _Route extends StatelessWidget {
  const _Route({required this.from, required this.to});
  final String from, to;

  @override
  Widget build(BuildContext context) {
    final style = DText.bodyMuted.copyWith(fontSize: 13);
    return Text.rich(
      TextSpan(
        style: style,
        children: [
          TextSpan(text: from),
          if (to.isNotEmpty) ...[
            const TextSpan(text: ' '),
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Icon(
                Icons.arrow_forward_rounded,
                size: MediaQuery.textScalerOf(context).scale(13),
                color: D.muted,
              ),
            ),
            TextSpan(text: ' $to'),
          ],
        ],
      ),
      semanticsLabel: to.isEmpty ? from : '$from vers $to',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// Terminée : heure de livraison et distance estimée du retrait au client ;
/// annulée : date et motif.
List<(String, String)> _pastFacts(WorkMission m, DateTime now) {
  final delivered = m.deliveredAt;
  if (delivered != null) {
    final from = m.pickup.location, to = m.client?.location;
    final today = lomeDay(delivered) == lomeDay(now);
    return [
      today
          ? ('Livrée à', hhmm(delivered))
          : ('Livrée le', '${_day(delivered)} · ${hhmm(delivered)}'),
      if (from != null && to != null)
        (
          'Distance',
          '≈ ${distance((straightMeters(from, to) * roadFactor).round())}',
        ),
    ];
  }
  final at = m.failedAt ?? m.assignedAt;
  return [
    ('Le', '${_day(at)} · ${hhmm(at)}'),
    if (m.failureReason.isNotEmpty) ('Motif', m.failureReason),
  ];
}

/// « 07/11 » (jour de Lomé).
String _day(DateTime d) {
  final day = lomeDay(d);
  return '${day.day.toString().padLeft(2, '0')}/'
      '${day.month.toString().padLeft(2, '0')}';
}

/// Libellé et couleurs du statut d'une mission.
(String, Color, Color) statusTag(WorkMission m) {
  switch (missionGroup(m)) {
    case MissionGroup.done:
      return ('Livrée', D.page, D.label);
    case MissionGroup.cancelled:
      return switch (m.status) {
        'withdrawn' => ('Désistement', D.redSoft, D.red),
        'returned' => ('Non livrée', D.redSoft, D.red),
        _ when m.failedAt != null => ('Non livrée', D.redSoft, D.red),
        _ => ('Annulée', D.redSoft, D.red),
      };
    case MissionGroup.active:
      if (m.status == 'returning') {
        return (
          'Retour',
          IviaDriverColors.warningSoft,
          IviaDriverColors.warning,
        );
      }
      return m.pickedUpAt == null
          ? ('Vers le retrait', D.blueSoft, D.blue)
          : ('En route', D.blueSoft, D.blue);
  }
}

class _Empty extends StatelessWidget {
  const _Empty({
    required this.icon,
    required this.text,
    this.action,
    this.onAction,
  });
  final IconData icon;
  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 12),
    child: Column(
      children: [
        DIconTile(icon, bg: Colors.white, fg: D.muted, size: 64, circle: true),
        const SizedBox(height: 14),
        Text(
          text,
          textAlign: TextAlign.center,
          style: DText.body.copyWith(fontSize: 15),
        ),
        if (action case final label?) ...[
          const SizedBox(height: 8),
          TextButton(onPressed: onAction, child: Text(label)),
        ],
      ],
    ),
  );
}

/// Détail d'une mission passée : lieux, étapes datées, gain, motif.
class _MissionDetails extends StatelessWidget {
  const _MissionDetails({required this.mission});
  final WorkMission mission;

  @override
  Widget build(BuildContext context) {
    final m = mission;
    final (tag, tagBg, tagFg) = statusTag(m);
    final steps = [
      ('Acceptée', m.assignedAt),
      if (m.pickedUpAt case final at?) ('Colis récupéré', at),
      if (m.deliveredAt case final at?) ('Livrée', at),
      if (m.failedAt case final at?) ('Non livrée', at),
    ];
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(D.gutter, 0, D.gutter, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      m.reference.isEmpty
                          ? 'Course pharmacie'
                          : 'Commande ${shortRef(m.reference)}',
                      style: DText.heading,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                MTag(tag, bg: tagBg, fg: tagFg),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              formatXof(m.feeXof),
              style: DText.amount.copyWith(fontSize: 28),
            ),
            const SizedBox(height: 12),
            _Place(
              icon: m.pharmacy
                  ? Icons.local_pharmacy_rounded
                  : Icons.storefront_rounded,
              title: m.pickup.name.isEmpty ? 'Retrait' : m.pickup.name,
              subtitle: placeAddress(m.pickup),
            ),
            if (m.client case final client?)
              _Place(
                icon: Icons.location_on_rounded,
                title: client.name.isEmpty ? 'Client' : client.name,
                subtitle: placeAddress(client),
              ),
            const SizedBox(height: 8),
            for (final (label, at) in steps)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: MergeSemantics(
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          label,
                          style: DText.body.copyWith(fontSize: 15),
                        ),
                      ),
                      Text(
                        '${_day(at)} · ${hhmm(at)}',
                        style: DText.cardTitle.copyWith(fontSize: 15),
                      ),
                    ],
                  ),
                ),
              ),
            if (m.failureReason.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Motif : ${m.failureReason}',
                style: DText.body.copyWith(fontSize: 15),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Place extends StatelessWidget {
  const _Place({required this.icon, required this.title, this.subtitle});
  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: MergeSemantics(
      child: Row(
        children: [
          DIconTile(icon, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: DText.cardTitle.copyWith(fontSize: 16)),
                if (subtitle case final s?)
                  Text(s, style: DText.bodyMuted.copyWith(fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
