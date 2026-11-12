part of 'client.dart';

/// Notification du compte (la même que le push envoyé au téléphone).
class AppNotification {
  AppNotification.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      kind = j['kind'] as String? ?? '',
      title = j['title'] as String? ?? '',
      body = j['body'] as String? ?? '',
      data = {
        for (final e in (j['data'] as Map? ?? const {}).entries)
          '${e.key}': '${e.value}',
      },
      read = j['read_at'] != null,
      createdAt = DateTime.parse(j['created_at'] as String);
  final String id, kind, title, body;
  final Map<String, String> data;
  final bool read;
  final DateTime createdAt;
}

extension NotificationsApi on IviaApiClient {
  /// Dernières notifications d'une app (`buyer`, `seller`, `driver`, `pharmacy`).
  Future<List<AppNotification>> notifications({
    String app = 'buyer',
    int limit = 10,
  }) async {
    final j = await _send(
      'GET',
      '/v1/notifications',
      query: {'app': app, 'limit': '$limit'},
    );
    return [for (final i in _list(j['items'])) AppNotification.fromJson(i)];
  }

  /// Marque une notification comme lue.
  Future<void> markNotificationRead(String id) =>
      _send('POST', '/v1/notifications/${Uri.encodeComponent(id)}/read');
}
