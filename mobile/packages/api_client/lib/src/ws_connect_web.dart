import 'package:web_socket_channel/web_socket_channel.dart';

/// Navigateur : un WebSocket ne peut pas porter d'en-tête ; le jeton part dans le sous-protocole
/// `ivia-bearer` (jamais dans l'URL, qui finit dans les journaux).
WebSocketChannel? connectWebSocket(Uri uri, String token) =>
    WebSocketChannel.connect(uri, protocols: ['ivia-bearer', token]);
