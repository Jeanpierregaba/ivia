import 'package:firebase_core/firebase_core.dart';

/// Configuration Firebase du navigateur : seulement sur le web.
class WebFirebaseConfig {
  const WebFirebaseConfig(this.options, this.vapidKey);
  final FirebaseOptions options;
  final String? vapidKey;
}

WebFirebaseConfig? webFirebaseConfig() => null;
