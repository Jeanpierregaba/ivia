import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../app/driver_dossier.dart';
import 'document_row.dart';

/// « Devenez livreur ivia » : profil (s'il est incomplet), véhicule,
/// immatriculation et documents. En correction ([correction]), le formulaire
/// est prérempli et les documents déjà reçus restent valables.
class DossierFormScreen extends ConsumerStatefulWidget {
  const DossierFormScreen({super.key, this.correction = false});

  final bool correction;

  @override
  ConsumerState<DossierFormScreen> createState() => _DossierFormScreenState();
}

class _DossierFormScreenState extends ConsumerState<DossierFormScreen> {
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _phone = TextEditingController();
  final _plate = TextEditingController();
  var _vehicle = VehicleType.motorbike;
  var _consent = false;
  final _photos = <DriverDocumentKind, Uint8List>{};

  /// Fichiers déjà envoyés au stockage (clé), et documents déjà transmis au
  /// dossier : un nouvel essai ne les renvoie pas.
  final _uploadedKeys = <DriverDocumentKind, String>{};
  final _transmitted = <DriverDocumentKind>{};

  /// Profil déjà enregistré : un nouvel essai ne le renvoie pas.
  var _profileSaved = false;

  var _errors = <String, String>{};
  String? _generalError;
  var _busy = false;

  late final User? _user = switch (ref.read(authControllerProvider)) {
    AuthSignedIn(:final user) || AuthNeedsProfile(:final user) => user,
    _ => null,
  };

  /// Le serveur exige prénom, téléphone et consentement pour postuler.
  late final bool _needsProfile = !(_user?.profileComplete ?? false);
  late final bool _needsConsent = _user?.privacyConsentAt == null;

  /// Documents déjà dans le dossier (correction).
  late final Set<DriverDocumentKind> _alreadySent = {
    ...?ref.read(driverDossierProvider).value?.documents,
  };

  @override
  void initState() {
    super.initState();
    _firstName.text = _user?.firstName ?? '';
    _lastName.text = _user?.lastName ?? '';
    _phone.text = formatTogoPhone(_user?.phone ?? '');
    if (widget.correction) {
      final dossier = ref.read(driverDossierProvider).value;
      if (dossier != null) {
        _vehicle = dossier.vehicleType;
        _plate.text = dossier.vehiclePlate;
      }
    }
    _plate.addListener(_rebuild);
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _phone.dispose();
    _plate.dispose();
    super.dispose();
  }

  void _rebuild() => setState(() {});

  bool _hasDocument(DriverDocumentKind kind) =>
      _photos.containsKey(kind) || _alreadySent.contains(kind);

