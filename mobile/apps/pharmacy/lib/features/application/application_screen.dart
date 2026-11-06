import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../common/providers.dart';
import '../../common/ui.dart';
import '../push/push.dart';
import 'payout_screen.dart';
import '../planning/planning_screen.dart';

final _neighborhoodsProvider = FutureProvider.autoDispose(
  (ref) => ref.read(apiClientProvider).neighborhoods(),
);

/// Inscription : fiche, carte, pièces, planning de garde, versement, envoi.
/// Le statut du dossier décide de l'écran.
class ApplicationScreen extends ConsumerWidget {
  const ApplicationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(pharmacyProfileProvider).value;
    if (profile == null) return const PharmacyFormScreen();
    return profile.editable
        ? _Dossier(profile: profile)
        : _Waiting(profile: profile);
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

/// Fiche de la pharmacie puis placement sur la carte.
class PharmacyFormScreen extends ConsumerStatefulWidget {
  const PharmacyFormScreen({super.key, this.profile});
  final PharmacyProfile? profile;

  @override
  ConsumerState<PharmacyFormScreen> createState() => _PharmacyFormScreenState();
}

class _PharmacyFormScreenState extends ConsumerState<PharmacyFormScreen> {
  late final _name = TextEditingController(text: widget.profile?.name);
  late final _license = TextEditingController(
    text: widget.profile?.licenseNumber,
  );
  late final _phone = TextEditingController(
    text: (widget.profile?.phone ?? '').replaceFirst('+228', ''),
  );
  late final _email = TextEditingController(text: widget.profile?.email);
  late final _address = TextEditingController(
    text: widget.profile?.addressText,
  );
  late final _hours = TextEditingController(
    text: widget.profile?.openingHours ?? 'Lun-Sam 8 h - 21 h',
  );
  late String? _neighborhood = widget.profile?.neighborhoodId;
  late var _center = GeoPoint(
    lat: widget.profile?.lat ?? 6.1480,
    lng: widget.profile?.lng ?? 1.2150,
  );
  var _errors = <String, String>{};
  var _busy = false;

  @override
  void dispose() {
    for (final c in [_name, _license, _phone, _email, _address, _hours]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Étape 2 : l'emplacement, puis l'enregistrement de la fiche.
  Future<void> _place() async {
    final picked = await Navigator.of(context).push<PickedPlace>(
      MaterialPageRoute(
        builder: (_) => PlacePickerScreen(
          initial: widget.profile == null ? null : _center,
          title: 'Placez votre pharmacie',
          hint: 'Étape 2 sur 5 · Mettez le repère sur votre porte : les patients vous trouvent à cet endroit.',
          confirmLabel: 'Confirmer cet emplacement',
        ),
      ),
    );
    if (picked == null || !mounted) return;
    _center = picked.point;
    await _save();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _errors = {};
    });
    final navigator = Navigator.of(context);
    try {
      await ref
          .read(apiClientProvider)
          .pharmacyApply(
            name: _name.text.trim(),
            licenseNumber: _license.text.trim(),
            phone: '+228${togoPhoneDigits(_phone.text)}',
            email: _email.text.trim(),
            addressText: _address.text.trim(),
            neighborhoodId: _neighborhood,
            location: _center,
            openingHours: _hours.text.trim(),
          );
      ref.invalidate(pharmacyProfileProvider);
      if (widget.profile != null && mounted) navigator.pop();
    } on ApiException catch (e) {
      // Une erreur sur la fiche ramène au formulaire.
      if (mounted) {
        setState(
          () => _errors = e.fields.isEmpty ? {'name': e.message} : e.fields,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(
    String key,
    String label,
    TextEditingController c, {
    String? hint,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: IviaFieldLabel(
      label: label,
      child: TextField(
        controller: c,
        decoration: InputDecoration(hintText: hint, errorText: _errors[key]),
      ),
    ),
  );

  Widget _form(TextTheme t) {
    final hoods = ref.watch(_neighborhoodsProvider).value ?? const <Choice>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PTitle('Votre ', 'pharmacie'),
        const SizedBox(height: 8),
        Text(
          'Étape 1 sur 5 · Les patients autour de vous vous envoient leurs alertes médicament. Vous recevrez la validation à cette adresse e-mail.',
          style: t.bodyMedium?.copyWith(color: P.muted),
        ),
        const SizedBox(height: 20),
        _field(
          'name',
          'Nom de la pharmacie',
          _name,
          hint: 'Pharmacie du Boulevard',
        ),
        _field('license_number', 'Numéro d\'autorisation', _license),
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: TogoPhoneField(
            label: 'Téléphone de la pharmacie',
            controller: _phone,
            errorText: _errors['phone'],
          ),
        ),
        _field(
          'email',
          'E-mail de la pharmacie',
          _email,
          hint: 'contact@pharmacie.tg',
        ),
        _field('address_text', 'Adresse', _address, hint: 'Rue, repère'),
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: IviaFieldLabel(
            label: 'Quartier',
            child: DropdownButtonFormField<String>(
              initialValue: hoods.any((h) => h.id == _neighborhood)
                  ? _neighborhood
                  : null,
              items: [
                for (final h in hoods)
                  DropdownMenuItem(value: h.id, child: Text(h.name)),
              ],
              onChanged: (v) => setState(() => _neighborhood = v),
            ),
          ),
        ),
        _field('opening_hours', 'Horaires', _hours),
        PButton(
          label: 'Placer sur la carte',
          icon: Icons.place_outlined,
          busy: _busy,
          onTap: _place,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final body = _form(t);
    if (widget.profile != null) {
      return Scaffold(
        backgroundColor: P.page,
        appBar: AppBar(
          backgroundColor: P.page,
          title: const Text('Ma pharmacie'),
        ),
        body: ListView(
          padding: const EdgeInsets.all(IviaSpacing.screen),
          children: [body],
        ),
      );
    }
    return _Frame(children: [body]);
  }
}

/// Pièces, planning, versement et envoi.
class _Dossier extends ConsumerStatefulWidget {
  const _Dossier({required this.profile});
  final PharmacyProfile profile;

  @override
  ConsumerState<_Dossier> createState() => _DossierState();
}

class _DossierState extends ConsumerState<_Dossier> {
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
          onTap: () => open(PharmacyFormScreen(profile: p)),
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
