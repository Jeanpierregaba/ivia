import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_ui/ivia_ui.dart';

import 'photo_picker.dart';

/// Taille maximale d'un fichier accepté par le serveur (`POST /v1/uploads`).
const maxUploadBytes = 5 * 1024 * 1024;

/// Une ligne de document à photographier (dossier livreur, pièces du
/// marchand) : « Ajouter », puis [pickedLabel] (photo choisie, à envoyer) ou
/// [sentLabel] (déjà reçu par le serveur). Un appui propose de prendre ou de
/// choisir une photo ; une photo trop lourde est refusée dès le choix.
class DocumentPhotoRow extends ConsumerStatefulWidget {
  const DocumentPhotoRow({
    super.key,
    required this.label,
    required this.photo,
    required this.alreadySent,
    required this.onPicked,
    this.tag,
    this.hint,
    this.pickedLabel = 'Ajouté',
    this.sentLabel = 'Envoyé',
    this.enabled = true,
  });

  final String label;

  /// Mention sous le libellé (« Obligatoire », « Facultatif »).
  final String? tag;

  /// Précision sur le document attendu.
  final String? hint;

  /// Photo choisie, prête à l'envoi ; `null` : aucune.
  final Uint8List? photo;

  /// Déjà reçu par le serveur.
  final bool alreadySent;
  final ValueChanged<Uint8List> onPicked;
  final String pickedLabel;
  final String sentLabel;
  final bool enabled;

  @override
  ConsumerState<DocumentPhotoRow> createState() => _DocumentPhotoRowState();
}

class _DocumentPhotoRowState extends ConsumerState<DocumentPhotoRow> {
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
        ? widget.pickedLabel
        : widget.alreadySent
        ? widget.sentLabel
        : 'Ajouter';
    final statusText = Text(
      status,
      style: textTheme.titleSmall?.copyWith(
        color: done ? IviaColors.textMuted : brand.link,
      ),
    );
    // Grand texte : l'état passe sous le libellé, qui garde toute la largeur.
    final stacked = MediaQuery.textScalerOf(context).scale(10) > 15;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          label: [widget.label, ?widget.tag, ?widget.hint, status].join(', '),
          enabled: widget.enabled,
          onTap: widget.enabled ? _pick : null,
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.label, style: textTheme.titleSmall),
                          if (widget.tag case final tag?)
                            Text(
                              tag,
                              style: textTheme.labelMedium?.copyWith(
                                color: IviaColors.textSecondary,
                              ),
                            ),
                          if (widget.hint case final hint?)
                            Padding(
                              padding: const EdgeInsets.only(
                                top: IviaSpacing.xs,
                              ),
                              child: Text(hint, style: textTheme.bodySmall),
                            ),
                          if (stacked) ...[
                            const SizedBox(height: IviaSpacing.xs),
                            statusText,
                          ],
                        ],
                      ),
                    ),
                    if (!stacked) ...[
                      const SizedBox(width: IviaSpacing.sm),
                      statusText,
                    ],
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
