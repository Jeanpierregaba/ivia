import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Clé du réglage, lue aussi par le push en arrière-plan.
const alertSoundKey = 'pharmacy_alert_sound';

/// Sonnerie des alertes sur ce téléphone : forte et répétée (par défaut), ou
/// coupée (la notification reste, sans son).
Future<bool> readAlertSound() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return prefs.getBool(alertSoundKey) ?? true;
  } on Exception {
    return true;
  }
}

final alertSoundProvider = AsyncNotifierProvider<AlertSound, bool>(
  AlertSound.new,
);

class AlertSound extends AsyncNotifier<bool> {
  @override
  Future<bool> build() => readAlertSound();

  Future<void> set(bool on) async {
    state = AsyncData(on);
    try {
      await (await SharedPreferences.getInstance()).setBool(alertSoundKey, on);
    } on Exception {
      // Écriture impossible : le réglage reviendra par défaut (sonnerie).
    }
  }
}
