import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../common/providers.dart';
import '../../common/ui.dart';
import 'documents.dart';

/// Étape 3 du dossier (F07) : pièces vues par l'équipe ivia seulement, et
/// la case « Je certifie… », obligatoire pour continuer. La devanture revient
/// ici si son envoi a échoué à l'étape 1.
class DocumentsStep extends ConsumerStatefulWidget {
  const DocumentsStep({
    super.key,
    required this.profile,
    required this.certified,
    required this.onCertified,
    required this.onNext,
    required this.header,
  });

  final PharmacyProfile profile;
  final bool certified;
  final ValueChanged<bool> onCertified;
  final VoidCallback onNext;
  final Widget header;

  @override
  ConsumerState<DocumentsStep> createState() => _DocumentsStepState();
}

class _DocumentsStepState extends ConsumerState<DocumentsStep> {
  /// Pièce en cours d'envoi : une seule à la fois.
  String? _sending;

  Future<void> _add(String kind) async {
    final bytes = await choosePhoto(context, ref);
    if (bytes == null || !mounted) return;
    setState(() => _sending = kind);
    try {
      await sendPharmacyDocument(ref.read(apiClientProvider), kind, bytes);
      ref.invalidate(pharmacyProfileProvider);
    } on ApiException catch (e) {
      if (mounted) say(context, e.message);
    } finally {
      if (mounted) setState(() => _sending = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.profile;
    final rows = [
      if (p.missingDocuments.contains('storefront_photo'))
        (
          kind: 'storefront_photo',
          label: 'Photo de la devanture',
          hint: 'Prise de la rue, enseigne visible',
          required: true,
        ),
      ...dossierDocuments,
    ];
    final ready = p.missingDocuments.isEmpty && widget.certified;
    return Column(
      children: [
        widget.header,
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(P.gutter, 8, P.gutter, 8),
            children: [
              Semantics(
                header: true,
                child: Text(
                  'Vérification de la pharmacie',
                  style: PText.heading,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                "Ces documents sont vus uniquement par l'équipe ivia.",
                style: PText.bodyMuted,
              ),
              const SizedBox(height: 18),
              for (final d in rows)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _DocumentRow(
                    label: d.label,
                    hint: d.hint,
                    done: p.documents.contains(d.kind),
                    sending: _sending == d.kind,
                    onTap: _sending == null ? () => _add(d.kind) : null,
                  ),
                ),
              const SizedBox(height: 6),
              PCheckRow(
                value: widget.certified,
                onChanged: widget.onCertified,
                label:
                    'Je certifie être titulaire ou gérant de cette pharmacie.',
              ),
            ],
          ),
        ),
        PBottomBar(
          children: [
            PButton(
              label: 'Continuer',
              onTap: ready && _sending == null ? widget.onNext : null,
            ),
          ],
        ),
      ],
    );
  }
}

/// Ligne de pièce : case verte cochée (« Ajouté ») ou case pointillée
/// (« Ajouter »).
class _DocumentRow extends StatelessWidget {
  const _DocumentRow({
    required this.label,
    required this.hint,
    required this.done,
    required this.sending,
    required this.onTap,
  });

  final String label, hint;
  final bool done, sending;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final action = done ? 'Ajouté' : 'Ajouter';
    return Semantics(
      button: true,
      label:
          '$label, $hint, ${done ? 'ajouté, toucher pour remplacer' : 'à ajouter'}',
      excludeSemantics: true,
      child: PCard(
        onTap: onTap,
        padding: const EdgeInsets.fromLTRB(14, 12, 16, 12),
        child: Row(
          children: [
            SizedBox.square(
              dimension: 34,
              child: done
                  ? DecoratedBox(
                      decoration: BoxDecoration(
                        color: P.green,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.check,
                        size: 18,
                        color: Colors.white,
                      ),
                    )
                  : const CustomPaint(
                      painter: _DashedBox(),
                      child: Icon(Icons.add, size: 18, color: P.muted),
                    ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: PText.cardTitle.copyWith(fontSize: 16)),
                  Text(hint, style: PText.small),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (sending)
              const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Text(
                action,
                style: PText.button.copyWith(
                  fontSize: 15,
                  color: done ? P.muted : P.green,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Case vide aux bords pointillés.
class _DashedBox extends CustomPainter {
  const _DashedBox();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = IviaPharmacyColors.checkOff
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(1),
          const Radius.circular(10),
        ),
      );
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 7) {
        canvas.drawPath(metric.extractPath(d, d + 4), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBox oldDelegate) => false;
}
