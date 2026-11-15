import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_api_client/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> keychainSession() => SessionStore().save(
    'jeton-ancien',
    User.fromJson(userBody(complete: true)),
  );

  test('réinstallation : ancienne session du Keychain effacée', () async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    await keychainSession();

    await clearSessionAfterReinstall(SessionStore());
    expect(await SessionStore().read(), isNull);
  });

  test('lancements suivants : session gardée', () async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({'app_installed': true});
    await keychainSession();

    await clearSessionAfterReinstall(SessionStore());
    expect((await SessionStore().read())?.token, 'jeton-ancien');
  });
}
