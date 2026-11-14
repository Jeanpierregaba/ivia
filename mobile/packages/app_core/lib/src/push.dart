import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';

import 'providers.dart';
import 'push_web_config.dart'
    if (dart.library.js_interop) 'push_web_config_web.dart';

/// Notifications push (Firebase Cloud Messaging) des apps ivia : sur le
/// téléphone (app fermée ou en arrière-plan, le système les affiche) et dans
/// le navigateur. Sans configuration Firebase, rien ne se passe : l'app relit
/// ses notifications à l'écran.
class IviaPush {
  IviaPush(this._ref, this.app);

  final Ref _ref;

  /// `buyer`, `seller` ou `driver`.
  final String app;

  bool _started = false;
  String? _token;
  final _subs = <StreamSubscription<Object?>>[];

  String get _platform => kIsWeb
      ? 'web'
      : defaultTargetPlatform == TargetPlatform.iOS
      ? 'ios'
      : 'android';

  /// Enregistre l'appareil du compte connecté. [onOpen] : notification
  /// touchée (ses données : `order_id`…) ; [onReceived] : reçue app ouverte.
  Future<void> start({
    required void Function(Map<String, String> data) onOpen,
    void Function(Map<String, String> data)? onReceived,
  }) async {
    try {
      if (kIsWeb) {
        final web = webFirebaseConfig();
        if (web == null) return;
        if (Firebase.apps.isEmpty) {
          await Firebase.initializeApp(options: web.options);
        }
      } else if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
    } on Object {
      // Pas encore de projet Firebase sur cet appareil.
      return;
    }
    final messaging = FirebaseMessaging.instance;
    try {
      final settings = await messaging.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;
      await _register(
        await messaging.getToken(vapidKey: webFirebaseConfig()?.vapidKey),
      );
    } on Object {
      // Navigateur sans push (ou refus) : l'écran reste à jour sans lui.
      return;
    }
    if (_started) return;
    _started = true;
    _ref.read(activePushesProvider).add(this);
    Map<String, String> data(RemoteMessage m) => {
      for (final e in m.data.entries) e.key: '${e.value}',
    };
    _subs
      ..add(messaging.onTokenRefresh.listen(_register))
      ..add(
        FirebaseMessaging.onMessage.listen((m) => onReceived?.call(data(m))),
      )
      ..add(
        FirebaseMessaging.onMessageOpenedApp.listen((m) => onOpen(data(m))),
      );
    final initial = await messaging.getInitialMessage();
    if (initial != null) onOpen(data(initial));
  }

  Future<void> _register(String? token) async {
    if (token == null || token == _token) return;
    _token = token;
    try {
      await _ref
          .read(apiClientProvider)
          .registerPushToken(token, platform: _platform, app: app);
    } on ApiException {
      // Réseau : le prochain démarrage réessaie.
    }
  }

  /// Avant la déconnexion : cet appareil ne reçoit plus les notifications du
  /// compte.
  Future<void> stop() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    _started = false;
    _ref.read(activePushesProvider).remove(this);
    final token = _token;
    _token = null;
    if (token == null) return;
    try {
      await _ref.read(apiClientProvider).unregisterPushToken(token);
    } on ApiException {
      // Le serveur retire de lui-même les jetons qui ne répondent plus.
    }
  }
}

/// Push en service : arrêtés avant la déconnexion (l'appareil ne reçoit plus
/// rien du compte).
final activePushesProvider = Provider<Set<IviaPush>>((ref) => {});

/// Push de l'app (`buyer`, `seller`, `driver`).
final iviaPushProvider = Provider.family<IviaPush, String>(
  (ref, app) => IviaPush(ref, app),
);
