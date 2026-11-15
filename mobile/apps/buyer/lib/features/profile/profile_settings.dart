import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Préférences de notifications, gardées sur le téléphone.
class NotificationPrefs {
  const NotificationPrefs({
    this.orders = true,
    this.pharmacy = true,
    this.promos = true,
    this.sound = 'ivia',
    this.vibrate = true,
  });

  final bool orders, pharmacy, promos, vibrate;

  /// Son des notifications : ivia, cloche, douce, silencieux.
  final String sound;

  NotificationPrefs copyWith({
    bool? orders,
    bool? pharmacy,
    bool? promos,
    String? sound,
    bool? vibrate,
  }) => NotificationPrefs(
    orders: orders ?? this.orders,
    pharmacy: pharmacy ?? this.pharmacy,
    promos: promos ?? this.promos,
    sound: sound ?? this.sound,
    vibrate: vibrate ?? this.vibrate,
  );
}

const notificationSounds = {
  'ivia': 'ivia (par défaut)',
  'bell': 'Cloche',
  'soft': 'Douce',
  'silent': 'Silencieux',
};

final notificationPrefsProvider =
    AsyncNotifierProvider<NotificationPrefsNotifier, NotificationPrefs>(
      NotificationPrefsNotifier.new,
    );

class NotificationPrefsNotifier extends AsyncNotifier<NotificationPrefs> {
  static const _p = 'notif_';

  @override
  Future<NotificationPrefs> build() async {
    final p = await SharedPreferences.getInstance();
    return NotificationPrefs(
      orders: p.getBool('${_p}orders') ?? true,
      pharmacy: p.getBool('${_p}pharmacy') ?? true,
      promos: p.getBool('${_p}promos') ?? true,
      sound: p.getString('${_p}sound') ?? 'ivia',
      vibrate: p.getBool('${_p}vibrate') ?? true,
    );
  }

  Future<void> save(NotificationPrefs v) async {
    state = AsyncData(v);
    final p = await SharedPreferences.getInstance();
    await p.setBool('${_p}orders', v.orders);
    await p.setBool('${_p}pharmacy', v.pharmacy);
    await p.setBool('${_p}promos', v.promos);
    await p.setString('${_p}sound', v.sound);
    await p.setBool('${_p}vibrate', v.vibrate);
  }
}
