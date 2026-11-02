import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../app/seller_shop.dart';

/// Pièces demandées au marchand, dans l'ordre d'affichage, avec leur
/// précision. Seule la pièce d'identité est exigée par le serveur.
const merchantDocuments = [
  (MerchantDocumentKind.idCard, "Pièce d'identité", 'Obligatoire'),
  (
    MerchantDocumentKind.businessRegistration,
    'Registre du commerce (RCCM)',
    'Facultatif',
  ),
];

/// « Vos pièces » : chaque photo choisie est envoyée aussitôt (URL signée,
/// compartiment privé), puis rattachée au marchand. L'équipe ivia ne publie
/// la boutique qu'après avoir vérifié la pièce d'identité.
class MerchantDocumentsSection extends ConsumerStatefulWidget {
  const MerchantDocumentsSection({super.key, required this.shop});

  final Shop shop;

  @override
  ConsumerState<MerchantDocumentsSection> createState() =>
      _MerchantDocumentsSectionState();
}

class _MerchantDocumentsSectionState
    extends ConsumerState<MerchantDocumentsSection> {
  MerchantDocumentKind? _sending;

  Future<void> _send(MerchantDocumentKind kind, Uint8List photo) async {
    final client = ref.read(apiClientProvider);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _sending = kind);
    try {
      final prepared = await client.prepareUpload(
        purpose: 'merchant_document',
        contentType: 'image/jpeg',
        sizeBytes: photo.length,
      );
      await client.upload(prepared, photo);
      final documents = await client.addMerchantDocument(
        kind,
        prepared.objectKey,
      );
      ref.read(sellerShopProvider.notifier).documentsReceived(documents);
    } on ApiException catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              e.isNetwork
                  ? 'Pas de connexion : pièce non envoyée. Réessayez.'
                  : e.message,
            ),
          ),
        );
    } finally {
      if (mounted) setState(() => _sending = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final received = widget.shop.merchantDocuments.toSet();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            'Vos pièces',
            style: textTheme.labelMedium?.copyWith(
              color: IviaColors.textSecondary,
            ),
          ),
        ),
        const SizedBox(height: IviaSpacing.xs),
        Text(
          'Vues seulement par l’équipe ivia, pour vérifier votre identité. '
          'Elles valent pour toutes vos boutiques.',
          style: textTheme.bodySmall?.copyWith(color: IviaColors.textMuted),
        ),
        const SizedBox(height: IviaSpacing.sm),
        for (final (kind, label, hint) in merchantDocuments) ...[
          DocumentRow(
            label: label,
            hint: hint,
            photo: null,
            alreadySent: received.contains(kind),
            busy: _sending == kind,
            enabled: _sending == null,
            onPicked: (photo) => _send(kind, photo),
          ),
          const SizedBox(height: IviaSpacing.sm),
        ],
      ],
    );
  }
}
