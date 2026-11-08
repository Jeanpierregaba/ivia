import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../app/driver_dossier.dart';
import '../../common/formats.dart';
import '../../common/ui.dart';
import '../offer/offer_card.dart' show parcelLabel;
import '../profile/settings.dart';
import '../work/work_screens.dart' show MissionView;
import '../work/work_state.dart';
import 'eta.dart';
import 'mission_ui.dart';
import 'navigation.dart';
import 'pickup_view.dart';

/// Étape d'une mission en cours.
enum MissionPhase { toPickup, atPickup, toClient, atClient }

/// Étape d'après le serveur ; [arrivedLocally] : arrivées signalées dans
/// l'app, pour les courses pharmacie qui n'ont pas d'étape « arrivé » côté
/// serveur.
MissionPhase missionPhase(WorkMission m, Set<MissionPhase> arrivedLocally) {
  if (m.pharmacy) {
    if (m.pickedUpAt == null) {
      return arrivedLocally.contains(MissionPhase.toPickup)
          ? MissionPhase.atPickup
          : MissionPhase.toPickup;
    }
    return arrivedLocally.contains(MissionPhase.toClient)
        ? MissionPhase.atClient
        : MissionPhase.toClient;
  }
  if (m.arrivedPickupAt == null) return MissionPhase.toPickup;
  if (m.pickedUpAt == null) return MissionPhase.atPickup;
  if (m.arrivedClientAt == null) return MissionPhase.toClient;
  return MissionPhase.atClient;
}

/// Mission en cours : trajets vers le retrait (D11) et vers le client (D13) ;
/// retrait et remise sur l'écran existant (refaits aux tâches 13 à 15).
class MissionScreen extends ConsumerStatefulWidget {
  const MissionScreen({super.key, required this.mission});
  final WorkMission mission;

  @override
  ConsumerState<MissionScreen> createState() => _MissionScreenState();
}

class _MissionScreenState extends ConsumerState<MissionScreen> {
  final _arrived = <MissionPhase>{};
  String? _missionId;

  @override
  Widget build(BuildContext context) {
    final m = widget.mission;
    if (_missionId != m.id) {
      _missionId = m.id;
      _arrived.clear();
    }
    final phase = missionPhase(m, _arrived);
    return switch (phase) {
      MissionPhase.toPickup || MissionPhase.toClient => _RouteView(
        key: ValueKey('${m.id}-${phase.name}'),
        mission: m,
        toClient: phase == MissionPhase.toClient,
        onArrived: () => _arrive(m, phase),
      ),
      MissionPhase.atPickup => PickupView(mission: m),
      MissionPhase.atClient => MissionView(mission: m),
    };
  }

  /// « Glisser à l'arrivée » : étape du serveur (boutique) ou de l'app
  /// (pharmacie).
  Future<void> _arrive(WorkMission m, MissionPhase phase) async {
    if (m.pharmacy) {
      setState(() => _arrived.add(phase));
      return;
    }
    final step = phase == MissionPhase.toPickup
        ? 'arrived-at-shop'
        : 'arrived-at-customer';
    final error = await ref
        .read(workProvider.notifier)
        .run((api) => api.missionStep(m, step));
    if (error != null && mounted) {
      announce(context, error);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    }
  }
}

/// Trajet vers le retrait (D11) ou vers le client (D13) : carte et tracé,
/// bandeau de destination, volet de l'étape, « Glisser à l'arrivée ».
/// Le guidage tour par tour est masqué : il se fait dans l'app de
/// navigation (spec 033).
class _RouteView extends ConsumerStatefulWidget {
  const _RouteView({
    super.key,
    required this.mission,
    required this.toClient,
    required this.onArrived,
  });
  final WorkMission mission;
  final bool toClient;
  final Future<void> Function() onArrived;

  @override
  ConsumerState<_RouteView> createState() => _RouteViewState();
}

class _RouteViewState extends ConsumerState<_RouteView> {
  GeoRoute? _route;
  GeoPoint? _routedFrom;
  Timer? _refresh;

  MissionPlace? get _target =>
      widget.toClient ? widget.mission.client : widget.mission.pickup;

