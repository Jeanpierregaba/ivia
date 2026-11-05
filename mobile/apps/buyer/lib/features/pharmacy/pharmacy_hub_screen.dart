import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/router.dart';
import 'pharmacy_state.dart';

/// Service Pharmacie : nouvelle alerte, alertes en cours, pharmacies de garde.
class PharmacyHubScreen extends ConsumerWidget {
  const PharmacyHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final brand = IviaAppBrand.of(context);
    final alerts = ref.watch(myAlertsProvider).value ?? const <MedAlert>[];
    final duty =
        ref.watch(onDutyPharmaciesProvider).value ?? const <OnDutyPharmacy>[];
    return Scaffold(
      appBar: AppBar(title: const Text('Pharmacie')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref
              ..invalidate(myAlertsProvider)
              ..invalidate(onDutyPharmaciesProvider);
          },
          child: ListView(
            padding: const EdgeInsets.all(IviaSpacing.screen),
            children: [
              Text.rich(
                TextSpan(
                  text: 'Votre médicament,\n',
                  children: [
                    TextSpan(
                      text: 'sans faire le tour des pharmacies.',
                      style: TextStyle(color: brand.highlight),
                    ),
                  ],
                ),
                style: t.headlineSmall,
              ),
              const SizedBox(height: IviaSpacing.lg),
              FilledButton.icon(
                onPressed: () => context.push(Routes.medNewAlert),
                icon: const Icon(Icons.add_alert),
                label: const Text('Trouver un médicament'),
              ),
              if (alerts.isNotEmpty) ...[
                const SizedBox(height: IviaSpacing.xl),
                Text('Mes alertes', style: t.titleLarge),
                for (final a in alerts.take(10))
                  Card(
                    margin: const EdgeInsets.only(top: IviaSpacing.sm),
                    child: ListTile(
                      leading: Icon(
                        a.searching ? Icons.radar : Icons.medication_outlined,
                      ),
                      title: Text(a.title),
                      subtitle: Text(
                        a.searching
                            ? '${a.responded} réponse(s) · ${a.notified} pharmacie(s) contactée(s)'
                            : _date(a.createdAt.toLocal()),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push(Routes.medAlert(a.id)),
                    ),
                  ),
              ],
              const SizedBox(height: IviaSpacing.xl),
              Text('Pharmacies de garde', style: t.titleLarge),
              if (duty.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: IviaSpacing.sm),
                  child: Text(
                    'Aucune pharmacie de garde signalée près de vous.',
                    style: t.bodyMedium,
                  ),
                ),
              for (final p in duty) OnDutyTile(pharmacy: p),
            ],
          ),
        ),
      ),
    );
  }
}

String _date(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} à '
    '${d.hour} h ${d.minute.toString().padLeft(2, '0')}';

/// Ligne « Pharmacie de garde » (accueil A01 et service Pharmacie).
class OnDutyTile extends StatelessWidget {
  const OnDutyTile({super.key, required this.pharmacy});
  final OnDutyPharmacy pharmacy;

  @override
  Widget build(BuildContext context) {
    final p = pharmacy;
    final t = Theme.of(context).textTheme;
    final until = p.dutyUntil;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 4),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: IviaColors.background,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.local_hospital_outlined),
      ),
      title: Text(p.name, style: t.titleMedium),
      subtitle: Wrap(
        spacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFE5EEF8),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'De garde',
              style: t.labelSmall?.copyWith(color: const Color(0xFF0E2E54)),
            ),
          ),
          Text(
            [
              until == null ? '24 h/24' : '→ ${until.toLocal().hour} h',
              formatDistance(p.distanceM),
            ].join(' · '),
            style: t.bodySmall,
          ),
        ],
      ),
      trailing: p.phone.isEmpty
          ? null
          : IconButton.filled(
              style: IconButton.styleFrom(
                backgroundColor: const Color(0xFF0E2E54),
              ),
              tooltip: 'Appeler ${p.name}',
              icon: const Icon(Icons.call, color: Colors.white),
              onPressed: () => launchUrl(Uri.parse('tel:${p.phone}')),
            ),
    );
  }
}
