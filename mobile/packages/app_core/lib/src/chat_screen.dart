import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_ui/ivia_ui.dart';

import 'messages.dart';
import 'providers.dart';
import 'realtime.dart';

/// Ouvre la discussion d'une course (spec 037).
Future<void> openChat(BuildContext context, ChatChannel channel) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => ChatScreen(channel: channel)),
    );

/// Bandeau « nouveau message » quand la discussion n'est pas déjà ouverte ;
/// le toucher ouvre la discussion. [channelOf] traduit l'événement en fil.
void showChatBanner(
  BuildContext context,
  RealtimeEvent e,
  ChatChannel? Function(RealtimeEvent) channelOf,
) {
  final channel = channelOf(e);
  if (channel == null || ChatScreen.openKey == channel.key) return;
  HapticFeedback.lightImpact();
  showIviaNotification(
    context,
    title: e.title.isEmpty ? 'Nouveau message' : e.title,
    body: e.body,
    icon: Icons.chat_bubble_rounded,
    color: const Color(0xFF128C7E),
    visibleFor: const Duration(seconds: 6),
    onTap: () => openChat(context, channel),
  );
}

const _mineBubble = Color(0xFFD9FDD3);
const _paper = Color(0xFFEFE7DD);
const _readBlue = Color(0xFF53BDEB);

/// Messages rapides selon qui écrit à qui.
List<String> _quickReplies(ChatChannel c) => switch ((c.app, c.thread)) {
  ('buyer', _) => [
    'Je descends',
    'Je suis au portail',
    'Appelez-moi',
    'Merci !',
  ],
  ('seller', _) => [
    'La commande est prête',
    'Encore 5 minutes',
    'Venez au comptoir',
    'Merci !',
  ],
  ('driver', 'driver_shop') => [
    'Je suis en route',
    'Je suis devant la boutique',
    'La commande est prête ?',
  ],
  _ => [
    'J’arrive',
    'Je suis devant',
    'Où êtes-vous exactement ?',
    'Je vous appelle',
  ],
};

