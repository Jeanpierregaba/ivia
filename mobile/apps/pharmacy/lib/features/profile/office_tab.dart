import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../common/providers.dart';
import '../../common/ui.dart';
import '../planning/planning_screen.dart';
import '../earnings/balance_tab.dart';
import '../push/push.dart';

class OfficeTab extends ConsumerStatefulWidget {
  const OfficeTab({super.key});

  @override
  ConsumerState<OfficeTab> createState() => _OfficeTabState();
}

class _OfficeTabState extends ConsumerState<OfficeTab> {
  var _busy = false;

  Future<void> _set(
    PharmacyProfile p, {
    bool? open,
    bool? duty,
    bool? h24,
  }) async {
    setState(() => _busy = true);
    try {
      await ref
          .read(apiClientProvider)
          .setPharmacyStatus(
            isOpen: open ?? p.isOpen,
            onDuty: duty ?? p.onDuty,
            open24h: h24 ?? p.open24h,
          );
      ref.invalidate(pharmacyProfileProvider);
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
    final p = ref.watch(pharmacyProfileProvider).value;
    final shifts = ref.watch(shiftsProvider).value ?? const [];
    if (p == null) return const Center(child: CircularProgressIndicator());
    final open = p.isOpen || p.onDuty || p.open24h;
    Widget toggle(String title, String sub, bool v, void Function(bool) on) =>
        SwitchListTile(
          title: Text(
            title,
            style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          subtitle: Text(sub),
          value: v,
          activeTrackColor: P.green,
          onChanged: _busy ? null : on,
        );
    return ListView(
      padding: const EdgeInsets.all(IviaSpacing.screen),
      children: [
        const PTitle('Mon ', 'officine'),
        const SizedBox(height: 14),
        PCard(
          color: open ? P.green : P.navy,
          child: Row(
            children: [
              Icon(
                open ? Icons.storefront : Icons.no_meeting_room_outlined,
                color: Colors.white,
                size: 34,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.name,
                      style: t.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      p.onDuty
                          ? 'De garde : vous recevez les alertes de nuit'
                          : open
                          ? 'Ouverte : vous recevez les alertes'
                          : 'Fermée : aucune alerte',
                      style: t.bodyMedium?.copyWith(color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        PCard(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            children: [
              toggle(
                'En service',
                p.openingHours.isEmpty ? 'Horaires habituels' : p.openingHours,
                p.isOpen,
                (v) => _set(p, open: v),
              ),
              const Divider(height: 1),
              toggle(
                'De garde',
                'Visible dans « De garde maintenant »',
                p.onDuty,
                (v) => _set(p, duty: v),
              ),
              const Divider(height: 1),
              toggle(
                'Ouverte 24 h/24',
                'Toujours joignable',
                p.open24h,
                (v) => _set(p, h24: v),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: Text(
                'Planning de garde',
                style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            TextButton(
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const PlanningScreen(),
                  ),
                );
                ref.invalidate(shiftsProvider);
              },
              child: const Text('Gérer'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        PCard(
          child: shifts.isEmpty
              ? Text(
                  'Aucune garde planifiée. La nuit, seules les pharmacies de garde reçoivent les alertes.',
                  style: t.bodyMedium,
                )
              : Column(
                  children: [
                    for (final s in shifts)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const PIcon(
                          Icons.nightlight_outlined,
                          size: 42,
                        ),
                        title: Text(
                          '${s.startsAt.toLocal().day}/${s.startsAt.toLocal().month} · ${hhmm(s.startsAt)} → ${hhmm(s.endsAt)}',
                        ),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 18),
        PCard(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            children: [
              ListTile(
                leading: const PIcon(Icons.call_outlined, size: 42),
                title: const Text('Téléphone'),
                subtitle: Text(p.phone),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const PIcon(Icons.place_outlined, size: 42),
                title: const Text('Adresse'),
                subtitle: Text(p.addressText),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const PIcon(
                  Icons.account_balance_wallet_outlined,
                  size: 42,
                ),
                title: const Text('Relevé des versements'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const Scaffold(
                      backgroundColor: P.page,
                      body: SafeArea(child: BalanceTab()),
                    ),
                  ),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const PIcon(Icons.devices_outlined, size: 42),
                title: const Text('Appareils connectés'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ConnectedDevicesScreen(),
                  ),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const PIcon(
                  Icons.logout,
                  bg: P.softRed,
                  fg: P.red,
                  size: 42,
                ),
                title: const Text(
                  'Se déconnecter',
                  style: TextStyle(color: P.red, fontWeight: FontWeight.w800),
                ),
                onTap: () => signOutPharmacy(ref),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
