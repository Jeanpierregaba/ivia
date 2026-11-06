import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../main.dart';
import 'ui.dart';

/// Inscription de la pharmacie : informations, pièces exigées, validation par ivia.
class ApplicationScreen extends ConsumerStatefulWidget {
  const ApplicationScreen({super.key});

  @override
  ConsumerState<ApplicationScreen> createState() => _ApplicationScreenState();
}

class _ApplicationScreenState extends ConsumerState<ApplicationScreen> {
  final _name = TextEditingController();
  final _license = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _hours = TextEditingController(text: 'Lun-Sam 8 h - 21 h');
  var _errors = <String, String>{};
  String? _uploading;
  var _busy = false;

  @override
  void dispose() {
    for (final c in [_name, _license, _phone, _address, _hours]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    // Occupé dès l'appui : un second appui n'envoie pas deux dossiers.
    setState(() {
      _busy = true;
      _errors = {};
    });
    try {
      // Position de l'officine : écran d'autorisation d'abord s'il le faut.
      await askForLocation(context, ref);
      if (!mounted) return;
      final p =
          (await ref.read(locationServiceProvider).current()).point ??
          const GeoPoint(lat: 6.1480, lng: 1.2150);
      await ref
          .read(apiClientProvider)
          .pharmacyApply(
            name: _name.text.trim(),
            licenseNumber: _license.text.trim(),
            phone: '+228${togoPhoneDigits(_phone.text)}',
            addressText: _address.text.trim(),
            location: p,
            openingHours: _hours.text.trim(),
          );
      ref.invalidate(pharmacyProfileProvider);
    } on ApiException catch (e) {
      setState(
        () => _errors = e.fields.isEmpty ? {'name': e.message} : e.fields,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

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
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _uploading = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final profile = ref.watch(pharmacyProfileProvider).value;
    Widget field(
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
    return Scaffold(
      backgroundColor: P.page,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async => ref.invalidate(pharmacyProfileProvider),
          child: ListView(
            padding: const EdgeInsets.all(IviaSpacing.screen),
            children: [
              Row(
                children: [
                  IviaLogoTile(size: 56, color: P.green),
                  const Spacer(),
                  TextButton(
                    onPressed: () =>
                        ref.read(authControllerProvider.notifier).signOut(),
                    child: const Text('Se déconnecter'),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (profile == null) ...[
                const PTitle('Inscrivez votre ', 'pharmacie'),
                const SizedBox(height: 8),
                Text(
                  'Les patients autour de vous vous envoient leurs alertes médicament. Vous répondez avec vos prix, '
                  'ils viennent ou se font livrer. Aucune commission sur vos ventes.',
                  style: t.bodyLarge?.copyWith(color: P.muted),
                ),
                const SizedBox(height: 20),
                field(
                  'name',
                  'Nom de la pharmacie',
                  _name,
                  hint: 'Pharmacie du Boulevard',
                ),
                field(
                  'license_number',
                  'Numéro d\'autorisation',
                  _license,
                  hint: 'N° d\'agrément',
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: TogoPhoneField(
                    label: 'Téléphone de la pharmacie',
                    controller: _phone,
                    errorText: _errors['phone'],
                  ),
                ),
                field(
                  'address_text',
                  'Adresse',
                  _address,
                  hint: 'Rue, quartier, repère',
                ),
                field('opening_hours', 'Horaires', _hours),
                Text(
                  'La position du téléphone sert à situer la pharmacie : remplissez ce formulaire sur place.',
                  style: t.bodySmall?.copyWith(color: P.muted),
                ),
                const SizedBox(height: 20),
                PButton(
                  label: 'Envoyer la demande',
                  icon: Icons.send,
                  busy: _busy,
                  onTap: _submit,
                ),
              ] else ...[
                PTitle(
                  profile.reviewStatus == 'rejected'
                      ? 'Dossier '
                      : 'Dossier en ',
                  profile.reviewStatus == 'rejected'
                      ? 'à corriger'
                      : 'vérification',
                ),
                const SizedBox(height: 8),
                Text(
                  profile.reviewStatus == 'rejected'
                      ? (profile.reviewNote.isEmpty
                            ? 'L\'équipe ivia a refusé le dossier.'
                            : profile.reviewNote)
                      : 'L\'équipe ivia vérifie vos pièces. Vous recevrez les alertes dès la validation.',
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
                              profile.name,
                              style: t.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              profile.addressText,
                              style: t.bodyMedium?.copyWith(color: P.muted),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Pièces exigées',
                  style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                for (final e in pharmacyDocumentLabels.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: PCard(
                      child: Row(
                        children: [
                          PIcon(
                            profile.documents.contains(e.key)
                                ? Icons.check
                                : Icons.description_outlined,
                            bg: profile.documents.contains(e.key)
                                ? P.softGreen
                                : P.softYellow,
                            fg: profile.documents.contains(e.key)
                                ? P.green
                                : P.yellow,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              e.value,
                              style: t.titleSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          if (_uploading == e.key)
                            const SizedBox.square(
                              dimension: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          else
                            TextButton(
                              onPressed: () => _upload(e.key),
                              child: Text(
                                profile.documents.contains(e.key)
                                    ? 'Remplacer'
                                    : 'Ajouter',
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => ref.invalidate(pharmacyProfileProvider),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Actualiser le statut'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