/// Discussion de la course, façon messagerie : bulles, heures, accusés de
/// lecture, messages rapides ; mise à jour en direct ; lecture seule une fois
/// la course terminée.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.channel});
  final ChatChannel channel;

  /// Fil actuellement ouvert (pas de bandeau pour lui).
  static String? openKey;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  ChatThread? _thread;
  final _pending = <ChatMessage>[];
  String? _error;
  StreamSubscription<RealtimeEvent>? _live;
  Timer? _fallback;
  var _typing = false;

  ChatChannel get _c => widget.channel;

  @override
  void initState() {
    super.initState();
    ChatScreen.openKey = _c.key;
    unawaited(_load());
    _live = ref.read(iviaRealtimeProvider(_c.app)).events.listen((e) {
      final mine = e.orderId == _c.orderId && e.data['thread'] == _c.thread;
      if (mine || e.kind == RealtimeEvent.reconnected) unawaited(_load());
    });
    _fallback = Timer.periodic(const Duration(seconds: 20), (_) => _load());
    _input.addListener(() {
      final t = _input.text.trim().isNotEmpty;
      if (t != _typing) setState(() => _typing = t);
    });
  }

  @override
  void dispose() {
    if (ChatScreen.openKey == _c.key) ChatScreen.openKey = null;
    unawaited(_live?.cancel());
    _fallback?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final t = await ref.read(apiClientProvider).chatThread(_c);
      if (!mounted) return;
      final grew = (t.messages.length) > (_thread?.messages.length ?? -1);
      setState(() {
        _thread = t;
        _error = null;
      });
      if (grew) _toBottom();
    } on ApiException catch (e) {
      if (mounted && _thread == null) setState(() => _error = e.message);
    }
  }

  void _toBottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_scroll.hasClients) {
      unawaited(
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: IviaMotion.slow,
          curve: IviaMotion.soft,
        ),
      );
    }
  });

  Future<void> _send([String? text]) async {
    final body = (text ?? _input.text).trim();
    if (body.isEmpty) return;
    final temp = ChatMessage(
      id: 'tmp-${DateTime.now().microsecondsSinceEpoch}',
      mine: true,
      senderRole: _c.app,
      body: body,
      createdAt: DateTime.now(),
      pending: true,
    );
    setState(() => _pending.add(temp));
    if (text == null) _input.clear();
    _toBottom();
    try {
      await ref.read(apiClientProvider).sendChat(_c, body);
      await _load();
      if (mounted) setState(() => _pending.remove(temp));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _pending.remove(temp));
      if (text == null) _input.text = body;
      showMessage(ScaffoldMessenger.of(context), e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final th = _thread;
    final messages = [...?th?.messages, ..._pending];
    final role = switch (th?.otherRole) {
      'driver' => 'Livreur',
      'seller' => 'Boutique',
      'buyer' => 'Client',
      _ => '',
    };
    return Scaffold(
      backgroundColor: _paper,
      appBar: AppBar(
        backgroundColor: IviaColors.tertiary,
        foregroundColor: Colors.white,
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: Colors.white24,
              child: Text(
                (th?.otherName.isNotEmpty ?? false)
                    ? th!.otherName.characters.first.toUpperCase()
                    : '…',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    th?.otherName ?? 'Discussion',
                    style: t.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (th != null)
                    Text(
                      [
                        role,
                        th.orderReference,
                      ].where((s) => s.isNotEmpty).join(' · '),
                      style: t.bodySmall?.copyWith(color: Colors.white70),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: th == null
                ? Center(
                    child: _error == null
                        ? const CircularProgressIndicator()
                        : Padding(
                            padding: const EdgeInsets.all(IviaSpacing.xl),
                            child: Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: t.bodyLarge,
                            ),
                          ),
                  )
                : messages.isEmpty
                ? _Empty(other: th.otherName)
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
                    itemCount: messages.length,
                    itemBuilder: (context, i) {
                      final m = messages[i];
                      final prev = i > 0 ? messages[i - 1] : null;
                      final newDay =
                          prev == null ||
                          !_sameDay(prev.createdAt, m.createdAt);
                      final read =
                          m.mine &&
                          !m.pending &&
                          th.otherReadAt != null &&
                          !th.otherReadAt!.isBefore(m.createdAt);
                      return Column(
                        children: [
                          if (newDay) _DayChip(m.createdAt),
                          _Bubble(
                            key: ValueKey(m.id),
                            message: m,
                            read: read,
                            grouped:
                                prev != null && prev.mine == m.mine && !newDay,
                          ),
                        ],
                      );
                    },
                  ),
          ),
          if (th != null && !th.canSend)
            Container(
              width: double.infinity,
              color: Colors.white,
              padding: const EdgeInsets.all(IviaSpacing.md),
              child: Text(
                'Course terminée : la discussion est en lecture seule.',
                textAlign: TextAlign.center,
                style: t.bodyMedium?.copyWith(color: IviaColors.textMuted),
              ),
            )
          else if (th != null)
            SafeArea(
              top: false,
              child: Column(
                children: [
                  SizedBox(
                    height: 44,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      children: [
                        for (final q in _quickReplies(_c))
                          Padding(
                            padding: const EdgeInsets.only(right: 6, top: 4),
                            child: ActionChip(
                              label: Text(q),
                              backgroundColor: Colors.white,
                              side: BorderSide.none,
                              shape: const StadiumBorder(),
                              onPressed: () => _send(q),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: TextField(
                              controller: _input,
                              minLines: 1,
                              maxLines: 5,
                              maxLength: 1000,
                              textCapitalization: TextCapitalization.sentences,
                              decoration: const InputDecoration(
                                hintText: 'Message',
                                counterText: '',
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                filled: false,
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 12,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        AnimatedScale(
                          scale: _typing ? 1 : 0.85,
                          duration: IviaMotion.medium,
                          curve: Curves.easeOutBack,
                          child: Material(
                            color: const Color(0xFF128C7E),
                            shape: const CircleBorder(),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: _typing ? _send : null,
                              child: const SizedBox.square(
                                dimension: 48,
                                child: Icon(
                                  Icons.send_rounded,
                                  color: Colors.white,
                                  semanticLabel: 'Envoyer',
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

bool _sameDay(DateTime a, DateTime b) {
  final x = a.toLocal(), y = b.toLocal();
  return x.year == y.year && x.month == y.month && x.day == y.day;
}

String _hm(DateTime d) {
  final l = d.toLocal();
  return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
}

class _DayChip extends StatelessWidget {
  const _DayChip(this.at);
  final DateTime at;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final label = _sameDay(at, now)
        ? 'Aujourd’hui'
        : _sameDay(at, now.subtract(const Duration(days: 1)))
        ? 'Hier'
        : '${at.toLocal().day}/${at.toLocal().month}/${at.toLocal().year}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(label, style: Theme.of(context).textTheme.labelSmall),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    super.key,
    required this.message,
    required this.read,
    required this.grouped,
  });
  final ChatMessage message;
  final bool read, grouped;

  @override
  Widget build(BuildContext context) {
    final m = message;
    final t = Theme.of(context).textTheme;
    final r = const Radius.circular(14);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: IviaMotion.medium,
      curve: IviaMotion.soft,
      builder: (_, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(
          offset: Offset(0, (1 - v) * 8),
          child: child,
        ),
      ),
      child: Align(
        alignment: m.mine ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.78,
          ),
          child: Container(
            margin: EdgeInsets.only(top: grouped ? 2 : 8),
            padding: const EdgeInsets.fromLTRB(11, 7, 9, 5),
            decoration: BoxDecoration(
              color: m.mine ? _mineBubble : Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: r,
                topRight: r,
                bottomLeft: m.mine ? r : const Radius.circular(4),
                bottomRight: m.mine ? const Radius.circular(4) : r,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 2,
                  offset: Offset(0, 1),
                ),
              ],
            ),
            child: Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.end,
              spacing: 8,
              children: [
                Text(m.body, style: t.bodyLarge),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _hm(m.createdAt),
                      style: t.labelSmall?.copyWith(
                        color: IviaColors.textMuted,
                      ),
                    ),
                    if (m.mine) ...[
                      const SizedBox(width: 3),
                      Icon(
                        m.pending
                            ? Icons.schedule_rounded
                            : read
                            ? Icons.done_all_rounded
                            : Icons.done_rounded,
                        size: 16,
                        color: read ? _readBlue : IviaColors.textMuted,
                        semanticLabel: m.pending
                            ? 'Envoi en cours'
                            : read
                            ? 'Lu'
                            : 'Envoyé',
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.other});
  final String other;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(IviaSpacing.xl),
      child: Container(
        padding: const EdgeInsets.all(IviaSpacing.md),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF3C4),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          'Écrivez à ${other.isEmpty ? 'votre contact' : other} pour la course. Les messages restent liés à cette commande.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    ),
  );
}
