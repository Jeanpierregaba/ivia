import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../common/providers.dart';
import '../../common/ui.dart';
import '../push/push.dart';
import 'application_flow.dart';
import 'payout_screen.dart';
import '../planning/planning_screen.dart';

/// Inscription : le statut du dossier décide de l'écran. Brouillon,
/// compléments ou refus : les 5 étapes ; envoyé ou suspendu : l'attente.
class ApplicationScreen extends ConsumerWidget {
  const ApplicationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(pharmacyProfileProvider).value;
    if (profile == null || profile.editable) {
      return ApplicationFlow(profile: profile);
    }
    return _Waiting(profile: profile);
  }
}

class _Frame extends ConsumerWidget {
  const _Frame({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    backgroundColor: P.page,
    body: SafeArea(
      child: RefreshIndicator(
        onRefresh: () async => ref.invalidate(pharmacyProfileProvider),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(IviaSpacing.screen),
          children: [
            Row(
              children: [
                const IviaLogoTile(size: 48, color: P.green),
                const Spacer(),
                TextButton(
                  onPressed: () => signOutPharmacy(ref),
                  child: const Text('Se déconnecter'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    ),
  );
}

/// Pièces, planning, versement et envoi (étapes 3 à 5, avant leur écran).
class DossierHub extends ConsumerStatefulWidget {
  const DossierHub({
    super.key,
    required this.profile,
    required this.onEditDetails,
  });
  final PharmacyProfile profile;
  final VoidCallback onEditDetails;

  @override
  ConsumerState<DossierHub> createState() => _DossierHubState();
}

class _DossierHubState extends ConsumerState<DossierHub> {
  String? _uploading;
  var _busy = false;

  Future<void> _upload(String kind) async {
    final bytes = await ref
        .read(photoPickerProvider)
        .pick(source: PhotoSource.gallery, maxSide: 1600);
    if (bytes == null) return;
    setState(() => _uploading = kind);
    try {
      final api = ref.read(apiClientProvider);
      final prepared = await api.prepareUpload(
        purpose: 'pharmacy_document',
        contentType: 'image/jpeg',
        sizeBytes: bytes.length,
      );
      await api.upload(prepared, bytes);
      await api.pharmacyAddDocument(kind, prepared.objectKey);
      ref.invalidate(pharmacyProfileProvider);
    } on ApiException catch (e) {
      if (mounted) say(context, e.message);
    } finally {
      if (mounted) setState(() => _uploading = null);
    }
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      await ref.read(apiClientProvider).submitPharmacy();
      ref.invalidate(pharmacyProfileProvider);
    } on ApiException catch (e) {
      if (mounted) say(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _tile({
    required bool done,
    required IconData icon,
    required String title,
    String? sub,
    required String action,
    VoidCallback? onTap,
    bool loading = false,
  }) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: PCard(
        padding: const EdgeInsets.all(16),
        onTap: loading ? null : onTap,
        child: Row(
          children: [
            PIcon(
              done ? Icons.check : icon,
              size: 42,
              bg: done ? P.softGreen : P.softYellow,
              fg: done ? P.green : P.yellow,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  if (sub != null)
                    Text(sub, style: t.bodySmall?.copyWith(color: P.muted)),
                ],
              ),
            ),
            if (loading)
              const SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Text(
                action,
                style: t.labelLarge?.copyWith(
                  color: P.green,
                  fontWeight: FontWeight.w800,
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final p = widget.profile;
    final shifts = ref.watch(shiftsProvider).value?.length ?? 0;
    final ready = p.missingDocuments.isEmpty && p.hasPayout;
    Future<void> open(Widget screen) async {
      await Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => screen));
      ref.invalidate(shiftsProvider);
      ref.invalidate(pharmacyProfileProvider);
    }

    return _Frame(
      children: [
        PTitle(
          p.reviewStatus == 'draft' ? 'Terminez votre ' : 'Corrigez votre ',
          'dossier',
        ),
        const SizedBox(height: 6),
        Text(
          p.name,
          style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 14),
        if (p.reviewNote.isNotEmpty) ...[
          PCard(
            color: P.softYellow,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.reviewStatus == 'rejected'
                      ? 'Dossier refusé'
                      : 'Compléments demandés',
                  style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(p.reviewNote, style: t.bodyMedium),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
        _tile(
          done: true,
          icon: Icons.local_pharmacy_outlined,
          title: 'Fiche et position',
          sub: p.addressText,
          action: 'Modifier',
          onTap: widget.onEditDetails,
        ),
        const SizedBox(height: 6),
        Text(
          'Justificatifs',
          style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        for (final e in pharmacyDocumentLabels.entries)
          _tile(
            done: p.documents.contains(e.key),
            icon: e.key == 'storefront_photo'
                ? Icons.storefront_outlined
                : Icons.description_outlined,
            title: e.value,
            action: p.documents.contains(e.key) ? 'Remplacer' : 'Ajouter',
            loading: _uploading == e.key,
            onTap: _uploading == null ? () => _upload(e.key) : null,
          ),
        const SizedBox(height: 6),
        Text(
          'Garde et versements',
          style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        _tile(
          done: shifts > 0,
          icon: Icons.nightlight_outlined,
          title: 'Planning de garde',
          sub: shifts > 0
              ? '$shifts garde${shifts > 1 ? 's' : ''} à venir'
              : 'La nuit, seules les pharmacies de garde reçoivent les alertes',
          action: 'Gérer',
          onTap: () => open(const PlanningScreen()),
        ),
        _tile(
          done: p.hasPayout,
          icon: Icons.account_balance_wallet_outlined,
          title: 'Compte de versement',
          sub: p.hasPayout
              ? '${p.payoutMasked} · ${p.payoutHolder}'
              : 'Mobile Money',
          action: p.hasPayout ? 'Modifier' : 'Ajouter',
          onTap: () => open(const PayoutScreen()),
        ),
        const SizedBox(height: 14),
        PButton(
          label: 'Envoyer mon dossier',
          icon: Icons.send,
          busy: _busy,
          onTap: ready ? _submit : null,
        ),
        if (!ready)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Ajoutez les justificatifs et le compte de versement pour envoyer le dossier.',
              textAlign: TextAlign.center,
              style: t.bodySmall?.copyWith(color: P.muted),
            ),
          ),
      ],
    );
  }
}

/// Dossier envoyé ou pharmacie suspendue : aucune alerte reçue.
class _Waiting extends ConsumerWidget {
  const _Waiting({required this.profile});
  final PharmacyProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final p = profile;
    return _Frame(
      children: [
        if (p.suspended)
          const PTitle('Pharmacie ', 'suspendue')
        else
          const PTitle('Dossier en ', 'vérification'),
        const SizedBox(height: 8),
        Text(
          p.suspended
              ? 'Votre pharmacie ne reçoit plus d\'alertes. Contactez l\'équipe ivia.'
              : 'L\'équipe ivia vérifie votre autorisation, votre identité et votre position. Vous ne recevez aucune alerte avant la validation.',
          style: t.bodyLarge?.copyWith(color: P.muted),
        ),
        const SizedBox(height: 20),
        PCard(
          child: Row(
            children: [
              const PIcon(Icons.local_pharmacy),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.name,
                      style: t.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      p.addressText,
                      style: t.bodyMedium?.copyWith(color: P.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: () => ref.invalidate(pharmacyProfileProvider),
          icon: const Icon(Icons.refresh),
          label: const Text('Actualiser le statut'),
        ),
      ],
    );
  }
}
