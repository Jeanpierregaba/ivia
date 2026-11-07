import 'package:flutter/material.dart';
import 'package:ivia_app_core/ivia_app_core.dart';

import '../../common/ui.dart';

/// Commande remise (F19, et remise au client) : coche, texte, récapitulatif,
/// « Retour aux commandes ».
class OrderDoneScreen extends StatelessWidget {
  const OrderDoneScreen({
    super.key,
    required this.title,
    required this.body,
    required this.rows,
    required this.totalLabel,
    required this.totalXof,
    this.doubleCheck = false,
  });

  final String title, body, totalLabel;
  final List<(String, String)> rows;
  final int totalXof;

  /// Double coche (remise au livreur).
  final bool doubleCheck;

  @override
  Widget build(BuildContext context) {
    Widget row(String label, String value, {bool strong = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: strong
                  ? PText.cardTitle.copyWith(fontSize: 20)
                  : PText.body.copyWith(color: P.label),
            ),
          ),
          const SizedBox(width: 12),
          // Souple : à 200 % sur un petit écran, le montant passe à la ligne au lieu de déborder.
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: PText.cardTitle.copyWith(fontSize: strong ? 20 : 16),
            ),
          ),
        ],
      ),
    );
    return Scaffold(
      backgroundColor: P.page,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: P.gutter),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DoneBadge(doubleCheck: doubleCheck),
                      const SizedBox(height: 22),
                      Semantics(
                        header: true,
                        liveRegion: true,
                        child: Text(title, style: PText.heading),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        body,
                        style: PText.body.copyWith(
                          fontSize: 16,
                          color: P.label,
                        ),
                      ),
                      const SizedBox(height: 22),
                      PCard(
                        child: Column(
                          children: [
                            for (final (label, value) in rows)
                              row(label, value),
                            const Divider(height: 18, color: P.line),
                            row(totalLabel, formatXof(totalXof), strong: true),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            PBottomBar(
              children: [
                PButton(
                  label: 'Retour aux commandes',
                  style: PButtonStyle.outline,
                  onTap: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
