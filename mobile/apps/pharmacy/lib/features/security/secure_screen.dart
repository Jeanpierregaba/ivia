import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Blocage de la capture d'écran (Android, `FLAG_SECURE`) pendant
/// l'affichage d'une ordonnance. Sur iOS, rien ne le garantit : rien n'est
/// fait, et l'écran ne l'annonce pas.
abstract final class SecureScreen {
  static const channel = MethodChannel('ivia/secure_screen');

  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Écrans protégés ouverts : la capture ne revient qu'à la fermeture du
  /// dernier.
  static var _open = 0;

  static Future<void> enable() async {
    if (_open++ == 0) await _call('enable');
  }

  static Future<void> disable() async {
    if (_open == 0) return;
    if (--_open == 0) await _call('disable');
  }

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
