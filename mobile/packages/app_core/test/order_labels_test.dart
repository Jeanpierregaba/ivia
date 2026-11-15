import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

void main() {
  test('chaque statut a un libellé, un ton et une icône', () {
    for (final s in OrderStatus.values) {
      expect(statusLabel(s), isNotEmpty, reason: s.code);
      statusTone(s);
      statusIcon(s);
    }
    expect(
      statusLabel(OrderStatus.awaitingSeller),
      'En attente de la boutique',
    );
    expect(statusTone(OrderStatus.awaitingSeller), IviaPillTone.warning);
    expect(statusTone(OrderStatus.completed), IviaPillTone.success);
    expect(statusTone(OrderStatus.cancelled), IviaPillTone.error);
  });

  test('mode et nombre d\'articles', () {
    expect(fulfillmentLabel(Fulfillment.pickup), 'Retrait');
    expect(fulfillmentLabel(Fulfillment.delivery), 'Livraison');
    expect(articles(1), '1 article');
    expect(articles(3), '3 articles');
  });

  testWidgets('pastille : libellé propre à l\'app, icône toujours là', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: statusPill(OrderStatus.awaitingSeller, label: 'Nouvelle'),
        ),
      ),
    );
    expect(find.text('Nouvelle'), findsOneWidget);
    expect(find.byIcon(Icons.hourglass_empty), findsOneWidget);
  });
}
