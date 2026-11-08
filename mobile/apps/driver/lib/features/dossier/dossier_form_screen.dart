import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../app/driver_dossier.dart';
import '../../common/ui.dart';
import 'dossier_labels.dart';

/// « Devenez livreur ivia » (maquette D06, spec 033), sur le dossier
/// partenaire du serveur : profil (s'il est incomplet), véhicule, plaque (sauf
/// vélo), marque et modèle, zone de travail, pièces exigées pour le véhicule,
/// compte de versement. En correction ([correction]), le formulaire est
/// prérempli et les pièces déjà reçues restent valables.
class DossierFormScreen extends ConsumerStatefulWidget {
  const DossierFormScreen({super.key, this.correction = false});

  final bool correction;

  @override
  ConsumerState<DossierFormScreen> createState() => _DossierFormScreenState();
}

/// Étape de l'envoi, pour placer les erreurs du serveur sous le bon champ.
enum _Step { profile, activity, documents, payout, submit }

class _DossierFormScreenState extends ConsumerState<DossierFormScreen> {
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _phone = TextEditingController();
  final _plate = TextEditingController();
  final _brand = TextEditingController();
  final _model = TextEditingController();
  final _payoutPhone = TextEditingController();
  final _holder = TextEditingController();
  var _vehicle = VehicleType.motorbike;
  String? _zoneId;
  var _operator = PayoutOperator.flooz;
  var _consent = false;
  final _photos = <DriverDocumentKind, Uint8List>{};

  /// Choix du serveur (véhicules, pièces, zones) ; `null` : en chargement.
  DriverOptions? _options;
  var _optionsFailed = false;

  /// Fichiers déjà envoyés au stockage (clé), et pièces déjà transmises :
  /// un nouvel essai ne les renvoie pas.
  final _uploadedKeys = <DriverDocumentKind, String>{};
  final _transmitted = <DriverDocumentKind>{};

  /// Profil et compte déjà enregistrés : un nouvel essai ne les renvoie pas.
  var _profileSaved = false;
  var _payoutSaved = false;

  /// Compte déjà enregistré : affiché masqué ; « Modifier » rouvre la saisie.
  late final DriverPayout? _payout = _dossier?.payout;
  var _editPayout = false;

  var _errors = <String, String>{};
  String? _generalError;
  var _busy = false;

  late final User? _user = switch (ref.read(authControllerProvider)) {
    AuthSignedIn(:final user) || AuthNeedsProfile(:final user) => user,
    _ => null,
  };

  late final DriverDossier? _dossier = ref.read(driverDossierProvider).value;

  /// Le serveur exige prénom, téléphone et consentement pour s'inscrire.
  late final bool _needsProfile = !(_user?.profileComplete ?? false);
  late final bool _needsConsent = _user?.privacyConsentAt == null;

  /// Pièces déjà dans le dossier (correction, envoi interrompu).
  late final Set<DriverDocumentKind> _alreadySent = {...?_dossier?.documents};

  @override
  void initState() {
    super.initState();
    _firstName.text = _user?.firstName ?? '';
    _lastName.text = _user?.lastName ?? '';
    _phone.text = formatTogoPhone(_user?.phone ?? '');
    _holder.text = [
      _user?.firstName ?? '',
      _user?.lastName ?? '',
    ].where((s) => s.isNotEmpty).join(' ');
    if (_user?.phone case final phone?) {
      _payoutPhone.text = formatTogoPhone(phone);
    }
    if (_dossier?.delivery case final d?) {
      _vehicle = d.vehicleType;
      _plate.text = d.plate;
      _brand.text = d.brand;
      _model.text = d.model;
      _zoneId = d.workZoneId;
    } else if (_dossier case final d?) {
      // Ancien dossier, sans activité : véhicule et plaque.
      _vehicle = d.vehicleType;
      _plate.text = d.vehiclePlate;
    }
    for (final c in [_plate, _payoutPhone, _holder]) {
      c.addListener(_rebuild);
    }
    _loadOptions();
  }