  @override
  void initState() {
    super.initState();
    // Itinéraire relu à la minute (la position avance entre-temps).
    _refresh = Timer.periodic(const Duration(minutes: 1), (_) {
      _routedFrom = null;
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  Future<void> _fetchRoute(GeoPoint from, GeoPoint to, VehicleType v) async {
    _routedFrom = from;
    try {
      final route = await ref
          .read(apiClientProvider)
          .geoRoute(from, to, profile: routeProfile(v));
      if (mounted) setState(() => _route = route);
    } on ApiException {
      // Repli à vol d'oiseau.
    }
  }

  Future<void> _openNavigation(GeoPoint to) async {
    final app = await ref.read(navAppProvider.future);
    final ok = await ref.read(linkLauncherProvider)(app.route(to));
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Impossible d'ouvrir ${app.label}.")),
      );
    }
  }

  Future<void> _call(String phone) async {
    final ok = await ref.read(linkLauncherProvider)(Uri.parse('tel:$phone'));
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Impossible de lancer l'appel.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.mission;
    final target = _target;
    final here = ref.watch(herePositionProvider).value;
    final vehicle =
        ref.watch(driverDossierProvider).value?.vehicleType ??
        VehicleType.motorbike;
    final to = target?.location;
    if (here != null && to != null && _routedFrom == null) {
      unawaited(_fetchRoute(here, to, vehicle));
    }
    final leg = here != null && to != null
        ? estimateLeg(
            straight: straightMeters(here, to),
            vehicle: vehicle,
            route: _route,
          )
        : null;
    final navApp = ref.watch(navAppProvider).value ?? NavApp.google;
    return LayoutBuilder(
      builder: (context, box) => Column(
        children: [
          Expanded(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  bottom: -32,
                  child: ExcludeSemantics(
                    child: _TripMap(
                      here: here,
                      target: to,
                      toClient: widget.toClient,
                      pharmacy: m.pharmacy,
                      route: _route,
                    ),
                  ),
                ),
                Positioned(
                  left: 14,
                  right: 14,
                  top: MediaQuery.paddingOf(context).top + 4,
                  child: _DestinationBanner(
                    name: target?.name ?? '',
                    leg: leg,
                    toClient: widget.toClient,
                  ),
                ),
              ],
            ),
          ),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: box.maxHeight * .7),
            child: DecoratedBox(
              decoration: const BoxDecoration(
                borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x1A0B1A33),
                    blurRadius: 24,
                    offset: Offset(0, -4),
                  ),
                ],
              ),
              child: DSheet(
                child: Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (widget.toClient)
                          _ToClient(
                            mission: m,
                            leg: leg,
                            onCall: _call,
                            onNavigate: to == null
                                ? null
                                : () => _openNavigation(to),
                            navApp: navApp,
                          )
                        else
                          _ToPickup(
                            mission: m,
                            onCall: _call,
                            onNavigate: to == null
                                ? null
                                : () => _openNavigation(to),
                            navApp: navApp,
                          ),
                        const SizedBox(height: 16),
                        DSlide(
                          label: "Glisser à l'arrivée",
                          dark: true,
                          onConfirmed: widget.onArrived,
                        ),
                        if (!widget.toClient) _Withdraw(mission: m),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Carte du trajet : position, destination et tracé de l'itinéraire.
class _TripMap extends StatelessWidget {
  const _TripMap({
    required this.here,
    required this.target,
    required this.toClient,
    required this.pharmacy,
    required this.route,
  });
  final GeoPoint? here, target;
  final bool toClient, pharmacy;
  final GeoRoute? route;

  @override
  Widget build(BuildContext context) {
    final a = here, b = target;
    final center = switch ((a, b)) {
      (final a?, final b?) => GeoPoint(
        lat: (a.lat + b.lat) / 2,
        lng: (a.lng + b.lng) / 2,
      ),
      (final a?, null) => a,
      (null, final b?) => b,
      _ => lome,
    };
    final span = a != null && b != null ? straightMeters(a, b) : 0;
    // Les deux points à l'écran, au-dessus du volet.
    final zoom = span < 600
        ? 16.0
        : span < 1500
        ? 15.0
        : span < 3500
        ? 14.0
        : span < 8000
        ? 13.0
        : 12.0;
    final polyline = route?.polyline ?? '';
    return IviaMap(
      center: center,
      zoom: zoom,
      interactive: false,
      route: polyline.isEmpty ? const [] : decodePolyline6(polyline),
      markers: [
        if (b != null)
          IviaMapMarker(
            id: 'target',
            point: b,
            color: toClient ? D.red : D.night,
            icon: toClient
                ? Icons.home_rounded
                : pharmacy
                ? Icons.local_pharmacy_rounded
                : Icons.storefront_rounded,
          ),
        if (a != null)
          IviaMapMarker(
            id: 'here',
            point: a,
            color: D.blue,
            icon: Icons.navigation_rounded,
          ),
      ],
    );
  }
}

/// Bandeau sombre : distance restante, destination, durée et heure
/// d'arrivée estimées.
class _DestinationBanner extends StatelessWidget {
  const _DestinationBanner({
    required this.name,
    required this.leg,
    required this.toClient,
  });
  final String name;
  final Leg? leg;
  final bool toClient;

  @override
  Widget build(BuildContext context) {
    final leg = this.leg;
    final where = toClient ? 'Vers le client' : 'Vers $name';
    // Bandeau posé sur la carte : texte agrandi jusqu'à 150 %, au-delà il
    // cacherait la carte (le volet reprend les mêmes chiffres en grand).
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.5,
      child: MergeSemantics(
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
          decoration: BoxDecoration(
            color: D.night,
            borderRadius: BorderRadius.circular(26),
          ),
          child: Row(
            children: [
              ExcludeSemantics(
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: D.blue,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.near_me_rounded,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      leg == null ? 'Position inconnue' : distance(leg.meters),
                      style: DText.amount.copyWith(
                        color: Colors.white,
                        fontSize: leg == null ? 18 : 26,
                      ),
                    ),
                    Text(
                      where,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DText.body.copyWith(
                        color: D.nightMuted,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              if (leg != null) ...[
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      duration(leg.duration),
                      style: DText.cardTitle.copyWith(
                        color: D.blueOnDark,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      hhmm(DateTime.now().add(leg.duration)),
                      style: DText.body.copyWith(
                        color: D.nightMuted,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Volet vers le retrait (D11).
class _ToPickup extends StatelessWidget {
  const _ToPickup({
    required this.mission,
    required this.onCall,
    required this.onNavigate,
    required this.navApp,
  });
  final WorkMission mission;
  final void Function(String phone) onCall;
  final VoidCallback? onNavigate;
  final NavApp navApp;

  @override
  Widget build(BuildContext context) {
    final m = mission;
    final place = m.pickup;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  m.pharmacy
                      ? 'ÉTAPE 1 SUR 2 · PHARMACIE'
                      : 'ÉTAPE 1 SUR 2 · RETRAIT',
                  style: DText.overline.copyWith(color: D.blue),
                ),
              ),
            ),
            if (m.reference.isNotEmpty) ...[
              const SizedBox(width: 8),
              MTag(shortRef(m.reference)),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Text(place.name, style: DText.heading.copyWith(fontSize: 26)),
        if (placeAddress(place) case final address?) ...[
          const SizedBox(height: 4),
          Text(address, style: DText.bodyMuted.copyWith(fontSize: 14)),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            if (m.itemsCount > 0)
              MTag(
                m.pharmacy
                    ? '${m.itemsCount} ${m.itemsCount > 1 ? 'produits' : 'produit'}'
                    : '${m.itemsCount} ${m.itemsCount > 1 ? 'articles' : 'article'}',
              ),
            if (m.parcelSize case final size?) MTag(parcelLabel(size)),
            if (m.awaitingPayment)
              const MTag(
                'Paiement en attente',
                bg: IviaDriverColors.warningSoft,
                fg: IviaDriverColors.warning,
              )
            else
              const MTag('Payée', bg: D.greenSoft, fg: D.green),
          ],
        ),
        if (m.awaitingPayment) ...[
          const SizedBox(height: 10),
          Text(
            "Le client n'a pas encore payé. Rendez-vous à la pharmacie : "
            'les produits vous seront remis dès son paiement.',
            style: DText.bodyMuted.copyWith(fontSize: 14),
          ),
        ],
        const SizedBox(height: 14),
        _Actions(
          phone: place.phone,
          callLabel: m.pharmacy
              ? 'Appeler la pharmacie'
              : 'Appeler la boutique',
          onCall: onCall,
          onNavigate: onNavigate,
          navApp: navApp,
        ),
      ],
    );
  }
}

/// Volet vers le client (D13).
class _ToClient extends StatelessWidget {
  const _ToClient({
    required this.mission,
    required this.leg,
    required this.onCall,
    required this.onNavigate,
    required this.navApp,
  });
  final WorkMission mission;
  final Leg? leg;
  final void Function(String phone) onCall;
  final VoidCallback? onNavigate;
  final NavApp navApp;

  @override
  Widget build(BuildContext context) {
    final m = mission;
    final client = m.client;
    final leg = this.leg;
    final pickupTo = switch ((m.pickup.location, client?.location)) {
      (final a?, final b?) => straightMeters(a, b) * roadFactor,
      _ => null,
    };
    final progress = leg == null || pickupTo == null || pickupTo == 0
        ? 0.0
        : (1 - leg.meters / pickupTo).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            'ÉTAPE 2 SUR 2 · LIVRAISON',
            style: DText.overline.copyWith(color: D.blue),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _Figure(
                leg == null ? '—' : distance(leg.meters),
                'Distance',
              ),
            ),
            Expanded(
              child: _Figure(
                leg == null ? '—' : duration(leg.duration),
                'Restant',
              ),
            ),
            Expanded(
              child: _Figure(
                leg == null ? '—' : hhmm(DateTime.now().add(leg.duration)),
                'Arrivée',
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _Progress(value: progress, pharmacy: m.pharmacy),
        if (m.pharmacy && m.pickedUpAt != null) ...[
          const SizedBox(height: 14),
          _Validated(mission: m),
        ],
        const SizedBox(height: 14),
        const Divider(height: 1, color: IviaDriverColors.line),
        const SizedBox(height: 14),
        MergeSemantics(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    color: D.blueSoft,
                    shape: BoxShape.circle,
                  ),
                  child: SizedBox.square(
                    dimension: 48,
                    child: Center(
                      child: MediaQuery.withNoTextScaling(
                        child: Text(
                          initials(client?.name ?? ''),
                          style: DText.cardTitle.copyWith(
                            color: D.blue,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (client?.name ?? '').isEmpty ? 'Client' : client!.name,
                      style: DText.cardTitle.copyWith(fontSize: 17),
                    ),
                    if (client != null && placeAddress(client) != null)
                      Text(
                        placeAddress(client)!,
                        style: DText.bodyMuted.copyWith(fontSize: 14),
                      ),
                  ],
                ),
              ),
              // À la place de la messagerie des maquettes (pas de serveur) :
              // l'itinéraire dans l'app de navigation.
              if (onNavigate != null) ...[
                const SizedBox(width: 8),
                RoundButton(
                  icon: Icons.map_rounded,
                  tooltip: 'Ouvrir dans ${navApp.shortLabel}',
                  bg: D.blueSoft,
                  fg: D.blue,
                  onTap: onNavigate!,
                ),
              ],
              if ((client?.phone ?? '').isNotEmpty) ...[
                const SizedBox(width: 8),
                RoundButton(
                  icon: Icons.call_rounded,
                  tooltip: 'Appeler le client',
                  bg: D.blue,
                  fg: Colors.white,
                  onTap: () => onCall(client!.phone),
                ),
              ],
            ],
          ),
        ),
        if ((client?.instructions ?? '').isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: IviaDriverColors.warningSoft,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.sticky_note_2_rounded,
                  color: IviaDriverColors.warning,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '« ${client!.instructions} »',
                    style: DText.body.copyWith(color: D.ink, fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Appel et itinéraire dans l'app de navigation. La messagerie des
/// maquettes est masquée (pas de serveur).
class _Actions extends StatelessWidget {
  const _Actions({
    required this.phone,
    required this.callLabel,
    required this.onCall,
    required this.onNavigate,
    required this.navApp,
  });
  final String phone, callLabel;
  final void Function(String phone) onCall;
  final VoidCallback? onNavigate;
  final NavApp navApp;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      if (phone.isNotEmpty) ...[
        RoundButton(
          icon: Icons.call_rounded,
          tooltip: callLabel,
          bg: D.page,
          fg: D.ink,
          onTap: () => onCall(phone),
          size: 56,
        ),
        const SizedBox(width: 10),
      ],
      Expanded(
        child: OutlinedButton.icon(
          onPressed: onNavigate,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(56),
            shape: const StadiumBorder(),
            side: const BorderSide(color: D.outline, width: 1.5),
            foregroundColor: D.ink,
          ),
          icon: const Icon(Icons.map_outlined, size: 20),
          label: Text(
            'Ouvrir dans ${navApp.shortLabel}',
            style: DText.button.copyWith(color: D.ink, fontSize: 16),
          ),
        ),
      ),
    ],
  );
}

class _Figure extends StatelessWidget {
  const _Figure(this.value, this.label);
  final String value, label;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Heure insécable : réduite plutôt que coupée en gros caractères.
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value, style: DText.amount.copyWith(fontSize: 20)),
        ),
        Text(label, style: DText.bodyMuted.copyWith(fontSize: 13)),
      ],
    ),
  );
}

/// Progression retrait → client : colis, véhicule, maison.
class _Progress extends StatelessWidget {
  const _Progress({required this.value, required this.pharmacy});
  final double value;
  final bool pharmacy;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Trajet parcouru : ${(value * 100).round()} %',
    excludeSemantics: true,
    child: SizedBox(
      height: 28,
      child: LayoutBuilder(
        builder: (context, box) {
          const dot = 28.0;
          final track = box.maxWidth - dot;
          final x = dot / 2 + track * value;
          return Stack(
            alignment: Alignment.centerLeft,
            children: [
              Positioned(
                left: dot / 2,
                right: dot / 2,
                child: Container(height: 4, color: D.line),
              ),
              Positioned(
                left: dot / 2,
                width: track * value,
                child: Container(height: 4, color: D.blue),
              ),
              _Dot(
                left: 0,
                bg: D.night,
                icon: pharmacy
                    ? Icons.medication_rounded
                    : Icons.inventory_2_rounded,
              ),
              _Dot(
                left: x - dot / 2,
                bg: Colors.white,
                fg: D.blue,
                border: D.blue,
                icon: Icons.two_wheeler_rounded,
              ),
              _Dot(left: track, bg: D.red, icon: Icons.home_rounded),
            ],
          );
        },
      ),
    ),
  );
}