  /// Bouton actif quand le dossier est complet ; le reste est vérifié à
  /// l'envoi.
  bool get _ready =>
      _plate.text.trim().isNotEmpty && requiredDocuments.every(_hasDocument);

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
    if (plate.length < 2 || plate.length > 20) {
      errors['vehicle_plate'] = 'Immatriculation de 2 à 20 caractères.';
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
      for (final MapEntry(key: kind, value: photo) in _photos.entries) {
        if (_uploadedKeys.containsKey(kind)) continue;
        final prepared = await client.prepareUpload(
          purpose: 'driver_document',
          contentType: 'image/jpeg',
          sizeBytes: photo.length,
        );
        await client.upload(prepared, photo);
        _uploadedKeys[kind] = prepared.objectKey;
      }
      // 2. Candidature, puis 3. documents pas encore transmis.
      var dossier = await client.applyAsDriver(
        vehicleType: _vehicle,
        vehiclePlate: _plate.text.trim(),
      );
      for (final MapEntry(key: kind, value: key) in _uploadedKeys.entries) {
        if (_transmitted.contains(kind)) continue;
        dossier = await client.addDriverDocument(kind, key);
        _transmitted.add(kind);
      }
      // Correction ouverte par-dessus un autre écran : on y revient d'abord,
      // puis le dossier mis à jour fait choisir l'écran par le routeur (dans
      // l'autre ordre, le rafraîchissement du routeur rouvrirait l'édition).
      final notifier = ref.read(driverDossierProvider.notifier);
      if (widget.correction && mounted && context.canPop()) context.pop();
      notifier.submitted(dossier);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        if (e.code == 'phone_taken') {
          _errors = {'phone': e.message};
        } else if (e.fields.keys.any(_shownFields.contains)) {
          _errors = e.fields;
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
    'vehicle_plate',
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

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(IviaSpacing.screen),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    IviaBackButton(onPressed: _busy ? null : _back),
                    const SizedBox(width: IviaSpacing.md),
                    const Spacer(),
                    const Flexible(
                      flex: 4,
                      child: IviaPill(label: 'Votre dossier'),
                    ),
                  ],
                ),
                const SizedBox(height: IviaSpacing.lg),
                Semantics(
                  header: true,
                  child: Text(
                    widget.correction
                        ? 'Corrigez votre dossier'
                        : 'Devenez livreur ivia',
                    style: textTheme.headlineMedium,
                  ),
                ),
                const SizedBox(height: IviaSpacing.xl),
                if (_needsProfile) ..._profileFields(),
                IviaFieldLabel(
                  label: 'Véhicule',
                  child: SegmentedButton<VehicleType>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(
                        value: VehicleType.motorbike,
                        label: Text('Moto'),
                      ),
                      ButtonSegment(
                        value: VehicleType.car,
                        label: Text('Voiture'),
                      ),
                    ],
                    selected: {_vehicle},
                    onSelectionChanged: _busy
                        ? null
                        : (v) => setState(() => _vehicle = v.single),
                    // Choix sélectionné en Berkeley (maquette du 2026-10-31).
                    style: SegmentedButton.styleFrom(
                      selectedBackgroundColor: IviaColors.berkeleyBlue,
                      selectedForegroundColor: Colors.white,
                      backgroundColor: IviaColors.surface,
                      minimumSize: const Size(0, 52),
                    ),
                  ),
                ),
                const SizedBox(height: IviaSpacing.lg),
                IviaFieldLabel(
                  label: "Numéro d'immatriculation",
                  child: TextField(
                    controller: _plate,
                    enabled: !_busy,
                    textCapitalization: TextCapitalization.characters,
                    onChanged: (_) {
                      if (_errors.containsKey('vehicle_plate')) {
                        setState(
                          () => _errors = {..._errors}..remove('vehicle_plate'),
                        );
                      }
                    },
                    decoration: InputDecoration(
                      hintText: 'TG 4521 AB',
                      errorText: _errors['vehicle_plate'],
                      errorMaxLines: 2,
                    ),
                  ),
                ),
                const SizedBox(height: IviaSpacing.lg),
                Text(
                  'Documents',
                  style: textTheme.labelMedium?.copyWith(
                    color: IviaColors.textSecondary,
                  ),
                ),
                const SizedBox(height: IviaSpacing.sm),
                for (final kind in requiredDocuments) ...[
                  DocumentRow(
                    kind: kind,
                    photo: _photos[kind],
                    alreadySent: _alreadySent.contains(kind),
                    enabled: !_busy,
                    onPicked: (photo) => setState(() {
                      _photos[kind] = photo;
                      // Nouvelle photo : elle sera envoyée et transmise.
                      _uploadedKeys.remove(kind);
                      _transmitted.remove(kind);
                    }),
                  ),
                  const SizedBox(height: IviaSpacing.sm),
                ],
                Text(
                  "Vos documents sont visibles uniquement par l'équipe ivia.",
                  style: textTheme.bodySmall,
                ),
                const SizedBox(height: IviaSpacing.xxl),
                if (_generalError != null) ...[
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _generalError!,
                      style: textTheme.bodyMedium?.copyWith(
                        color: IviaColors.error,
                      ),
                    ),
                  ),
                  const SizedBox(height: IviaSpacing.md),
                ],
                FilledButton(
                  onPressed: _busy || !_ready ? null : _submit,
                  child: _busy
                      ? const ButtonProgress()
                      : const Text('Envoyer mon dossier'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
    const SizedBox(height: IviaSpacing.lg),
    IviaFieldLabel(
      label: 'Nom',
      child: TextField(
        controller: _lastName,
        // Profil déjà enregistré : figé, il ne serait pas renvoyé.
        enabled: !_busy && !_profileSaved,
        textCapitalization: TextCapitalization.words,
        autofillHints: const [AutofillHints.familyName],
        decoration: InputDecoration(
          errorText: _errors['last_name'],
          errorMaxLines: 2,
        ),
      ),
    ),
    const SizedBox(height: IviaSpacing.lg),
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
      const SizedBox(height: IviaSpacing.lg),
      ConsentCheckbox(
        value: _consent,
        error: _errors['accept_privacy_policy'],
        onChanged: _busy ? null : (v) => setState(() => _consent = v),
      ),
    ],
    const SizedBox(height: IviaSpacing.xl),
  ];
}
