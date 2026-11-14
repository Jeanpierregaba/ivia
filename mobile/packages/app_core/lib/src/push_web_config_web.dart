import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:firebase_core/firebase_core.dart';

/// Configuration Firebase du navigateur, posée par la page (`window.iviaFirebase`).
class WebFirebaseConfig {
  const WebFirebaseConfig(this.options, this.vapidKey);
  final FirebaseOptions options;
  final String? vapidKey;
}

/// `null` tant que la page ne la fournit pas (pas de push dans ce navigateur).
WebFirebaseConfig? webFirebaseConfig() {
  final c = globalContext['iviaFirebase'];
  if (c == null || c.isUndefinedOrNull) return null;
  final o = c as JSObject;
  String? s(String key) {
    final v = o[key];
    return v == null || v.isUndefinedOrNull ? null : (v as JSString).toDart;
  }

  final apiKey = s('apiKey'), appId = s('appId');
  final sender = s('messagingSenderId'), project = s('projectId');
  if (apiKey == null || appId == null || sender == null || project == null) {
    return null;
  }
  return WebFirebaseConfig(
    FirebaseOptions(
      apiKey: apiKey,
      appId: appId,
      messagingSenderId: sender,
      projectId: project,
      authDomain: s('authDomain'),
      storageBucket: s('storageBucket'),
    ),
    s('vapidKey'),
  );
}
