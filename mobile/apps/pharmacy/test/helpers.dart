import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_api_client/testing.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_app_core/testing.dart';
import 'package:ivia_pharmacy/main.dart';
import 'package:ivia_ui/ivia_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Titre de l'écran de localisation de la pharmacie (spec 030).
const locationTitle = 'Les alertes de votre quartier';

/// App pharmacie branchée sur un serveur factice.
class PharmacyHarness {
  PharmacyHarness({LocationAccess location = LocationAccess.askable})
    : location = FakeLocationService(state: location);

  final server = FakeApiServer();
  final FakeLocationService location;
  final picker = FakePicker();

  /// Envoi de fichiers : URL signée puis dépôt.
  void acceptUploads() => server
    ..on(
      'POST',
      '/v1/uploads',
      (_) => FakeResponse.json(201, {
        'object_key': 'pharmacy_document/u1/piece.jpg',
        'upload': {
          'method': 'PUT',
          'url': 'https://stockage.test/pharmacy_document/u1/piece.jpg?sig=x',
          'headers': {'Content-Type': 'image/jpeg'},
          'expires_at': '2026-11-06T10:05:00Z',
        },
      }),
    )
    ..on(
      'PUT',
      '/pharmacy_document/u1/piece.jpg',
      (_) => FakeResponse.json(200, null),
    )
    ..on(
      'POST',
      '/v1/pharmacy/me/documents',
      (_) => FakeResponse.json(201, {}),
    );

  /// Réglages du téléphone et session vides (à appeler dans `setUp`).
  static void resetDevice({Map<String, Object> prefs = const {}}) {
    SharedPreferences.setMockInitialValues(prefs);
    FlutterSecureStorage.setMockInitialValues({});
  }

  /// Compte connecté, profil complet, écran de localisation déjà passé.
  Future<void> signIn() async {
    SharedPreferences.setMockInitialValues({
      'location_prompt_done': true,
      'onboarding_seen': true,
    });
    await SessionStore().save(
      'jeton-secret',
      User.fromJson(userBody(complete: true)),
    );
    server.on(
      'GET',
      '/v1/me',
      (_) => FakeResponse.json(200, userBody(complete: true)),
    );
  }

  Future<void> launch(WidgetTester tester) async {
    final locationPrompt = await LocationPromptStore.open(location);
    final onboarding = await OnboardingStore.open();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appIdentityProvider.overrideWithValue(pharmacyIdentity),
          locationServiceProvider.overrideWithValue(location),
          photoPickerProvider.overrideWithValue(picker),
          locationPromptStoreProvider.overrideWithValue(locationPrompt),
          onboardingStoreProvider.overrideWithValue(onboarding),
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
        ],
        child: const PharmacyApp(),
      ),
    );
    await tester.pumpAndSettle();
  }
}

/// Touche un texte, en faisant défiler la liste s'il le faut.
Future<void> tapText(WidgetTester tester, String text) async {
  final target = find.text(text);
  // Liste longue : l'élément n'est construit qu'en s'en approchant.
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      target,
      200,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

/// Photo choisie par le faux sélecteur ; `null` : choix annulé.
class FakePicker implements PhotoPicker {
  /// PNG de 1 pixel : l'aperçu se décode.
  Uint8List? next = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
  );

  @override
  Future<Uint8List?> pick({
    PhotoSource source = PhotoSource.gallery,
    int maxSide = 1024,
  }) async => next;
}

/// Pharmacie type (schéma `PharmacyProfile`).
Map<String, dynamic> pharmacyBody({
  String status = 'draft',
  String note = '',
  List<String> documents = const [],
  List<String>? missing,
  bool payout = false,
  bool isOpen = true,
  bool onDuty = false,
  bool open24h = false,
  bool suspended = false,
}) => {
  'id': '5b1f3c2e-8a4d-4e6f-9b7a-1c2d3e4f5a6b',
  'name': 'Pharmacie du Boulevard',
  'license_number': 'AE-2019-0412',
  'phone': '+22822214567',
  'email': 'contact@boulevard.tg',
  'night_from_hour': 20,
  'night_to_hour': 8,
  'address_text': 'Bd du 13 Janvier, Tokoin',
  'opening_hours': 'Lun-Sam 8 h - 21 h',
  'is_open': isOpen,
  'on_duty': onDuty,
  'open_24h': open24h,
  'duty_until': null,
  'review_status': status,
  'review_note': note,
  'suspended_at': suspended ? '2026-11-05T10:00:00Z' : null,
  'neighborhood_id': null,
  'location': {'lat': 6.1375, 'lng': 1.2123},
  'payout': payout
      ? {'phone_masked': '+228 90 •• •• 33', 'holder': 'K. Mensah'}
      : null,
  'documents': [
    for (final d in documents) {'kind': d},
  ],
  'missing_documents':
      missing ??
      [
        for (final k in [
          'opening_authorization',
          'owner_id',
          'storefront_photo',
        ])
          if (!documents.contains(k)) k,
      ],
};

