import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _installedKey = 'app_installed';

/// iOS garde le Keychain après une désinstallation, mais pas les préférences :
/// au premier lancement d'une installation, une ancienne session restée dans
/// le Keychain est effacée.
Future<void> clearSessionAfterReinstall(SessionStore sessions) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_installedKey) ?? false) return;
    await sessions.clear();
    await prefs.setBool(_installedKey, true);
  } on Exception {
    // Préférences illisibles : la session est simplement gardée.
  }
}
