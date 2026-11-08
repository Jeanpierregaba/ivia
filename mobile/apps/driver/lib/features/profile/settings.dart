import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Réglages du téléphone (spec 033). Ivia Driver n'a pas de notifications
/// push : la sonnerie des missions est jouée par l'app, au premier plan.

const _ringKey = 'driver_mission_ring';

/// Sonnerie et vibration à l'arrivée d'une proposition (activée par défaut).
final missionRingProvider = AsyncNotifierProvider<MissionRing, bool>(
  MissionRing.new,
);

class MissionRing extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async =>
      (await SharedPreferences.getInstance()).getBool(_ringKey) ?? true;

  Future<void> set(bool on) async {
    state = AsyncData(on);
    await (await SharedPreferences.getInstance()).setBool(_ringKey, on);
  }
}
