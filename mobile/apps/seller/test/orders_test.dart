import 'dart:typed_data';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_api_client/testing.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_app_core/testing.dart';
import 'package:ivia_ui/ivia_ui.dart';
import 'package:ivia_seller/features/business/biz_ui.dart';
import 'package:ivia_seller/app/device_services.dart';
import 'package:ivia_seller/app/identity.dart';
import 'package:ivia_seller/app/router.dart';
import 'package:ivia_seller/features/orders/handover_screen.dart';
import 'package:ivia_seller/features/orders/order_labels.dart';
import 'package:ivia_seller/features/orders/orders_screen.dart';
import 'package:ivia_seller/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NoLocation extends FakeLocationService {}

/// Texte affiché, espaces typographiques remplacés (« 10 500 F »).
Finder textPlain(String text) => find.byWidgetPredicate(
  (w) =>
      w is Text &&
      (w.data ?? '').replaceAll('\u202f', ' ').replaceAll('\u00a0', ' ') ==
          text,
);

void main() {
  late FakeApiServer server;
  late FakeSellerOrders orders;

  Map<String, dynamic> seller() => {
    ...userBody(complete: true),
    'roles': ['buyer', 'seller'],
  };

  void withShop(String status) => server.on(
    'GET',
    '/v1/seller/shops',
    (_) => FakeResponse.json(200, {
      'items': [shopBody(status: status)],
    }),
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({'onboarding_seen': true});
    FlutterSecureStorage.setMockInitialValues({});
    server = FakeApiServer()
      ..on('GET', '/v1/me', (_) => FakeResponse.json(200, seller()))
      ..on('POST', '/v1/auth/logout', (_) => FakeResponse.json(204, null));
    withShop('published');
    FakeBusiness(server);
    FakeCatalog(server);
    orders = FakeSellerOrders(server);
    await SessionStore().save('jeton-secret', User.fromJson(seller()));
  });

  /// Onglet de la barre du bas (l'icône peut aussi figurer dans l'écran).
  Finder dockTab(IconData icon) =>
      find.descendant(of: find.byType(BizDock), matching: find.byIcon(icon));

  /// Libellé lu d'un onglet de la barre du bas (pastille comprise).
  Finder dockLabel(String label) => find.descendant(
    of: find.byType(BizDock),
    matching: find.bySemanticsLabel(label),
  );

  /// Texte affiché dans la barre du bas (pastille).
  Finder dockText(String text) =>
      find.descendant(of: find.byType(BizDock), matching: find.text(text));

  Future<void> launch(WidgetTester tester, {bool settle = true}) async {
    // Animations réduites : le point « en direct » du pilotage s'arrête.
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final store = await OnboardingStore.open();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          onboardingStoreProvider.overrideWithValue(store),
          appIdentityProvider.overrideWithValue(sellerIdentity),
          apiClientProvider.overrideWithValue(
            IviaApiClient(
              config: ApiConfig(baseUrl: Uri.parse('http://api.test')),
              adapter: server,
            ),
          ),
          authTimingsProvider.overrideWithValue(
            const AuthTimings(
              minSplash: Duration.zero,
              meTimeout: Duration(seconds: 1),
            ),
          ),
          photoPickerProvider.overrideWithValue(_NoPicker()),
          locationServiceProvider.overrideWithValue(_NoLocation()),
          locationPromptStoreProvider.overrideWithValue(
            await LocationPromptStore.open(_NoLocation()),
          ),
          mapsEnabledProvider.overrideWithValue(false),
        ],
        child: const SellerApp(),
      ),
    );
    if (settle) await tester.pumpAndSettle();
  }

  Iterable<RecordedRequest> lists() => server.calls('GET', '/v1/seller/orders');

  void lifecycle(WidgetTester tester, List<AppLifecycleState> states) {
    for (final state in states) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
  }

  group('arrivée des commandes', () {
    testWidgets('lues au lancement, pour la boutique, 100 au plus', (
      tester,
    ) async {
      await launch(tester);
      expect(lists().single.query, {
        'shop_id': shopId,
        'offset': '0',
        'limit': '100',
      });
    });

    testWidgets('nouvelle commande : visible 30 s après, pastille', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await launch(tester);
      expect(dockLabel('Commandes'), findsOneWidget);

      orders.add();
      await tester.pump(const Duration(seconds: 29));
      expect(lists(), hasLength(1));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(lists(), hasLength(2));
      expect(dockLabel('Commandes, 1 nouvelle'), findsOneWidget);
      expect(dockText('1'), findsOneWidget);

      orders.add();
      await tester.pump(const Duration(seconds: 30));
      await tester.pumpAndSettle();
      expect(dockLabel('Commandes, 2 nouvelles'), findsOneWidget);

      // Acceptée ailleurs : plus nouvelle, pastille retirée au passage
      // suivant.
      for (final o in orders.orders) {
        o['status'] = 'accepted';
      }
      await tester.pump(const Duration(seconds: 30));
      await tester.pumpAndSettle();
      expect(dockLabel('Commandes'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('arrière-plan : aucune requête ; au retour, relue aussitôt', (
      tester,
    ) async {
      await launch(tester);
      lifecycle(tester, const [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]);
      await tester.pump(const Duration(minutes: 2));
      expect(lists(), hasLength(1));

      orders.add();
      lifecycle(tester, const [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]);
      await tester.pumpAndSettle();
      expect(lists(), hasLength(2));
      expect(dockText('1'), findsOneWidget);

      // Puis de nouveau toutes les 30 s.
      await tester.pump(const Duration(seconds: 30));
      expect(lists(), hasLength(3));
    });

    testWidgets(
      'toutes les 30 s : nouvelles seulement ; onglet ouvert : tout',
      (tester) async {
        final active = orders.add(status: 'accepted')['id'] as String;
        await launch(tester);
        await tester.pump(const Duration(seconds: 30));
        await tester.pumpAndSettle();
        expect(lists().last.query['status'], 'awaiting_seller');

        // Commande en cours annulée par l'admin : vue à l'ouverture de
        // l'onglet (liste complète).
        orders.cancel(active, "Annulée par l'équipe ivia.");
        await tester.tap(dockTab(Icons.receipt_long_outlined));
        await tester.pumpAndSettle();
        expect(lists().last.query.containsKey('status'), isFalse);
        await tester.tap(find.textContaining('Terminées').first);
        await tester.pumpAndSettle();
        expect(find.text('Annulée'), findsOneWidget);
      },
    );

    testWidgets('nouvelle disparue de la relecture : relue seule', (
      tester,
    ) async {
      final id = orders.add()['id'] as String;
      await launch(tester);
      expect(dockText('1'), findsOneWidget);
      orders.cancel(id, "Annulée par l'acheteur.");
      await tester.pump(const Duration(seconds: 30));
      await tester.pumpAndSettle();
      expect(server.calls('GET', '/v1/seller/orders/$id'), hasLength(1));
      expect(dockText('1'), findsNothing);
    });

    testWidgets('relecture en échec : la pastille reste, sans message', (
      tester,
    ) async {
      orders.add();
      await launch(tester);
      expect(dockText('1'), findsOneWidget);
      orders.failures['GET /v1/seller/orders'] = FakeResponse.networkError();
      await tester.pump(const Duration(seconds: 30));
      await tester.pumpAndSettle();
      expect(dockText('1'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('boutique en validation : aucune lecture des commandes', (
      tester,
    ) async {
      withShop('pending_review');
      await launch(tester);
      await tester.pump(const Duration(minutes: 1));
      expect(lists(), isEmpty);
    });

    testWidgets('boutique suspendue entre-temps : écran « suspendue »', (
      tester,
    ) async {
      await launch(tester);
      orders.shopSuspended = true;
      withShop('suspended');
      await tester.pump(const Duration(seconds: 30));
      await tester.pumpAndSettle();
      expect(find.textContaining('suspendue'), findsWidgets);
      expect(dockLabel('Commandes'), findsNothing);
    });
  });

  /// Ouvre l'onglet Commandes de la barre du bas.
  Future<void> openOrders(WidgetTester tester) async {
    await launch(tester);
    await tester.tap(dockTab(Icons.receipt_long_outlined));
    await tester.pumpAndSettle();
  }

  /// Fait défiler la liste du pilotage jusqu'au texte (construit à la
  /// demande).
  Future<void> scrollHomeTo(WidgetTester tester, String text) =>
      tester.scrollUntilVisible(
        find.text(text),
        200,
        scrollable: find
            .descendant(
              of: find.byType(RefreshIndicator),
              matching: find.byType(Scrollable),
            )
            .first,
      );

  /// Fait défiler jusqu'au texte, puis l'appuie.
  Future<void> tapText(WidgetTester tester, String text) async {
    final target = find.text(text, skipOffstage: false).last;
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Future<void> openTab(WidgetTester tester, String label) async {
    await tester.tap(find.textContaining(label).first);
    await tester.pumpAndSettle();
  }

  /// Titres des lignes, dans l'ordre de l'écran.
  List<String> rows(WidgetTester tester) => [
    for (final t in tester.widgetList<Text>(
      find.descendant(
        of: find.byType(OrderRow),
        matching: find.textContaining(RegExp(r'^#\d+')),
      ),
    ))
      t.data!,
  ];

  group('onglet Commandes', () {
    testWidgets('répartition, ordre, compteurs, compte à rebours', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      orders
        ..add(buyerFirstName: 'Ama', paidAgo: const Duration(minutes: 2))
        ..add(buyerFirstName: 'Yao', paidAgo: const Duration(minutes: 10))
        ..add(status: 'accepted', buyerFirstName: 'Kossi')
        ..add(status: 'ready_for_pickup', buyerFirstName: 'Efua')
        ..add(status: 'completed', buyerFirstName: 'Abla')
        ..add(
          status: 'cancelled',
          buyerFirstName: 'Kodjo',
          cancelReason: 'Boutique fermée',
        );
      await openOrders(tester);

      expect(find.bySemanticsLabel('Nouvelles, 2'), findsOneWidget);
      expect(find.bySemanticsLabel('En cours, 2'), findsOneWidget);
      // La plus urgente (payée il y a 10 min) en haut.
      expect(rows(tester), ['#1043 · Yao', '#1042 · Ama']);
      // Ligne sur toute la largeur : titre à gauche, montant à droite.
      final list = tester.getRect(find.byType(OrderRow).first);
      final title = tester.getRect(find.text('#1043 · Yao'));
      final amount = tester.getRect(textPlain('10 500 F').first);
      expect(title.left, lessThan(list.left + 24));
      expect(amount.right, greaterThan(list.right - 24));
      expect(find.text('Retrait · 3 articles'), findsNWidgets(2));
      expect(textPlain('10 500 F'), findsNWidgets(2));
      expect(find.text('Nouvelle'), findsNWidgets(2));
      // Heure réelle : quelques secondes passent pendant le lancement.
      expect(find.textContaining(RegExp(r'^0[45]:\d\d$')), findsOneWidget);
      expect(find.textContaining(RegExp(r'^1[23]:\d\d$')), findsOneWidget);
      expect(find.bySemanticsLabel('Il reste 5 min'), findsOneWidget);

      await openTab(tester, 'En cours');
      // Plus récentes d'abord.
      expect(rows(tester), ['#1045 · Efua', '#1044 · Kossi']);
      expect(find.text('Acceptée'), findsOneWidget);
      expect(find.text('Prête à retirer'), findsOneWidget);
      expect(find.byType(IviaCountdown), findsNothing);

      await openTab(tester, 'Terminées');
      expect(rows(tester), ['#1047 · Kodjo', '#1046 · Abla']);
      expect(find.text('Retirée'), findsOneWidget);
      expect(find.text('Annulée'), findsOneWidget);
      expect(find.textContaining("Aujourd'hui "), findsNWidgets(2));
      semantics.dispose();
    });

    testWidgets('textes vides', (tester) async {
      await openOrders(tester);
      expect(find.text('Aucune nouvelle commande.'), findsOneWidget);
      await openTab(tester, 'En cours');
      expect(find.text('Aucune commande en cours.'), findsOneWidget);
      await openTab(tester, 'Terminées');
      expect(find.text('Aucune commande terminée.'), findsOneWidget);
      expect(find.text('Afficher plus'), findsNothing);
    });

    testWidgets('tirer vers le bas : relue ; échec : message', (tester) async {
      await openOrders(tester);
      orders.add();
      await tester.fling(
        find.text('Aucune nouvelle commande.'),
        const Offset(0, 400),
        1000,
      );
      await tester.pumpAndSettle();
      expect(rows(tester), ['#1042 · Koffi']);

      orders.failures['GET /v1/seller/orders'] = FakeResponse.networkError();
      await tester.fling(
        find.text('#1042 · Koffi'),
        const Offset(0, 400),
        1000,
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Commandes non actualisées. Vérifiez votre connexion.'),
        findsOneWidget,
      );
      expect(rows(tester), ['#1042 · Koffi']);
    });

    testWidgets('premier chargement en échec : « Réessayer »', (tester) async {
      orders.failures['GET /v1/seller/orders'] = FakeResponse.networkError();
      await launch(tester);
      // La relecture à l'ouverture de l'onglet échoue aussi.
      orders.failures['GET /v1/seller/orders'] = FakeResponse.networkError();
      await tester.tap(dockTab(Icons.receipt_long_outlined));
      await tester.pumpAndSettle();
      expect(find.textContaining('Impossible de charger'), findsOneWidget);
      orders.add();
      await tester.tap(find.text('Réessayer'));
      await tester.pumpAndSettle();
      expect(rows(tester), ['#1042 · Koffi']);
    });

    testWidgets('Terminées : « Afficher plus » ajoute la suite', (
      tester,
    ) async {
      // Au-delà de 50 Ko, dio décode la réponse dans un isolat, qui ne
      // tourne pas dans le temps simulé du test : on lui laisse du temps réel.
      Future<void> settle() async {
        for (var i = 0; i < 20; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)),
          );
          await tester.pump(const Duration(milliseconds: 100));
          if (find.byType(CircularProgressIndicator).evaluate().isEmpty &&
              i >= 2) {
            break;
          }
        }
        await tester.pumpAndSettle();
      }

      for (var i = 0; i < 103; i++) {
        orders.add(status: 'completed');
      }
      await launch(tester, settle: false);
      await settle();
      await tester.tap(dockTab(Icons.receipt_long_outlined));
      await settle();
      await openTab(tester, 'Terminées');
      expect(find.byType(OrderRow, skipOffstage: false), findsNWidgets(100));
      await tester.scrollUntilVisible(
        find.text('Afficher plus'),
        2000,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Afficher plus'));
      await settle();
      expect(lists().last.query['offset'], '100');
      expect(find.byType(OrderRow, skipOffstage: false), findsNWidgets(103));
      expect(find.text('Afficher plus', skipOffstage: false), findsNothing);

      // Relecture suivante : la suite reste affichée.
      await tester.pump(const Duration(seconds: 30));
      await settle();
      expect(find.byType(OrderRow, skipOffstage: false), findsNWidgets(103));
    });

    testWidgets('lien ?tab=active : onglet En cours', (tester) async {
      orders.add(status: 'preparing');
      await launch(tester);
      GoRouter.of(tester.element(find.byType(Scaffold).first))
          .go(Routes.ordersTab(OrderTab.active));
      await tester.pumpAndSettle();
      expect(rows(tester), ['#1042 · Koffi']);
      expect(find.text('En préparation'), findsOneWidget);
    });
  });

  /// Ouvre le détail de la commande de [buyer] depuis l'onglet [tab].
  Future<void> openOrder(
    WidgetTester tester,
    String row, {
    String tab = 'Nouvelles',
  }) async {
    await openOrders(tester);
    if (tab != 'Nouvelles') await openTab(tester, tab);
    await tester.tap(find.text(row));
    await tester.pumpAndSettle();
  }

  Iterable<RecordedRequest> posts(String id, String action) =>
      server.calls('POST', '/v1/seller/orders/$id/$action');

  Future<void> tapButton(WidgetTester tester, String label) async {
    await tester.tap(find.widgetWithText(FilledButton, label));
    await tester.pumpAndSettle();
  }

  group('détail d\'une commande', () {
    testWidgets('en-tête, compte à rebours, articles, montants', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      orders.add(paidAgo: const Duration(minutes: 2));
      await openOrder(tester, '#1042 · Koffi');

      expect(find.text('Commande #1042'), findsOneWidget);
      expect(find.text('Nouvelle'), findsOneWidget);
      expect(find.text('Pour Koffi · Retrait en boutique'), findsOneWidget);
      expect(find.textContaining('Payée à '), findsOneWidget);
      // Heure réelle : quelques secondes passent pendant le lancement.
      expect(
        find.textContaining(
          RegExp(r'^Il vous reste 1[23]:\d\d pour répondre$'),
        ),
        findsOneWidget,
      );
      expect(
        // Carte d'en-tête lue d'un bloc, temps restant à la minute près.
        find.bySemanticsLabel(RegExp('Il vous reste 1[23] min pour répondre')),
        findsOneWidget,
      );
      expect(
        find.text(
          "Sans réponse, la commande est annulée et l'acheteur remboursé.",
        ),
        findsOneWidget,
      );
      expect(find.text('3 articles'), findsOneWidget);
      expect(find.text('2 × Pagne wax'), findsOneWidget);
      expect(textPlain('9 000 F'), findsOneWidget);
      // Seul le savon est à stock non suivi.
      expect(
        find.text("Stock non suivi : vérifiez que vous l'avez."),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.text('Vous recevez'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(textPlain('10 500 F'), findsOneWidget);
      expect(textPlain('− 525 F'), findsOneWidget);
      expect(find.text('Vous recevez'), findsOneWidget);
      expect(textPlain('9 975 F'), findsOneWidget);
      // Jamais le numéro ni l'adresse de l'acheteur.
      expect(find.textContaining('+228'), findsNothing);
      expect(
        find.widgetWithText(FilledButton, 'Accepter la commande'),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('retrait : accepter, préparer, prête', (tester) async {
      final id = orders.add()['id'] as String;
      await openOrder(tester, '#1042 · Koffi');

      await tapButton(tester, 'Accepter la commande');
      expect(posts(id, 'accept'), hasLength(1));
      expect(find.text('Acceptée'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byType(IviaCountdown), findsNothing);

      await tapButton(tester, 'Commencer la préparation');
      expect(posts(id, 'preparing'), hasLength(1));
      expect(find.text('En préparation'), findsOneWidget);
      expect(
        find.text("L'acheteur sera prévenu qu'il peut venir."),
        findsOneWidget,
      );
      expect(
        find.text("Stock non suivi : vérifiez que vous l'avez."),
        findsNothing,
      );

      await tapButton(tester, 'Commande prête');
      expect(posts(id, 'ready'), hasLength(1));
      expect(find.text('Prête à retirer'), findsOneWidget);

      // La liste suit : la commande est dans « En cours », pastille retirée.
      await tester.tap(find.byType(IviaBackButton));
      await tester.pumpAndSettle();
      expect(find.text('Aucune nouvelle commande.'), findsOneWidget);
      expect(find.bySemanticsLabel('En cours, 1'), findsOneWidget);
    });

    testWidgets('livraison : prête ⇒ recherche d\'un livreur, sans action', (
      tester,
    ) async {
      orders.add(status: 'preparing', fulfillment: 'delivery');
      await openOrder(tester, '#1042 · Koffi', tab: 'En cours');
      expect(find.text('Pour Koffi · Livraison'), findsOneWidget);
      expect(find.text('Un livreur sera recherché.'), findsOneWidget);
      await tapButton(tester, 'Commande prête');
      expect(find.text('Recherche d’un livreur'), findsOneWidget);
      expect(
        find.text('La suite de la livraison est gérée par ivia.'),
        findsOneWidget,
      );
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('double appui : une seule acceptation', (tester) async {
      final id = orders.add()['id'] as String;
      await openOrder(tester, '#1042 · Koffi');
      final release = Completer<void>();
      orders.beforeRequest = (r) async {
        if (r.method == 'POST') await release.future;
      };
      final button = find.widgetWithText(FilledButton, 'Accepter la commande');
      await tester.tap(button);
      await tester.pump();
      expect(find.byType(ButtonProgress), findsOneWidget);
      await tester.tap(find.byType(FilledButton), warnIfMissed: false);
      await tester.pump();
      release.complete();
      await tester.pumpAndSettle();
      expect(posts(id, 'accept'), hasLength(1));
      expect(find.text('Acceptée'), findsOneWidget);
    });

    testWidgets('annulée entre-temps : message du serveur, vrai statut', (
      tester,
    ) async {
      final id = orders.add()['id'] as String;
      await openOrder(tester, '#1042 · Koffi');
      orders.cancel(id, "Annulée par l'acheteur.");
      await tapButton(tester, 'Accepter la commande');
      expect(
        find.text('Action impossible : la commande est « annulée ».'),
        findsOneWidget,
      );
      expect(find.text('Annulée'), findsOneWidget);
      expect(find.text("Annulée par l'acheteur."), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('réseau coupé : message, rien ne change ; nouvel essai', (
      tester,
    ) async {
      final id = orders.add()['id'] as String;
      await openOrder(tester, '#1042 · Koffi');
      orders.failures['POST /v1/seller/orders'] = FakeResponse.networkError();
      await tapButton(tester, 'Accepter la commande');
      expect(find.text('Pas de connexion. Réessayez.'), findsOneWidget);
      expect(find.text('Nouvelle'), findsOneWidget);
      await tapButton(tester, 'Accepter la commande');
      expect(posts(id, 'accept'), hasLength(2));
      expect(find.text('Acceptée'), findsOneWidget);
      expect(find.text('Pas de connexion. Réessayez.'), findsNothing);
    });

    testWidgets('délai dépassé écran ouvert : plus d\'acceptation, annulée', (
      tester,
    ) async {
      var shift = Duration.zero;
      var serverShift = Duration.zero;
      orders.now = () => DateTime.now().toUtc().add(shift);
      server.clock = () => DateTime.now().toUtc().add(serverShift);
      // 30 s de marge en heure réelle : le test reste juste sur une machine
      // lente ou lancé seul.
      orders.add(paidAgo: const Duration(minutes: 14, seconds: 30));
      await openOrder(tester, '#1042 · Koffi');
      expect(
        find.textContaining(RegExp(r'^Il vous reste 00:[0-3]\d')),
        findsOneWidget,
      );

      // L'heure du serveur (lue dans l'en-tête Date) passe le délai, avant
      // que la commande soit annulée.
      serverShift = const Duration(minutes: 1);
      await tester.fling(
        find.text('Commande #1042'),
        const Offset(0, 400),
        1000,
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('Délai dépassé'), findsOneWidget);
      final accept = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Accepter la commande'),
      );
      expect(accept.onPressed, isNull);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Refuser'),
            )
            .onPressed,
        isNull,
      );

      // Annulée par le serveur : relue au passage suivant.
      shift = const Duration(minutes: 1);
      await tester.pump(const Duration(seconds: 30));
      await tester.pumpAndSettle();
      expect(find.text('Annulée'), findsOneWidget);
      expect(find.text("Le marchand n'a pas répondu à temps."), findsOneWidget);
    });

    testWidgets('relu toutes les 30 s : annulation par l\'admin', (
      tester,
    ) async {
      final id = orders.add(status: 'accepted')['id'] as String;
      await openOrder(tester, '#1042 · Koffi', tab: 'En cours');
      orders.cancel(id, "Annulée par l'équipe ivia.");
      await tester.pump(const Duration(seconds: 30));
      await tester.pumpAndSettle();
      expect(find.text('Annulée'), findsOneWidget);
    });

    testWidgets('réponse en retard : ne défait pas une action', (tester) async {
      final id = orders.add()['id'] as String;
      await openOrder(tester, '#1042 · Koffi');
      final stale = Map<String, dynamic>.of(orders.byId(id));
      await tapButton(tester, 'Accepter la commande');
      // Relecture partie avant l'acceptation, arrivée après.
      orders.failures['GET /v1/seller/orders/$id'] = FakeResponse.json(
        200,
        stale,
      );
      await tester.pump(const Duration(seconds: 30));
      await tester.pumpAndSettle();
      expect(find.text('Acceptée'), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'Commencer la préparation'),
        findsOneWidget,
      );
    });

    testWidgets('commande disparue pendant une action : retour à la liste', (
      tester,
    ) async {
      orders.add();
      await openOrder(tester, '#1042 · Koffi');
      orders.failures['POST /v1/seller/orders'] = FakeResponse.error(
        404,
        'order_not_found',
        'Commande introuvable.',
      );
      await tapButton(tester, 'Accepter la commande');
      expect(find.text('Commande introuvable.'), findsOneWidget);
      expect(find.text('Commande #1042'), findsNothing);
      expect(find.byType(OrderRow), findsWidgets);
    });

    testWidgets('commande introuvable : message, retour à la liste', (
      tester,
    ) async {
      await launch(tester);
      GoRouter.of(tester.element(find.byType(Scaffold).first))
          .go(Routes.order('c0000000-0000-4000-8000-000000000999'));
      await tester.pumpAndSettle();
      expect(find.text('Commande introuvable.'), findsOneWidget);
      await tester.tap(find.text('Voir les commandes'));
      await tester.pumpAndSettle();
      expect(find.text('Aucune nouvelle commande.'), findsOneWidget);
    });

    testWidgets('boutique suspendue pendant une action : écran « suspendue »', (
      tester,
    ) async {
      orders.add();
      await openOrder(tester, '#1042 · Koffi');
      orders.shopSuspended = true;
      withShop('suspended');
      await tapButton(tester, 'Accepter la commande');
      expect(find.textContaining('suspendue'), findsWidgets);
      expect(find.text('Commande #1042'), findsNothing);
    });
  });

  group('refus', () {
    Finder confirm() =>
        find.widgetWithText(FilledButton, 'Refuser la commande');

    Future<void> openSheet(WidgetTester tester) async {
      await tester.tap(find.widgetWithText(OutlinedButton, 'Refuser'));
      await tester.pumpAndSettle();
    }

    testWidgets('motif proposé : envoyé, commande annulée avec le motif', (
      tester,
    ) async {
      final id = orders.add()['id'] as String;
      await openOrder(tester, '#1042 · Koffi');
      await openSheet(tester);
      expect(find.text('Pourquoi refusez-vous ?'), findsOneWidget);
      expect(
        find.text("L'acheteur verra ce motif et sera remboursé."),
        findsOneWidget,
      );
      expect(tester.widget<FilledButton>(confirm()).onPressed, isNull);

      await tester.tap(find.text('Boutique fermée'));
      await tester.pumpAndSettle();
      await tester.tap(confirm());
      await tester.pumpAndSettle();
      expect(posts(id, 'reject').single.body, {'reason': 'Boutique fermée'});
      expect(find.text('Annulée'), findsOneWidget);
      expect(find.text('Boutique fermée'), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
      expect(find.byType(IviaCountdown), findsNothing);
    });

    testWidgets('« Autre » : texte exigé, nettoyé, 200 caractères au plus', (
      tester,
    ) async {
      final id = orders.add()['id'] as String;
      await openOrder(tester, '#1042 · Koffi');
      await openSheet(tester);
      await tester.tap(find.text('Autre'));
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(confirm()).onPressed, isNull);

      await tester.enterText(find.byType(TextField), '   ');
      await tester.pump();
      expect(tester.widget<FilledButton>(confirm()).onPressed, isNull);

      await tester.enterText(find.byType(TextField), 'x' * 250);
      await tester.pump();
      await tester.enterText(find.byType(TextField), '  Client injoignable  ');
      await tester.pump();
      await tester.tap(confirm());
      await tester.pumpAndSettle();
      expect(posts(id, 'reject').single.body, {'reason': 'Client injoignable'});
      expect(find.text('Client injoignable'), findsOneWidget);
    });

    testWidgets('« Autre » trop long : coupé à 200 caractères', (tester) async {
      final id = orders.add()['id'] as String;
      await openOrder(tester, '#1042 · Koffi');
      await openSheet(tester);
      await tester.tap(find.text('Autre'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'x' * 250);
      await tester.pump();
      await tester.tap(confirm());
      await tester.pumpAndSettle();
      final reason = (posts(id, 'reject').single.body! as Map)['reason'];
      expect(reason, 'x' * 200);
    });

    testWidgets('« Annuler » : rien n\'est envoyé', (tester) async {
      final id = orders.add()['id'] as String;
      await openOrder(tester, '#1042 · Koffi');
      await openSheet(tester);
      await tester.tap(find.text('Produit en rupture'));
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(posts(id, 'reject'), isEmpty);
      expect(find.text('Nouvelle'), findsOneWidget);
    });

    testWidgets('refus en échec réseau : message, commande inchangée', (
      tester,
    ) async {
      orders.add();
      await openOrder(tester, '#1042 · Koffi');
      orders.failures['POST /v1/seller/orders'] = FakeResponse.networkError();
      await openSheet(tester);
      await tester.tap(find.text('Produit en rupture'));
      await tester.pumpAndSettle();
      await tester.tap(confirm());
      await tester.pumpAndSettle();
      expect(find.text('Pas de connexion. Réessayez.'), findsOneWidget);
      expect(find.text('Nouvelle'), findsOneWidget);
    });
  });

  group('remise par code', () {
    Finder codeField() => find.descendant(
      of: find.byType(IviaCodeInput),
      matching: find.byType(TextField),
    );
    Finder handOver() =>
        find.widgetWithText(FilledButton, 'Remettre la commande');

    Future<String> openHandover(WidgetTester tester, {int attempts = 0}) async {
      final id =
          orders.add(
                status: 'ready_for_pickup',
                handoverAttempts: attempts,
              )['id']
              as String;
      await openOrder(tester, '#1042 · Koffi', tab: 'En cours');
      await tapButton(tester, "Saisir le code de l'acheteur");
      return id;
    }

    Future<void> submit(WidgetTester tester, String code) async {
      await tester.enterText(codeField(), code);
      await tester.pump();
      await tester.tap(handOver());
      await tester.pumpAndSettle();
    }

    testWidgets('code juste : « Retirée », retour au détail', (tester) async {
      final id = await openHandover(tester);
      expect(find.text('Code de remise'), findsOneWidget);
      expect(
        find.text('Demandez à Koffi son code à 4 chiffres.'),
        findsOneWidget,
      );
      expect(tester.widget<FilledButton>(handOver()).onPressed, isNull);

      await submit(tester, FakeSellerOrders.handoverCode);
      expect(posts(id, 'handover').single.body, {
        'code': FakeSellerOrders.handoverCode,
      });
      expect(find.text('Commande remise.'), findsOneWidget);
      expect(find.text('Commande #1042'), findsOneWidget);
      expect(find.text('Retirée'), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('code faux : essais restants, cases vidées, puis juste', (
      tester,
    ) async {
      await openHandover(tester);
      await submit(tester, '1111');
      expect(find.text('Code incorrect. Il reste 4 essai(s).'), findsOneWidget);
      expect(tester.widget<TextField>(codeField()).controller!.text, isEmpty);
      expect(tester.widget<FilledButton>(handOver()).onPressed, isNull);

      await submit(tester, FakeSellerOrders.handoverCode);
      expect(find.text('Retirée'), findsOneWidget);
    });

    testWidgets('5e essai faux : code bloqué, plus de saisie ni au détail', (
      tester,
    ) async {
      await openHandover(tester, attempts: 4);
      await submit(tester, '1111');
      expect(find.text(handoverLockedMessage), findsOneWidget);
      expect(find.byType(IviaCodeInput), findsNothing);
      expect(handOver(), findsNothing);

      await tester.tap(find.byType(IviaBackButton));
      await tester.pumpAndSettle();
      expect(find.text('Prête à retirer'), findsOneWidget);
      expect(find.text(handoverLockedMessage), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('code déjà bloqué : le détail ne propose pas la saisie', (
      tester,
    ) async {
      orders.add(status: 'ready_for_pickup', handoverAttempts: 5);
      await openOrder(tester, '#1042 · Koffi', tab: 'En cours');
      expect(find.text(handoverLockedMessage), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('annulée pendant la saisie : retour au détail, vrai statut', (
      tester,
    ) async {
      final id = await openHandover(tester);
      orders.cancel(id, "Annulée par l'équipe ivia.");
      await submit(tester, FakeSellerOrders.handoverCode);
      expect(
        find.text('Action impossible : la commande est « annulée ».'),
        findsOneWidget,
      );
      expect(find.text('Code de remise'), findsNothing);
      expect(find.text('Annulée'), findsOneWidget);
    });

    testWidgets('code collé avec espaces : chiffres seuls gardés', (
      tester,
    ) async {
      final id = await openHandover(tester);
      await submit(tester, '48 27');
      expect(posts(id, 'handover').single.body, {'code': '4827'});
    });

    testWidgets('réseau coupé : message, cases vidées, rien de compté', (
      tester,
    ) async {
      final id = await openHandover(tester);
      orders.failures['POST /v1/seller/orders'] = FakeResponse.networkError();
      await submit(tester, FakeSellerOrders.handoverCode);
      expect(find.text('Pas de connexion. Réessayez.'), findsOneWidget);
      expect(tester.widget<TextField>(codeField()).controller!.text, isEmpty);
      expect(orders.byId(id)['handover_attempts'], 0);
    });
  });

  group('Accueil (pilotage)', () {
    testWidgets('nouvelles d\'abord (plus urgente), puis à traiter', (
      tester,
    ) async {
      orders
        ..add(paidAgo: const Duration(minutes: 3))
        ..add(paidAgo: const Duration(minutes: 9))
        ..add(status: 'accepted');
      await launch(tester);
      expect(find.text('Chez Afi'), findsOneWidget);
      expect(find.text('Ventes du jour'), findsOneWidget);
      expect(find.text('NOUVELLE COMMANDE PAYÉE'), findsNWidgets(2));
      // Payée il y a 9 min : 6 min restantes, en tête.
      final first = tester.getTopLeft(find.text('#1043 · Koffi')).dy;
      final second = tester.getTopLeft(find.text('#1042 · Koffi')).dy;
      expect(first, lessThan(second));
      expect(find.textContaining(RegExp(r'^0[56]:\d\d$')), findsOneWidget);

      await scrollHomeTo(tester, '#1044 · Koffi');
      expect(find.text('À traiter'), findsOneWidget);
      await tapText(tester, 'Tout voir');
      expect(rows(tester), ['#1044 · Koffi']);

      await tester.tap(dockTab(Icons.space_dashboard_outlined));
      await tester.pumpAndSettle();
      // Liste restée défilée : retour à la carte la plus urgente.
      await tester.ensureVisible(find.text('#1043 · Koffi'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('#1043 · Koffi'));
      await tester.pumpAndSettle();
      expect(find.text('Commande #1043'), findsOneWidget);
    });

    testWidgets('« Tout voir » après un sous-onglet choisi à la main', (
      tester,
    ) async {
      orders
        ..add()
        ..add(status: 'accepted', buyerFirstName: 'Kossi');
      await launch(tester);
      await tester.tap(dockTab(Icons.receipt_long_outlined));
      await tester.pumpAndSettle();
      await openTab(tester, 'Nouvelles');
      expect(rows(tester), ['#1042 · Koffi']);
      await tester.tap(dockTab(Icons.space_dashboard_outlined));
      await tester.pumpAndSettle();
      await tapText(tester, 'Tout voir');
      expect(rows(tester), ['#1043 · Kossi']);
    });

    testWidgets(
      'plus de 3 nouvelles : bouton vers l\'onglet ; prêtes comptées',
      (tester) async {
        for (var i = 0; i < 4; i++) {
          orders.add();
        }
        orders
          ..add(status: 'preparing')
          ..add(status: 'ready_for_pickup');
        await launch(tester);
        expect(find.text('NOUVELLE COMMANDE PAYÉE'), findsNWidgets(3));
        await scrollHomeTo(tester, 'À traiter · 1 prête');
        await tapText(tester, 'Voir les 4 commandes à accepter');
        expect(rows(tester), hasLength(4));
      },
    );

    testWidgets('« Accepter » sur l\'Accueil, puis « Préparer »', (
      tester,
    ) async {
      orders.add();
      await launch(tester);
      await tapText(tester, 'Accepter');
      expect(find.text('Commande #1042 acceptée'), findsOneWidget);
      expect(find.text('NOUVELLE COMMANDE PAYÉE'), findsNothing);
      await tapText(tester, 'Préparer');
      expect(find.text('Préparation de #1042 commencée'), findsOneWidget);
      expect(find.text('Prête ?'), findsOneWidget);
    });

    testWidgets('rien à traiter (terminées seulement)', (tester) async {
      orders.add(status: 'completed');
      await launch(tester);
      expect(find.text('Tout est à jour'), findsOneWidget);
      expect(find.text('NOUVELLE COMMANDE PAYÉE'), findsNothing);
      await tapText(tester, 'Gérer mon catalogue');
      expect(find.text('Produits'), findsWidgets);
    });

    testWidgets('mis à jour par la relecture toutes les 30 s', (tester) async {
      await launch(tester);
      expect(find.text('Tout est à jour'), findsOneWidget);
      orders.add();
      await tester.pump(const Duration(seconds: 30));
      await tester.pumpAndSettle();
      expect(find.text('NOUVELLE COMMANDE PAYÉE'), findsOneWidget);
    });
  });

  group('police à 200 % sur 320 dp', () {
    void large(WidgetTester tester) {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }

    testWidgets('Accueil, liste, détail, refus : rien ne déborde', (
      tester,
    ) async {
      large(tester);
      orders
        ..add(
          buyerFirstName: 'Abla-Kossiwa',
          paidAgo: const Duration(minutes: 1),
        )
        ..add(status: 'ready_for_pickup');
      await launch(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('NOUVELLE COMMANDE PAYÉE'), findsOneWidget);

      await tester.tap(dockTab(Icons.receipt_long_outlined));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(OrderRow), findsOneWidget);

      await tester.tap(find.text('#1042 · Abla-Kossiwa'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.text('Vous recevez'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.takeException(), isNull);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Refuser'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Autre'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('détail prêt et code de remise : rien ne déborde', (
      tester,
    ) async {
      large(tester);
      orders.add(status: 'ready_for_pickup');
      await launch(tester);
      await tester.tap(dockTab(Icons.receipt_long_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('En cours').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('#1042 · Koffi'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tapButton(tester, "Saisir le code de l'acheteur");
      expect(tester.takeException(), isNull);
      await tester.enterText(
        find.descendant(
          of: find.byType(IviaCodeInput),
          matching: find.byType(TextField),
        ),
        '1111',
      );
      await tester.pump();
      await tester.tap(
        find.widgetWithText(FilledButton, 'Remettre la commande'),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        find.text('Code incorrect. Il reste 4 essai(s).', skipOffstage: false),
        findsOneWidget,
      );
    });

    testWidgets('lecteur d\'écran : ligne lue d\'un bloc, bouton', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      orders.add();
      await launch(tester);
      await tester.tap(dockTab(Icons.receipt_long_outlined));
      await tester.pumpAndSettle();
      final row = tester.getSemantics(find.byType(OrderRow));
      expect(
        row.label,
        allOf(
          contains('Commande 1042, Koffi, Retrait · 3 articles'),
          contains('Nouvelle'),
        ),
      );
      expect(row, isSemantics(isButton: true));
      semantics.dispose();
    });
  });
}

class _NoPicker implements PhotoPicker {
  @override
  Future<Uint8List?> pick({
    PhotoSource source = PhotoSource.gallery,
    int maxSide = 1024,
  }) async => null;
}
