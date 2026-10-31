import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_api_client/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('aucune session au départ', () async {
    expect(await SessionStore().read(), isNull);
  });

  test('enregistre puis relit le jeton et le profil', () async {
    final user = User.fromJson(userBody(complete: true));
    await SessionStore().save('jeton-secret', user);

    final stored = await SessionStore().read();
    expect(stored?.token, 'jeton-secret');
    expect(stored?.user?.firstName, 'Awa');
    expect(stored?.user?.profileComplete, isTrue);
  });

  test('met à jour le profil sans toucher au jeton', () async {
    final store = SessionStore();
    await store.save('jeton-secret', User.fromJson(userBody()));
    await store.saveUser(User.fromJson(userBody(complete: true)));

    final stored = await store.read();
    expect(stored?.token, 'jeton-secret');
    expect(stored?.user?.profileComplete, isTrue);
  });

  test('efface tout', () async {
    final store = SessionStore();
    await store.save('jeton-secret', User.fromJson(userBody()));
    await store.clear();
    expect(await store.read(), isNull);
  });

  test('profil illisible : jeton gardé, profil ignoré', () async {
    FlutterSecureStorage.setMockInitialValues({
      'session_token': 'jeton-secret',
      'session_user': '{pas du json',
    });
    final stored = await SessionStore().read();
    expect(stored?.token, 'jeton-secret');
    expect(stored?.user, isNull);
  });
}
