import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
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

  Future<void> _sendLocation() async {
    final p = (await ref.read(locationServiceProvider).current()).point;
    if (p != null) {
      try {
        await _api.sendLocation(p);
      } on ApiException {
        // Prochain envoi dans 30 s.
      }
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
          const Duration(seconds: 30),
          (_) => _sendLocation(),
        );
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
