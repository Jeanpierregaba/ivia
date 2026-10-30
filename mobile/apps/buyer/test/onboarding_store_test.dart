import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivia_buyer/app/onboarding_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

/// Stockage du téléphone en panne, en lecture ou en écriture.
class _FailingStore extends InMemorySharedPreferencesStore {
  _FailingStore({this.failRead = false, this.failWrite = false})
    : super.empty();

  final bool failRead;
  final bool failWrite;

  PlatformException get _error => PlatformException(code: 'storage');

  @override
  Future<Map<String, Object>> getAll() =>
      failRead ? Future.error(_error) : super.getAll();

  @override
  Future<Map<String, Object>> getAllWithParameters(
    GetAllParameters parameters,
  ) => failRead ? Future.error(_error) : super.getAllWithParameters(parameters);

  @override
  Future<bool> setValue(String valueType, String key, Object value) =>
      failWrite ? Future.error(_error) : super.setValue(valueType, key, value);
}

void main() {
  void useStore(SharedPreferencesStorePlatform store) {
    SharedPreferences.resetStatic();
    SharedPreferencesStorePlatform.instance = store;
  }

  test('stockage vide : présentation pas vue, puis mémorisée', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await OnboardingStore.open();
    expect(store.seenAtLaunch, isFalse);

    await store.markSeen();
    expect((await OnboardingStore.open()).seenAtLaunch, isTrue);
  });

  test('lecture impossible : la présentation est montrée', () async {
    useStore(_FailingStore(failRead: true));
    final store = await OnboardingStore.open();
    expect(store.seenAtLaunch, isFalse);
    await store.markSeen(); // ne lève pas
  });

  test('écriture impossible : pas d\'erreur', () async {
    useStore(_FailingStore(failWrite: true));
    final store = await OnboardingStore.open();
    await expectLater(store.markSeen(), completes);
  });

  test('valeur corrompue : vaut « pas vue » et est remplacée', () async {
    SharedPreferences.setMockInitialValues({'onboarding_seen': 'oui'});
    final store = await OnboardingStore.open();
    expect(store.seenAtLaunch, isFalse);

    await store.markSeen();
    expect((await OnboardingStore.open()).seenAtLaunch, isTrue);
  });
}
