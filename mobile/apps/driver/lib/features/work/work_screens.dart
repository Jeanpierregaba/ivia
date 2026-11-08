import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../app/driver_dossier.dart';
import '../../common/ui.dart';
import '../earnings/earnings_screen.dart';
import '../home/home_screen.dart';
import '../mission/mission_screen.dart';
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
              children: const [
                HomeTab(),
                _HistoryTab(),
                EarningsTab(),
                _ProfileTab(),
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

/// Course en cours : carte, étapes, appels, remise par code.
class MissionView extends ConsumerStatefulWidget {
  const MissionView({super.key, required this.mission});
  final WorkMission mission;

  @override
  ConsumerState<MissionView> createState() => _MissionViewState();
}

class _MissionViewState extends ConsumerState<MissionView> {
  final _code = TextEditingController();
  var _checked = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _do(Future<void> Function(IviaApiClient) a) async {
    final err = await ref.read(workProvider.notifier).run(a);
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    } else {
      ref.invalidate(workHistoryProvider);
    }
  }

  Future<void> _fail(WorkMission m) async {
    final reason = TextEditingController();
    var calls = 2;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('Livraison impossible'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: reason,
                decoration: const InputDecoration(
                  labelText: 'Motif (client absent, adresse introuvable…)',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Expanded(child: Text('Appels au client')),
                  IconButton(
                    onPressed: calls > 0 ? () => set(() => calls--) : null,
                    icon: const Icon(Icons.remove),
                  ),
                  Text('$calls'),
                  IconButton(
                    onPressed: () => set(() => calls++),
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Confirmer'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      await _do((api) => api.failMission(m, reason.text.trim(), calls));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final m = widget.mission;
    final busy = ref.watch(workProvider.select((s) => s.busy));
    final atClient = m.pharmacy
        ? m.pickedUpAt != null
        : m.arrivedClientAt != null;
    final goingToClient = m.pickedUpAt != null;
    final target = goingToClient ? m.client : m.pickup;
    final points = <(GeoPoint, IconData, Color)>[
      if (m.pickup.location case final p?)
        (p, m.pharmacy ? Icons.local_pharmacy : Icons.storefront, W.navy),
      if (m.client?.location case final p?) (p, Icons.person_pin_circle, W.red),
    ];
    final step = m.pharmacy
        ? (m.awaitingPayment
              ? 0
              : m.pickedUpAt == null
              ? 1
              : 3)
        : (m.arrivedPickupAt == null
              ? 0
              : m.pickedUpAt == null
              ? 1
              : m.arrivedClientAt == null
              ? 2
              : 3);
    return Stack(
      children: [
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: MediaQuery.sizeOf(context).height * .36,
          child: WMap(points: points.reversed.toList()),
        ),
        Positioned.fill(
          top: MediaQuery.sizeOf(context).height * .32,
          child: Container(
            decoration: const BoxDecoration(
              color: W.page,
              borderRadius: BorderRadius.vertical(top: Radius.circular(36)),
            ),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                IviaSpacing.screen,
                24,
                IviaSpacing.screen,
                24,
              ),
              children: [
                Row(
                  children: [
                    WPill(
                      m.pharmacy
                          ? 'Médicaments ${m.reference}'
                          : 'Commande ${m.reference}',
                      bg: m.pharmacy ? W.softRed : W.soft,
                      fg: m.pharmacy ? W.red : W.accent,
                    ),
                    const Spacer(),
                    Text(
                      formatXof(m.feeXof),
                      style: t.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (m.awaitingPayment)
                  WCard(
                    color: const Color(0xFFFCEFD5),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.hourglass_top,
                          color: Color(0xFF8A5A00),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'En attente du paiement du client. Rendez-vous à la pharmacie : vous récupérerez les produits dès qu\'il aura payé.',
                            style: t.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
                for (final (place, label, isTarget) in [
                  (
                    m.pickup,
                    m.pharmacy ? 'Pharmacie' : 'Boutique',
                    !goingToClient,
                  ),
                  if (m.client != null) (m.client!, 'Client', goingToClient),
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: WCard(
                      border: isTarget ? W.accent : null,
                      child: Row(
                        children: [
                          WIcon(
                            label == 'Client'
                                ? Icons.person_outline
                                : (m.pharmacy
                                      ? Icons.local_pharmacy_outlined
                                      : Icons.storefront_outlined),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '$label · ${place.name}',
                                  style: t.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  [
                                    place.addressText,
                                    if (place.instructions.isNotEmpty)
                                      place.instructions,
                                  ].join(' · '),
                                  style: t.bodyMedium?.copyWith(color: W.muted),
                                ),
                              ],
                            ),
                          ),
                          if (place.phone.isNotEmpty)
                            WRound(
                              icon: Icons.call_outlined,
                              dark: true,
                              onTap: () => call(place.phone),
                            ),
                        ],
                      ),
                    ),
                  ),
                if (m.pharmacy && m.lines.isNotEmpty)
                  WCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'À récupérer',
                          style: t.titleSmall?.copyWith(
                            color: W.muted,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        for (final l in m.lines.where((l) => l.available))
                          Text('${l.quantity} × ${l.name}', style: t.bodyLarge),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
                if (target?.location case final p?)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(56),
                        shape: const StadiumBorder(),
                      ),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => RouteScreen(
                            title: 'Itinéraire',
                            destination: p,
                            destinationLabel: goingToClient
                                ? 'Client'
                                : (m.pharmacy ? 'Pharmacie' : 'Boutique'),
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.directions_outlined),
                      label: Text(
                        goingToClient
                            ? 'Itinéraire vers le client'
                            : 'Itinéraire vers ${m.pharmacy ? 'la pharmacie' : 'la boutique'}',
                      ),
                    ),
                  ),
                switch (step) {
                  0 when m.pharmacy => const SizedBox.shrink(),
                  0 => WButton(
                    label: 'Je suis à la boutique',
                    icon: Icons.storefront,
                    busy: busy,
                    onTap: () =>
                        _do((api) => api.missionStep(m, 'arrived-at-shop')),
                  ),
                  1 => WButton(
                    label: 'Colis récupéré',
                    icon: Icons.inventory_2_outlined,
                    busy: busy,
                    onTap: () => _do((api) => api.missionStep(m, 'picked-up')),
                  ),
                  2 => WButton(
                    label: 'Je suis chez le client',
                    icon: Icons.home_outlined,
                    busy: busy,
                    onTap: () =>
                        _do((api) => api.missionStep(m, 'arrived-at-customer')),
                  ),
                  _ when atClient => WCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Code du client',
                          style: t.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Demandez au client le code affiché dans son app.',
                          style: t.bodyMedium?.copyWith(color: W.muted),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _code,
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                          textAlign: TextAlign.center,
                          style: t.headlineMedium?.copyWith(
                            letterSpacing: 12,
                            fontWeight: FontWeight.w800,
                          ),
                          decoration: const InputDecoration(
                            counterText: '',
                            hintText: '• • • •',
                          ),
                        ),
                        if (m.prescriptionCheck)
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            value: _checked,
                            onChanged: (v) =>
                                setState(() => _checked = v ?? false),
                            title: const Text(
                              'J\'ai vérifié l\'ordonnance originale',
                            ),
                          ),
                        const SizedBox(height: 8),
                        WButton(
                          label: 'Remettre la commande',
                          icon: Icons.check_circle_outline,
                          color: W.green,
                          busy: busy,
                          onTap: () => _do(
                            (api) => api.deliverMission(
                              m,
                              _code.text.trim(),
                              prescriptionChecked: _checked,
                            ),
                          ),
                        ),
                        if (!m.pharmacy)
                          TextButton(
                            onPressed: busy ? null : () => _fail(m),
                            child: const Text('Livraison impossible'),
                          ),
                      ],
                    ),
                  ),
                  _ => const SizedBox.shrink(),
                },
                if (step <= 1)
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => _do(
                            (api) => api.withdrawMission(
                              m,
                              'Empêchement du livreur',
                            ),
                          ),
                    child: const Text('Je ne peux pas faire cette course'),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _HistoryTab extends ConsumerWidget {
  const _HistoryTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final items = ref.watch(workHistoryProvider).value ?? const <WorkMission>[];
    final delivered = items.where((m) => m.deliveredAt != null).toList();
    final total = delivered.fold<int>(0, (s, m) => s + m.feeXof);
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () async => ref.invalidate(workHistoryProvider),
        child: ListView(
          padding: const EdgeInsets.all(IviaSpacing.screen),
          children: [
            Text(
              'Mes gains',
              style: t.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: W.navy,
                borderRadius: BorderRadius.circular(W.radius),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Total des courses livrées',
                    style: t.bodyMedium?.copyWith(color: Colors.white70),
                  ),
                  Text(
                    formatXof(total),
                    style: t.displaySmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    '${delivered.length} course${delivered.length > 1 ? 's' : ''}',
                    style: t.bodyMedium?.copyWith(color: Colors.white70),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (items.isEmpty)
              Text('Aucune course pour l\'instant.', style: t.bodyLarge),
            for (final m in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: WCard(
                  child: Row(
                    children: [
                      WIcon(
                        m.pharmacy
                            ? Icons.local_pharmacy_outlined
                            : Icons.storefront_outlined,
                        bg: m.deliveredAt != null ? W.softGreen : W.softRed,
                        fg: m.deliveredAt != null ? W.green : W.red,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${m.pickup.name} · ${m.reference}',
                              style: t.titleSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              '${DateUtils.dateOnly(m.assignedAt.toLocal()).day}/${m.assignedAt.toLocal().month} à ${hhmm(m.assignedAt)} · '
                              '${m.deliveredAt != null
                                  ? 'livrée'
                                  : m.done
                                  ? 'non livrée'
                                  : 'en cours'}',
                              style: t.bodySmall?.copyWith(color: W.muted),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        m.deliveredAt != null ? '+${formatXof(m.feeXof)}' : '—',
                        style: t.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: W.green,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
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
