import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';

import '../../common/providers.dart';
import '../../common/ui.dart';

/// Pièces envoyées avec le dossier, validées par l'équipe ivia.
class DocumentsScreen extends ConsumerWidget {
  const DocumentsScreen({super.key});

  static const _labels = {
    'opening_authorization': "Autorisation d'exercice",
    'owner_id': "Pièce d'identité du titulaire",
    'order_registration': "Inscription à l'Ordre",
    'storefront_photo': 'Photo de la devanture',
    'other': 'Autre pièce',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(pharmacyProfileProvider).value;
    final docs = p?.documents.toSet().toList() ?? const <String>[];
    return Scaffold(
      backgroundColor: P.page,
      body: SafeArea(
        child: Column(
          children: [
            const PHeader(title: 'Documents'),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(P.gutter, 4, P.gutter, 12),
                children: [
                  Text(
                    "Vus uniquement par l'équipe ivia. Pour en changer un, "
                    'contactez-la.',
                    style: PText.bodyMuted,
                  ),
                  const SizedBox(height: 14),
                  if (docs.isEmpty)
                    const PEmpty(
                      icon: Icons.description_outlined,
                      text: 'Aucune pièce.',
                    )
                  else
                    PCard(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          for (final (i, d) in docs.indexed) ...[
                            if (i > 0) const Divider(height: 1, color: P.line),
                            Padding(
                              padding: const EdgeInsets.all(14),
                              child: Row(
                                children: [
                                  const PIcon(Icons.check, size: 34),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Text(
                                      _labels[d] ??
                                          pharmacyDocumentLabels[d] ??
                                          d,
                                      style: PText.cardTitle.copyWith(
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                  Text('Envoyée', style: PText.bodyMuted),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
