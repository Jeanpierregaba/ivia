import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';
import 'package:latlong2/latlong.dart';

import '../main.dart';
import 'ui.dart';

void _say(BuildContext context, String message) =>
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));

final _shiftsProvider = FutureProvider.autoDispose(
  (ref) => ref.read(apiClientProvider).pharmacyDutyShifts(),
);

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
                  onPressed: ref.read(authControllerProvider.notifier).signOut,
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
  final _map = MapController();
  late var _center = LatLng(
    widget.profile?.lat ?? 6.1480,
    widget.profile?.lng ?? 1.2150,
  );
  var _onMap = false;
  var _errors = <String, String>{};
  var _busy = false;

  @override
  void dispose() {
    for (final c in [_name, _license, _phone, _email, _address, _hours]) {
      c.dispose();
    }
    _map.dispose();
    super.dispose();
  }

  Future<void> _locate() async {
    final p = (await ref.read(locationServiceProvider).current()).point;
    if (!mounted) return;
    if (p == null) {
      _say(context, 'Position indisponible : déplacez la carte à la main.');
      return;
    }
    _map.move(LatLng(p.lat, p.lng), 17);
    setState(() => _center = LatLng(p.lat, p.lng));
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
            location: GeoPoint(lat: _center.latitude, lng: _center.longitude),
            openingHours: _hours.text.trim(),
          );
      ref.invalidate(pharmacyProfileProvider);
      if (widget.profile != null && mounted) navigator.pop();
    } on ApiException catch (e) {
      // Une erreur sur la fiche ramène au formulaire.
      if (mounted) {
        setState(() {
          _errors = e.fields.isEmpty ? {'name': e.message} : e.fields;
          _onMap = false;
        });
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
          onTap: () => setState(() => _onMap = true),
        ),
      ],
    );
  }

  Widget _mapStep(TextTheme t) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const PTitle('Placez votre ', 'pharmacie'),
      const SizedBox(height: 8),
      Text(
        'Étape 2 sur 5 · Déplacez la carte pour mettre le repère sur votre porte. Les patients vous trouvent à cet endroit.',
        style: t.bodyMedium?.copyWith(color: P.muted),
      ),
      const SizedBox(height: 14),
      ClipRRect(
        borderRadius: BorderRadius.circular(P.radius),
        child: SizedBox(
          height: 340,
          child: Stack(
            alignment: Alignment.center,
            children: [
              FlutterMap(
                mapController: _map,
                options: MapOptions(
                  initialCenter: _center,
                  initialZoom: 16,
                  onPositionChanged: (position, _) => _center = position.center,
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'tg.ivia.pharmacy',
                  ),
                ],
              ),
              // La pointe du repère désigne le centre de la carte.
              const IgnorePointer(
                child: Padding(
                  padding: EdgeInsets.only(bottom: 44),
                  child: Icon(Icons.location_on, size: 44, color: P.green),
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 10),
      OutlinedButton.icon(
        onPressed: _locate,
        icon: const Icon(Icons.my_location),
        label: const Text('Utiliser ma position'),
      ),
      const SizedBox(height: 14),
      PButton(
        label: 'Confirmer cet emplacement',
        icon: Icons.check,
        busy: _busy,
        onTap: _save,
      ),
      TextButton(
        onPressed: () => setState(() => _onMap = false),
        child: const Text('Retour'),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final body = _onMap ? _mapStep(t) : _form(t);
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
      if (mounted) _say(context, e.message);
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
      if (mounted) _say(context, e.message);
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
    final shifts = ref.watch(_shiftsProvider).value?.length ?? 0;
    final ready = p.missingDocuments.isEmpty && p.hasPayout;
    Future<void> open(Widget screen) async {
      await Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => screen));
      ref.invalidate(_shiftsProvider);
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

/// Compte de versement, avant l'envoi du dossier.
class PayoutScreen extends ConsumerStatefulWidget {
  const PayoutScreen({super.key});

  @override
  ConsumerState<PayoutScreen> createState() => _PayoutScreenState();
}

class _PayoutScreenState extends ConsumerState<PayoutScreen> {
  var _operator = 'flooz';
  final _phone = TextEditingController();
  late final _holder = TextEditingController(
    text: ref.read(pharmacyProfileProvider).value?.payoutHolder,
  );
  var _errors = <String, String>{};
  var _busy = false;

  @override
  void dispose() {
    _phone.dispose();
    _holder.dispose();
    super.dispose();
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
          .setPharmacyPayout(
            operator: _operator,
            phone: '+228${togoPhoneDigits(_phone.text)}',
            holder: _holder.text.trim(),
          );
      if (mounted) navigator.pop();
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _errors = e.fields);
        if (e.fields.isEmpty) _say(context, e.message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: P.page,
      appBar: AppBar(
        backgroundColor: P.page,
        title: const Text('Compte de versement'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(IviaSpacing.screen),
        children: [
          Text(
            'Vos ventes livrées y sont versées. Le titulaire doit correspondre à la pièce d\'identité du dossier.',
            style: t.bodyMedium?.copyWith(color: P.muted),
          ),
          const SizedBox(height: 16),
          IviaFieldLabel(
            label: 'Opérateur',
            child: DropdownButtonFormField<String>(
              initialValue: _operator,
              items: const [
                DropdownMenuItem(
                  value: 'flooz',
                  child: Text('Moov Money (Flooz)'),
                ),
                DropdownMenuItem(value: 'tmoney', child: Text('Yas (T-Money)')),
              ],
              onChanged: (v) => setState(() => _operator = v ?? 'flooz'),
            ),
          ),
          const SizedBox(height: 14),
          TogoPhoneField(
            label: 'Numéro Mobile Money',
            controller: _phone,
            errorText: _errors['phone'],
          ),
          const SizedBox(height: 14),
          IviaFieldLabel(
            label: 'Titulaire du compte',
            child: TextField(
              controller: _holder,
              decoration: InputDecoration(errorText: _errors['holder']),
            ),
          ),
          const SizedBox(height: 20),
          PButton(label: 'Enregistrer', busy: _busy, onTap: _save),
        ],
      ),
    );
  }
}

/// Planning de garde : créneau par créneau, ou import d'une liste.
class PlanningScreen extends ConsumerStatefulWidget {
  const PlanningScreen({super.key});

  @override
  ConsumerState<PlanningScreen> createState() => _PlanningScreenState();
}

class _PlanningScreenState extends ConsumerState<PlanningScreen> {
  DateTime? _day;
  var _from = const TimeOfDay(hour: 20, minute: 0);
  var _to = const TimeOfDay(hour: 7, minute: 0);
  final _import = TextEditingController();
  var _busy = false;

  @override
  void dispose() {
    _import.dispose();
    super.dispose();
  }

  /// Heure de Lomé, soit UTC ; une fin avant le début tombe le lendemain.
  ({DateTime startsAt, DateTime endsAt}) _shift(
    DateTime day,
    TimeOfDay from,
    TimeOfDay to,
  ) {
    final start = DateTime.utc(
      day.year,
      day.month,
      day.day,
      from.hour,
      from.minute,
    );
    var end = DateTime.utc(day.year, day.month, day.day, to.hour, to.minute);
    if (!end.isAfter(start)) end = end.add(const Duration(days: 1));
    return (startsAt: start, endsAt: end);
  }

  Future<void> _send(
    List<({DateTime startsAt, DateTime endsAt})> shifts,
  ) async {
    setState(() => _busy = true);
    try {
      await ref.read(apiClientProvider).addPharmacyDutyShifts(shifts);
      ref.invalidate(_shiftsProvider);
      _import.clear();
      if (mounted)
        _say(
          context,
          shifts.length > 1
              ? '${shifts.length} gardes ajoutées.'
              : 'Garde ajoutée.',
        );
    } on ApiException catch (e) {
      if (mounted) _say(context, e.fields.values.firstOrNull ?? e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Une garde par ligne : 08/11/2026 20:00 07:00
  void _importList() {
    final line = RegExp(
      r'^(\d{1,2})/(\d{1,2})/(\d{4})\s+(\d{1,2})[:h](\d{2})\s+(\d{1,2})[:h](\d{2})$',
    );
    final out = <({DateTime startsAt, DateTime endsAt})>[];
    final lines = _import.text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    for (final (i, l) in lines.indexed) {
      final m = line.firstMatch(l);
      if (m == null) {
        _say(
          context,
          'Ligne ${i + 1} illisible. Format : 08/11/2026 20:00 07:00',
        );
        return;
      }
      int n(int g) => int.parse(m.group(g)!);
      out.add(
        _shift(
          DateTime.utc(n(3), n(2), n(1)),
          TimeOfDay(hour: n(4) % 24, minute: n(5) % 60),
          TimeOfDay(hour: n(6) % 24, minute: n(7) % 60),
        ),
      );
    }
    if (out.isNotEmpty) _send(out);
  }

  Future<void> _delete(String id) async {
    try {
      await ref.read(apiClientProvider).deletePharmacyDutyShift(id);
      ref.invalidate(_shiftsProvider);
    } on ApiException catch (e) {
      if (mounted) _say(context, e.message);
    }
  }

  String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final shifts = ref.watch(_shiftsProvider).value ?? const [];
    final day = _day;
    return Scaffold(
      backgroundColor: P.page,
      appBar: AppBar(
        backgroundColor: P.page,
        title: const Text('Planning de garde'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(IviaSpacing.screen),
        children: [
          const _NightHours(),
          const SizedBox(height: 12),
          PCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Ajouter une garde',
                  style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_today_outlined, size: 18),
                  label: Text(day == null ? 'Choisir le jour' : _date(day)),
                  onPressed: () async {
                    final now = DateTime.now();
                    final d = await showDatePicker(
                      context: context,
                      firstDate: now,
                      lastDate: now.add(const Duration(days: 365)),
                      initialDate: day ?? now,
                    );
                    if (d != null) setState(() => _day = d);
                  },
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        child: Text('De ${_from.format(context)}'),
                        onPressed: () async {
                          final v = await showTimePicker(
                            context: context,
                            initialTime: _from,
                          );
                          if (v != null) setState(() => _from = v);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        child: Text('À ${_to.format(context)}'),
                        onPressed: () async {
                          final v = await showTimePicker(
                            context: context,
                            initialTime: _to,
                          );
                          if (v != null) setState(() => _to = v);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                PButton(
                  label: 'Ajouter',
                  busy: _busy,
                  onTap: day == null
                      ? null
                      : () => _send([_shift(day, _from, _to)]),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          PCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Importer une liste',
                  style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  'Une garde par ligne, 60 au plus.',
                  style: t.bodySmall?.copyWith(color: P.muted),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _import,
                  minLines: 3,
                  maxLines: 8,
                  decoration: const InputDecoration(
                    hintText: '08/11/2026 20:00 07:00\n15/11/2026 20:00 07:00',
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton(
                  onPressed: _busy ? null : _importList,
                  child: const Text('Importer'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Gardes à venir',
            style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          if (shifts.isEmpty)
            PCard(child: Text('Aucune garde planifiée.', style: t.bodyMedium)),
          for (final s in shifts)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: PCard(
                padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${_date(s.startsAt.toLocal())} · ${hhmm(s.startsAt)} → ${hhmm(s.endsAt)}',
                        style: t.bodyMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Retirer',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _delete(s.id),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Heures de nuit choisies par la pharmacie.
class _NightHours extends ConsumerStatefulWidget {
  const _NightHours();

  @override
  ConsumerState<_NightHours> createState() => _NightHoursState();
}

class _NightHoursState extends ConsumerState<_NightHours> {
  int? _from, _to;
  var _busy = false;

  Future<void> _save(int from, int to) async {
    setState(() => _busy = true);
    try {
      await ref.read(apiClientProvider).setPharmacyNightHours(from, to);
      ref.invalidate(pharmacyProfileProvider);
      if (mounted) _say(context, 'Heures de nuit enregistrées.');
    } on ApiException catch (e) {
      if (mounted) _say(context, e.fields.values.firstOrNull ?? e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _hour(String label, int value, ValueChanged<int> onChanged) =>
      Expanded(
        child: IviaFieldLabel(
          label: label,
          child: DropdownButtonFormField<int>(
            initialValue: value,
            items: [
              for (var h = 0; h < 24; h++)
                DropdownMenuItem(value: h, child: Text('$h h')),
            ],
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final p = ref.watch(pharmacyProfileProvider).value;
    final from = _from ?? p?.nightFromHour ?? 20;
    final to = _to ?? p?.nightToHour ?? 7;
    return PCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Vos heures de nuit',
            style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            'Pendant ces heures, vous ne recevez les alertes que si vous êtes de garde.',
            style: t.bodySmall?.copyWith(color: P.muted),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _hour('De', from, (v) => setState(() => _from = v)),
              const SizedBox(width: 10),
              _hour('À', to, (v) => setState(() => _to = v)),
            ],
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: _busy ? null : () => _save(from, to),
            child: Text(_busy ? 'Patientez…' : 'Enregistrer mes heures'),
          ),
        ],
      ),
    );
  }
}
