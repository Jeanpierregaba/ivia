import 'package:web_socket_channel/web_socket_channel.dart';

/// Navigateur : pas d'en-tête possible sur un WebSocket, donc pas de temps réel.
WebSocketChannel? connectWebSocket(Uri uri, String token) => null;
