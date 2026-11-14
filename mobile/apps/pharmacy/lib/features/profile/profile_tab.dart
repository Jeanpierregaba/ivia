import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../common/providers.dart';
import '../../common/ui.dart';
import '../alerts/history_row.dart';
import '../earnings/statement_screen.dart';
import '../planning/planning_screen.dart';
import '../push/push.dart';
import 'alert_sound.dart';
import 'documents_screen.dart';
import 'info_screen.dart';

/// Prochaine garde : « ce soir », « demain », ou la date.
String nextDutyLabel(
  List<({String id, DateTime startsAt, DateTime endsAt})> shifts,
  DateTime now,
) {
  final next = [
    for (final s in shifts)
      if (s.endsAt.isAfter(now)) s,
  ]..sort((a, b) => a.startsAt.compareTo(b.startsAt));
  if (next.isEmpty) return 'Aucune garde prévue';
  final start = next.first.startsAt;
  if (!start.isAfter(now)) return 'De garde maintenant';
  // Jours de Lomé, quel que soit le fuseau du téléphone.
  final days = lomeDay(start).difference(lomeDay(now)).inDays;
  return switch (days) {
    0 => 'Prochaine garde : ce soir',
    1 => 'Prochaine garde : demain',
    _ => 'Prochaine garde : le ${dayLabel(start, now)}',
  };
}

/// Profil (F23) : informations, planning, documents, relevé, sonnerie,
/// aide, déconnexion.
class ProfileTab extends ConsumerWidget {
  const ProfileTab({super.key});

  static const _supportPhone = String.fromEnvironment('IVIA_SUPPORT_PHONE');

  void _help(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Numéro du service client fourni au build (IVIA_SUPPORT_PHONE).
          if (_supportPhone.isNotEmpty) ...[
            ListTile(
              leading: const Icon(Icons.chat_outlined),
              title: const Text('Écrire sur WhatsApp'),
              onTap: () => launchUrl(
                Uri.parse('https://wa.me/$_supportPhone'),
                mode: LaunchMode.externalApplication,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.call_outlined),
              title: const Text("Appeler l'équipe ivia"),
              onTap: () => launchUrl(Uri.parse('tel:+$_supportPhone')),
            ),
          ],
          ListTile(
            leading: const Icon(Icons.mail_outline),
            title: const Text('support@ivia.tg'),
            onTap: () => launchUrl(Uri.parse('mailto:support@ivia.tg')),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(pharmacyProfileProvider).value;
    final shifts = ref.watch(shiftsProvider).value ?? const [];
    final earnings = ref.watch(earningsProvider).value;
    final sound = ref.watch(alertSoundProvider).value ?? true;
    if (p == null) return const Center(child: CircularProgressIndicator());
    Future<void> open(Widget screen) =>
        Navigator.of(context)
            .push(MaterialPageRoute<void>(builder: (_) => screen));
    return ListView(
      padding: const EdgeInsets.fromLTRB(P.gutter, 20, P.gutter, 120),
      children: [
        Row(
          children: [
            const SizedBox.square(
              dimension: 62,
              child: IviaImagePlaceholder(radius: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      p.name,
                      style: PText.figure.copyWith(fontSize: 26),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const PPill('Validée', icon: Icons.verified),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _Group(
          rows: [
            _Row(
              icon: Icons.storefront,
              title: 'Informations',
              subtitle: 'Adresse, téléphone, horaires',
              onTap: () => open(const InfoScreen()),
            ),
            _Row(
              icon: Icons.calendar_month,
              title: 'Planning de garde',
              subtitle: nextDutyLabel(shifts, DateTime.now()),
              onTap: () async {
                await open(const PlanningScreen());
                ref.invalidate(shiftsProvider);
              },
            ),
            _Row(
              icon: Icons.description_outlined,
              title: 'Documents',
              subtitle: "Autorisation d'exercice validée",
              onTap: () => open(const DocumentsScreen()),
            ),
            _Row(
              icon: Icons.receipt_long,
              title: 'Relevé des versements',
              subtitle: '${formatXof(earnings?.balanceXof ?? 0)} à recevoir',
              onTap: () => open(const StatementScreen()),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _Group(
          rows: [
            // iOS : le serveur fait sonner le push lui-même ; le réglage n'y
            // aurait pas d'effet (noté pour Gedeon).
            if (defaultTargetPlatform == TargetPlatform.android)
              _Row(
                icon: Icons.volume_up,
                title: 'Sonnerie des alertes',
                subtitle: sound
                    ? 'Forte · répétée'
                    : 'Coupée · notification seule',
                trailing: PSwitch(
                  value: sound,
                  onChanged: (v) =>
                      ref.read(alertSoundProvider.notifier).set(v),
                ),
                onTap: () => ref.read(alertSoundProvider.notifier).set(!sound),
              ),
            _Row(
              icon: Icons.help_outline,
              title: 'Aide et contact ivia',
              onTap: () => _help(context),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _Group(
          rows: [
            _Row(
              icon: Icons.logout,
              title: 'Se déconnecter',
              onTap: () => signOutPharmacy(ref),
            ),
          ],
        ),
      ],
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.rows});
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) => PCard(
    padding: EdgeInsets.zero,
    child: Column(
      children: [
        for (final (i, r) in rows.indexed) ...[
          if (i > 0) const Divider(height: 1, color: P.line),
          r,
        ],
      ],
    ),
  );
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          subtitle == null ? 18 : 12,
          12,
          subtitle == null ? 18 : 12,
        ),
        child: Row(
          children: [
            ExcludeSemantics(child: Icon(icon, color: P.green, size: 24)),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: PText.cardTitle),
                  if (subtitle != null) Text(subtitle!, style: PText.bodyMuted),
                ],
              ),
            ),
            trailing ??
                const ExcludeSemantics(
                  child: Icon(Icons.chevron_right, color: P.muted),
                ),
          ],
        ),
      ),
    ),
  );
}