/// Champ de saisie sous un libellé.
Finder fieldOf(String label) => find.descendant(
  of: find.ancestor(
    of: find.text(label),
    matching: find.byType(IviaFieldLabel),
  ),
  matching: find.byType(TextField),
);

/// Alerte reçue type (schéma `PharmacyInboxItem`), à [endsIn] de la fin.
Map<String, dynamic> alertBody({
  String id = 'a1',
  bool seen = false,
  bool responded = false,
  bool unlocked = false,
  String status = 'pending',
  Duration endsIn = const Duration(minutes: 18, seconds: 42),
  Duration receivedAgo = Duration.zero,
  List<Map<String, dynamic>>? items,
  List<Map<String, dynamic>> photos = const [],
  bool generic = true,
  String note = '',
}) {
  final now = DateTime.now().toUtc();
  return {
    'alert_id': id,
    'items':
        items ??
        [
          {
            'id': 'i1',
            'name': 'Paracétamol 1000 mg',
            'form': 'Comprimés · boîte',
            'quantity': 1,
          },
          {
            'id': 'i2',
            'name': 'Amoxicilline 500 mg',
            'form': 'Gélules · boîte',
            'quantity': 2,
          },
        ],
    'photos': photos,
    'photo_count': photos.length,
    'note': note,
    'generic_accepted': generic,
    'distance_m': 650,
    'status': status,
    'alert_status': 'searching',
    'search_ends_at': now.add(endsIn).toIso8601String(),
    'seen': seen,
    'received_at': now.subtract(receivedAgo).toIso8601String(),
    'my_response': responded
        ? {'total_xof': 7450, 'unlocked': unlocked, 'lines': <Object>[]}
        : null,
  };
}

/// Réservation type (schéma `PharmacyReservation`).
Map<String, dynamic> orderBody({
  String id = 'o1',
  String status = 'reserved',
  bool delivery = false,
  bool prepared = false,
  Map<String, dynamic>? courier,
  Duration expiresIn = const Duration(minutes: 55),
}) {
  final now = DateTime.now().toUtc();
  return {
    'id': id,
    'number': 'M-208',
    'fulfillment': delivery ? 'delivery' : 'pickup',
    'status': status,
    'lines': [
      {
        'name': 'Paracétamol 1000 mg',
        'quantity': 1,
        'unit_price_xof': 1250,
        'line_total_xof': 1250,
        'available': true,
        'prescription_required': false,
      },
      {
        'name': 'Amoxicilline Denk 500 mg',
        'quantity': 2,
        'unit_price_xof': 3100,
        'line_total_xof': 6200,
        'available': true,
        'prescription_required': true,
      },
    ],
    'items_xof': 7450,
    'pharmacy_due_xof': 7450,
    'prescription_required': true,
    'buyer_first_name': 'Afi',
    'expires_at': now.add(expiresIn).toIso8601String(),
    'prepared_at': prepared ? now.toIso8601String() : null,
    'cancel_reason': '',
    'courier': courier,
    'created_at': now.subtract(const Duration(minutes: 5)).toIso8601String(),
    'completed_at': null,
  };
}

extension ApprovedPharmacy on PharmacyHarness {
  /// Pharmacie validée, ouverte, avec ses alertes et ses réservations.
  Future<void> signInApproved({
    Map<String, dynamic> Function()? profile,
    List<Map<String, dynamic>> Function()? inbox,
    List<Map<String, dynamic>> Function()? orders,
  }) async {
    await signIn();
    server
      ..on(
        'GET',
        '/v1/pharmacy/me',
        (_) => FakeResponse.json(
          200,
          profile?.call() ??
              pharmacyBody(
                status: 'approved',
                payout: true,
                documents: [
                  'opening_authorization',
                  'owner_id',
                  'storefront_photo',
                ],
              ),
        ),
      )
      ..on(
        'GET',
        '/v1/pharmacy/inbox',
        (_) => FakeResponse.json(200, {'items': inbox?.call() ?? <Object>[]}),
      )
      ..on(
        'GET',
        '/v1/pharmacy/reservations',
        (_) => FakeResponse.json(200, {'items': orders?.call() ?? <Object>[]}),
      )
      ..on(
        'GET',
        '/v1/pharmacy/me/duty-shifts',
        (_) => FakeResponse.json(200, {'items': <Object>[]}),
      )
      ..on(
        'GET',
        '/v1/pharmacy/earnings',
        (_) => FakeResponse.json(200, {
          'due_xof': 0,
          'paid_out_xof': 0,
          'balance_xof': 0,
          'delivered_count': 0,
          'pickup_count': 0,
          'payouts': <Object>[],
        }),
      );
  }
}
