import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ivia_api_client/testing.dart';
import 'package:ivia_buyer/app/router.dart';
import 'package:ivia_buyer/features/orders/order_screen.dart';
import 'package:ivia_buyer/features/payment/payment_screen.dart';
import 'package:ivia_buyer/features/payment/payment_wait_screen.dart';
import 'package:ivia_ui/ivia_ui.dart';

import 'support/buyer_app.dart';

/// Espaces typographiques remplacés par des espaces simples.
String plain(String s) => s.replaceAll(' ', ' ').replaceAll(' ', ' ');

Finder textPlain(String text) => find.byWidgetPredicate(
  (w) => w is Text && plain(w.data ?? w.textSpan?.toPlainText() ?? '') == text,
);

Finder textPlainContaining(String text) => find.byWidgetPredicate(
  (w) =>
      w is Text &&
      plain(w.data ?? w.textSpan?.toPlainText() ?? '').contains(text),
);

/// L'attente a un indicateur qui tourne sans fin : on avance le temps
/// au lieu d'attendre qu'il s'arrête.
Future<void> settle(WidgetTester tester, [int steps = 10]) async {
  for (var i = 0; i < steps; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  late BuyerHarness app;
  late Map<String, dynamic> afi;
  late Map<String, dynamic> order;
  late String orderId;

  setUp(() async {
    await BuyerHarness.resetStorage();
    app = BuyerHarness();
    afi = app.search.shop('Chez Afi');
    final riz = app.search.product(afi, 'Riz parfumé 5 kg');
    final huile = app.search.product(
      afi,
      'Huile 1 L',
      price: 1500,
      stockMode: 'untracked',
    );
    order = app.orders.seed(afi, [(riz, 2), (huile, 1)]);
    orderId = order['id'] as String;
  });

  Iterable<RecordedRequest> starts() =>
      app.server.calls('POST', '/v1/orders/$orderId/payments');

  Iterable<RecordedRequest> reads(String paymentId) =>
      app.server.calls('GET', '/v1/payments/$paymentId');

  Map<String, dynamic> payment([int index = 0]) => app.payments.payments[index];

  Future<void> goTo(WidgetTester tester, String location) async {
    await app.launch(tester);
    GoRouter.of(tester.element(find.byType(IviaBottomNav))).go(location);
    await settle(tester);
  }

  /// Écran Paiement ouvert, demande envoyée : attente affichée.
  Future<void> startPayment(WidgetTester tester) async {
    await goTo(tester, Routes.pay(orderId));
    await tester.tap(textPlain('Payer 10 500 F'));
    await settle(tester);
    expect(find.byType(PaymentWaitScreen), findsOneWidget);
  }

  group('écran Paiement', () {
    testWidgets('montant, Flooz par défaut, numéro du profil, une demande', (
      tester,
    ) async {
      await goTo(tester, Routes.pay(orderId));
      expect(find.text('Paiement'), findsOneWidget);
      expect(textPlain('10 500 F'), findsOneWidget);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Flooz')),
        matchesSemantics(
          label: 'Flooz',
          isButton: true,
          hasCheckedState: true,
          isChecked: true,
          isInMutuallyExclusiveGroup: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );
      expect(find.text('Numéro Flooz'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '90 12 34 56',
      );
      expect(find.textContaining('Paiement sécurisé'), findsOneWidget);

      await tester.tap(textPlain('Payer 10 500 F'));
      await settle(tester);
      expect(starts().single.body, {
        'operator': 'flooz',
        'phone': '+22890123456',
      });
      expect(find.byType(PaymentWaitScreen), findsOneWidget);
      expect(
        find.text('Validez le paiement sur votre téléphone'),
        findsOneWidget,
      );
      expect(
        textPlainContaining(
          'Une demande Flooz de 10 500 F a été envoyée au +228 90 •• •• 56.',
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp('numéro se terminant par 56')),
        findsOneWidget,
      );
      expect(find.text('Temps restant'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp(r'^Temps restant : \d+ minutes?')),
        findsOneWidget,
      );
      expect(
        find.text('Vos produits sont réservés pendant 15 minutes.'),
        findsOneWidget,
      );

      // Retour (flèche) : le suivi, sans annuler la demande.
      await tester.tap(find.byTooltip('Retour'));
      await tester.pumpAndSettle();
      expect(find.byType(OrderScreen), findsOneWidget);
      expect(payment()['status'], 'pending');
      expect(
        app.server.calls('POST', '/v1/payments/${payment()['id']}/cancel'),
        isEmpty,
      );
    });

    testWidgets('T-Money choisi, autre numéro', (tester) async {
      await goTo(tester, Routes.pay(orderId));
      await tester.tap(find.text('T-Money'));
      await tester.pump();
      expect(find.text('Numéro T-Money'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '70 11 22 33');
      await tester.tap(textPlain('Payer 10 500 F'));
      await settle(tester);
      expect(starts().single.body, {
        'operator': 'tmoney',
        'phone': '+22870112233',
      });
      expect(textPlainContaining('Une demande T-Money'), findsOneWidget);
    });

    testWidgets('numéro invalide : erreur sous le champ, rien envoyé', (
      tester,
    ) async {
      await goTo(tester, Routes.pay(orderId));
      await tester.enterText(find.byType(TextField), '12 34');
      await tester.tap(textPlain('Payer 10 500 F'));
      await tester.pumpAndSettle();
      expect(
        find.text('Numéro à 8 chiffres commençant par 7 ou 9.'),
        findsOneWidget,
      );
      expect(starts(), isEmpty);
      expect(find.byType(PaymentScreen), findsOneWidget);
    });

    testWidgets('double appui : une seule demande', (tester) async {
      await goTo(tester, Routes.pay(orderId));
      final gate = Completer<void>();
      app.payments.beforeRequest = (r) =>
          r.method == 'POST' ? gate.future : Future.value();
      await tester.tap(textPlain('Payer 10 500 F'));
      await tester.pump();
      await tester.tap(find.byType(FilledButton).last, warnIfMissed: false);
      // Retour bloqué pendant l'envoi.
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byType(PaymentScreen), findsOneWidget);
      gate.complete();
      await settle(tester);
      expect(starts(), hasLength(1));
      expect(find.byType(PaymentWaitScreen), findsOneWidget);
    });

    testWidgets('prestataire injoignable, réseau coupé : on reste', (
      tester,
    ) async {
      await goTo(tester, Routes.pay(orderId));
      app.payments.providerDown = true;
      await tester.tap(textPlain('Payer 10 500 F'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Le paiement n’a pas pu être lancé. Réessayez dans un instant.'
              .replaceAll('’', "'"),
        ),
        findsOneWidget,
      );
      expect(find.byType(PaymentScreen), findsOneWidget);
      app.payments
        ..providerDown = false
        ..failures['POST /v1/orders'] = FakeResponse.networkError();
      await tester.tap(textPlain('Payer 10 500 F'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Pas de connexion internet'), findsOneWidget);
      expect(find.byType(PaymentScreen), findsOneWidget);
      await tester.tap(textPlain('Payer 10 500 F'));
      await settle(tester);
      expect(find.byType(PaymentWaitScreen), findsOneWidget);
    });

    testWidgets('commande plus payable : message et retour au suivi', (
      tester,
    ) async {
      await goTo(tester, Routes.pay(orderId));
      app.orders.advance(order, 'expired');
      await tester.tap(textPlain('Payer 10 500 F'));
      await tester.pumpAndSettle();
      expect(
        find.text("Cette commande n'attend pas de paiement."),
        findsOneWidget,
      );
      expect(find.byType(OrderScreen), findsOneWidget);
      expect(find.text('Paiement expiré'), findsWidgets);
    });

    testWidgets('trop de demandes : message du serveur', (tester) async {
      await goTo(tester, Routes.pay(orderId));
      app.payments.rateLimited = true;
      await tester.tap(textPlain('Payer 10 500 F'));
      await tester.pumpAndSettle();
      expect(
        find.text('Trop de demandes de paiement. Réessayez plus tard.'),
        findsOneWidget,
      );
    });
  });

  group('attente', () {
    testWidgets('validation : suivi ouvert en moins de 3 s, avec le code', (
      tester,
    ) async {
      await startPayment(tester);
      final id = payment()['id'] as String;
      final before = reads(id).length;
      app.payments.succeed(payment());
      await tester.pump(const Duration(seconds: 3));
      await settle(tester);
      expect(reads(id).length, before + 1);
      expect(find.byType(OrderScreen), findsOneWidget);
      expect(
        find.text('La boutique va confirmer votre commande.'),
        findsOneWidget,
      );
      expect(find.text('En attente de la boutique'), findsOneWidget);
      expect(find.byType(IviaHandoverCode), findsOneWidget);
    });

    testWidgets('refus : raison, « Réessayer » rouvre le paiement', (
      tester,
    ) async {
      await startPayment(tester);
      app.payments.fail(payment());
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.text('Le paiement n’a pas abouti'), findsOneWidget);
      expect(find.text('Paiement refusé ou annulé.'), findsOneWidget);
      await tester.tap(find.text('Réessayer'));
      await tester.pumpAndSettle();
      expect(find.byType(PaymentScreen), findsOneWidget);
      await tester.tap(textPlain('Payer 10 500 F'));
      await settle(tester);
      expect(app.payments.payments, hasLength(2));
      expect(find.byType(PaymentWaitScreen), findsOneWidget);
    });

    testWidgets('« Annuler le paiement » : confirmé, suivi toujours à payer', (
      tester,
    ) async {
      await startPayment(tester);
      await tester.tap(find.text('Annuler le paiement'));
      await settle(tester);
      expect(find.text('Annuler le paiement ?'), findsOneWidget);
      expect(find.textContaining('reste réservée jusqu’à'), findsOneWidget);
      // « Continuer d'attendre » : rien n'est annulé.
      await tester.tap(find.text('Continuer d’attendre'));
      await settle(tester);
      expect(payment()['status'], 'pending');

      await tester.tap(find.text('Annuler le paiement'));
      await settle(tester);
      await tester.tap(find.text('Annuler le paiement').last);
      await tester.pumpAndSettle();
      expect(
        app.server.calls('POST', '/v1/payments/${payment()['id']}/cancel'),
        hasLength(1),
      );
      expect(payment()['status'], 'failed');
      expect(find.byType(OrderScreen), findsOneWidget);
      expect(find.textContaining('À payer avant'), findsOneWidget);
      expect(find.textContaining('Paiement annulé.'), findsOneWidget);
    });

    testWidgets('« Je n’ai rien reçu » : renvoyer, même opérateur et numéro', (
      tester,
    ) async {
      await startPayment(tester);
      await tester.tap(find.text('Je n’ai rien reçu'));
      await settle(tester);
      expect(
        textPlainContaining('le +228 90 •• •• 56 est bien votre numéro Flooz'),
        findsOneWidget,
      );
      await tester.tap(find.text('Renvoyer la demande'));
      await settle(tester);
      expect(payment(0)['status'], 'failed');
      expect(payment(1)['status'], 'pending');
      expect(starts().map((r) => r.body), [
        {'operator': 'flooz', 'phone': '+22890123456'},
        {'operator': 'flooz', 'phone': '+22890123456'},
      ]);
      expect(find.byType(PaymentWaitScreen), findsOneWidget);
      // La nouvelle demande est celle relue.
      app.payments.succeed(payment(1));
      await tester.pump(const Duration(seconds: 3));
      await settle(tester);
      expect(find.byType(IviaHandoverCode), findsOneWidget);
    });

    testWidgets('« Je n’ai rien reçu » : changer de numéro', (tester) async {
      await goTo(tester, Routes.pay(orderId));
      await tester.tap(find.text('T-Money'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), '70 11 22 33');
      await tester.tap(textPlain('Payer 10 500 F'));
      await settle(tester);
      await tester.tap(find.text('Je n’ai rien reçu'));
      await settle(tester);
      await tester.tap(find.text('Changer de numéro'));
      await tester.pumpAndSettle();
      expect(payment()['status'], 'failed');
      expect(find.byType(PaymentScreen), findsOneWidget);
      expect(find.text('Numéro T-Money'), findsOneWidget);
    });

    testWidgets('annulation qui croise une validation : suivi avec le code', (
      tester,
    ) async {
      await startPayment(tester);
      app.payments.succeed(payment());
      await tester.tap(find.text('Annuler le paiement'));
      await settle(tester);
      await tester.tap(find.text('Annuler le paiement').last);
      await settle(tester);
      expect(find.byType(OrderScreen), findsOneWidget);
      expect(find.byType(IviaHandoverCode), findsOneWidget);
      expect(payment()['status'], 'succeeded');
    });

    testWidgets('« Payer » du suivi reprend la demande en cours', (
      tester,
    ) async {
      await startPayment(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(OrderScreen), findsOneWidget);
      await tester.tap(textPlain('Payer 10 500 F'));
      await settle(tester);
      expect(find.byType(PaymentWaitScreen), findsOneWidget);
      expect(starts(), hasLength(1));
      // Sans le numéro complet, « Renvoyer » repart de l'écran Paiement.
      await tester.tap(find.text('Je n’ai rien reçu'));
      await settle(tester);
      await tester.tap(find.text('Renvoyer la demande'));
      await tester.pumpAndSettle();
      expect(find.byType(PaymentScreen), findsOneWidget);
      expect(starts(), hasLength(1));
    });

    testWidgets('délai dépassé : message, relecture continue', (tester) async {
      // Le serveur accepte encore la demande ; l'heure limite est passée
      // pour le téléphone.
      app.orders.now = () =>
          DateTime.now().toUtc().subtract(const Duration(minutes: 1));
      order['payment_deadline_at'] = DateTime.now()
          .toUtc()
          .subtract(const Duration(seconds: 5))
          .toIso8601String();
      await startPayment(tester);
      expect(find.text('Délai de paiement dépassé'), findsOneWidget);
      expect(find.text('Je n’ai rien reçu'), findsNothing);
      expect(find.text('Annuler le paiement'), findsOneWidget);
      final id = payment()['id'] as String;
      final before = reads(id).length;
      await tester.pump(const Duration(seconds: 3));
      expect(reads(id).length, before + 1);
    });

    testWidgets('arrière-plan : relecture arrêtée, reprise au retour', (
      tester,
    ) async {
      await startPayment(tester);
      final id = payment()['id'] as String;
      tester.binding
        ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
        ..handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      final before = reads(id).length;
      await tester.pump(const Duration(seconds: 10));
      expect(reads(id).length, before);
      tester.binding
        ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
        ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settle(tester, 2);
      expect(reads(id).length, before + 1);
    });

    testWidgets('paiement inconnu : plus disponible', (tester) async {
      await goTo(
        tester,
        Routes.payWait(orderId, 'c0000000-0000-4000-8000-000000000099'),
      );
      expect(find.text('Ce paiement n’est plus disponible.'), findsOneWidget);
    });

    testWidgets('simulation locale : boutons absents par défaut', (
      tester,
    ) async {
      await startPayment(tester);
      expect(find.text('Simuler la validation'), findsNothing);
    });

    testWidgets('simulation locale : validation puis suivi', (tester) async {
      app.devPayments = true;
      await startPayment(tester);
      await tester.tap(find.text('Simuler un refus'));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('Le paiement n’a pas abouti'), findsOneWidget);
      await tester.tap(find.text('Réessayer'));
      await tester.pumpAndSettle();
      await tester.tap(textPlain('Payer 10 500 F'));
      await settle(tester);
      await tester.tap(find.text('Simuler la validation'));
      await settle(tester);
      expect(
        app.server.requests
            .where((r) => r.path.endsWith('/simulate'))
            .map((r) => r.body),
        [
          {'outcome': 'failed'},
          {'outcome': 'succeeded'},
        ],
      );
      expect(find.byType(IviaHandoverCode), findsOneWidget);
    });
  });

  group('attente : cas limites', () {
    testWidgets('relecture finie 10 min après l’heure limite', (tester) async {
      app.orders.now = () =>
          DateTime.now().toUtc().subtract(const Duration(minutes: 12));
      order['payment_deadline_at'] = DateTime.now()
          .toUtc()
          .subtract(const Duration(minutes: 11))
          .toIso8601String();
      await startPayment(tester);
      expect(find.text('Retour à la commande'), findsOneWidget);
      final id = payment()['id'] as String;
      final before = reads(id).length;
      await tester.pump(const Duration(seconds: 10));
      expect(reads(id).length, before);
      // Annulation : le texte ne promet plus de payer plus tard.
      await tester.tap(find.text('Annuler le paiement'));
      await settle(tester);
      expect(find.textContaining('ne pourra plus être payée'), findsOneWidget);
      await tester.tap(find.text('Annuler le paiement').last);
      await tester.pumpAndSettle();
      expect(find.text('Paiement annulé.'), findsOneWidget);
    });

    testWidgets('heure du téléphone en retard : celle du serveur fait foi', (
      tester,
    ) async {
      app.server.clock = () => DateTime.now().add(const Duration(minutes: 12));
      await startPayment(tester);
      expect(find.text('Délai de paiement dépassé'), findsOneWidget);
    });

    testWidgets(
      'réseau coupé pendant l’attente : rien ne passe pour un échec',
      (tester) async {
        await startPayment(tester);
        final id = payment()['id'] as String;
        app.payments.failures['GET /v1/payments/$id'] =
            FakeResponse.networkError();
        await tester.pump(const Duration(seconds: 3));
        await settle(tester);
        expect(
          find.text('Validez le paiement sur votre téléphone'),
          findsOneWidget,
        );
        app.payments.succeed(payment());
        await tester.pump(const Duration(seconds: 3));
        await settle(tester);
        expect(find.byType(IviaHandoverCode), findsOneWidget);
      },
    );

    testWidgets('statut inconnu de l’app : attente, relecture continue', (
      tester,
    ) async {
      await startPayment(tester);
      payment()['status'] = 'on_hold';
      final id = payment()['id'] as String;
      await tester.pump(const Duration(seconds: 3));
      await settle(tester);
      expect(
        find.text('Validez le paiement sur votre téléphone'),
        findsOneWidget,
      );
      final before = reads(id).length;
      await tester.pump(const Duration(seconds: 3));
      expect(reads(id).length, before + 1);
    });

    testWidgets('statut final : relecture arrêtée', (tester) async {
      await startPayment(tester);
      app.payments.fail(payment());
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.text('Le paiement n’a pas abouti'), findsOneWidget);
      final id = payment()['id'] as String;
      final before = reads(id).length;
      await tester.pump(const Duration(seconds: 10));
      expect(reads(id).length, before);
    });

    testWidgets('retour bloqué pendant l’annulation', (tester) async {
      await startPayment(tester);
      final gate = Completer<void>();
      app.payments.beforeRequest = (r) =>
          r.path.endsWith('/cancel') ? gate.future : Future.value();
      await tester.tap(find.text('Annuler le paiement'));
      await settle(tester);
      await tester.tap(find.text('Annuler le paiement').last);
      await settle(tester);
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.byType(PaymentWaitScreen), findsOneWidget);
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.byType(OrderScreen), findsOneWidget);
    });

    testWidgets('renvoi refusé après l’annulation : écran Paiement, message', (
      tester,
    ) async {
      await startPayment(tester);
      app.payments.rateLimited = true;
      await tester.tap(find.text('Je n’ai rien reçu'));
      await settle(tester);
      await tester.tap(find.text('Renvoyer la demande'));
      await tester.pumpAndSettle();
      expect(payment()['status'], 'failed');
      expect(find.byType(PaymentScreen), findsOneWidget);
      expect(
        find.text('Trop de demandes de paiement. Réessayez plus tard.'),
        findsOneWidget,
      );
    });

    testWidgets(
      'réponse perdue puis autre numéro : la demande du serveur est montrée, '
      '« Renvoyer » rouvre le paiement',
      (tester) async {
        await goTo(tester, Routes.pay(orderId));
        app.payments.loseNextStartResponse = true;
        await tester.tap(textPlain('Payer 10 500 F'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Pas de connexion internet'),
          findsOneWidget,
        );
        await tester.tap(find.text('T-Money'));
        await tester.pump();
        await tester.enterText(find.byType(TextField), '70 11 22 33');
        await tester.tap(textPlain('Payer 10 500 F'));
        await settle(tester);
        // Le serveur rend la demande Flooz déjà en attente.
        expect(
          textPlainContaining(
            'Une demande Flooz de 10 500 F a été envoyée au '
            '+228 90 •• •• 56.',
          ),
          findsOneWidget,
        );
        ScaffoldMessenger.of(tester.element(find.byType(PaymentWaitScreen)))
            .hideCurrentSnackBar();
        await settle(tester);
        await tester.tap(find.text('Je n’ai rien reçu'));
        await settle(tester);
        await tester.tap(find.text('Renvoyer la demande'));
        await tester.pumpAndSettle();
        expect(find.byType(PaymentScreen), findsOneWidget);
        expect(starts(), hasLength(2));
        expect(app.payments.payments, hasLength(1));
        expect(payment()['status'], 'failed');
      },
    );

    testWidgets("paiement d'un autre compte : plus disponible, retour", (
      tester,
    ) async {
      await startPayment(tester);
      final id = payment()['id'] as String;
      app.payments.giveTo(payment(), 'Bearer jeton-kofi');
      final router = GoRouter.of(tester.element(find.byType(PaymentWaitScreen)))
        ..go(Routes.order(orderId));
      await tester.pumpAndSettle();
      router.go(Routes.payWait(orderId, id));
      await settle(tester);
      expect(find.text('Ce paiement n’est plus disponible.'), findsOneWidget);
      await tester.tap(find.byTooltip('Retour'));
      await tester.pumpAndSettle();
      expect(find.byType(OrderScreen), findsOneWidget);
    });
  });

  group('écran Paiement, délai', () {
    testWidgets('délai dépassé au serveur : message et retour au suivi', (
      tester,
    ) async {
      await goTo(tester, Routes.pay(orderId));
      order['payment_deadline_at'] = DateTime.now()
          .toUtc()
          .subtract(const Duration(seconds: 1))
          .toIso8601String();
      await tester.tap(textPlain('Payer 10 500 F'));
      await tester.pumpAndSettle();
      expect(find.text('Le délai de paiement est dépassé.'), findsOneWidget);
      expect(find.byType(OrderScreen), findsOneWidget);
    });
  });

  testWidgets('police 200 %, écran de 320 dp : rien ne déborde', (
    tester,
  ) async {
    smallScreenLargeFont(tester);
    await goTo(tester, Routes.pay(orderId));
    expect(tester.takeException(), isNull);
    await tester.tap(textPlain('Payer 10 500 F'));
    await settle(tester);
    expect(find.byType(PaymentWaitScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
    // Bas de l'écran : la liste se construit à mesure qu'on la fait défiler.
    await tester.drag(find.byType(ListView), const Offset(0, -3000));
    await settle(tester);
    await tester.tap(find.text('Je n’ai rien reçu'));
    await settle(tester);
    expect(find.text('Renvoyer la demande'), findsOneWidget);
    expect(tester.takeException(), isNull);
    // Feuille fermée.
    Navigator.of(tester.element(find.text('Renvoyer la demande'))).pop();
    await settle(tester);
    await tester.drag(find.byType(ListView), const Offset(0, -3000));
    await settle(tester);
    await tester.tap(find.text('Annuler le paiement'));
    await settle(tester);
    expect(find.text('Annuler le paiement ?'), findsOneWidget);
    expect(tester.takeException(), isNull);
    Navigator.of(tester.element(find.text('Annuler le paiement ?'))).pop();
    await settle(tester);
    app.payments.fail(payment());
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('Le paiement n’a pas abouti'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
