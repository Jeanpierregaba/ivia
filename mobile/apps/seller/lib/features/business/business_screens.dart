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

// Parcours Ivia Business : écrans fonctionnels, en attendant les maquettes.

void _say(BuildContext context, String message) =>
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));

class _Box extends StatelessWidget {
  const _Box({required this.child, this.onTap, this.color});
  final Widget child;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Material(
      color: color ?? IviaColors.surface,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: const EdgeInsets.all(16), child: child),
      ),
    ),
  );
}

class _Page extends StatelessWidget {
  const _Page({required this.title, required this.children, this.actions});
  final String title;
  final List<Widget> children;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: IviaColors.background,
    appBar: AppBar(
      backgroundColor: IviaColors.background,
      title: Text(title),
      actions: actions,
    ),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(IviaSpacing.screen),
        children: children,
      ),
    ),
  );
}

/// Choix du secteur : il décide du formulaire, des justificatifs et du module.
class SectorScreen extends ConsumerWidget {
  const SectorScreen({super.key});

  static const _icons = {
    'shop': Icons.storefront_outlined,
    'real_estate': Icons.apartment_outlined,
    'artisan': Icons.handyman_outlined,
    'restaurant': Icons.restaurant_outlined,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) => _Page(
    title: 'Votre activité',
    actions: [
      TextButton(
        onPressed: ref.read(authControllerProvider.notifier).signOut,
        child: const Text('Se déconnecter'),
      ),
    ],
    children: [
      Text(
        'Quel est votre secteur ?',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: IviaSpacing.lg),
      for (final e in businessSectorLabels.entries)
        _Box(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => SpaceFormScreen(sector: e.key),
            ),
          ),
          child: Row(
            children: [
              Icon(_icons[e.key], color: IviaColors.berkeleyBlue),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  e.value,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
    ],
  );
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
  late final _hours = _text('opening_hours');
  late final _trades = TextEditingController(
    text: ((_d['trades'] as List?) ?? const []).join(', '),
  );
  late final List<String> _photoKeys = [
    for (final k in (_d['photo_keys'] as List?) ?? const []) k as String,
  ];
  var _errors = <String, String>{};
  var _busy = false;

  TextEditingController _text(String key) =>
      TextEditingController(text: _d[key] as String?);

  bool get _establishment =>
      widget.sector == 'shop' || widget.sector == 'restaurant';

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
      _hours,
      _trades,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<String?> _upload(String purpose) async {
    final bytes = await ref
        .read(photoPickerProvider)
        .pick(source: PhotoSource.gallery, maxSide: 1600);
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

  Future<void> _addPhoto() async {
    try {
      final key = await _upload('business_photo');
      if (key != null && mounted) setState(() => _photoKeys.add(key));
    } on ApiException catch (e) {
      if (mounted) _say(context, e.message);
    }
  }

  Future<void> _addLogo() async {
    try {
      // Le logo d'une boutique est repris par sa fiche visible des clients.
      final key = await _upload(
        _establishment ? 'shop_logo' : 'business_photo',
      );
      if (key != null && mounted) setState(() => _d['logo_key'] = key);
    } on ApiException catch (e) {
      if (mounted) _say(context, e.message);
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
      if (v.isEmpty) {
        _d.remove(key);
      } else {
        _d[key] = v;
      }
    }

    put('description', _description.text);
    put('address_text', _address.text);
    put('rccm', _rccm.text);
    put('zone', _zone.text);
    put('cuisine', _cuisine.text);
    put('opening_hours', _hours.text);
    if (_establishment) _d['phone'] = '+228${togoPhoneDigits(_phone.text)}';
    _d['trades'] = [
      for (final t in _trades.text.split(','))
        if (t.trim().isNotEmpty) t.trim(),
    ];
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

  Widget _error(String key) => _errors[key] == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            _errors[key]!,
            style: const TextStyle(color: IviaColors.imperialRed),
          ),
        );

  @override
  Widget build(BuildContext context) {
    final sector = widget.sector;
    final choices = ref.watch(shopChoicesProvider).value;
    return _Page(
      title: businessSectorLabels[sector] ?? sector,
      children: [
        _field(
          'name',
          sector == 'real_estate'
              ? 'Nom de l\'agence'
              : sector == 'artisan'
              ? 'Nom ou enseigne'
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
        if (sector == 'artisan')
          _field('trades', 'Métiers', _trades, hint: 'Plombier, électricien'),
        if (sector == 'real_estate' || sector == 'artisan')
          _field(
            'zone',
            sector == 'artisan' ? 'Zone d\'intervention' : 'Zone',
            _zone,
            hint: 'Lomé, Baguida',
          ),
        if (sector == 'restaurant') ...[
          _field('cuisine', 'Cuisine', _cuisine, hint: 'Togolaise, grillades'),
          _field(
            'opening_hours',
            'Horaires',
            _hours,
            hint: 'Lun-Sam 11 h - 22 h',
          ),
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
          _field(
            'address_text',
            'Adresse',
            _address,
            hint: 'Rue, quartier, repère',
          ),
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
          OutlinedButton.icon(
            onPressed: _locate,
            icon: const Icon(Icons.my_location),
            label: Text(
              _d['lat'] == null
                  ? 'Utiliser ma position'
                  : 'Position enregistrée',
            ),
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
        OutlinedButton.icon(
          onPressed: _addLogo,
          icon: const Icon(Icons.image_outlined),
          label: Text(
            _d['logo_key'] == null
                ? 'Ajouter un logo'
                : 'Logo ajouté (remplacer)',
          ),
        ),
        _error('logo_key'),
        if (sector != 'real_estate') ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _addPhoto,
            icon: const Icon(Icons.add_a_photo_outlined),
            label: Text(
              '${sector == 'artisan' ? 'Photos de réalisations' : 'Photos'} (${_photoKeys.length})',
            ),
          ),
          _error('photo_keys'),
        ],
        const SizedBox(height: IviaSpacing.xl),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(_busy ? 'Patientez…' : 'Continuer'),
        ),
      ],
    );
  }
}

/// Dossier : motif éventuel, justificatifs, compte de versement, code PIN, envoi.
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
    final bytes = await ref
        .read(photoPickerProvider)
        .pick(source: source, maxSide: 1600);
    if (bytes == null) return;
    setState(() => _uploading = kind);
    try {
      final api = ref.read(apiClientProvider);
      final prepared = await api.prepareUpload(
        purpose: 'business_document',
        contentType: 'image/jpeg',
        sizeBytes: bytes.length,
      );
      await api.upload(prepared, bytes);
      await api.addBusinessDocument(space.id, kind, prepared.objectKey);
      await ref.read(businessGateProvider.notifier).refresh();
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
      // Boutique ou restaurant : le rôle marchand vient d'être accordé.
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

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final space = ref.watch(businessGateProvider).value?.opened;
    if (space == null) return const Scaffold(body: SizedBox.shrink());
    final push = Navigator.of(context);
    return _Page(
      title: space.name,
      actions: [
        TextButton(
          onPressed: ref.read(businessGateProvider.notifier).close,
          child: const Text('Mes espaces'),
        ),
      ],
      children: [
        if (space.statusReason.isNotEmpty)
          _Box(
            color: IviaColors.warningSoft,
            child: Text(
              '${space.statusLabel} : ${space.statusReason}',
              style: t.bodyLarge,
            ),
          ),
        _Box(
          onTap: () => push.push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  SpaceFormScreen(sector: space.sector, space: space),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Informations · ${space.sectorLabel}',
                  style: t.titleMedium,
                ),
              ),
              const Icon(Icons.edit_outlined),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
          child: Text('Justificatifs', style: t.titleMedium),
        ),
        for (final kind in businessDocumentsOf(space.sector))
          _Box(
            child: Row(
              children: [
                Icon(
                  space.documents.contains(kind)
                      ? Icons.check_circle
                      : Icons.description_outlined,
                  color: space.documents.contains(kind)
                      ? IviaColors.success
                      : IviaColors.textMuted,
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(businessDocumentLabels[kind] ?? kind)),
                if (_uploading == kind)
                  const SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  TextButton(
                    onPressed: () => _upload(space, kind),
                    child: Text(
                      space.documents.contains(kind) ? 'Remplacer' : 'Ajouter',
                    ),
                  ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
          child: Text('Versements', style: t.titleMedium),
        ),
        _Box(
          onTap: () => push.push(
            MaterialPageRoute<void>(builder: (_) => PayoutScreen(space: space)),
          ),
          child: Row(
            children: [
              Icon(
                space.payout == null
                    ? Icons.account_balance_wallet_outlined
                    : Icons.check_circle,
                color: space.payout == null
                    ? IviaColors.textMuted
                    : IviaColors.success,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  space.payout == null
                      ? 'Compte de versement et code PIN'
                      : '${space.payout!.phoneMasked} · ${space.payout!.holder}',
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
        const SizedBox(height: IviaSpacing.xl),
        FilledButton(
          onPressed:
              _busy || space.missingDocuments.isNotEmpty || space.payout == null
              ? null
              : () => _submit(space),
          child: Text(_busy ? 'Patientez…' : 'Envoyer mon dossier'),
        ),
        if (space.missingDocuments.isNotEmpty || space.payout == null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Ajoutez les justificatifs et le compte de versement pour envoyer le dossier.',
              style: t.bodySmall,
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
      widget.space.status == 'approved' || widget.space.status == 'suspended';

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
      if (_pinSet == false) {
        await api.setBusinessPin(_newPin.text.trim());
        _pinSet = true;
      }
      await api.setBusinessPayout(
        widget.space.id,
        operator: _operator,
        phone: '+228${togoPhoneDigits(_phone.text)}',
        holder: _holder.text.trim(),
        pin: _sensitive ? _pin.text.trim() : '',
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

  @override
  Widget build(BuildContext context) => _Page(
    title: 'Compte de versement',
    children: [
      IviaFieldLabel(
        label: 'Opérateur',
        child: DropdownButtonFormField<String>(
          initialValue: _operator,
          items: const [
            DropdownMenuItem(value: 'flooz', child: Text('Moov Money (Flooz)')),
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
          decoration: InputDecoration(
            hintText: 'Le nom de votre pièce d\'identité',
            errorText: _errors['holder'],
          ),
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
            decoration: InputDecoration(
              helperText:
                  'Il confirmera vos retraits et ce changement de compte.',
              errorText: _errors['pin'],
            ),
          ),
        ),
      if (_sensitive)
        IviaFieldLabel(
          label: 'Code PIN',
          child: TextField(
            controller: _pin,
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: 6,
          ),
        ),
      if (_errors['general'] != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            _errors['general']!,
            style: const TextStyle(color: IviaColors.imperialRed),
          ),
        ),
      const SizedBox(height: IviaSpacing.xl),
      FilledButton(
        onPressed: _busy || _pinSet == null ? null : _save,
        child: Text(_busy ? 'Patientez…' : 'Enregistrer'),
      ),
    ],
  );
}

/// Plusieurs espaces : le marchand choisit celui à ouvrir.
class ChooseSpaceScreen extends ConsumerWidget {
  const ChooseSpaceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final spaces = ref.watch(businessGateProvider).value?.spaces ?? const [];
    return _Page(
      title: 'Mes espaces',
      actions: [
        TextButton(
          onPressed: ref.read(authControllerProvider.notifier).signOut,
          child: const Text('Se déconnecter'),
        ),
      ],
      children: [
        for (final s in spaces)
          _Box(
            onTap: () => ref.read(businessGateProvider.notifier).open(s.id),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.name, style: t.titleMedium),
                      Text(
                        '${s.sectorLabel} · ${s.statusLabel}',
                        style: t.bodySmall,
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        OutlinedButton.icon(
          onPressed: () => context.go(Routes.businessNew),
          icon: const Icon(Icons.add),
          label: const Text('Créer un autre espace'),
        ),
      ],
    );
  }
}

/// En attente de validation (accès restreint) ou suspendu.
class BusinessStatusScreen extends ConsumerWidget {
  const BusinessStatusScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final gate = ref.watch(businessGateProvider).value;
    final space = gate?.opened;
    if (space == null) return const Scaffold(body: SizedBox.shrink());
    final pending = space.status == 'pending_review';
    return _Page(
      title: space.name,
      children: [
        _Box(
          color: pending ? IviaColors.secondarySoft : IviaColors.warningSoft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(space.statusLabel, style: t.titleLarge),
              const SizedBox(height: 6),
              Text(
                pending
                    ? 'L\'équipe ivia vérifie votre dossier. Préparez votre espace : il reste invisible des clients jusqu\'à la validation.'
                    : space.statusReason,
                style: t.bodyLarge,
              ),
            ],
          ),
        ),
        if (pending)
          FilledButton(
            onPressed: () => context.go(
              space.usesShop ? Routes.catalog : Routes.businessModule,
            ),
            child: const Text('Préparer mon espace'),
          ),
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: () async {
            await ref.read(businessGateProvider.notifier).refresh();
            ref.invalidate(sellerShopProvider);
          },
          child: const Text('Actualiser le statut'),
        ),
        TextButton(
          onPressed: ref.read(businessGateProvider.notifier).close,
          child: const Text('Mes espaces'),
        ),
        TextButton(
          onPressed: ref.read(authControllerProvider.notifier).signOut,
          child: const Text('Se déconnecter'),
        ),
      ],
    );
  }
}

final _itemsProvider = FutureProvider.autoDispose
    .family<List<BusinessItem>, String>(
      (ref, id) => ref.read(apiClientProvider).businessItems(id),
    );

/// Module agence ou artisan : biens et services, versements, compte.
class BusinessModuleScreen extends ConsumerStatefulWidget {
  const BusinessModuleScreen({super.key});

  @override
  ConsumerState<BusinessModuleScreen> createState() =>
      _BusinessModuleScreenState();
}

class _BusinessModuleScreenState extends ConsumerState<BusinessModuleScreen> {
  final _title = TextEditingController();
  final _price = TextEditingController();

  @override
  void dispose() {
    _title.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _add(String spaceId) async {
    try {
      await ref
          .read(apiClientProvider)
          .addBusinessItem(
            spaceId,
            title: _title.text.trim(),
            priceXof:
                int.tryParse(_price.text.replaceAll(RegExp(r'\D'), '')) ?? 0,
          );
      _title.clear();
      _price.clear();
      ref.invalidate(_itemsProvider(spaceId));
    } on ApiException catch (e) {
      if (mounted) _say(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final space = ref.watch(businessGateProvider).value?.opened;
    if (space == null) return const Scaffold(body: SizedBox.shrink());
    final items =
        ref.watch(_itemsProvider(space.id)).value ?? const <BusinessItem>[];
    final pending = space.status == 'pending_review';
    final isAgency = space.sector == 'real_estate';
    return _Page(
      title: space.name,
      children: [
        _Box(
          color: pending ? IviaColors.warningSoft : IviaColors.successSoft,
          child: Text(
            pending
                ? 'Brouillon : invisible des clients jusqu\'à la validation.'
                : 'Espace actif.',
            style: t.bodyLarge,
          ),
        ),
        Text(isAgency ? 'Mes biens' : 'Mes services', style: t.titleMedium),
        const SizedBox(height: 8),
        for (final i in items)
          _Box(
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    i.priceXof > 0
                        ? '${i.title} · ${formatXof(i.priceXof)}'
                        : i.title,
                  ),
                ),
                IconButton(
                  tooltip: 'Retirer',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    await ref.read(apiClientProvider).deleteBusinessItem(i.id);
                    ref.invalidate(_itemsProvider(space.id));
                  },
                ),
              ],
            ),
          ),
        TextField(
          controller: _title,
          decoration: InputDecoration(
            hintText: isAgency
                ? 'Villa 4 chambres à Kégué'
                : 'Dépannage plomberie',
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _price,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            hintText: 'Prix en FCFA (facultatif)',
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () => _add(space.id),
          child: const Text('Ajouter'),
        ),
        const SizedBox(height: IviaSpacing.xl),
        _Box(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => PayoutScreen(space: space)),
          ),
          child: Text(
            space.payout == null
                ? 'Compte de versement'
                : 'Compte de versement · ${space.payout!.phoneMasked}',
          ),
        ),
        _Box(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const ConnectedDevicesScreen(),
            ),
          ),
          child: const Text('Appareils connectés'),
        ),
        TextButton(
          onPressed: ref.read(businessGateProvider.notifier).close,
          child: const Text('Mes espaces'),
        ),
        TextButton(
          onPressed: ref.read(authControllerProvider.notifier).signOut,
          child: const Text('Se déconnecter'),
        ),
      ],
    );
  }
}
