import 'dart:math';

final _random = Random.secure();

/// Identifiant de requête aléatoire au format UUID v4, pour rendre une
/// création idempotente (`client_request_id`) : renvoyé tel quel à chaque
/// nouvel essai de la même action.
String newRequestId() {
  final b = List<int>.generate(16, (_) => _random.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40; // version 4
  b[8] = (b[8] & 0x3f) | 0x80; // variante RFC 4122
  String hex(int from, int to) =>
      [for (var i = from; i < to; i++) b[i].toRadixString(16).padLeft(2, '0')]
          .join();
  return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
}
