import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';

// Alertes médicament : un push urgent réveille l'app, qui sonne comme un réveil et affiche l'alerte
// par-dessus l'écran verrouillé (Android). Sans configuration Firebase, l'app fonctionne sans push.

const _channelId = 'pharmacy_alerts';
const _kindAlert = 'pharmacy_alert';

final _plugin = FlutterLocalNotificationsPlugin();

/// Une alerte sonne au plus 10 minutes : au-delà, le patient est passé à autre chose.
const _ringMs = 10 * 60 * 1000;

int _idOf(String alertId) => alertId.hashCode & 0x7fffffff;

/// Android 14 et plus : le plein écran demande une autorisation à part.
Future<void> requestFullScreenAlerts() async {
  await _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.requestFullScreenIntentPermission();
}

Future<void> _initPlugin(void Function(String alertId)? onOpen) =>
    _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (r) {
        final id = r.payload;
        if (id != null && id.isNotEmpty) onOpen?.call(id);
      },
    );

/// Fait sonner l'alerte : son de réveil, répété jusqu'à ce que le responsable réagisse.
Future<void> _ring(Map<String, dynamic> data) async {
  final alertId = data['alert_id'] as String?;
  if (data['kind'] != _kindAlert || alertId == null) return;
  await _plugin.show(
    id: _idOf(alertId),
    title: data['title'] as String? ?? 'Alerte médicament',
    body:
        data['body'] as String? ??
        'Un patient cherche des produits. Répondez vite !',
    notificationDetails: NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        'Alertes médicament',
        channelDescription:
            'Sonne quand un patient cherche des produits près de vous.',
        importance: Importance.max,
        priority: Priority.max,
        category: AndroidNotificationCategory.alarm,
        visibility: NotificationVisibility.public,
        fullScreenIntent: true,
        audioAttributesUsage: AudioAttributesUsage.alarm,
        sound: const UriAndroidNotificationSound(
          'content://settings/system/alarm_alert',
        ),
        // FLAG_INSISTENT : le son se répète jusqu'à l'ouverture.
        additionalFlags: Int32List.fromList(const [4]),
        timeoutAfter: _ringMs,
        autoCancel: true,
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentSound: true,
        interruptionLevel: InterruptionLevel.timeSensitive,
      ),
    ),
    payload: alertId,
  );
}

/// Push reçu app fermée ou en arrière-plan.
@pragma('vm:entry-point')
Future<void> pushBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  await _initPlugin(null);
  await _ring(message.data);
}

/// À appeler avant `runApp`.
void setUpPushBackground() {
  if (kIsWeb) return;
  FirebaseMessaging.onBackgroundMessage(pushBackgroundHandler);
}

final pushProvider = Provider<PushManager>((ref) => PushManager(ref));

class PushManager {
  PushManager(this._ref);
  final Ref _ref;

  bool _started = false;
  String? _token;

  /// Ouvre l'alerte touchée.
  void Function(String alertId)? onOpenAlert;

  /// Nouvelle alerte reçue, app ouverte.
  void Function(String alertId)? onAlertReceived;

  String get _platform =>
      defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';

  /// Enregistre l'appareil pour le compte connecté et branche les réceptions.
  Future<void> start() async {
    if (kIsWeb) return;
    try {
      await Firebase.initializeApp();
    } on Object {
      // Pas encore de configuration Firebase : l'app relit ses alertes à l'écran.
      return;
    }
    final messaging = FirebaseMessaging.instance;
    await _register(await messaging.getToken());
    if (_started) return;
    _started = true;
    await _initPlugin(_open);
    messaging.onTokenRefresh.listen(_register);
    FirebaseMessaging.onMessage.listen((m) {
      _ring(m.data);
      final id = m.data['alert_id'];
      if (m.data['kind'] == _kindAlert && id is String) {
        onAlertReceived?.call(id);
      }
    });
    FirebaseMessaging.onMessageOpenedApp.listen((m) {
      final id = m.data['alert_id'];
      if (id is String) _open(id);
    });
    final launch = await _plugin.getNotificationAppLaunchDetails();
    final payload = launch?.notificationResponse?.payload;
    if (launch?.didNotificationLaunchApp == true &&
        payload != null &&
        payload.isNotEmpty) {
      _open(payload);
    }
    final initial = await messaging.getInitialMessage();
    final id = initial?.data['alert_id'];
    if (id is String) _open(id);
  }

  void _open(String alertId) {
    _plugin.cancel(id: _idOf(alertId));
    onOpenAlert?.call(alertId);
  }

  Future<void> _register(String? token) async {
    if (token == null) return;
    _token = token;
    try {
      await _ref
          .read(apiClientProvider)
          .registerPushToken(token, platform: _platform, app: 'pharmacy');
    } on ApiException {
      // Réseau : le prochain démarrage réessaie.
    }
  }

  /// Avant la déconnexion : un téléphone déconnecté ne reçoit plus d'alertes.
  Future<void> stop() async {
    final token = _token;
    if (token == null) return;
    _token = null;
    try {
      await _ref.read(apiClientProvider).unregisterPushToken(token);
    } on ApiException {
      // Réseau : la session est de toute façon révoquée.
    }
  }
}

/// Déconnexion : l'appareil cesse d'abord de recevoir les alertes.
Future<void> signOutPharmacy(WidgetRef ref) async {
  await ref.read(pushProvider).stop();
  await ref.read(authControllerProvider.notifier).signOut();
}
