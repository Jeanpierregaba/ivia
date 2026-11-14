import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../common/providers.dart';
import '../../common/ui.dart';
import 'documents.dart';

final _neighborhoodsProvider = FutureProvider.autoDispose(
  (ref) => ref.read(apiClientProvider).neighborhoods(),
);

/// Étapes 1 et 2 du dossier (F06) : fiche et photo de la devanture, puis
/// l'emplacement sur la carte. « Continuer » enregistre la pharmacie en
/// brouillon, puis envoie la photo.
class DetailsStep extends ConsumerStatefulWidget {
  const DetailsStep({
    super.key,
    required this.profile,
    required this.storefront,
    required this.onStorefront,
    required this.onSaved,
    required this.header,
  });

  final PharmacyProfile? profile;

  /// Photo de la devanture choisie, pas encore envoyée.
  final Uint8List? storefront;
  final ValueChanged<Uint8List?> onStorefront;
  final VoidCallback onSaved;
  final Widget header;

  @override
  ConsumerState<DetailsStep> createState() => _DetailsStepState();
}

class _DetailsStepState extends ConsumerState<DetailsStep> {
  late final PharmacyProfile? _p = widget.profile;
  late final _name = TextEditingController(text: _p?.name);
  late final _license = TextEditingController(text: _p?.licenseNumber);
  late final _phone = TextEditingController(
    text: formatTogoPhone((_p?.phone ?? '').replaceFirst('+228', '')),
  );
  late final _email = TextEditingController(text: _p?.email);
  late final _address = TextEditingController(text: _p?.addressText);
  late final _hours = TextEditingController(
    text: _p?.openingHours ?? 'Lun-Sam 8 h - 21 h',
  );
  late String? _neighborhood = _p?.neighborhoodId;

  /// Emplacement choisi dans cette session, sinon celui du dossier.
  GeoPoint? _picked;
  var _errors = <String, String>{};
  var _busy = false;

  GeoPoint? get _center =>
      _picked ??
      (_p?.lat != null && _p?.lng != null
          ? GeoPoint(lat: _p!.lat!, lng: _p.lng!)
          : null);

