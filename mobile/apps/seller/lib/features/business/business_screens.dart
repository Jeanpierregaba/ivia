import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../app/business_state.dart';
import '../../app/router.dart';
import '../../app/seller_shop.dart';
import '../account/revenue_screen.dart';
import 'pro_ui.dart';

void _say(BuildContext context, String message) =>
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));

void _open(BuildContext context, Widget screen) => Navigator.of(
  context,
  rootNavigator: true,
).push(MaterialPageRoute<void>(builder: (_) => screen));

Future<String?> _pickAndUpload(
  WidgetRef ref,
  String purpose, {
  PhotoSource source = PhotoSource.gallery,
}) async {
  final bytes = await ref
      .read(photoPickerProvider)
      .pick(source: source, maxSide: 1600);
  if (bytes == null) return null;
  final api = ref.read(apiClientProvider);
  final prepared = await api.prepareUpload(
    purpose: purpose,
    contentType: 'image/jpeg',
    sizeBytes: bytes.length,
  );
  await api.upload(prepared, bytes);
  return prepared.objectKey;
}

const _sectorHints = {
  'shop': 'Produits, stock, commandes',
  'restaurant': 'Menu, commandes, cuisine',
  'real_estate': 'Annonces, demandes de visite',
  'artisan': 'Services à prix fixe, créneaux',
};

/// Étape 1 : le secteur décide du formulaire, des justificatifs et du module.
class SectorScreen extends ConsumerStatefulWidget {
  const SectorScreen({super.key});

  @override
  ConsumerState<SectorScreen> createState() => _SectorScreenState();
}

