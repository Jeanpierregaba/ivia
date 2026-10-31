import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

/// Taille maximale d'un fichier accepté par le serveur (POST /v1/uploads).
const maxUploadBytes = 5 * 1024 * 1024;

/// Documents demandés au livreur, dans l'ordre d'affichage.
const requiredDocuments = [
  DriverDocumentKind.idCard,
  DriverDocumentKind.drivingLicense,
  DriverDocumentKind.vehicleRegistration,
];

String documentLabel(DriverDocumentKind kind) => switch (kind) {
  DriverDocumentKind.idCard => "Pièce d'identité",
  DriverDocumentKind.drivingLicense => 'Permis de conduire',
  DriverDocumentKind.vehicleRegistration => 'Carte grise',
  DriverDocumentKind.photo => 'Photo',
  DriverDocumentKind.other => 'Autre document',
};

/// Une ligne de document : « Ajouter », puis « Ajouté » (photo choisie) ou
/// « Envoyé » (déjà dans le dossier, lors d'une correction). Un appui
/// propose de prendre ou de choisir une photo.
class DocumentRow extends ConsumerStatefulWidget {
  const DocumentRow({
    super.key,
    required this.kind,
    required this.photo,
    required this.alreadySent,
    required this.onPicked,
    this.enabled = true,
  });

  final DriverDocumentKind kind;

  /// Photo choisie, prête à l'envoi ; `null` : aucune.
  final Uint8List? photo;

  /// Déjà reçu par le serveur (correction d'un dossier refusé).
  final bool alreadySent;
  final ValueChanged<Uint8List> onPicked;
  final bool enabled;

  @override
  ConsumerState<DocumentRow> createState() => _DocumentRowState();
}

class _DocumentRowState extends ConsumerState<DocumentRow> {
  String? _error;

  Future<void> _pick() async {
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
    if (source == null || !mounted) return;
    try {
      // 2048 px : un document doit rester lisible par l'équipe ivia.
      final bytes = await ref
          .read(photoPickerProvider)
          .pick(source: source, maxSide: 2048);
      if (bytes == null || !mounted) return;
      if (bytes.length > maxUploadBytes) {
        setState(() => _error = 'Photo trop lourde (5 Mo au plus).');
        return;
      }
      setState(() => _error = null);
      widget.onPicked(bytes);
    } on Exception {
      if (mounted) {
        setState(
          () => _error =
              'Photo impossible à utiliser. Vérifiez les autorisations '
              "de l'appareil photo et des photos.",
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final brand = IviaAppBrand.of(context);
    final picked = widget.photo != null;
    final done = picked || widget.alreadySent;
    final status = picked
        ? 'Ajouté'
        : widget.alreadySent
        ? 'Envoyé'
        : 'Ajouter';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          label: '${documentLabel(widget.kind)}, $status',
          excludeSemantics: true,
          child: Material(
            color: IviaColors.surface,
            borderRadius: BorderRadius.circular(IviaRadius.large),
            child: InkWell(
              onTap: widget.enabled ? _pick : null,
              borderRadius: BorderRadius.circular(IviaRadius.large),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: IviaSpacing.lg,
                  vertical: IviaSpacing.md,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: done ? brand.action : null,
                        borderRadius: BorderRadius.circular(IviaRadius.tile),
                        border: done
                            ? null
                            : Border.all(color: IviaColors.borderInput),
                      ),
                      child: Icon(
                        done ? Icons.check : Icons.add,
                        size: 18,
                        color: done ? Colors.white : IviaColors.textSecondary,
                      ),
                    ),
                    const SizedBox(width: IviaSpacing.lg),
                    Expanded(
                      child: Text(
                        documentLabel(widget.kind),
                        style: textTheme.titleSmall,
                      ),
                    ),
                    const SizedBox(width: IviaSpacing.sm),
                    Text(
                      status,
                      style: textTheme.titleSmall?.copyWith(
                        color: done ? IviaColors.textMuted : brand.link,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: IviaSpacing.xs),
            child: Semantics(
              liveRegion: true,
              child: Text(
                _error!,
                style: textTheme.bodySmall?.copyWith(color: IviaColors.error),
              ),
            ),
          ),
      ],
    );
  }
}
