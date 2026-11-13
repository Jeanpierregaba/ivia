import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'auth_controller.dart';
import 'providers.dart';

/// Événement poussé par le serveur (spec 036) : notification, étape d'une course, proposition.
class RealtimeEvent {
  const RealtimeEvent({
    required this.id,
    required this.kind,
    this.title = '',
    this.body = '',
    this.data = const {},
  });

  factory RealtimeEvent.fromJson(Map<String, dynamic> j) => RealtimeEvent(
    id: j['id'] as String? ?? '',
    kind: j['kind'] as String? ?? '',
    title: j['title'] as String? ?? '',
    body: j['body'] as String? ?? '',
    data: {
      for (final MapEntry(:key, :value)
          in (j['data'] as Map<String, dynamic>? ?? const {}).entries)
        key: '$value',
    },
  );

  /// Connexion rétablie après une coupure : tout relire (un événement a pu être manqué).
  static const reconnected = 'reconnected';

  final String id, kind, title, body;
  final Map<String, String> data;

  String? get orderId => data['order_id'];

  /// Notification enregistrée (avec un titre), et pas un simple signal.
  bool get isNotification => title.isNotEmpty;
}

/// Connexion temps réel d'une app (`buyer`, `seller`, `driver`, `pharmacy`) : ouverte tant que
/// le compte est connecté, rétablie seule après une coupure (attente croissante, 1 s à 30 s).
/// Les écrans écoutent [events] et relisent ce qui les concerne, sans attendre leur relecture
/// régulière, qui reste en secours.
class IviaRealtime {
  IviaRealtime(this._ref, this.app);

  final Ref _ref;
  final String app;
  final _controller = StreamController<RealtimeEvent>.broadcast();
  final _seen = <String>[];
  WebSocketChannel? _socket;
  StreamSubscription<dynamic>? _sub;
  Timer? _retry;
  var _attempt = 0;
  var _running = false;
  var _hadConnection = false;

  /// Événements reçus (sans doublon).
  Stream<RealtimeEvent> get events => _controller.stream;

  /// Connecté au serveur.
  bool get connected => _socket != null && _hadConnection;

  /// Tests d'écran : pas de connexion réseau.
  static bool get _disabled =>
      WidgetsBinding.instance is! WidgetsFlutterBinding;

  void start() {
    if (_running || _disabled) return;
    _running = true;
    _connect();
  }

  void stop() {
    _running = false;
    _retry?.cancel();
    _close();
  }

  void dispose() {
    stop();
    unawaited(_controller.close());
  }

  void _close() {
    unawaited(_sub?.cancel());
    _sub = null;
    unawaited(_socket?.sink.close());
    _socket = null;
  }

  void _connect() {
    if (!_running) return;
    final socket = _ref
        .read(apiClientProvider)
        .openSocket('/v1/ws/events', query: {'app': app});
    if (socket == null) {
      _scheduleRetry();
      return;
    }
    _socket = socket;
    _sub = socket.stream.listen(
      _onMessage,
      onError: (_) => _lost(),
      onDone: _lost,
      cancelOnError: true,
    );
  }

  void _onMessage(dynamic raw) {
    if (raw is! String) return;
    final RealtimeEvent e;
    try {
      e = RealtimeEvent.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on Object {
      return;
    }
    if (e.kind == 'ready') {
      final again = _hadConnection;
      _hadConnection = true;
      _attempt = 0;
      if (again) {
        _controller.add(
          const RealtimeEvent(id: '', kind: RealtimeEvent.reconnected),
        );
      }
      return;
    }
    if (e.id.isNotEmpty) {
      if (_seen.contains(e.id)) return;
      _seen.add(e.id);
      if (_seen.length > 100) _seen.removeAt(0);
    }
    _controller.add(e);
  }

  void _lost() {
    _close();
    _scheduleRetry();
  }

  void _scheduleRetry() {
    if (!_running) return;
    _retry?.cancel();
    final seconds = math.min(30, 1 << math.min(_attempt, 5));
    _attempt++;
    _retry = Timer(Duration(seconds: seconds), _connect);
  }
}

/// Connexion temps réel de l'app : démarrée à la connexion du compte, arrêtée à la déconnexion.
final iviaRealtimeProvider = Provider.family<IviaRealtime, String>((ref, app) {
  final r = IviaRealtime(ref, app);
  ref.onDispose(r.dispose);
  ref.listen(authControllerProvider, (_, next) {
    if (next is AuthSignedIn) {
      r.start();
    } else {
      r.stop();
    }
  }, fireImmediately: true);
  return r;
});