class _Dot extends StatelessWidget {
  const _Dot({
    required this.left,
    required this.bg,
    required this.icon,
    this.fg = Colors.white,
    this.border,
  });
  final double left;
  final Color bg, fg;
  final Color? border;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Positioned(
    left: left,
    child: Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        border: border == null ? null : Border.all(color: border!, width: 2),
      ),
      child: Icon(icon, color: fg, size: 15),
    ),
  );
}

/// « Je ne peux pas faire cette course » (avant le retrait).
class _Withdraw extends ConsumerWidget {
  const _Withdraw({required this.mission});
  final WorkMission mission;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final busy = ref.watch(workProvider.select((s) => s.busy));
    return TextButton(
      onPressed: busy
          ? null
          : () async {
              final error = await ref
                  .read(workProvider.notifier)
                  .run(
                    (api) =>
                        api.withdrawMission(mission, 'Empêchement du livreur'),
                  );
              if (error != null && context.mounted) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(error)));
              }
            },
      style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
      child: Text(
        'Je ne peux pas faire cette course',
        style: DText.button.copyWith(color: D.label, fontSize: 15),
      ),
    );
  }
}

/// « La pharmacie a validé la remise · hh:mm » et les espèces avancées
/// (ADR 0014), rappelés pendant le trajet vers le client.
class _Validated extends StatelessWidget {
  const _Validated({required this.mission});
  final WorkMission mission;

  @override
  Widget build(BuildContext context) {
    final at = mission.pickedUpAt!;
    final cash = mission.cashAdvancedXof;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: D.greenSoft,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.verified_rounded, color: D.green, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'La pharmacie a validé la remise · ${hhmm(at)}',
                    style: DText.label.copyWith(color: D.ink, fontSize: 14),
                  ),
                  if (cash != null && cash > 0)
                    Text(
                      'Espèces avancées : ${formatXof(cash)} (remboursées '
                      'par ivia)',
                      style: DText.bodyMuted.copyWith(fontSize: 13),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
