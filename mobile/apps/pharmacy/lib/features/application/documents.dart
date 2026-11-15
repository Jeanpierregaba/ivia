import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';

import '../../common/ui.dart';

/// Pièces du dossier, dans l'ordre de l'étape 3 (F07). La devanture est
/// choisie à l'étape 1 et ne revient ici que si son envoi a échoué.
const dossierDocuments = [
  (
    kind: 'opening_authorization',
    label: "Autorisation d'exercice",
    hint: 'Photo lisible',
    required: true,
  ),
  (
    kind: 'owner_id',
    label: "Pièce d'identité du titulaire",
    hint: 'Recto et verso',
    required: true,
  ),
  (
    kind: 'order_registration',
    label: "Inscription à l'Ordre",
    hint: 'Facultatif',
    required: false,
  ),
];

/// Demande « Prendre une photo » ou « Choisir une photo » ; `null` si
/// abandonné. Une photo trop lourde est refusée avec un message.
Future<Uint8List?> choosePhoto(BuildContext context, WidgetRef ref) async {
  final source = await showModalBottomSheet<PhotoSource>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Prendre une photo'),
            onTap: () => Navigator.pop(context, PhotoSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choisir une photo'),
            onTap: () => Navigator.pop(context, PhotoSource.gallery),
          ),
        ],
      ),
    ),
  );
  if (source == null || !context.mounted) return null;
  final Uint8List? bytes;
  try {
    // 2048 px : une pièce doit rester lisible par l'équipe ivia.
    bytes = await ref
        .read(photoPickerProvider)
        .pick(source: source, maxSide: 2048);
  } on Exception {
    if (context.mounted) {
      say(
        context,
        'Photo impossible à utiliser. Vérifiez les autorisations de '
        "l'appareil photo et des photos.",
      );
    }
    return null;
  }
  if (bytes != null && bytes.length > maxUploadBytes && context.mounted) {
    say(context, 'Photo trop lourde (5 Mo au plus). Reprenez-la.');
    return null;
  }
  return bytes;
}

/// Envoie une pièce : URL signée, envoi, puis rattachement au dossier.
Future<void> sendPharmacyDocument(
  IviaApiClient api,
  String kind,
  Uint8List bytes,
) async {
  final prepared = await api.prepareUpload(
    purpose: 'pharmacy_document',
    contentType: 'image/jpeg',
    sizeBytes: bytes.length,
  );
  await api.upload(prepared, bytes);
  await api.pharmacyAddDocument(kind, prepared.objectKey);
}