  @override
  void dispose() {
    for (final c in [
      _firstName,
      _lastName,
      _phone,
      _plate,
      _brand,
      _model,
      _payoutPhone,
      _holder,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _rebuild() => setState(() {});

  Future<void> _loadOptions() async {
    setState(() => _optionsFailed = false);
    try {
      final options = await ref.read(apiClientProvider).driverOptions();
      if (!mounted) return;
      setState(() {
        _options = options;
        // Véhicule hors des choix du serveur : le premier proposé.
        if (!options.vehicles.containsKey(_vehicle) &&
            options.vehicles.isNotEmpty) {
          _vehicle = options.vehicles.keys.first;
        }
        if (_zoneId != null && !options.zones.any((z) => z.id == _zoneId)) {
          _zoneId = null;
        }
      });
    } on Exception {
      if (mounted) setState(() => _optionsFailed = true);
    }
  }

  List<DriverDocumentKind> get _required =>
      _options?.vehicles[_vehicle] ?? const [];

  bool get _needsPlate => _vehicle != VehicleType.bicycle;

  bool _hasDocument(DriverDocumentKind kind) =>
      _photos.containsKey(kind) || _alreadySent.contains(kind);

  bool get _payoutFilled =>
      isTogoMobile(togoPhoneDigits(_payoutPhone.text)) &&
      _holder.text.trim().length >= 3;

  bool get _askPayout => _payout == null || _editPayout;

  /// Bouton actif quand le dossier est complet ; le reste est vérifié à
  /// l'envoi.
  bool get _ready =>
      _options != null &&
      (!_needsPlate || _plate.text.trim().isNotEmpty) &&
      _zoneId != null &&
      _required.every(_hasDocument) &&
      (!_askPayout || _payoutFilled);

  Map<String, String> _validate() {
    final errors = <String, String>{};
    if (_needsProfile) {
      final first = _firstName.text.trim();
      final last = _lastName.text.trim();
      if (first.isEmpty || first.length > 100) {
        errors['first_name'] =
            'Saisissez votre prénom (100 caractères au plus).';
      }
      if (last.isEmpty || last.length > 100) {
        errors['last_name'] = 'Saisissez votre nom (100 caractères au plus).';
      }
      if (!isTogoMobile(togoPhoneDigits(_phone.text))) {
        errors['phone'] = 'Numéro mobile togolais attendu (8 chiffres commençant par 7 ou 9).';
      }
      if (_needsConsent && !_consent) {
        errors['accept_privacy_policy'] =
            'Cochez la case pour continuer : votre accord est nécessaire.';
      }
    }
    final plate = _plate.text.trim();
    if (_needsPlate && (plate.length < 2 || plate.length > 20)) {
      errors['plate'] = 'Immatriculation de 2 à 20 caractères.';
    }
    return errors;
  }

  Future<void> _submit() async {
    if (_busy) return;
    final errors = _validate();
    setState(() {
      _errors = errors;
      _generalError = null;
    });
    if (errors.isNotEmpty) return;
    setState(() => _busy = true);
    final client = ref.read(apiClientProvider);
    DriverDocumentKind? transmitting;
    var step = _Step.profile;
    try {
      if (_needsProfile && !_profileSaved) {
        final user = await client.updateMe(
          firstName: _firstName.text.trim(),
          lastName: _lastName.text.trim(),
          phone: '+228${togoPhoneDigits(_phone.text)}',
          acceptPrivacyPolicy: _needsConsent ? true : null,
        );
        await ref.read(authControllerProvider.notifier).profileUpdated(user);
        _profileSaved = true;
      }
      // 1. Fichiers vers le compartiment privé (une seule fois chacun).
      step = _Step.documents;
      for (final MapEntry(key: kind, value: photo) in _photos.entries) {
        if (_uploadedKeys.containsKey(kind) || !_required.contains(kind)) {
          continue;
        }
        final prepared = await client.prepareUpload(
          purpose: 'driver_document',
          contentType: 'image/jpeg',
          sizeBytes: photo.length,
        );
        await client.upload(prepared, photo);
        _uploadedKeys[kind] = prepared.objectKey;
      }
      // 2. Activité livraison (crée le dossier en brouillon).
      step = _Step.activity;
      var dossier = await client.saveDriverDelivery(
        vehicleType: _vehicle,
        plate: _plate.text.trim(),
        brand: _brand.text.trim(),
        model: _model.text.trim(),
        workZoneId: _zoneId!,
      );
      // 3. Pièces pas encore transmises.
      step = _Step.documents;
      for (final MapEntry(key: kind, value: key) in _uploadedKeys.entries) {
        if (_transmitted.contains(kind)) continue;
        transmitting = kind;
        dossier = await client.addDriverDocument(kind, key);
        _transmitted.add(kind);
      }
      transmitting = null;
      // 4. Compte de versement, s'il est saisi.
      step = _Step.payout;
      if (_askPayout && !_payoutSaved) {
        dossier = await client.setDriverPayout(
          operator: _operator,
          phone: '+228${togoPhoneDigits(_payoutPhone.text)}',
          holder: _holder.text.trim(),
        );
        _payoutSaved = true;
      }
      // 5. Envoi, sauf dossier déjà en vérification (correction de pièces).
      step = _Step.submit;
      if (dossier.delivery?.status != DriverReview.pending) {
        dossier = await client.submitDriverDelivery();
      }
      // Correction ouverte par-dessus un autre écran : on y revient d'abord,
      // puis le dossier mis à jour fait choisir l'écran par le routeur (dans
      // l'autre ordre, le rafraîchissement du routeur rouvrirait l'édition).
      final notifier = ref.read(driverDossierProvider.notifier);
      if (widget.correction && mounted && context.canPop()) context.pop();
      notifier.submitted(dossier);
    } on ApiException catch (e) {
      // Fichier refusé à la transmission (non reçu, expiré) : il sera renvoyé
      // au prochain essai, sinon la même clé serait refusée à chaque fois.
      final keyError = e.fields['object_key'];
      if (keyError != null && transmitting != null) {
        _uploadedKeys.remove(transmitting);
      }
      if (!mounted) return;
      setState(() {
        final fields = switch (step) {
          // Compte de versement : ses champs ont des noms à part.
          _Step.payout => {
            for (final MapEntry(:key, :value) in e.fields.entries)
              'payout_$key': value,
          },
          _ => e.fields,
        };
        if (keyError != null) {
          _generalError = keyError;
        } else if (e.code == 'phone_taken') {
          _errors = {'phone': e.message};
        } else if (fields.keys.any(_shownFields.contains)) {
          _errors = fields;
        } else {
          _generalError = e.message;
        }
      });
    } on Exception {
      // Stockage du téléphone, réponse inattendue : message général.
      if (mounted) {
        setState(
          () => _generalError =
              'Une erreur est survenue. Réessayez dans un instant.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static const _shownFields = {
    'first_name',
    'last_name',
    'phone',
    'accept_privacy_policy',
    'plate',
    'brand',
    'model',
    'work_zone_id',
    'payout_phone',
    'payout_holder',
    'payout_operator',
  };

  /// Retour : abandon (déconnexion) ; en correction, retour au motif.
  Future<void> _back() async {
    if (_busy) return;
    if (widget.correction && context.canPop()) {
      context.pop();
      return;
    }
    await ref.read(authControllerProvider.notifier).signOut();
  }

  void _clearError(String key) {
    if (_errors.containsKey(key)) {
      setState(() => _errors = {..._errors}..remove(key));
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _back();
    },
    child: Scaffold(
      backgroundColor: D.page,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(D.gutter, 8, D.gutter, 0),
              child: Row(
                children: [
                  DRound.back(onTap: _busy ? null : _back),
                  const Spacer(),
                  const _DossierPill(),
                ],
              ),
            ),
            Expanded(child: _body()),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(D.gutter, 8, D.gutter, 10),
          child: DButton(
            label: 'Envoyer mon dossier',
            busy: _busy,
            onTap: _busy || !_ready ? null : _submit,
          ),
        ),
      ),
    ),
  );

  Widget _body() {
    if (_optionsFailed) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(D.gutter),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Impossible de charger le dossier. Vérifiez votre connexion.',
                textAlign: TextAlign.center,
                style: DText.body,
              ),
              const SizedBox(height: 16),
              DButton(
                label: 'Réessayer',
                style: DButtonStyle.outline,
                onTap: _loadOptions,
              ),
            ],
          ),
        ),
      );
    }
    if (_options == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(D.gutter, 12, D.gutter, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              widget.correction
                  ? 'Corrigez votre dossier'
                  : 'Devenez livreur ivia',
              style: DText.heading,
            ),
          ),
          const SizedBox(height: 16),
          if (_needsProfile) ..._profileFields(),
          _Label('Véhicule'),
          _Segmented<VehicleType>(
            values: _options!.vehicles.keys.toList(),
            selected: _vehicle,
            label: vehicleLabel,
            enabled: !_busy,
            onSelect: (v) => setState(() => _vehicle = v),
          ),
          if (_needsPlate) ...[
            const SizedBox(height: 16),
            IviaFieldLabel(
              label: "Numéro d'immatriculation",
              child: TextField(
                controller: _plate,
                enabled: !_busy,
                textCapitalization: TextCapitalization.characters,
                onChanged: (_) => _clearError('plate'),
                decoration: InputDecoration(
                  hintText: 'TG 4521 AB',
                  errorText: _errors['plate'],
                  errorMaxLines: 2,
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: IviaFieldLabel(
                  label: 'Marque',
                  child: TextField(
                    controller: _brand,
                    enabled: !_busy,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      hintText: 'Facultatif',
                      errorText: _errors['brand'],
                      errorMaxLines: 2,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: IviaFieldLabel(
                  label: 'Modèle',
                  child: TextField(
                    controller: _model,
                    enabled: !_busy,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      hintText: 'Facultatif',
                      errorText: _errors['model'],
                      errorMaxLines: 2,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          IviaFieldLabel(
            label: 'Zone de travail',
            child: DropdownButtonFormField<String>(
              initialValue: _zoneId,
              isExpanded: true,
              // Même texte que les autres champs (le thème grossit le menu).
              style: DText.body.copyWith(color: D.ink, fontSize: 16),
              hint: Text(
                'Choisissez votre quartier',
                style: DText.bodyMuted.copyWith(fontSize: 16),
              ),
              items: [
                for (final z in _options!.zones)
                  DropdownMenuItem(value: z.id, child: Text(z.name)),
              ],
              onChanged: _busy
                  ? null
                  : (v) {
                      _clearError('work_zone_id');
                      setState(() => _zoneId = v);
                    },
              decoration: InputDecoration(
                errorText: _errors['work_zone_id'],
                errorMaxLines: 2,
              ),
            ),
          ),
          if (_options!.zones.isEmpty) ...[
            const SizedBox(height: 6),
            Text(
              "Aucune zone ouverte pour l'instant. Réessayez plus tard.",
              style: DText.small,
            ),
          ],
          const SizedBox(height: 16),
          _Label('Documents'),
          for (final kind in _required) ...[
            DocumentPhotoRow(
              label: documentLabel(kind),
              photo: _photos[kind],
              alreadySent: _alreadySent.contains(kind),
              sentLabel: 'Ajouté',
              enabled: !_busy,
              onPicked: (photo) => setState(() {
                _photos[kind] = photo;
                // Nouvelle photo : elle sera envoyée et transmise.
                _uploadedKeys.remove(kind);
                _transmitted.remove(kind);
              }),
            ),
            const SizedBox(height: 8),
          ],
          Text(
            "Vos documents sont visibles uniquement par l'équipe ivia.",
            style: DText.small,
          ),
          const SizedBox(height: 20),
          _Label('Compte de versement'),
          ..._payoutFields(),
          if (_generalError != null) ...[
            const SizedBox(height: 16),
            Semantics(
              liveRegion: true,
              child: Text(
                _generalError!,
                style: DText.body.copyWith(color: IviaColors.error),
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _payoutFields() {
    if (!_askPayout) {
      final p = _payout!;
      return [
        DCard(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(
            children: [
              const DIconTile(Icons.account_balance_wallet_outlined, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.operator.label, style: DText.cardTitle),
                    Text('${p.phoneMasked} · ${p.holder}', style: DText.small),
                  ],
                ),
              ),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() => _editPayout = true),
                child: const Text('Modifier'),
              ),
            ],
          ),
        ),
      ];
    }
    return [
      _Segmented<PayoutOperator>(
        values: PayoutOperator.values,
        selected: _operator,
        label: (o) => o == PayoutOperator.flooz ? 'Flooz' : 'T-Money',
        enabled: !_busy,
        onSelect: (o) => setState(() {
          _operator = o;
          _payoutSaved = false;
        }),
      ),
      const SizedBox(height: 16),
      TogoPhoneField(
        label: 'Numéro Mobile Money',
        controller: _payoutPhone,
        enabled: !_busy,
        errorText: _errors['payout_phone'],
      ),
      const SizedBox(height: 16),
      IviaFieldLabel(
        label: 'Titulaire du compte',
        child: TextField(
          controller: _holder,
          enabled: !_busy,
          textCapitalization: TextCapitalization.words,
          onChanged: (_) => _payoutSaved = false,
          decoration: InputDecoration(
            errorText: _errors['payout_holder'],
            errorMaxLines: 2,
          ),
        ),
      ),
      const SizedBox(height: 6),
      Text(
        'Vos gains y sont versés. Après la validation, seule l’équipe ivia '
        'peut le changer.',
        style: DText.small,
      ),
    ];
  }

  List<Widget> _profileFields() => [
    IviaFieldLabel(
      label: 'Prénom',
      child: TextField(
        controller: _firstName,
        // Profil déjà enregistré : figé, il ne serait pas renvoyé.
        enabled: !_busy && !_profileSaved,
        textCapitalization: TextCapitalization.words,
        autofillHints: const [AutofillHints.givenName],
        decoration: InputDecoration(
          errorText: _errors['first_name'],
          errorMaxLines: 2,
        ),
      ),
    ),
    const SizedBox(height: 16),
    IviaFieldLabel(
      label: 'Nom',
      child: TextField(
        controller: _lastName,
        enabled: !_busy && !_profileSaved,
        textCapitalization: TextCapitalization.words,
        autofillHints: const [AutofillHints.familyName],
        decoration: InputDecoration(
          errorText: _errors['last_name'],
          errorMaxLines: 2,
        ),
      ),
    ),
    const SizedBox(height: 16),
    TogoPhoneField(
      label: 'Téléphone',
      controller: _phone,
      enabled: !_busy && !_profileSaved,
      helperText:
          'Pour que ivia, les boutiques et les clients vous joignent '
          'pendant une mission.',
      errorText: _errors['phone'],
    ),
    if (_needsConsent) ...[
      const SizedBox(height: 16),
      ConsentCheckbox(
        value: _consent,
        error: _errors['accept_privacy_policy'],
        onChanged: _busy ? null : (v) => setState(() => _consent = v),
      ),
    ],
    const SizedBox(height: 20),
  ];
}

/// Pastille « Votre dossier » en haut à droite.
class _DossierPill extends StatelessWidget {
  const _DossierPill();

  @override
  Widget build(BuildContext context) => Flexible(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(IviaRadius.pill),
      ),
      child: Text(
        'Votre dossier',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: DText.label.copyWith(color: D.blue, fontWeight: FontWeight.w700),
      ),
    ),
  );
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: DText.label.copyWith(fontWeight: FontWeight.w700)),
  );
}

/// Choix exclusif en pastilles (véhicule, opérateur) : le choix actif sur
/// fond bleu nuit (maquette D06).
class _Segmented<T> extends StatelessWidget {
  const _Segmented({
    required this.values,
    required this.selected,
    required this.label,
    required this.onSelect,
    required this.enabled,
  });
  final List<T> values;
  final T selected;
  final String Function(T) label;
  final ValueChanged<T> onSelect;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      children: [
        for (final v in values)
          Expanded(
            child: Semantics(
              button: true,
              selected: v == selected,
              child: Material(
                color: v == selected ? D.navy : Colors.transparent,
                borderRadius: BorderRadius.circular(13),
                child: InkWell(
                  borderRadius: BorderRadius.circular(13),
                  onTap: enabled ? () => onSelect(v) : null,
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 46),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 8,
                    ),
                    child: Text(
                      label(v),
                      textAlign: TextAlign.center,
                      style: DText.button.copyWith(
                        color: v == selected ? Colors.white : D.label,
                        fontWeight: v == selected
                            ? FontWeight.w800
                            : FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}
