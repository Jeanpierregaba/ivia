import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';

/// Notifications du compte, relues par le veilleur (toutes les 20 s) et à
/// l'ouverture de l'écran. `null` : pas encore lues.
final notificationsProvider =
    NotifierProvider<NotificationsController, List<AppNotification>?>(
      NotificationsController.new,
    );

/// Nombre de notifications non lues (pastille de la cloche).
final unreadNotificationsProvider = Provider<int>(
  (ref) => ref.watch(notificationsProvider)?.where((n) => !n.read).length ?? 0,
);

class NotificationsController extends Notifier<List<AppNotification>?> {
  @override
  List<AppNotification>? build() {
    // Déconnexion : plus rien à montrer.
    ref.listen(authControllerProvider, (_, next) {
      if (next is! AuthSignedIn) state = null;
    });
    return null;
  }

  /// Relit les dernières notifications ; renvoie la liste lue.
  Future<List<AppNotification>> refresh() async {
    final items = await ref.read(apiClientProvider).notifications(limit: 40);
    state = items;
    return items;
  }

  /// Marque une notification comme lue (tout de suite à l'écran).
  Future<void> markRead(String id) async {
    final items = state;
    if (items == null) return;
    state = [for (final n in items) n.id == id ? n.markedRead() : n];
    try {
      await ref.read(apiClientProvider).markNotificationRead(id);
    } catch (_) {
      // Réessayé au prochain appui ; l'écran reste à jour.
    }
  }

  /// Tout marquer comme lu.
  Future<void> markAllRead() async {
    final items = state;
    if (items == null) return;
    state = [for (final n in items) n.markedRead()];
    try {
      await ref.read(apiClientProvider).markAllNotificationsRead();
    } catch (_) {}
  }
}
