import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

class _FakePicker implements PhotoPicker {
  Uint8List? next = Uint8List.fromList([1, 2, 3]);
  Exception? error;
  final calls = <(PhotoSource, int)>[];

  @override
  Future<Uint8List?> pick({
    PhotoSource source = PhotoSource.gallery,
    int maxSide = 1024,
  }) async {
    calls.add((source, maxSide));
    if (error case final e?) throw e;
    return next;
  }
}

void main() {
  late _FakePicker picker;
  late List<Uint8List> picked;

  setUp(() {
    picker = _FakePicker();
    picked = [];
  });

  Future<void> pump(
    WidgetTester tester, {
    Uint8List? photo,
    bool alreadySent = false,
    bool enabled = true,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [photoPickerProvider.overrideWithValue(picker)],
        child: MaterialApp(
          theme: IviaTheme.light(IviaAppBrand.seller),
          home: Scaffold(
            body: SingleChildScrollView(
              child: DocumentPhotoRow(
                label: "Pièce d'identité",
                tag: 'Obligatoire',
                hint: 'Face avec la photo',
                pickedLabel: 'Ajoutée',
                sentLabel: 'Envoyée',
                photo: photo,
                alreadySent: alreadySent,
                enabled: enabled,
                onPicked: picked.add,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> choose(WidgetTester tester, String source) async {
    await tester.tap(find.text("Pièce d'identité"));
    await tester.pumpAndSettle();
    await tester.tap(find.text(source));
    await tester.pumpAndSettle();
  }

  testWidgets('états : Ajouter, Ajoutée, Envoyée ; mention et précision', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('Ajouter'), findsOneWidget);
    expect(find.text('Obligatoire'), findsOneWidget);
    expect(find.text('Face avec la photo'), findsOneWidget);

    await pump(tester, alreadySent: true);
    expect(find.text('Envoyée'), findsOneWidget);

    // Photo choisie : à envoyer, même si une pièce est déjà reçue.
    await pump(tester, photo: Uint8List(1), alreadySent: true);
    expect(find.text('Ajoutée'), findsOneWidget);
  });

  testWidgets('lecteur d\'écran : un seul bouton qui dit tout', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(tester);
    expect(
      find.bySemanticsLabel(
        "Pièce d'identité, Obligatoire, Face avec la photo, Ajouter",
      ),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('appareil photo : photo réduite à 2048 px, transmise', (
    tester,
  ) async {
    await pump(tester);
    await choose(tester, 'Prendre une photo');
    expect(picker.calls.single, (PhotoSource.camera, 2048));
    expect(picked.single, [1, 2, 3]);
  });

  testWidgets('galerie, puis annulation du choix : rien de transmis', (
    tester,
  ) async {
    picker.next = null;
    await pump(tester);
    await choose(tester, 'Choisir une photo');
    expect(picker.calls.single.$1, PhotoSource.gallery);
    expect(picked, isEmpty);
  });

  testWidgets('photo trop lourde : refusée, message', (tester) async {
    picker.next = Uint8List(maxUploadBytes + 1);
    await pump(tester);
    await choose(tester, 'Choisir une photo');
    expect(picked, isEmpty);
    expect(find.text('Photo trop lourde (5 Mo au plus).'), findsOneWidget);

    // Photo valable ensuite : message retiré.
    picker.next = Uint8List(4);
    await choose(tester, 'Choisir une photo');
    expect(picked, hasLength(1));
    expect(find.textContaining('trop lourde'), findsNothing);
  });

  testWidgets('autorisation refusée : message', (tester) async {
    picker.error = Exception('refus');
    await pump(tester);
    await choose(tester, 'Prendre une photo');
    expect(picked, isEmpty);
    expect(find.textContaining('Vérifiez les autorisations'), findsOneWidget);
  });

  testWidgets('désactivée (envoi en cours) : aucun choix proposé', (
    tester,
  ) async {
    await pump(tester, enabled: false);
    await tester.tap(find.text("Pièce d'identité"));
    await tester.pumpAndSettle();
    expect(find.text('Prendre une photo'), findsNothing);
  });

  testWidgets('police à 200 % sur 320 dp : rien ne déborde', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pump(tester, alreadySent: true);
    expect(tester.takeException(), isNull);
    // État sous le libellé : le libellé garde presque toute la largeur.
    final label = tester.getRect(find.text("Pièce d'identité"));
    final status = tester.getRect(find.text('Envoyée'));
    expect(status.top, greaterThan(label.bottom));
    expect(
      tester.getSize(find.text('Face avec la photo')).width,
      greaterThan(200),
    );
  });
}
