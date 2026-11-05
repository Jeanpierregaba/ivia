import 'package:flutter/material.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_ui/ivia_ui.dart';

/// Marque affichée sous le nom de l'opérateur (Flooz est le service de Moov
/// Africa, T-Money celui de Yas, ex-Togocom).
String operatorBrand(PaymentOperator operator) => switch (operator) {
  PaymentOperator.flooz => 'Moov Money',
  PaymentOperator.tmoney => 'Mixx by Yas',
};

/// Logo d'un moyen de paiement. Les logos officiels se déposent dans
/// `assets/payment/<code>.png` (flooz, tmoney, visa, mastercard) ; sans
/// fichier, un logo aux couleurs de la marque est dessiné.
class PaymentLogo extends StatelessWidget {
  const PaymentLogo.operator(
    PaymentOperator operator, {
    super.key,
    this.size = 48,
  }) : code = operator == PaymentOperator.flooz ? 'flooz' : 'tmoney';

  const PaymentLogo.card({super.key, this.size = 48}) : code = 'visa';

  final String code;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(IviaRadius.button),
      child: SizedBox.square(
        dimension: size,
        child: Image.asset(
          'assets/payment/$code.png',
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => _drawn(context),
        ),
      ),
    );
  }

  Widget _drawn(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return switch (code) {
      'flooz' => Container(
        color: const Color(0xFF005BAA),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'moov',
              style: t.labelLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
            Container(
              width: size * .5,
              height: 3,
              color: const Color(0xFFF7931E),
            ),
          ],
        ),
      ),
      'tmoney' => Container(
        color: const Color(0xFFFFD400),
        alignment: Alignment.center,
        child: Text(
          'yas',
          style: t.titleMedium?.copyWith(
            color: const Color(0xFF1D1D1B),
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      _ => Container(
        color: Colors.white,
        alignment: Alignment.center,
        child: Text(
          'VISA',
          style: t.labelLarge?.copyWith(
            color: const Color(0xFF1A1F71),
            fontWeight: FontWeight.w900,
            fontStyle: FontStyle.italic,
          ),
        ),
      ),
    };
  }
}

/// Carte bancaire : proposée dès que l'agrégateur de paiement (CinetPay,
/// PayDunya, FedaPay…) est branché, ADR 0007.
class CardPaymentSoon extends StatelessWidget {
  const CardPaymentSoon({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Opacity(
      opacity: .6,
      child: Container(
        padding: const EdgeInsets.all(IviaSpacing.lg),
        decoration: BoxDecoration(
          color: IviaColors.surface,
          borderRadius: BorderRadius.circular(IviaRadius.large),
        ),
        child: Row(
          children: [
            const PaymentLogo.card(size: 44),
            const SizedBox(width: IviaSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Carte Visa ou Mastercard', style: t.titleMedium),
                  Text('Bientôt disponible', style: t.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