  @override
  void dispose() {
    for (final c in [_name, _license, _phone, _email, _address, _hours]) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, String> _validate() => {
    if (_name.text.trim().length < 2)
      'name': 'Saisissez le nom de la pharmacie.',
    if (_license.text.trim().isEmpty)
      'license_number': "Saisissez le numéro d'autorisation d'exercice.",
    if (togoPhoneDigits(_phone.text).length != 8)
      'phone': 'Numéro togolais attendu : 8 chiffres.',
    if (!_email.text.contains('@'))
      'email':
          "Saisissez l'e-mail de la pharmacie : la validation y est envoyée.",
    if (_address.text.trim().isEmpty)
      'address_text': "Saisissez l'adresse de la pharmacie.",
  };

  /// Étape 2 : la carte. `null` si l'utilisateur revient sans confirmer.
  Future<GeoPoint?> _pickPlace() async {
    final picked = await Navigator.of(context).push<PickedPlace>(
      MaterialPageRoute(
        builder: (_) => PlacePickerScreen(
          initial: _center,
          title: 'Placez votre pharmacie',
          hint:
              'Étape 2 sur 5 · Mettez le repère sur votre porte : les clients '
              'vous trouvent à cet endroit.',
          confirmLabel: 'Confirmer cet emplacement',
        ),
      ),
    );
    if (picked == null || !mounted) return null;
    setState(() => _picked = picked.point);
    return picked.point;
  }

  Future<void> _continue() async {
    final errors = _validate();
    setState(() => _errors = errors);
    if (errors.isNotEmpty) return;
    final center = _picked ?? await _pickPlace();
    if (center == null || !mounted) return;
    setState(() => _busy = true);
    final api = ref.read(apiClientProvider);
    try {
      await api.pharmacyApply(
        name: _name.text.trim(),
        licenseNumber: _license.text.trim(),
        phone: '+228${togoPhoneDigits(_phone.text)}',
        email: _email.text.trim(),
        addressText: _address.text.trim(),
        neighborhoodId: _neighborhood,
        location: center,
        openingHours: _hours.text.trim(),
      );
    } on ApiException catch (e) {
      // Une erreur de champ ramène à la fiche, champ en erreur.
      if (mounted) {
        setState(() {
          _busy = false;
          _errors = e.fields.isEmpty ? {'name': e.message} : e.fields;
        });
      }
      return;
    }
    // La pharmacie existe : la photo de la devanture peut partir.
    if (widget.storefront case final photo?) {
      try {
        await sendPharmacyDocument(api, 'storefront_photo', photo);
        widget.onStorefront(null);
      } on ApiException {
        if (mounted) {
          say(
            context,
            "La photo de la devanture n'est pas partie : ajoutez-la à "
            "l'étape suivante.",
          );
        }
      }
    }
    ref.invalidate(pharmacyProfileProvider);
    if (!mounted) return;
    setState(() => _busy = false);
    widget.onSaved();
  }

  Widget _field(
    String key,
    String label,
    TextEditingController c, {
    String? hint,
    TextInputType? keyboard,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: IviaFieldLabel(
      label: label,
      child: TextField(
        controller: c,
        enabled: !_busy,
        keyboardType: keyboard,
        textInputAction: TextInputAction.next,
        decoration: InputDecoration(
          hintText: hint,
          errorText: _errors[key],
          errorMaxLines: 3,
        ),
      ),
    ),
  );

  Widget _storefront() {
    final photo = widget.storefront;
    final sent = _p?.documents.contains('storefront_photo') ?? false;
    return Semantics(
      label: 'Photo de la devanture',
      child: SizedBox(
        height: 110,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (photo != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(P.radius),
                child: Image.memory(
                  photo,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) =>
                      const IviaImagePlaceholder(radius: P.radius),
                ),
              )
            else
              const IviaImagePlaceholder(radius: P.radius),
            if (photo == null)
              Center(
                child: Text(
                  sent
                      ? 'Photo de la devanture envoyée'
                      : 'Photo de la devanture',
                  style: PText.small,
                ),
              ),
            Positioned(
              right: 10,
              bottom: 10,
              child: Material(
                color: Colors.white,
                shape: const StadiumBorder(),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: _busy
                      ? null
                      : () async {
                          final bytes = await choosePhoto(context, ref);
                          if (bytes != null) widget.onStorefront(bytes);
                        },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.photo_camera,
                          size: 16,
                          color: P.green,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          photo != null || sent ? 'Changer' : 'Ajouter',
                          style: PText.pill.copyWith(
                            fontSize: 15,
                            color: P.green,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mapPreview() {
    final center = _center;
    return IviaFieldLabel(
      label: 'Position sur la carte',
      child: Semantics(
        button: true,
        label: center == null
            ? "Placer la pharmacie sur la carte"
            : "Modifier l'emplacement sur la carte",
        excludeSemantics: true,
        child: GestureDetector(
          onTap: _busy ? null : _pickPlace,
          child: SizedBox(
            height: 88,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(P.radius),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (center != null)
                    IgnorePointer(
                      child: IviaMap(
                        center: center,
                        zoom: 16,
                        interactive: false,
                      ),
                    )
                  else
                    const IviaImagePlaceholder(radius: P.radius),
                  Center(
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: P.green,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                      ),
                      child: const Icon(
                        Icons.local_pharmacy,
                        size: 16,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    final hoods = ref.watch(_neighborhoodsProvider).value ?? const <Choice>[];
    return Column(
      children: [
        widget.header,
        Expanded(
          child: PFormTheme(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(P.gutter, 4, P.gutter, 8),
              children: [
                if (p != null && p.reviewNote.isNotEmpty) ...[
                  PCard(
                    color: P.softYellow,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.reviewStatus == 'rejected'
                              ? 'Dossier refusé'
                              : 'Compléments demandés',
                          style: PText.cardTitle.copyWith(color: P.yellow),
                        ),
                        const SizedBox(height: 4),
                        Text(p.reviewNote, style: PText.body),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                _storefront(),
                const SizedBox(height: 18),
                _field(
                  'name',
                  'Nom de la pharmacie',
                  _name,
                  hint: 'Pharmacie du Boulevard',
                ),
                _field(
                  'license_number',
                  "N° d'autorisation d'exercice",
                  _license,
                  hint: 'AE-2019-0412',
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: TogoPhoneField(
                    label: 'Téléphone de la pharmacie',
                    controller: _phone,
                    enabled: !_busy,
                    errorText: _errors['phone'],
                  ),
                ),
                _field(
                  'email',
                  'E-mail de la pharmacie',
                  _email,
                  hint: 'contact@pharmacie.tg',
                  keyboard: TextInputType.emailAddress,
                ),
                _field(
                  'address_text',
                  'Adresse',
                  _address,
                  hint: 'Bd du 13 Janvier, Tokoin',
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: IviaFieldLabel(
                    label: 'Quartier',
                    child: DropdownButtonFormField<String>(
                      initialValue: hoods.any((h) => h.id == _neighborhood)
                          ? _neighborhood
                          : null,
                      decoration: InputDecoration(
                        errorText: _errors['neighborhood_id'],
                      ),
                      items: [
                        for (final h in hoods)
                          DropdownMenuItem(value: h.id, child: Text(h.name)),
                      ],
                      onChanged: _busy
                          ? null
                          : (v) => setState(() => _neighborhood = v),
                    ),
                  ),
                ),
                _field('opening_hours', 'Horaires', _hours),
                _mapPreview(),
              ],
            ),
          ),
        ),
        PBottomBar(
          children: [
            PButton(label: 'Continuer', busy: _busy, onTap: _continue),
          ],
        ),
      ],
    );
  }
}
