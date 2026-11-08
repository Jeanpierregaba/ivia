// Captures des écrans à 360 dp, au double (720 px comme les maquettes D00 à
// D19), avec les vraies polices. Outil de vérification visuelle (spec 033) :
//   flutter test tool/shots_test.dart --update-goldens
// Les images vont dans tool/shots/ (non versionné).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_api_client/testing.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_driver/app/driver_dossier.dart';
import 'package:ivia_driver/app/identity.dart';
import 'package:ivia_driver/features/dossier/dossier_form_screen.dart';
import 'package:ivia_driver/features/dossier/dossier_pending_screen.dart';
import 'package:ivia_driver/features/work/work_screens.dart';
import 'package:ivia_driver/features/work/work_state.dart';
import 'package:ivia_driver/features/onboarding/onboarding_screen.dart';
import 'package:ivia_driver/features/splash/loading_screen.dart';
import 'package:ivia_ui/ivia_ui.dart';

Future<void> _font(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final f in files) {
    loader.addFont(File(f).readAsBytes().then((b) => ByteData.view(b.buffer)));
  }
  await loader.load();
}

Future<void> loadFonts() async {
  const ui = '../../packages/ui/fonts';
  await _font('packages/ivia_ui/Parkinsans', [
    '$ui/Parkinsans-Regular.ttf',
    '$ui/Parkinsans-SemiBold.ttf',
    '$ui/Parkinsans-Bold.ttf',
  ]);
  // flutter_tester est dans <sdk>/bin/cache/artifacts/engine/<plateforme>/.
  final cache = File(Platform.resolvedExecutable).parent.parent.parent.path;
  await _font('MaterialIcons', [
    '$cache/material_fonts/MaterialIcons-Regular.otf',
  ]);
}

Future<void> shot(
  WidgetTester tester,
  String name,
  Widget screen, {
  Future<void> Function(WidgetTester)? before,
  List overrides = const [],
}) async {
  tester.view.physicalSize = const Size(720, 1560);
  tester.view.devicePixelRatio = 2;
  // Barre d'état des maquettes : 40 dp en haut.
  tester.view.padding = const FakeViewPadding(top: 80);
  tester.view.viewPadding = const FakeViewPadding(top: 80);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appIdentityProvider.overrideWithValue(driverIdentity),
        ...overrides,
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: IviaTheme.light(IviaAppBrand.driver),
        home: screen,
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 500));
  if (before != null) await before(tester);
  // Images d'assets (logotype) : chargées hors du temps simulé.
  await tester.runAsync(() async {
    for (final e in find.byType(Image).evaluate()) {
      await precacheImage((e.widget as Image).image, e);
    }
  });
  await tester.pump();
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('shots/$name.png'),
  );
}

/// Livreur connecté, profil complet (« Kossi Adjo »).
class _SignedIn extends AuthController {
  @override
  AuthState build() => AuthSignedIn(
    User.fromJson({
      ...userBody(complete: true),
      'first_name': 'Kossi',
      'last_name': 'Adjo',
      'phone': '+22890556677',
    }),
  );
}

/// Pas encore de dossier.
class _NoDossier extends DriverDossierNotifier {
  @override
  Future<DriverDossier?> build() async => null;
}

/// Dossier envoyé, en vérification (moto, 4 pièces).
class _PendingDossier extends DriverDossierNotifier {
  @override
  Future<DriverDossier?> build() async => DriverDossier.fromJson(
    driverBody(documents: driverRequiredDocuments('motorbike')),
  );
}

/// Faux serveur des écrans connectés.
FakeApiServer fakeServer() {
  final now = DateTime.now().toUtc();
  // Cinq livraisons aujourd'hui (12 400 F, comme la maquette D08).
  final fees = [3200, 2400, 2800, 2000, 2000];
  return FakeApiServer()
    ..on(
      'GET',
      '/v1/driver/options',
      (_) => FakeResponse.json(200, driverOptionsBody()),
    )
    ..on(
      'GET',
      '/v1/driver/missions/current',
      (_) => FakeResponse.json(200, {'mission': null}),
    )
    ..on(
      'GET',
      '/v1/driver/pharmacy-missions/current',
      (_) => FakeResponse.json(200, {'mission': null}),
    )
    ..on(
      'GET',
      '/v1/driver/missions',
      (_) => FakeResponse.json(200, {
        'items': [
          for (final (i, fee) in fees.indexed)
            {
              'id': 'm$i',
              'order_reference': '#104$i',
              'status': 'delivered',
              'fee_xof': fee,
              'items_count': 1,
              'parcel_size': 'medium',
              'shop': {'name': 'Chez Afi'},
              'customer': null,
              'assigned_at': now.toIso8601String(),
              'delivered_at': now.toIso8601String(),
            },
        ],
        'next_offset': null,
      }),
    )
    ..on(
      'GET',
      '/v1/driver/pharmacy-missions',
      (_) => FakeResponse.json(200, {'items': [], 'next_offset': null}),
    );
}

