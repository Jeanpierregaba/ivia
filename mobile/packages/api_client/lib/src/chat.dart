part of 'client.dart';

// Messagerie de la course (spec 037) : client ↔ livreur, livreur ↔ boutique.

/// Fil de discussion d'une commande, vu depuis une app.
class ChatChannel {
  const ChatChannel._(this.path, this.app, this.orderId, this.thread);

  /// Client → livreur.
  factory ChatChannel.buyer(String orderId) => ChatChannel._(
    '/v1/orders/$orderId/chat',
    'buyer',
    orderId,
    'buyer_driver',
  );

  /// Boutique → livreur.
  factory ChatChannel.seller(String orderId) => ChatChannel._(
    '/v1/seller/orders/$orderId/chat',
    'seller',
    orderId,
    'driver_shop',
  );

  /// Livreur → client.
  factory ChatChannel.driverClient(String orderId) => ChatChannel._(
    '/v1/driver/orders/$orderId/chat/client',
    'driver',
    orderId,
    'buyer_driver',
  );

  /// Livreur → boutique.
  factory ChatChannel.driverShop(String orderId) => ChatChannel._(
    '/v1/driver/orders/$orderId/chat/shop',
    'driver',
    orderId,
    'driver_shop',
  );

  final String path, app, orderId, thread;

  /// Identifiant du fil (bannière masquée quand il est déjà ouvert).
  String get key => '$app:$orderId:$thread';
}

/// Message d'un fil.
class ChatMessage {
  ChatMessage({
    required this.id,
    required this.mine,
    required this.senderRole,
    required this.body,
    required this.createdAt,
    this.pending = false,
  });

  ChatMessage.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      mine = j['mine'] as bool? ?? false,
      senderRole = j['sender_role'] as String? ?? '',
      body = j['body'] as String? ?? '',
      createdAt = DateTime.parse(j['created_at'] as String),
      pending = false;

  final String id, senderRole, body;
  final bool mine;
  final DateTime createdAt;

  /// Envoi en cours (affiché avant la réponse du serveur).
  final bool pending;
}

/// Fil de discussion : messages, autre participant, envoi possible.
class ChatThread {
  ChatThread.fromJson(Map<String, dynamic> j)
    : orderReference = j['order_reference'] as String? ?? '',
      canSend = j['can_send'] as bool? ?? false,
      otherName = j['other_name'] as String? ?? '',
      otherRole = j['other_role'] as String? ?? '',
      otherReadAt = _d(j['other_read_at']),
      messages = [
        for (final m in _list(j['messages'])) ChatMessage.fromJson(m),
      ];

  final String orderReference, otherName, otherRole;
  final bool canSend;
  final DateTime? otherReadAt;
  final List<ChatMessage> messages;
}

extension ChatApi on IviaApiClient {
  /// Fil (marqué lu).
  Future<ChatThread> chatThread(ChatChannel c) async =>
      ChatThread.fromJson(await _send('GET', c.path));

  /// Envoie un message.
  Future<ChatMessage> sendChat(ChatChannel c, String body) async =>
      ChatMessage.fromJson(await _send('POST', c.path, data: {'body': body}));
}
