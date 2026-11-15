import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Android et iOS : le jeton part dans l'en-tête, jamais dans l'URL.
WebSocketChannel? connectWebSocket(Uri uri, String token) =>
    IOWebSocketChannel.connect(
      uri,
      headers: {'Authorization': 'Bearer $token'},
    );
