import 'dart:convert';
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';

/// État du livreur : en ligne ou non, proposition et mission en cours, relus
/// en direct. En ligne, la position est envoyée toutes les 30 s.
class WorkState {
  const WorkState({
    this.online = false,
    this.offer,
    this.mission,
    this.busy = false,
    this.error,
  });

  final bool online, busy;
  final WorkOffer? offer;
  final WorkMission? mission;
  final String? error;

  WorkState copy({
    bool? online,
    WorkOffer? offer,
    bool clearOffer = false,
    WorkMission? mission,
    bool clearMission = false,
    bool? busy,
    String? error,
  }) => WorkState(
    online: online ?? this.online,
    offer: clearOffer ? null : offer ?? this.offer,
    mission: clearMission ? null : mission ?? this.mission,
    busy: busy ?? this.busy,
    error: error,
  );
}

final workProvider = NotifierProvider<WorkController, WorkState>(
  WorkController.new,
);

class WorkController extends Notifier<WorkState> {
  Timer? _poll, _gps;

  IviaApiClient get _api => ref.read(apiClientProvider);

  @override
  WorkState build() {
    ref.onDispose(() {
      _poll?.cancel();
      _gps?.cancel();
    });
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => refresh());
    unawaited(refresh());
    return const WorkState();
  }

  Future<void> refresh() async {
    try {
      final mission = await _api.currentWorkMission();
      final offer = mission == null && state.online
          ? await _api.currentWorkOffer()
          : null;
      state = state.copy(
        mission: mission,
        clearMission: mission == null,
        offer: offer,
        clearOffer: offer == null,
      );
    } on ApiException {
      // Réseau : nouvel essai au prochain tour.
    }
  }

  // Temps réel sur téléphone : position toutes les 5 s en mouvement, 15 s à l'arrêt. Sans connexion
  // temps réel (navigateur, coupure), envoi classique, qui renouvelle aussi le jeton.
  WebSocketChannel? _socket;
  GeoPoint? _lastSent;
  DateTime? _lastSentAt;

  void _closeSocket() {
    _socket?.sink.close();
    _socket = null;
  }

  void _openSocket() {
    if (_socket != null) return;
    final socket = _api.openSocket('/v1/ws/driver/location');
    if (socket == null) return;
    _socket = socket;
    socket.stream.listen(
      (_) {},
      onError: (_) => _socket = null,
      onDone: () => _socket = null,
      cancelOnError: true,
    );
  }

  Future<void> _sendLocation() async {
    final p = (await ref.read(locationServiceProvider).current()).point;
    if (p == null) return;
    final last = _lastSent;
    final at = _lastSentAt;
    final moved =
        last == null ||
        (p.lat - last.lat).abs() + (p.lng - last.lng).abs() > 0.0001;
    if (!moved && at != null && DateTime.now().difference(at).inSeconds < 15)
      return;
    _lastSent = p;
    _lastSentAt = DateTime.now();
    _openSocket();
    final socket = _socket;
    if (socket != null) {
      socket.sink.add(jsonEncode({'lat': p.lat, 'lng': p.lng}));
      return;
    }
    try {
      await _api.sendLocation(p);
    } on ApiException {
      // Prochain envoi au tour suivant.
    }
  }

  Future<void> setOnline(bool online) async {
    state = state.copy(busy: true);
    try {
      if (online) await _sendLocation();
      await _api.setAvailability(online);
      _gps?.cancel();
      if (online) {
        _gps = Timer.periodic(
          const Duration(seconds: 5),
          (_) => _sendLocation(),
        );
      } else {
        _closeSocket();
      }
      state = state.copy(online: online, busy: false, clearOffer: !online);
      await refresh();
    } on ApiException catch (e) {
      state = state.copy(busy: false, error: e.message);
    }
  }

  Future<String?> run(Future<void> Function(IviaApiClient api) action) async {
    state = state.copy(busy: true);
    try {
      await action(_api);
      state = state.copy(busy: false);
      await refresh();
      return null;
    } on ApiException catch (e) {
      state = state.copy(busy: false);
      return e.message;
    }
  }
}

final workHistoryProvider = FutureProvider.autoDispose<List<WorkMission>>(
  (ref) => ref.read(apiClientProvider).workHistory(),
);