/// Livreur validé.
class _ApprovedDossier extends DriverDossierNotifier {
  @override
  Future<DriverDossier?> build() async =>
      DriverDossier.fromJson(driverBody(review: 'approved', status: 'offline'));
}

List signedIn({DriverDossierNotifier Function() dossier = _NoDossier.new}) => [
  authControllerProvider.overrideWith(_SignedIn.new),
  driverDossierProvider.overrideWith(dossier),
  apiClientProvider.overrideWithValue(
    IviaApiClient(
      config: ApiConfig(baseUrl: Uri.parse('http://api.test')),
      adapter: fakeServer(),
    ),
  ),
];

/// Code demandé, pour l'écran du code (D05).
class _SentCode extends PhoneLoginFlow {
  @override
  PhoneLoginState? build() => const PhoneLoginState(
    phone: '+22890000102',
    channel: OtpChannel.whatsapp,
    resendAfter: Duration(seconds: 42),
    expiresIn: Duration(minutes: 10),
    attempt: 1,
  );
}

/// En ligne depuis 1 h 12 (D09).
class _Online extends WorkController {
  @override
  WorkState build() => WorkState(
    online: true,
    onlineSince: DateTime.now().subtract(const Duration(minutes: 72)),
  );
}

/// Proposition reçue (D10), 31 s restantes.
class _Offered extends WorkController {
  @override
  WorkState build() => WorkState(
    online: true,
    onlineSince: DateTime.now(),
    offer: WorkOffer.shop(
      driverOfferBody(
        expiresIn: const Duration(seconds: 31, milliseconds: 500),
      ),
    ),
  );
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // Cache des tuiles de la carte (D09) : dossier temporaire.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => Directory.systemTemp.path,
        );
    await loadFonts();
  });

  testWidgets(
    'D10',
    (t) => shot(
      t,
      'D10',
      const DriverShell(),
      overrides: [
        ...signedIn(dossier: _ApprovedDossier.new),
        workProvider.overrideWith(_Offered.new),
      ],
      before: (t) => t.pump(const Duration(milliseconds: 500)),
    ),
  );

  testWidgets(
    'D09',
    (t) => shot(
      t,
      'D09',
      const DriverShell(),
      overrides: [
        ...signedIn(dossier: _ApprovedDossier.new),
        workProvider.overrideWith(_Online.new),
      ],
      before: (t) async {
        await t.pump(const Duration(milliseconds: 500));
        await t.pump(const Duration(milliseconds: 500));
      },
    ),
  );

  testWidgets(
    'D08',
    (t) => shot(
      t,
      'D08',
      const DriverShell(),
      overrides: signedIn(dossier: _ApprovedDossier.new),
      before: (t) async {
        await t.pump(const Duration(milliseconds: 500));
        await t.pump(const Duration(milliseconds: 500));
      },
    ),
  );

  testWidgets(
    'D07',
    (t) => shot(
      t,
      'D07',
      const DossierPendingScreen(),
      overrides: signedIn(dossier: _PendingDossier.new),
      before: (t) => t.pump(const Duration(milliseconds: 300)),
    ),
  );

  testWidgets(
    'D06',
    (t) => shot(
      t,
      'D06',
      const DossierFormScreen(),
      overrides: signedIn(),
      before: (t) async {
        await t.pumpAndSettle();
        await t.enterText(find.byType(TextField).first, 'TG 4521 AB');
        await t.pump();
      },
    ),
  );

  testWidgets(
    'D04',
    (t) => shot(
      t,
      'D04',
      const PhoneScreen(),
      before: (t) async {
        await t.enterText(find.byType(TextField), '90000102');
        await t.pump();
      },
    ),
  );
  testWidgets(
    'D05',
    (t) => shot(
      t,
      'D05',
      const PhoneCodeScreen(),
      overrides: [phoneLoginFlowProvider.overrideWith(_SentCode.new)],
      before: (t) async {
        await t.enterText(find.byType(TextField), '2905');
        await t.pump();
      },
    ),
  );

  testWidgets('D00', (t) => shot(t, 'D00', const LoadingScreen()));
  for (final page in [0, 1, 2]) {
    testWidgets(
      'D0${page + 1}',
      (t) => shot(
        t,
        'D0${page + 1}',
        const OnboardingScreen(),
        before: (t) async {
          for (var i = 0; i < page; i++) {
            await t.tap(find.text('Suivant'));
            await t.pumpAndSettle();
          }
        },
      ),
    );
  }
}
