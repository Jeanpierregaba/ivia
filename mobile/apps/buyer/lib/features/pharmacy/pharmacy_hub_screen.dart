import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../app/router.dart';
import 'med_draft.dart';
import 'med_ui.dart';
import 'pharmacy_state.dart';

/// P01 : service Pharmacie. Alerte médicament, saisie rapide (ordonnance,
/// boîte, nom), alerte en cours, pharmacies de garde.
class PharmacyHubScreen extends ConsumerWidget {
  const PharmacyHubScreen({super.key});

  void _start(BuildContext context, WidgetRef ref, String method) {
    ref.read(medDraftProvider.notifier)
      ..reset()
      ..method(method);
    context.push(switch (method) {
      'prescription' || 'box_photo' => Routes.medCapture(method),
      'name' => Routes.medItems,
      _ => Routes.medNewAlert,
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final alerts = ref.watch(myAlertsProvider).value ?? const <MedAlert>[];
    final current = alerts
        .where((a) => a.searching || a.status == 'unlocked')
        .firstOrNull;
    final duty =
        ref.watch(onDutyPharmaciesProvider).value ?? const <OnDutyPharmacy>[];
    return MedScaffold(
      top: MedTopBar(
        title: 'Pharmacie',
        centered: true,
        trailing: MedRoundButton(
          icon: Icons.history,
          tooltip: 'Mes alertes',
          onTap: () => _history(context, alerts),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref
          ..invalidate(myAlertsProvider)
          ..invalidate(onDutyPharmaciesProvider),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            IviaSpacing.screen,
            0,
            IviaSpacing.screen,
            IviaSpacing.xxl,
          ),
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Med.navy,
                borderRadius: BorderRadius.circular(Med.radius),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'ALERTE MÉDICAMENT',
                          style: t.labelLarge?.copyWith(
                            color: Colors.white70,
                            letterSpacing: 1.4,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.notifications_active_outlined,
                        color: IviaColors.primary,
                        size: 32,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Un médicament introuvable cette nuit ?',
                    style: t.headlineMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Les pharmacies de garde autour de vous vérifient leur stock et vous répondent.',
                    style: t.bodyLarge?.copyWith(color: Colors.white),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 60,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: IviaColors.primary,
                        shape: const StadiumBorder(),
                      ),
                      onPressed: () => _start(context, ref, ''),
                      icon: const Icon(Icons.campaign_outlined),
                      label: Text(
                        'Lancer une alerte',
                        style: t.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                for (final (i, (icon, label, method)) in [
                  (Icons.description_outlined, 'Ordonnance', 'prescription'),
                  (Icons.photo_camera_outlined, 'Boîte', 'box_photo'),
                  (Icons.edit_note, 'Saisir', 'name'),
                ].indexed) ...[
                  if (i > 0) const SizedBox(width: 12),
                  Expanded(
                    child: MedCard(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      onTap: () => _start(context, ref, method),
                      child: Column(
                        children: [
                          MedIconTile(icon),
                          const SizedBox(height: 12),
                          Text(
                            label,
                            style: t.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
            if (current != null) ...[
              const SizedBox(height: 14),
              MedCard(
                onTap: () => context.push(Routes.medAlert(current.id)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Alerte en cours',
                            style: t.titleSmall?.copyWith(
                              color: Med.muted,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (current.responded > 0)
                          MedPill(
                            '${current.responded} réponse${current.responded > 1 ? 's' : ''}',
                            bg: Med.softRed,
                            fg: IviaColors.primary,
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        const MedIconTile(
                          Icons.add_box_outlined,
                          bg: Med.softRed,
                          fg: IviaColors.primary,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                current.title,
                                style: t.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                'Lancée à ${hhmm(current.createdAt)} · ${current.notified} pharmacies alertées',
                                style: t.bodyMedium?.copyWith(color: Med.muted),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right, color: Med.muted),
                      ],
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'De garde maintenant',
                    style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                TextButton(
                  onPressed: duty.isEmpty
                      ? null
                      : () => context.push(Routes.medMap),
                  child: const Text('Voir la carte'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (duty.isEmpty)
              MedCard(
                child: Text(
                  'Aucune pharmacie de garde signalée près de vous. Choisissez votre quartier sur l\'accueil.',
                  style: t.bodyMedium,
                ),
              )
            else
              MedCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                child: Column(
                  children: [
                    for (final (i, p) in duty.indexed) ...[
                      if (i > 0) const Divider(height: 1),
                      OnDutyTile(pharmacy: p),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _history(BuildContext context, List<MedAlert> alerts) =>
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (sheet) => SafeArea(
          child: alerts.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Aucune alerte pour l\'instant.'),
                )
              : ListView(
                  shrinkWrap: true,
                  children: [
                    for (final a in alerts)
                      ListTile(
                        leading: const Icon(Icons.medication_outlined),
                        title: Text(a.title),
                        subtitle: Text(
                          '${hhmm(a.createdAt)} · ${a.responded} réponse(s)',
                        ),
                        onTap: () {
                          Navigator.pop(sheet);
                          context.push(Routes.medAlert(a.id));
                        },
                      ),
                  ],
                ),
        ),
      );
}

/// Ligne « pharmacie de garde » (accueil A01, P01).
class OnDutyTile extends StatelessWidget {
  const OnDutyTile({super.key, required this.pharmacy});
  final OnDutyPharmacy pharmacy;

  @override
  Widget build(BuildContext context) {
    final p = pharmacy;
    final t = Theme.of(context).textTheme;
    final until = p.dutyUntil;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          const MedIconTile(Icons.add_box_outlined),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.name,
                  style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const MedPill('De garde', bg: Med.softBlue, fg: Med.blue),
                    Text(
                      '${until == null ? '24 h/24' : '→ ${until.toLocal().hour} h'} · ${formatDistance(p.distanceM)}',
                      style: t.bodyMedium?.copyWith(color: Med.muted),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (p.phone.isNotEmpty)
            Material(
              color: Med.navy,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => callNumber(p.phone),
                child: const SizedBox.square(
                  dimension: 54,
                  child: Icon(Icons.call_outlined, color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Carte des pharmacies de garde (« Voir la carte »).
class OnDutyMapScreen extends ConsumerWidget {
  const OnDutyMapScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final duty =
        ref.watch(onDutyPharmaciesProvider).value ?? const <OnDutyPharmacy>[];
    final center = duty.isEmpty
        ? const GeoPoint(lat: 6.1480, lng: 1.2150)
        : duty.first.location;
    return MedScaffold(
      top: const MedTopBar(title: 'Pharmacies de garde', centered: true),
      body: Column(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Med.radius),
              child: MedMap(
                center: center,
                markers: [for (final p in duty) p.location],
                zoom: 13.5,
              ),
            ),
          ),
          SizedBox(
            height: 260,
            child: ListView(
              padding: const EdgeInsets.symmetric(
                horizontal: IviaSpacing.screen,
              ),
              children: [for (final p in duty) OnDutyTile(pharmacy: p)],
            ),
          ),
        ],
      ),
    );
  }
}
