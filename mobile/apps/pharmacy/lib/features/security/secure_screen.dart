import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Blocage de la capture d'écran (Android, `FLAG_SECURE`) pendant
/// l'affichage d'une ordonnance. Sur iOS, rien ne le garantit : rien n'est
/// fait, et l'écran ne l'annonce pas.
abstract final class SecureScreen {
  static const channel = MethodChannel('ivia/secure_screen');

  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<void> enable() => _call('enable');
  static Future<void> disable() => _call('disable');

  static Future<void> _call(String method) async {
    if (!supported) return;
    try {
      await channel.invokeMethod<void>(method);
    } on PlatformException {
      // Ancien Android ou moteur sans le canal : l'écran reste utilisable.
    } on MissingPluginException {
      // Idem.
    }
  }
}