class _SectorScreenState extends ConsumerState<SectorScreen> {
  String? _sector;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ProPage(
      title: 'Votre activité',
      progress: 1 / 4,
      actions: [
        TextButton(
          onPressed: ref.read(authControllerProvider.notifier).signOut,
          child: const Text('Quitter'),
        ),
      ],
      bottom: ProButton(
        label: 'Continuer',
        onPressed: _sector == null
            ? null
            : () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SpaceFormScreen(sector: _sector!),
                ),
              ),
      ),
      children: [
        Text(
          'Que faites-vous ?',
          style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          'L\'application s\'adapte à votre métier. Une autre activité ? Vous pourrez ouvrir un second espace.',
          style: t.bodyMedium?.copyWith(color: Pro.muted),
        ),
        const SizedBox(height: 16),
        for (final e in businessSectorLabels.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: ProCard(
              border: _sector == e.key ? Pro.accent(e.key) : null,
              onTap: () => setState(() => _sector = e.key),
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: Pro.fast,
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: _sector == e.key
                          ? Pro.accent(e.key)
                          : Pro.accent(e.key).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Pro.icon(e.key),
                      color: _sector == e.key
                          ? Colors.white
                          : Pro.accent(e.key),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          e.value,
                          style: t.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          _sectorHints[e.key] ?? '',
                          style: t.bodySmall?.copyWith(color: Pro.muted),
                        ),
                      ],
                    ),
                  ),
                  AnimatedSwitcher(
                    duration: Pro.fast,
                    child: Icon(
                      _sector == e.key
                          ? Icons.check_circle
                          : Icons.circle_outlined,
                      key: ValueKey(_sector == e.key),
                      color: _sector == e.key ? Pro.accent(e.key) : Pro.line,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

const _dayNames = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];

/// Horaires de la semaine, au format de l'API.
List<Map<String, dynamic>> _weekOf(
  Map<String, dynamic> details, {
  String from = '08:00',
  String to = '18:00',
}) {
  final saved = {
    for (final d in (details['availability'] as List?) ?? const [])
      (d as Map)['day'] as int: d.cast<String, dynamic>(),
  };
  return [
    for (var day = 1; day <= 7; day++)
      saved[day] != null
          ? {...saved[day]!}
          : {'day': day, 'open': day < 7, 'from': from, 'to': to},
  ];
}

/// Éditeur compact des horaires.
class WeekEditor extends StatelessWidget {
  const WeekEditor({
    super.key,
    required this.week,
    required this.onChanged,
    required this.accent,
  });
  final List<Map<String, dynamic>> week;
  final VoidCallback onChanged;
  final Color accent;

  Future<void> _time(
    BuildContext context,
    Map<String, dynamic> day,
    String key,
  ) async {
    final parts = (day[key] as String).split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: int.parse(parts[0]),
        minute: int.parse(parts[1]),
      ),
    );
    if (picked == null) return;
    day[key] =
        '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ProCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Column(
        children: [
          for (final d in week)
            Row(
              children: [
                SizedBox(
                  width: 42,
                  child: Text(
                    _dayNames[(d['day'] as int) - 1],
                    style: t.labelLarge?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                Expanded(
                  child: AnimatedOpacity(
                    duration: Pro.fast,
                    opacity: d['open'] == true ? 1 : 0.45,
                    child: d['open'] == true
                        ? Row(
                            children: [
                              TextButton(
                                onPressed: () => _time(context, d, 'from'),
                                child: Text(d['from'] as String),
                              ),
                              const Icon(
                                Icons.arrow_forward,
                                size: 14,
                                color: Pro.muted,
                              ),
                              TextButton(
                                onPressed: () => _time(context, d, 'to'),
                                child: Text(d['to'] as String),
                              ),
                            ],
                          )
                        : Padding(
                            padding: const EdgeInsets.only(left: 12),
                            child: Text('Fermé', style: t.bodyMedium),
                          ),
                  ),
                ),
                Switch(
                  value: d['open'] == true,
                  activeTrackColor: accent,
                  onChanged: (v) {
                    d['open'] = v;
                    onChanged();
                  },
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Formulaire propre au secteur : création, ou correction du dossier.
class SpaceFormScreen extends ConsumerStatefulWidget {
  const SpaceFormScreen({super.key, required this.sector, this.space});
  final String sector;
  final BusinessSpace? space;

  @override
  ConsumerState<SpaceFormScreen> createState() => _SpaceFormScreenState();
}

class _SpaceFormScreenState extends ConsumerState<SpaceFormScreen> {
  late final Map<String, dynamic> _d = {...?widget.space?.details};
  late final _name = TextEditingController(text: widget.space?.name);
  late final _description = _text('description');
  late final _phone = TextEditingController(
    text: (_d['phone'] as String? ?? '').replaceFirst('+228', ''),
  );
  late final _address = _text('address_text');
  late final _rccm = _text('rccm');
  late final _zone = _text('zone');
  late final _cuisine = _text('cuisine');
  final _otherTrade = TextEditingController();
  late final Set<String> _trades = {
    for (final t in (_d['trades'] as List?) ?? const []) t as String,
  };
  late final List<String> _photoKeys = [
    for (final k in (_d['photo_keys'] as List?) ?? const []) k as String,
  ];
  late final _week = _weekOf(_d, from: '11:00', to: '22:00');
  late var _radius = ((_d['radius_km'] as num?) ?? 8).toDouble();
  late var _travel = _d['travel_included'] as bool? ?? true;
  var _errors = <String, String>{};
  var _busy = false;
  var _uploading = false;

  static const _commonTrades = [
    'Électricien',
    'Plombier',
    'Climatisation',
    'Menuisier',
    'Maçon',
    'Peintre',
    'Mécanicien',
    'Couturier',
  ];

  TextEditingController _text(String key) =>
      TextEditingController(text: _d[key] as String?);
  bool get _establishment =>
      widget.sector == 'shop' || widget.sector == 'restaurant';
  Color get _accent => Pro.accent(widget.sector);

  @override
  void dispose() {
    for (final c in [
      _name,
      _description,
      _phone,
      _address,
      _rccm,
      _zone,
      _cuisine,
      _otherTrade,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _addPhoto() async {
    setState(() => _uploading = true);
    try {
      final key = await _pickAndUpload(ref, 'business_photo');
      if (key != null && mounted) setState(() => _photoKeys.add(key));
    } on ApiException catch (e) {
      if (mounted) _say(context, e.message);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _addLogo() async {
    setState(() => _uploading = true);
    try {
      // Le logo d'un établissement est repris par sa fiche visible des clients.
      final key = await _pickAndUpload(
        ref,
        _establishment ? 'shop_logo' : 'business_photo',
      );
      if (key != null && mounted) setState(() => _d['logo_key'] = key);
    } on ApiException catch (e) {
      if (mounted) _say(context, e.message);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _locate() async {
    final point = (await ref.read(locationServiceProvider).current()).point;
    if (!mounted) return;
    if (point == null) {
      _say(context, 'Position indisponible. Autorisez la localisation.');
      return;
    }
    setState(() {
      _d['lat'] = point.lat;
      _d['lng'] = point.lng;
    });
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _errors = {};
    });
    void put(String key, String value) {
      final v = value.trim();
      v.isEmpty ? _d.remove(key) : _d[key] = v;
    }

    put('description', _description.text);
    put('address_text', _address.text);
    put('rccm', _rccm.text);
    put('zone', _zone.text);
    put('cuisine', _cuisine.text);
    if (_establishment) _d['phone'] = '+228${togoPhoneDigits(_phone.text)}';
    if (widget.sector == 'artisan') {
      _d['trades'] = _trades.toList();
      _d['radius_km'] = _radius.round();
      _d['travel_included'] = _travel;
    }
    if (widget.sector == 'restaurant') {
      _d['availability'] = _week;
      put(
        'opening_hours',
        [
          for (final d in _week)
            if (d['open'] == true)
              '${_dayNames[(d['day'] as int) - 1]} ${d['from']}-${d['to']}',
        ].join(', '),
      );
    }
    _d['photo_keys'] = _photoKeys;
    final api = ref.read(apiClientProvider);
    final gate = ref.read(businessGateProvider.notifier);
    final navigator = Navigator.of(context);
    try {
      final existing = widget.space;
      if (existing == null) {
        final space = await api.createBusinessSpace(
          sector: widget.sector,
          name: _name.text.trim(),
          details: _d,
        );
        await gate.open(space.id);
      } else {
        await api.updateBusinessSpace(
          existing.id,
          sector: widget.sector,
          name: _name.text.trim(),
          details: _d,
        );
        await gate.refresh();
      }
      if (mounted && navigator.canPop()) navigator.pop();
    } on ApiException catch (e) {
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
    int lines = 1,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: IviaFieldLabel(
      label: label,
      child: TextField(
        controller: c,
        maxLines: lines,
        decoration: InputDecoration(hintText: hint, errorText: _errors[key]),
      ),
    ),
  );

  Widget _error(String key) => AnimatedSize(
    duration: Pro.fast,
    child: _errors[key] == null
        ? const SizedBox(width: double.infinity)
        : Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 10),
            child: Text(
              _errors[key]!,
              style: const TextStyle(color: IviaColors.imperialRed),
            ),
          ),
  );

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final sector = widget.sector;
    final choices = ref.watch(shopChoicesProvider).value;
    return ProPage(
      title: businessSectorLabels[sector] ?? sector,
      progress: 2 / 4,
      bottom: ProButton(
        label: 'Continuer',
        busy: _busy,
        onPressed: _uploading ? null : _save,
      ),
      children: [
        ProCard(
          onTap: _uploading ? null : _addLogo,
          child: Row(
            children: [
              AnimatedContainer(
                duration: Pro.fast,
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: _d['logo_key'] != null
                      ? _accent
                      : _accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _d['logo_key'] != null
                      ? Icons.check
                      : Icons.add_a_photo_outlined,
                  color: _d['logo_key'] != null ? Colors.white : _accent,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sector == 'real_estate'
                          ? 'Logo de l\'agence'
                          : 'Logo ou photo principale',
                      style: t.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      sector == 'real_estate'
                          ? 'Obligatoire'
                          : 'Vue par vos clients',
                      style: t.bodySmall?.copyWith(color: Pro.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        _error('logo_key'),
        const SizedBox(height: 14),
        _field(
          'name',
          sector == 'real_estate'
              ? 'Nom de l\'agence'
              : sector == 'artisan'
              ? 'Nom affiché'
              : 'Nom de l\'établissement',
          _name,
        ),
        if (sector == 'shop' && choices != null) ...[
          IviaFieldLabel(
            label: 'Catégorie',
            child: DropdownButtonFormField<String>(
              initialValue: _d['category_id'] as String?,
              items: [
                for (final c in choices.$1)
                  DropdownMenuItem(value: c.id, child: Text(c.name)),
              ],
              onChanged: (v) => setState(() => _d['category_id'] = v),
            ),
          ),
          _error('category_id'),
          const SizedBox(height: 14),
        ],
        if (sector == 'real_estate') _field('rccm', 'Numéro RCCM', _rccm),
        if (sector == 'artisan') ...[
          Text(
            'Vos métiers',
            style: t.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final trade in {..._commonTrades, ..._trades})
                FilterChip(
                  label: Text(trade),
                  selected: _trades.contains(trade),
                  selectedColor: _accent.withValues(alpha: 0.14),
                  checkmarkColor: _accent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  onSelected: (v) => setState(
                    () => v ? _trades.add(trade) : _trades.remove(trade),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _otherTrade,
            decoration: const InputDecoration(
              hintText: 'Autre métier, puis Entrée',
            ),
            onSubmitted: (v) {
              if (v.trim().isEmpty) return;
              setState(() => _trades.add(v.trim()));
              _otherTrade.clear();
            },
          ),
          _error('trades'),
          const SizedBox(height: 14),
        ],
        if (sector == 'real_estate' || sector == 'artisan')
          _field(
            'zone',
            sector == 'artisan' ? 'Point de départ' : 'Zone couverte',
            _zone,
            hint: 'Adidogomé, Lomé',
          ),
        if (sector == 'artisan') ...[
          ProCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Zone d\'intervention',
                        style: t.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Text(
                      '${_radius.round()} km',
                      style: t.titleSmall?.copyWith(
                        color: _accent,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                Slider(
                  value: _radius,
                  min: 1,
                  max: 50,
                  activeColor: _accent,
                  onChanged: (v) => setState(() => _radius = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Déplacement inclus dans mes prix'),
                  value: _travel,
                  activeTrackColor: _accent,
                  onChanged: (v) => setState(() => _travel = v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
        if (sector == 'restaurant') ...[
          _field(
            'cuisine',
            'Type de cuisine',
            _cuisine,
            hint: 'Togolaise, grillades',
          ),
          Text(
            'Horaires d\'ouverture',
            style: t.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          WeekEditor(
            week: _week,
            accent: _accent,
            onChanged: () => setState(() {}),
          ),
          _error('opening_hours'),
          const SizedBox(height: 14),
        ],
        if (_establishment) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: TogoPhoneField(
              label: 'Téléphone de l\'établissement',
              controller: _phone,
              errorText: _errors['phone'],
            ),
          ),
          _field('address_text', 'Adresse', _address, hint: 'Rue, repère'),
          if (choices != null) ...[
            IviaFieldLabel(
              label: 'Quartier',
              child: DropdownButtonFormField<String>(
                initialValue: _d['neighborhood_id'] as String?,
                items: [
                  for (final c in choices.$2)
                    DropdownMenuItem(value: c.id, child: Text(c.name)),
                ],
                onChanged: (v) => setState(() => _d['neighborhood_id'] = v),
              ),
            ),
            const SizedBox(height: 14),
          ],
          ProButton(
            outlined: true,
            color: _d['lat'] == null ? Pro.ink : IviaColors.success,
            icon: _d['lat'] == null ? Icons.my_location : Icons.check,
            label: _d['lat'] == null
                ? 'Utiliser ma position'
                : 'Position enregistrée',
            onPressed: _locate,
          ),
          _error('location'),
          const SizedBox(height: 14),
        ],
        _field(
          'description',
          'Description (facultatif)',
          _description,
          lines: 3,
        ),
        if (sector != 'real_estate') ...[
          ProButton(
            outlined: true,
            icon: Icons.photo_library_outlined,
            label:
                '${sector == 'artisan' ? 'Photos de réalisations' : 'Photos'} · ${_photoKeys.length}',
            onPressed: _uploading ? null : _addPhoto,
          ),
          _error('photo_keys'),
        ],
      ],
    );
  }
}

/// Dossier : motif éventuel, informations, justificatifs, versement, envoi.
class DossierScreen extends ConsumerStatefulWidget {
  const DossierScreen({super.key});

  @override
  ConsumerState<DossierScreen> createState() => _DossierScreenState();
}

class _DossierScreenState extends ConsumerState<DossierScreen> {
  String? _uploading;
  var _busy = false;

  Future<void> _upload(BusinessSpace space, String kind) async {
    // Le selfie se prend à l'appareil photo ; le web passe par un fichier.
    final source = kind == 'selfie' && !kIsWeb
        ? PhotoSource.camera
        : PhotoSource.gallery;
    setState(() => _uploading = kind);
    try {
      final key = await _pickAndUpload(
        ref,
        'business_document',
        source: source,
      );
      if (key != null) {
        await ref
            .read(apiClientProvider)
            .addBusinessDocument(space.id, kind, key);
        await ref.read(businessGateProvider.notifier).refresh();
      }
    } on ApiException catch (e) {
      if (mounted) _say(context, e.message);
    } finally {
      if (mounted) setState(() => _uploading = null);
    }
  }

  Future<void> _submit(BusinessSpace space) async {
    setState(() => _busy = true);
    final api = ref.read(apiClientProvider);
    try {
      await api.submitBusinessSpace(space.id);
      // Boutique ou restaurant : le rôle vient d'être accordé.
      final user = await api.getMe();
      await ref.read(authControllerProvider.notifier).profileUpdated(user);
      await ref.read(businessGateProvider.notifier).refresh();
      ref.invalidate(sellerShopProvider);
    } on ApiException catch (e) {
      if (mounted) _say(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _stepIcon(bool done, Color accent, IconData icon) => AnimatedContainer(
    duration: Pro.medium,
    width: 38,
    height: 38,
    decoration: BoxDecoration(
      color: done ? IviaColors.success : accent.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(9),
    ),
    child: Icon(
      done ? Icons.check : icon,
      size: 20,
      color: done ? Colors.white : accent,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final space = ref.watch(businessGateProvider).value?.opened;
    if (space == null) return const Scaffold(body: SizedBox.shrink());
    final accent = Pro.accent(space.sector);
    final ready = space.missingDocuments.isEmpty && space.payout != null;
    return ProPage(
      title: 'Votre dossier',
      progress: ready ? 1 : 3 / 4,
      actions: [
        TextButton(
          onPressed: ref.read(businessGateProvider.notifier).close,
          child: const Text('Mes espaces'),
        ),
      ],
      bottom: ProButton(
        label: ready ? 'Envoyer mon dossier' : 'Dossier incomplet',
        icon: ready ? Icons.send_rounded : null,
        busy: _busy,
        onPressed: ready ? () => _submit(space) : null,
      ),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                space.name,
                style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            ProTag(
              space.sectorLabel,
              color: accent,
              icon: Pro.icon(space.sector),
            ),
          ],
        ),
        if (space.statusReason.isNotEmpty) ...[
          const SizedBox(height: 12),
          ProCard(
            color: IviaColors.warningSoft,
            border: IviaColors.warning,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline, color: IviaColors.warning),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        space.statusLabel,
                        style: t.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(space.statusReason, style: t.bodyMedium),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
        const ProSection('Informations'),
        ProCard(
          onTap: () => _open(
            context,
            SpaceFormScreen(sector: space.sector, space: space),
          ),
          child: Row(
            children: [
              _stepIcon(true, accent, Icons.edit_outlined),
              const SizedBox(width: 12),
              const Expanded(child: Text('Renseignées · modifier')),
              const Icon(Icons.chevron_right, color: Pro.muted),
            ],
          ),
        ),
        const ProSection('Justificatifs'),
        for (final kind in businessDocumentsOf(space.sector))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ProCard(
              onTap: _uploading == null ? () => _upload(space, kind) : null,
              child: Row(
                children: [
                  _stepIcon(
                    space.documents.contains(kind),
                    accent,
                    kind == 'selfie'
                        ? Icons.face_outlined
                        : Icons.description_outlined,
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(businessDocumentLabels[kind] ?? kind)),
                  if (_uploading == kind)
                    const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Text(
                      space.documents.contains(kind) ? 'Remplacer' : 'Ajouter',
                      style: t.labelLarge?.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
            ),
          ),
        const ProSection('Versements'),
        ProCard(
          onTap: () => _open(context, PayoutScreen(space: space)),
          child: Row(
            children: [
              _stepIcon(
                space.payout != null,
                accent,
                Icons.account_balance_wallet_outlined,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  space.payout == null
                      ? 'Compte Mobile Money et code PIN'
                      : '${space.payout!.phoneMasked} · ${space.payout!.holder}',
                ),
              ),
              const Icon(Icons.chevron_right, color: Pro.muted),
            ],
          ),
        ),
      ],
    );
  }
}

/// Compte de versement (Mobile Money) et code PIN.
class PayoutScreen extends ConsumerStatefulWidget {
  const PayoutScreen({super.key, required this.space});
  final BusinessSpace space;

  @override
  ConsumerState<PayoutScreen> createState() => _PayoutScreenState();
}

class _PayoutScreenState extends ConsumerState<PayoutScreen> {
  late var _operator = widget.space.payout?.operator ?? 'flooz';
  final _phone = TextEditingController();
  late final _holder = TextEditingController(text: widget.space.payout?.holder);
  final _pin = TextEditingController();
  final _newPin = TextEditingController();
  bool? _pinSet;
  var _errors = <String, String>{};
  var _busy = false;

  bool get _sensitive =>
      widget.space.status == 'active' || widget.space.status == 'suspended';

  @override
  void initState() {
    super.initState();
    ref.read(apiClientProvider).businessPinIsSet().then((v) {
      if (mounted) setState(() => _pinSet = v);
    });
  }

  @override
  void dispose() {
    for (final c in [_phone, _holder, _pin, _newPin]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _errors = {};
    });
    final api = ref.read(apiClientProvider);
    final navigator = Navigator.of(context);
    try {
      var pin = _pin.text.trim();
      if (_pinSet == false) {
        await api.setBusinessPin(_newPin.text.trim());
        _pinSet = true;
        pin = _newPin.text.trim();
      }
      await api.setBusinessPayout(
        widget.space.id,
        operator: _operator,
        phone: '+228${togoPhoneDigits(_phone.text)}',
        holder: _holder.text.trim(),
        pin: _sensitive ? pin : '',
      );
      await ref.read(businessGateProvider.notifier).refresh();
      if (mounted) navigator.pop();
    } on ApiException catch (e) {
      if (mounted) {
        setState(
          () => _errors = e.fields.isEmpty ? {'general': e.message} : e.fields,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _operatorTile(String code, String label) {
    final on = _operator == code;
    return Expanded(
      child: ProCard(
        border: on ? IviaColors.cobaltBlue : null,
        onTap: () => setState(() => _operator = code),
        child: Row(
          children: [
            Icon(
              on ? Icons.radio_button_checked : Icons.radio_button_off,
              size: 18,
              color: on ? IviaColors.cobaltBlue : Pro.muted,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
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
    final pinField = InputDecoration(
      errorText: _errors['pin'],
      counterText: '',
    );
    return ProPage(
      title: 'Compte de versement',
      bottom: ProButton(
        label: 'Enregistrer',
        busy: _busy,
        onPressed: _pinSet == null ? null : _save,
      ),
      children: [
        Text(
          'Le titulaire doit correspondre à votre pièce d\'identité : ivia le vérifie.',
          style: t.bodyMedium?.copyWith(color: Pro.muted),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            _operatorTile('flooz', 'Moov Money'),
            const SizedBox(width: 10),
            _operatorTile('tmoney', 'Yas'),
          ],
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
        const SizedBox(height: 14),
        if (_pinSet == false)
          IviaFieldLabel(
            label: 'Créez votre code PIN (4 à 6 chiffres)',
            child: TextField(
              controller: _newPin,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: pinField,
            ),
          ),
        if (_pinSet == true && _sensitive)
          IviaFieldLabel(
            label: 'Votre code PIN',
            child: TextField(
              controller: _pin,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: pinField,
            ),
          ),
        if (_errors['general'] != null)
          Text(
            _errors['general']!,
            style: const TextStyle(color: IviaColors.imperialRed),
          ),
      ],
    );
  }
}

/// Plusieurs espaces : le professionnel choisit celui à ouvrir.
class ChooseSpaceScreen extends ConsumerWidget {
  const ChooseSpaceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final spaces =
        ref.watch(businessGateProvider).value?.spaces ??
        const <BusinessSpace>[];
    return ProPage(
      title: 'Mes espaces',
      actions: [
        TextButton(
          onPressed: ref.read(authControllerProvider.notifier).signOut,
          child: const Text('Quitter'),
        ),
      ],
      bottom: ProButton(
        outlined: true,
        icon: Icons.add,
        label: 'Créer un autre espace',
        onPressed: () => context.go(Routes.businessNew),
      ),
      children: [
        Text(
          'Quelle activité ouvrir ?',
          style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 14),
        for (final s in spaces)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: ProCard(
              onTap: () => ref.read(businessGateProvider.notifier).open(s.id),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Pro.accent(s.sector),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Pro.icon(s.sector), color: Colors.white),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.name,
                          style: t.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          '${s.sectorLabel} · ${s.statusLabel}',
                          style: t.bodySmall?.copyWith(color: Pro.muted),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Pro.muted),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// En attente (accès restreint) ou suspendu ; le statut se relit tout seul.
class BusinessStatusScreen extends ConsumerStatefulWidget {
  const BusinessStatusScreen({super.key});

  @override
  ConsumerState<BusinessStatusScreen> createState() =>
      _BusinessStatusScreenState();
}

class _BusinessStatusScreenState extends ConsumerState<BusinessStatusScreen> {
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(seconds: 20), (_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      await ref.read(businessGateProvider.notifier).refresh();
      ref.invalidate(sellerShopProvider);
    } on ApiException {
      // Réseau : le prochain passage réessaie.
    }
  }

  Widget _step(
    String title,
    String? sub, {
    required bool done,
    bool current = false,
    bool last = false,
    required Color accent,
  }) {
    final t = Theme.of(context).textTheme;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 28,
            child: Column(
              children: [
                if (current)
                  PulseDot(color: accent, size: 10)
                else
                  Icon(
                    done ? Icons.check_circle : Icons.circle_outlined,
                    size: 24,
                    color: done ? IviaColors.success : Pro.line,
                  ),
                if (!last)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: done ? IviaColors.success : Pro.line,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 18, top: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: t.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: done || current ? null : Pro.muted,
                    ),
                  ),
                  if (sub != null)
                    Text(sub, style: t.bodySmall?.copyWith(color: Pro.muted)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final space = ref.watch(businessGateProvider).value?.opened;
    if (space == null) return const Scaffold(body: SizedBox.shrink());
    final pending = space.status == 'pending_review';
    final accent = Pro.accent(space.sector);
    return Scaffold(
      backgroundColor: Pro.page,
      body: Column(
        children: [
          ProPanel(
            accent: accent,
            child: Reveal(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ProTag(
                    space.sectorLabel,
                    color: accent,
                    icon: Pro.icon(space.sector),
                    solid: true,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    space.name,
                    style: t.headlineSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    pending
                        ? 'Votre dossier est entre les mains de l\'équipe ivia.'
                        : 'Votre espace est suspendu.',
                    style: t.bodyMedium?.copyWith(color: Colors.white70),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (pending)
                  Reveal(
                    index: 1,
                    child: ProCard(
                      child: Column(
                        children: [
                          _step(
                            'Compte créé',
                            null,
                            done: true,
                            accent: accent,
                          ),
                          _step(
                            'Dossier envoyé',
                            space.name,
                            done: true,
                            accent: accent,
                          ),
                          _step(
                            'Validation par ivia',
                            'En cours. Vous serez prévenu dès la décision.',
                            done: false,
                            current: true,
                            accent: accent,
                          ),
                          _step(
                            'Visible par les clients',
                            null,
                            done: false,
                            last: true,
                            accent: accent,
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Reveal(
                    index: 1,
                    child: ProCard(
                      color: IviaColors.warningSoft,
                      border: IviaColors.warning,
                      child: Text(
                        space.statusReason.isEmpty
                            ? 'Contactez le support ivia.'
                            : space.statusReason,
                        style: t.bodyLarge,
                      ),
                    ),
                  ),
                const SizedBox(height: 14),
                if (pending) ...[
                  Reveal(
                    index: 2,
                    child: ProButton(
                      icon: Icons.edit_note_rounded,
                      color: accent,
                      label: switch (space.sector) {
                        'restaurant' => 'Préparer mon menu',
                        'real_estate' => 'Préparer mes annonces',
                        'artisan' => 'Préparer mes services',
                        _ => 'Préparer mon catalogue',
                      },
                      onPressed: () => context.go(
                        space.usesShop ? Routes.catalog : Routes.businessModule,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Tout reste en brouillon, invisible des clients jusqu\'à la validation.',
                      textAlign: TextAlign.center,
                      style: t.bodySmall?.copyWith(color: Pro.muted),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                TextButton(
                  onPressed: ref.read(businessGateProvider.notifier).close,
                  child: const Text('Mes espaces'),
                ),
                TextButton(
                  onPressed: ref.read(authControllerProvider.notifier).signOut,
                  child: const Text('Se déconnecter'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

final itemsProvider = FutureProvider.autoDispose
    .family<List<BusinessItem>, String>(
      (ref, id) => ref.read(apiClientProvider).businessItems(id),
    );

/// Module agence ou artisan : pilotage, contenu, agenda, profil.
class BusinessModuleScreen extends ConsumerStatefulWidget {
  const BusinessModuleScreen({super.key});

  @override
  ConsumerState<BusinessModuleScreen> createState() =>
      _BusinessModuleScreenState();
}

class _BusinessModuleScreenState extends ConsumerState<BusinessModuleScreen> {
  var _tab = 0;

  @override
  Widget build(BuildContext context) {
    final space = ref.watch(businessGateProvider).value?.opened;
    if (space == null) return const Scaffold(body: SizedBox.shrink());
    final agency = space.sector == 'real_estate';
    return Scaffold(
      backgroundColor: Pro.page,
      body: AnimatedSwitcher(
        duration: Pro.fast,
        child: KeyedSubtree(
          key: ValueKey(_tab),
          child: switch (_tab) {
            0 => _ModuleHome(
              space: space,
              onSeeItems: () => setState(() => _tab = 1),
            ),
            1 => _ItemsTab(space: space),
            2 => _AgendaTab(space: space),
            _ => const ProProfile(),
          },
        ),
      ),
      bottomNavigationBar: ProDock(
        accent: Pro.accent(space.sector),
        current: _tab,
        onSelected: (i) => setState(() => _tab = i),
        items: [
          const ProDockItem(Icons.space_dashboard_outlined, 'Pilotage'),
          ProDockItem(
            agency ? Icons.apartment_outlined : Icons.handyman_outlined,
            agency ? 'Annonces' : 'Services',
          ),
          const ProDockItem(Icons.calendar_month_outlined, 'Agenda'),
          const ProDockItem(Icons.person_outline, 'Profil'),
        ],
      ),
    );
  }
}

/// En-tête du panneau : logo, nom, état vivant, secteur.
class SpaceHeader extends StatelessWidget {
  const SpaceHeader({super.key, required this.space});
  final BusinessSpace space;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final active = space.status == 'active';
    return Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: Pro.ink2,
            borderRadius: BorderRadius.circular(10),
          ),
          clipBehavior: Clip.antiAlias,
          child: space.logoUrl == null
              ? Icon(Pro.icon(space.sector), color: Colors.white)
              : Image.network(
                  space.logoUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) =>
                      Icon(Pro.icon(space.sector), color: Colors.white),
                ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                space.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Row(
                children: [
                  PulseDot(
                    color: active
                        ? const Color(0xFF3DD68C)
                        : const Color(0xFFF5B942),
                    size: 6,
                  ),
                  const SizedBox(width: 2),
                  Flexible(
                    child: Text(
                      active ? 'En ligne' : 'Brouillon · validation en cours',
                      overflow: TextOverflow.ellipsis,
                      style: t.bodySmall?.copyWith(color: Colors.white70),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: ProTag(
            space.sectorLabel,
            color: Pro.accent(space.sector),
            icon: Pro.icon(space.sector),
            solid: true,
          ),
        ),
      ],
    );
  }
}

class _ModuleHome extends ConsumerWidget {
  const _ModuleHome({required this.space, required this.onSeeItems});
  final BusinessSpace space;
  final VoidCallback onSeeItems;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items =
        ref.watch(itemsProvider(space.id)).value ?? const <BusinessItem>[];
    final agency = space.sector == 'real_estate';
    final active = items.where((i) => i.status == 'active').length;
    final drafts = items.where((i) => i.status == 'draft').length;
    final openDays = _weekOf(space.details)
        .where((d) => d['open'] == true)
        .length;
    final t = Theme.of(context).textTheme;
    return Column(
      children: [
        ProPanel(
          accent: Pro.accent(space.sector),
          child: Column(
            children: [
              SpaceHeader(space: space),
              const SizedBox(height: 18),
              KpiStrip(
                items: [
                  Kpi(
                    agency ? 'Annonces en ligne' : 'Services en ligne',
                    active,
                  ),
                  Kpi('Brouillons', drafts),
                  Kpi('Jours ouverts', openDays),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Reveal(
                child: ProCard(
                  onTap: () => _open(context, ItemFormScreen(space: space)),
                  child: Row(
                    children: [
                      Icon(
                        Icons.add_box_outlined,
                        color: Pro.accent(space.sector),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          agency ? 'Ajouter une annonce' : 'Ajouter un service',
                          style: t.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: Pro.muted),
                    ],
                  ),
                ),
              ),
              ProSection(
                agency ? 'Dernières annonces' : 'Derniers services',
                action: items.isEmpty ? null : 'Tout voir',
                onAction: onSeeItems,
              ),
              if (items.isEmpty)
                Reveal(
                  index: 1,
                  child: ProEmpty(
                    icon: Pro.icon(space.sector),
                    title: agency
                        ? 'Pas encore d\'annonce'
                        : 'Pas encore de service',
                    body: 'Ajoutez votre premier élément : il reste en brouillon tant que votre espace n\'est pas validé.',
                  ),
                ),
              for (final (i, item) in items.take(4).indexed)
                Reveal(
                  index: i + 1,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: ItemTile(space: space, item: item),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Ligne d'une annonce ou d'un service.
class ItemTile extends StatelessWidget {
  const ItemTile({super.key, required this.space, required this.item});
  final BusinessSpace space;
  final BusinessItem item;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final a = item.attributes;
    final agency = space.sector == 'real_estate';
    final rent = a['listing'] == 'rent';
    final accent = Pro.accent(space.sector);
    final sub = agency
        ? [
            if (a['bedrooms'] != null) '${a['bedrooms']} ch',
            if (a['surface'] != null) '${a['surface']} m²',
            if (a['neighborhood'] != null) a['neighborhood'],
          ].join(' · ')
        : [
            if (a['duration'] != null) a['duration'],
            if (a['trade'] != null) a['trade'],
          ].join(' · ');
    return ProCard(
      padding: const EdgeInsets.all(10),
      onTap: () => _open(context, ItemFormScreen(space: space, item: item)),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            clipBehavior: Clip.antiAlias,
            child: item.photoUrls.isEmpty
                ? Icon(Pro.icon(space.sector), color: accent)
                : Image.network(
                    item.photoUrls.first,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        Icon(Pro.icon(space.sector), color: accent),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                if (sub.isNotEmpty)
                  Text(
                    sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.bodySmall?.copyWith(color: Pro.muted),
                  ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (agency) ...[
                      ProTag(rent ? 'Location' : 'Vente', color: accent),
                      const SizedBox(width: 6),
                    ],
                    if (item.status != 'active')
                      ProTag(
                        item.status == 'draft' ? 'Brouillon' : 'Archivé',
                        color: Pro.muted,
                      ),
                  ],
                ),
              ],
            ),
          ),
          Text(
            '${item.priceXof > 0 ? formatXof(item.priceXof) : 'Sur devis'}${agency && rent ? '\n/ mois' : ''}',
            textAlign: TextAlign.end,
            style: t.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              fontFeatures: Pro.tabular,
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemsTab extends ConsumerStatefulWidget {
  const _ItemsTab({required this.space});
  final BusinessSpace space;

  @override
  ConsumerState<_ItemsTab> createState() => _ItemsTabState();
}

class _ItemsTabState extends ConsumerState<_ItemsTab> {
  var _filter = 0;
  static const _codes = ['active', 'draft', 'archived'];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final space = widget.space;
    final agency = space.sector == 'real_estate';
    final accent = Pro.accent(space.sector);
    final async = ref.watch(itemsProvider(space.id));
    final all = async.value ?? const <BusinessItem>[];
    final shown = all.where((i) => i.status == _codes[_filter]).toList();
    int n(String c) => all.where((i) => i.status == c).length;
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    agency ? 'Annonces' : 'Services',
                    style: t.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () => _open(context, ItemFormScreen(space: space)),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Ajouter'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ProFilter(
              accent: accent,
              current: _filter,
              onSelected: (i) => setState(() => _filter = i),
              labels: [
                'En ligne · ${n('active')}',
                'Brouillons · ${n('draft')}',
                'Archivés · ${n('archived')}',
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => ref.invalidate(itemsProvider(space.id)),
              child: ListView(
                key: ValueKey(_filter),
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  if (shown.isEmpty && !async.isLoading)
                    ProEmpty(
                      icon: Pro.icon(space.sector),
                      title: 'Rien ici pour le moment',
                      body: agency
                          ? 'Vos annonces de cette catégorie apparaîtront ici.'
                          : 'Vos services de cette catégorie apparaîtront ici.',
                    ),
                  for (final (i, item) in shown.indexed)
                    Reveal(
                      index: i,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: ItemTile(space: space, item: item),
                      ),
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

/// Saisie d'une annonce (agence) ou d'un service (artisan).
class ItemFormScreen extends ConsumerStatefulWidget {
  const ItemFormScreen({super.key, required this.space, this.item});
  final BusinessSpace space;
  final BusinessItem? item;

  @override
  ConsumerState<ItemFormScreen> createState() => _ItemFormScreenState();
}

class _ItemFormScreenState extends ConsumerState<ItemFormScreen> {
  late final _a = <String, dynamic>{...?widget.item?.attributes};
  late final _title = TextEditingController(text: widget.item?.title);
  late final _description = TextEditingController(
    text: widget.item?.description,
  );
  late final _price = TextEditingController(
    text: (widget.item?.priceXof ?? 0) > 0 ? '${widget.item!.priceXof}' : '',
  );
  late final _rooms = _attr('rooms');
  late final _bedrooms = _attr('bedrooms');
  late final _surface = _attr('surface');
  late final _neighborhood = _attr('neighborhood');
  late final List<String> _photos = [...?widget.item?.photoKeys];
  var _errors = <String, String>{};
  String? _busy;
  var _uploading = false;

  static const _kinds = {
    'apartment': 'Appartement',
    'house': 'Maison',
    'studio': 'Studio',
    'land': 'Terrain',
    'office': 'Bureau',
  };
  static const _durations = [
    '30 min',
    '45 min',
    '1 h',
    '1 h 30',
    '2 h',
    '3 h',
    '1 journée',
  ];

  bool get _agency => widget.space.sector == 'real_estate';
  Color get _accent => Pro.accent(widget.space.sector);

  TextEditingController _attr(String key) =>
      TextEditingController(text: _a[key]?.toString());

  @override
  void initState() {
    super.initState();
    if (_agency) {
      _a['listing'] ??= 'rent';
      _a['kind'] ??= 'apartment';
    } else {
      _a['duration'] ??= '1 h';
      _a['manual_confirm'] ??= true;
      final trades = widget.space.details['trades'] as List? ?? const [];
      if (trades.isNotEmpty) _a['trade'] ??= trades.first;
    }
  }

  @override
  void dispose() {
    for (final c in [
      _title,
      _description,
      _price,
      _rooms,
      _bedrooms,
      _surface,
      _neighborhood,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _addPhoto() async {
    setState(() => _uploading = true);
    try {
      final key = await _pickAndUpload(ref, 'business_photo');
      if (key != null && mounted) setState(() => _photos.add(key));
    } on ApiException catch (e) {
      if (mounted) _say(context, e.message);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _save(String status) async {
    setState(() {
      _busy = status;
      _errors = {};
    });
    if (_agency) {
      _a['rooms'] = int.tryParse(_rooms.text);
      _a['bedrooms'] = int.tryParse(_bedrooms.text);
      _a['surface'] = int.tryParse(_surface.text);
      _a['neighborhood'] = _neighborhood.text.trim();
      _a.removeWhere((_, v) => v == null || v == '');
    }
    final navigator = Navigator.of(context);
    try {
      await ref
          .read(apiClientProvider)
          .saveBusinessItem(
            spaceId: widget.space.id,
            itemId: widget.item?.id,
            title: _title.text.trim(),
            description: _description.text.trim(),
            priceXof:
                int.tryParse(_price.text.replaceAll(RegExp(r'\D'), '')) ?? 0,
            status: status,
            attributes: _a,
            photoKeys: _photos,
          );
      ref.invalidate(itemsProvider(widget.space.id));
      if (mounted) navigator.pop();
    } on ApiException catch (e) {
      if (mounted) {
        setState(
          () => _errors = e.fields.isEmpty ? {'title': e.message} : e.fields,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _delete() async {
    final navigator = Navigator.of(context);
    try {
      await ref.read(apiClientProvider).deleteBusinessItem(widget.item!.id);
      ref.invalidate(itemsProvider(widget.space.id));
      navigator.pop();
    } on ApiException catch (e) {
      if (mounted) _say(context, e.message);
    }
  }

  Widget _choices(Map<String, String> options, String key) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final e in options.entries)
        ChoiceChip(
          label: Text(e.value),
          selected: _a[key] == e.key,
          selectedColor: _accent.withValues(alpha: 0.14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          onSelected: (_) => setState(() => _a[key] = e.key),
        ),
    ],
  );

  Widget _num(String label, TextEditingController c) => Expanded(
    child: IviaFieldLabel(
      label: label,
      child: TextField(controller: c, keyboardType: TextInputType.number),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final active = widget.space.status == 'active';
    final trades = [
      for (final t in (widget.space.details['trades'] as List?) ?? const [])
        t as String,
    ];
    return ProPage(
      title: widget.item != null
          ? 'Modifier'
          : _agency
          ? 'Nouvelle annonce'
          : 'Nouveau service',
      actions: [
        if (widget.item != null)
          IconButton(
            tooltip: 'Supprimer',
            icon: const Icon(Icons.delete_outline),
            onPressed: _delete,
          ),
      ],
      bottom: Row(
        children: [
          Expanded(
            child: ProButton(
              outlined: true,
              label: 'Brouillon',
              busy: _busy == 'draft',
              onPressed: _busy == null && !_uploading
                  ? () => _save('draft')
                  : null,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: ProButton(
              color: _accent,
              label: active ? 'Publier' : 'Après validation',
              busy: _busy == 'active',
              onPressed: active && _busy == null && !_uploading
                  ? () => _save('active')
                  : null,
            ),
          ),
        ],
      ),
      children: [
        if (_agency) ...[
          _choices(const {'rent': 'Location', 'sale': 'Vente'}, 'listing'),
          const SizedBox(height: 12),
          _choices(_kinds, 'kind'),
          const SizedBox(height: 14),
        ],
        IviaFieldLabel(
          label: _agency ? 'Titre de l\'annonce' : 'Nom du service',
          child: TextField(
            controller: _title,
            decoration: InputDecoration(errorText: _errors['title']),
          ),
        ),
        const SizedBox(height: 14),
        IviaFieldLabel(
          label: _agency
              ? (_a['listing'] == 'rent'
                    ? 'Loyer mensuel (FCFA)'
                    : 'Prix de vente (FCFA)')
              : 'Prix fixe (FCFA)',
          child: TextField(
            controller: _price,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(errorText: _errors['price_xof']),
          ),
        ),
        const SizedBox(height: 14),
        if (_agency) ...[
          Row(
            children: [
              _num('Pièces', _rooms),
              const SizedBox(width: 10),
              _num('Chambres', _bedrooms),
              const SizedBox(width: 10),
              _num('Surface (m²)', _surface),
            ],
          ),
          const SizedBox(height: 14),
          IviaFieldLabel(
            label: 'Quartier',
            child: TextField(controller: _neighborhood),
          ),
          const SizedBox(height: 14),
        ] else ...[
          if (trades.isNotEmpty) ...[
            IviaFieldLabel(
              label: 'Métier',
              child: DropdownButtonFormField<String>(
                initialValue: trades.contains(_a['trade'])
                    ? _a['trade'] as String
                    : trades.first,
                items: [
                  for (final t in trades)
                    DropdownMenuItem(value: t, child: Text(t)),
                ],
                onChanged: (v) => setState(() => _a['trade'] = v),
              ),
            ),
            const SizedBox(height: 14),
          ],
          IviaFieldLabel(
            label: 'Durée',
            child: DropdownButtonFormField<String>(
              initialValue: _durations.contains(_a['duration'])
                  ? _a['duration'] as String
                  : '1 h',
              items: [
                for (final d in _durations)
                  DropdownMenuItem(value: d, child: Text(d)),
              ],
              onChanged: (v) => setState(() => _a['duration'] = v),
            ),
          ),
          const SizedBox(height: 14),
        ],
        IviaFieldLabel(
          label: _agency ? 'Description' : 'Ce qui est inclus',
          child: TextField(controller: _description, maxLines: 4),
        ),
        const SizedBox(height: 14),
        if (!_agency) ...[
          ProCard(
            padding: EdgeInsets.zero,
            child: SwitchListTile(
              title: const Text('Confirmation manuelle'),
              subtitle: const Text('Vous validez chaque réservation'),
              activeTrackColor: _accent,
              value: _a['manual_confirm'] == true,
              onChanged: (v) => setState(() => _a['manual_confirm'] = v),
            ),
          ),
          const SizedBox(height: 14),
        ],
        ProButton(
          outlined: true,
          icon: Icons.photo_library_outlined,
          label: 'Photos · ${_photos.length}',
          busy: _uploading,
          onPressed: _addPhoto,
        ),
      ],
    );
  }
}

/// Agenda : la semaine réelle de l'espace ; les demandes arriveront avec la
/// réservation côté client.
class _AgendaTab extends StatelessWidget {
  const _AgendaTab({required this.space});
  final BusinessSpace space;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final accent = Pro.accent(space.sector);
    final agency = space.sector == 'real_estate';
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Agenda',
            style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          Reveal(
            child: ProCard(
              child: Column(
                children: [
                  for (final d in _weekOf(space.details))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 42,
                            child: Text(
                              _dayNames[(d['day'] as int) - 1],
                              style: t.labelLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Container(
                              height: 26,
                              alignment: Alignment.centerLeft,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                              decoration: BoxDecoration(
                                color: d['open'] == true
                                    ? accent.withValues(alpha: 0.12)
                                    : Pro.page,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                d['open'] == true
                                    ? '${d['from']} → ${d['to']}'
                                    : 'Fermé',
                                style: t.labelMedium?.copyWith(
                                  color: d['open'] == true ? accent : Pro.muted,
                                  fontFeatures: Pro.tabular,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Reveal(
            index: 1,
            child: ProButton(
              outlined: true,
              icon: Icons.tune,
              label: 'Modifier mes disponibilités',
              onPressed: () => _open(context, AvailabilityScreen(space: space)),
            ),
          ),
          ProSection(agency ? 'Demandes de visite' : 'Réservations'),
          Reveal(
            index: 2,
            child: ProEmpty(
              icon: Icons.event_available_outlined,
              title: 'Aucune demande pour le moment',
              body: agency
                  ? 'Les demandes de visite des clients apparaîtront ici.'
                  : 'Les réservations des clients apparaîtront ici.',
            ),
          ),
        ],
      ),
    );
  }
}

/// Disponibilités de la semaine.
class AvailabilityScreen extends ConsumerStatefulWidget {
  const AvailabilityScreen({super.key, required this.space});
  final BusinessSpace space;

  @override
  ConsumerState<AvailabilityScreen> createState() => _AvailabilityScreenState();
}

class _AvailabilityScreenState extends ConsumerState<AvailabilityScreen> {
  late final _week = _weekOf(widget.space.details);
  var _busy = false;

  Future<void> _save() async {
    setState(() => _busy = true);
    final navigator = Navigator.of(context);
    try {
      await ref
          .read(apiClientProvider)
          .setBusinessAvailability(widget.space.id, _week);
      await ref.read(businessGateProvider.notifier).refresh();
      if (mounted) navigator.pop();
    } on ApiException catch (e) {
      if (mounted) _say(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ProPage(
    title: 'Disponibilités',
    bottom: ProButton(label: 'Enregistrer', busy: _busy, onPressed: _save),
    children: [
      WeekEditor(
        week: _week,
        accent: Pro.accent(widget.space.sector),
        onChanged: () => setState(() {}),
      ),
    ],
  );
}

/// Profil commun aux modules.
class ProProfile extends ConsumerWidget {
  const ProProfile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final user = switch (ref.watch(authControllerProvider)) {
      AuthSignedIn(:final user) || AuthNeedsProfile(:final user) => user,
      _ => null,
    };
    final space = ref.watch(businessGateProvider).value?.opened;
    final name = [
      user?.firstName,
      user?.lastName,
    ].whereType<String>().where((s) => s.isNotEmpty).join(' ');
    Widget row(
      IconData icon,
      String title,
      VoidCallback onTap, {
      String? sub,
      Color? color,
    }) => ListTile(
      leading: Icon(icon, color: color ?? Pro.ink),
      title: Text(
        title,
        style: t.bodyLarge?.copyWith(fontWeight: FontWeight.w600, color: color),
      ),
      subtitle: sub == null ? null : Text(sub),
      trailing: color == null
          ? const Icon(Icons.chevron_right, color: Pro.muted)
          : null,
      onTap: onTap,
    );
    return Column(
      children: [
        ProPanel(
          accent: Pro.accent(space?.sector),
          child: space == null
              ? const SizedBox(height: 46)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SpaceHeader(space: space),
                    const SizedBox(height: 12),
                    Text(
                      [
                        if (name.isNotEmpty) name,
                        if ((user?.phone ?? '').isNotEmpty)
                          formatTogoPhone(user!.phone!),
                      ].join(' · '),
                      style: t.bodySmall?.copyWith(color: Colors.white70),
                    ),
                  ],
                ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const ProSection('Mon activité'),
              Reveal(
                child: ProCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      if (space?.usesShop ?? false) ...[
                        row(
                          Icons.query_stats,
                          'Revenus et relevés',
                          () => _open(context, const RevenueScreen()),
                        ),
                        const Divider(height: 1),
                      ],
                      if (space != null) ...[
                        row(
                          Icons.account_balance_wallet_outlined,
                          'Compte de versement',
                          () => _open(context, PayoutScreen(space: space)),
                          sub: space.payout?.phoneMasked ?? 'À renseigner',
                        ),
                        const Divider(height: 1),
                      ],
                      row(
                        Icons.swap_horiz,
                        'Mes espaces',
                        ref.read(businessGateProvider.notifier).close,
                      ),
                    ],
                  ),
                ),
              ),
              const ProSection('Sécurité'),
              Reveal(
                index: 1,
                child: ProCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      row(
                        Icons.phone_iphone,
                        'Changer de numéro',
                        () => _open(context, const ChangePhoneScreen()),
                      ),
                      const Divider(height: 1),
                      row(
                        Icons.devices_outlined,
                        'Appareils connectés',
                        () => _open(context, const ConnectedDevicesScreen()),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Reveal(
                index: 2,
                child: ProCard(
                  padding: EdgeInsets.zero,
                  child: row(
                    Icons.logout,
                    'Se déconnecter',
                    ref.read(authControllerProvider.notifier).signOut,
                    color: Pro.urgent,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
