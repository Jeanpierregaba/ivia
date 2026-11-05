import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../main.dart';
import 'ui.dart';

final inboxProvider = FutureProvider.autoDispose<List<InboxAlert>>(
  (ref) => ref.read(apiClientProvider).pharmacyInbox(openOnly: false),
);
final ordersProvider = FutureProvider.autoDispose<List<PharmacyOrder>>(
  (ref) => ref.read(apiClientProvider).pharmacyOrders(),
);
final earningsProvider = FutureProvider.autoDispose<PharmacyEarnings>(
  (ref) => ref.read(apiClientProvider).pharmacyEarnings(),
);
final shiftsProvider = FutureProvider.autoDispose(
  (ref) => ref.read(apiClientProvider).pharmacyDutyShifts(),
);

/// Espace pharmacie : Alertes, Réservations, Officine, Solde.
class PharmacyShell extends ConsumerStatefulWidget {
  const PharmacyShell({super.key});

  @override
  ConsumerState<PharmacyShell> createState() => _PharmacyShellState();
}

class _PharmacyShellState extends ConsumerState<PharmacyShell> {
  var _tab = 0;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    // Alertes et réservations relues en direct (les notifications push
    // complètent sur téléphone).
    _poll = Timer.periodic(const Duration(seconds: 5), (_) {
      ref
        ..invalidate(inboxProvider)
        ..invalidate(ordersProvider);
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inbox = ref.watch(inboxProvider).value ?? const <InboxAlert>[];
    final waiting = inbox
        .where(
          (a) =>
              !a.responded &&
              a.status == 'pending' &&
              a.searchEndsAt.isAfter(DateTime.now()),
        )
        .length;
    final orders = ref.watch(ordersProvider).value ?? const <PharmacyOrder>[];
    final active = orders.where((o) => o.active).length;
    return Scaffold(
      backgroundColor: P.page,
      body: SafeArea(
        child: IndexedStack(
          index: _tab,
          children: const [
            _InboxTab(),
            _OrdersTab(),
            _OfficeTab(),
            _BalanceTab(),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        indicatorColor: P.softGreen,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          NavigationDestination(
            icon: Badge(
              isLabelVisible: waiting > 0,
              label: Text('$waiting'),
              child: const Icon(Icons.notifications_none),
            ),
            label: 'Alertes',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: active > 0,
              label: Text('$active'),
              child: const Icon(Icons.inventory_2_outlined),
            ),
            label: 'Réservations',
          ),
          const NavigationDestination(
            icon: Icon(Icons.local_pharmacy_outlined),
            label: 'Officine',
          ),
          const NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            label: 'Solde',
          ),
        ],
      ),
    );
  }
}

class _InboxTab extends ConsumerWidget {
  const _InboxTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final items = ref.watch(inboxProvider).value ?? const <InboxAlert>[];
    final profile = ref.watch(pharmacyProfileProvider).value;
    final now = DateTime.now();
    final open = items
        .where((a) => a.searchEndsAt.isAfter(now) && a.status != 'declined')
        .toList();
    final past = items.where((a) => !open.contains(a)).toList();
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(inboxProvider),
      child: ListView(
        padding: const EdgeInsets.all(IviaSpacing.screen),
        children: [
          Text(
            profile?.name ?? 'Pharmacie',
            style: t.bodyLarge?.copyWith(color: P.muted),
          ),
          const PTitle('Alertes ', 'médicament'),
          const SizedBox(height: 12),
          if (profile != null &&
              !profile.isOpen &&
              !profile.onDuty &&
              !profile.open24h)
            PCard(
              color: P.softYellow,
              child: Text(
                'Vous êtes fermé : vous ne recevez pas d\'alertes. Ouvrez la pharmacie dans l\'onglet Officine.',
                style: t.bodyMedium,
              ),
            ),
          const SizedBox(height: 8),
          if (open.isEmpty)
            PCard(
              child: Row(
                children: [
                  const PIcon(Icons.notifications_none),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      'Aucune alerte en cours. Les nouvelles alertes apparaissent ici en direct.',
                      style: t.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          for (final a in open)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _AlertTile(alert: a),
            ),
          if (past.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Terminées',
              style: t.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: P.muted,
              ),
            ),
            const SizedBox(height: 8),
            for (final a in past.take(20))
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _AlertTile(alert: a),
              ),
          ],
        ],
      ),
    );
  }
}

class _AlertTile extends StatelessWidget {
  const _AlertTile({required this.alert});
  final InboxAlert alert;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final a = alert;
    final left = a.searchEndsAt.difference(DateTime.now());
    final live = left > Duration.zero && a.status != 'declined';
    final (label, bg, fg) = a.unlocked
        ? ('Débloquée', P.softGreen, P.green)
        : a.responded
        ? ('Répondu · ${formatXof(a.myTotalXof)}', P.softBlue, P.blue)
        : a.status == 'declined'
        ? ('Refusée', P.page, P.muted)
        : live
        ? ('À répondre · ${left.inMinutes + 1} min', P.softRed, P.red)
        : ('Expirée', P.page, P.muted);
    return PCard(
      border: live && !a.responded ? P.red : null,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => AlertDetailScreen(alertId: a.alertId),
        ),
      ),
      child: Row(
        children: [
          PIcon(
            a.photoCount > 0
                ? Icons.description_outlined
                : Icons.medication_outlined,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  a.title,
                  style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
                Text(
                  [
                    if (a.items.isNotEmpty)
                      '${a.items.length} produit${a.items.length > 1 ? 's' : ''}',
                    if (a.photoCount > 0)
                      '${a.photoCount} photo${a.photoCount > 1 ? 's' : ''}',
                    formatDistance(a.distanceM),
                    'reçue à ${hhmm(a.receivedAt)}',
                  ].join(' · '),
                  style: t.bodySmall?.copyWith(color: P.muted),
                ),
                const SizedBox(height: 6),
                PPill(label, bg: bg, fg: fg),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: P.muted),
        ],
      ),
    );
  }
}

/// Détail d'une alerte : produits et photos, réponse ligne par ligne.
class AlertDetailScreen extends ConsumerStatefulWidget {
  const AlertDetailScreen({super.key, required this.alertId});
  final String alertId;

  @override
  ConsumerState<AlertDetailScreen> createState() => _AlertDetailScreenState();
}

class _AlertDetailScreenState extends ConsumerState<AlertDetailScreen> {
  InboxAlert? _alert;
  List<ResponseLineDraft> _lines = [];
  final _note = TextEditingController();
  var _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final a = await ref
          .read(apiClientProvider)
          .pharmacyInboxItem(widget.alertId);
      setState(() {
        _alert = a;
        _lines = a.responded && a.myLines.isNotEmpty
            ? [
                for (final l in a.myLines)
                  ResponseLineDraft(
                    name: l.name,
                    quantity: l.quantity,
                    unitPriceXof: l.unitPriceXof,
                    available: l.available,
                    prescriptionRequired: l.prescriptionRequired,
                  ),
              ]
            : a.items.isEmpty
            ? [ResponseLineDraft(name: 'Ordonnance complète', quantity: 1)]
            : [
                for (final i in a.items)
                  ResponseLineDraft(
                    alertItemId: i.id,
                    name: i.name,
                    quantity: i.quantity,
                  ),
              ];
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    }
  }

  Future<void> _send() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(apiClientProvider)
          .pharmacyRespond(widget.alertId, _lines, note: _note.text.trim());
      ref.invalidate(inboxProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Réponse envoyée au patient.')),
        );
        Navigator.of(context).pop();
      }
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _decline() async {
    setState(() => _busy = true);
    try {
      await ref.read(apiClientProvider).pharmacyDecline(widget.alertId);
      ref.invalidate(inboxProvider);
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final a = _alert;
    final total = _lines
        .where((l) => l.available)
        .fold<int>(0, (s, l) => s + l.unitPriceXof * l.quantity);
    final canAnswer =
        a != null &&
        !a.unlocked &&
        a.searchEndsAt.isAfter(DateTime.now()) &&
        a.status != 'declined';
    return Scaffold(
      backgroundColor: P.page,
      appBar: AppBar(
        backgroundColor: P.page,
        title: const Text('Alerte médicament'),
      ),
      body: a == null
          ? Center(
              child: _error == null
                  ? const CircularProgressIndicator()
                  : Text(_error!),
            )
          : ListView(
              padding: const EdgeInsets.all(IviaSpacing.screen),
              children: [
                Text(
                  a.title,
                  style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                Text(
                  'Patient à ${formatDistance(a.distanceM)} · reçue à ${hhmm(a.receivedAt)}',
                  style: t.bodyMedium?.copyWith(color: P.muted),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: [
                    if (a.genericAccepted)
                      const PPill(
                        'Générique accepté',
                        bg: P.softBlue,
                        fg: P.blue,
                      ),
                    if (canAnswer)
                      PPill(
                        'Répondre avant ${hhmm(a.searchEndsAt)}',
                        bg: P.softRed,
                        fg: P.red,
                      ),
                  ],
                ),
                if (a.note.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  PCard(
                    color: P.softYellow,
                    child: Text('« ${a.note} »', style: t.bodyLarge),
                  ),
                ],
                if (a.photos.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 220,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: a.photos.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 10),
                      itemBuilder: (context, i) {
                        final ph = a.photos[i];
                        return GestureDetector(
                          onTap: ph.url == null
                              ? null
                              : () => showDialog<void>(
                                  context: context,
                                  builder: (_) => Dialog(
                                    child: InteractiveViewer(
                                      child: Image.network(ph.url!),
                                    ),
                                  ),
                                ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: ph.url == null
                                ? Container(
                                    width: 180,
                                    color: const Color(0xFFE3E5E9),
                                    child: const Icon(
                                      Icons.image_not_supported,
                                    ),
                                  )
                                : Image.network(
                                    ph.url!,
                                    width: 180,
                                    fit: BoxFit.cover,
                                  ),
                          ),
                        );
                      },
                    ),
                  ),
                  Text(
                    'Photos visibles pendant l\'alerte seulement. Touchez pour agrandir.',
                    style: t.bodySmall?.copyWith(color: P.muted),
                  ),
                ],
                const SizedBox(height: 18),
                Text(
                  a.responded
                      ? 'Votre réponse'
                      : 'Votre réponse, produit par produit',
                  style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                for (final l in _lines)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: PCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${l.quantity} × ${l.name}',
                                  style: t.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              Switch(
                                value: l.available,
                                activeTrackColor: P.green,
                                onChanged: canAnswer
                                    ? (v) => setState(() => l.available = v)
                                    : null,
                              ),
                            ],
                          ),
                          Text(
                            l.available ? 'Disponible' : 'Indisponible',
                            style: t.bodySmall?.copyWith(
                              color: l.available ? P.green : P.muted,
                            ),
                          ),
                          if (l.available) ...[
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    initialValue: l.unitPriceXof == 0
                                        ? ''
                                        : '${l.unitPriceXof}',
                                    enabled: canAnswer,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                      labelText: 'Prix unitaire (F)',
                                    ),
                                    onChanged: (v) => setState(
                                      () => l.unitPriceXof =
                                          int.tryParse(
                                            v.replaceAll(RegExp(r'\D'), ''),
                                          ) ??
                                          0,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                SizedBox(
                                  width: 90,
                                  child: TextFormField(
                                    initialValue: '${l.quantity}',
                                    enabled: canAnswer,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                      labelText: 'Qté',
                                    ),
                                    onChanged: (v) => setState(
                                      () => l.quantity = (int.tryParse(v) ?? 1)
                                          .clamp(1, 99),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              value: l.prescriptionRequired,
                              onChanged: canAnswer
                                  ? (v) => setState(
                                      () => l.prescriptionRequired = v ?? false,
                                    )
                                  : null,
                              title: const Text('Sur ordonnance'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                if (canAnswer)
                  TextField(
                    controller: _note,
                    maxLength: 300,
                    decoration: const InputDecoration(
                      hintText: 'Message au patient (facultatif)',
                    ),
                  ),
                const SizedBox(height: 8),
                PCard(
                  color: P.navy,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Total proposé',
                          style: t.titleMedium?.copyWith(color: Colors.white70),
                        ),
                      ),
                      Text(
                        formatXof(total),
                        style: t.titleLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(_error!, style: const TextStyle(color: P.red)),
                  ),
                const SizedBox(height: 16),
                if (canAnswer) ...[
                  PButton(
                    label: a.responded
                        ? 'Mettre à jour ma réponse'
                        : 'Envoyer ma réponse',
                    icon: Icons.send,
                    busy: _busy,
                    onTap: _send,
                  ),
                  if (!a.responded)
                    TextButton(
                      onPressed: _busy ? null : _decline,
                      child: const Text('Je n\'ai pas ces produits'),
                    ),
                ] else
                  Text(
                    a.unlocked
                        ? 'Le patient a débloqué votre pharmacie : voyez l\'onglet Réservations.'
                        : 'Alerte terminée.',
                    style: t.bodyMedium,
                  ),
              ],
            ),
    );
  }
}

class _OrdersTab extends ConsumerWidget {
  const _OrdersTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final items = ref.watch(ordersProvider).value ?? const <PharmacyOrder>[];
    final active = items.where((o) => o.active).toList();
    final done = items.where((o) => !o.active).toList();
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(ordersProvider),
      child: ListView(
        padding: const EdgeInsets.all(IviaSpacing.screen),
        children: [
          const PTitle('Réservations ', 'à préparer'),
          const SizedBox(height: 12),
          if (active.isEmpty)
            PCard(
              child: Text('Aucune réservation en cours.', style: t.bodyMedium),
            ),
          for (final o in active)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _OrderTile(order: o),
            ),
          if (done.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Terminées',
              style: t.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: P.muted,
              ),
            ),
            const SizedBox(height: 8),
            for (final o in done.take(20))
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _OrderTile(order: o),
              ),
          ],
        ],
      ),
    );
  }
}

String orderStatusLabel(PharmacyOrder o) => switch (o.status) {
  'reserved' when o.preparedAt != null => 'Prête · client attendu',
  'reserved' => 'À préparer',
  'courier_search' => 'Recherche d\'un livreur',
  'awaiting_payment' => 'Livreur trouvé · paiement du client',
  'courier_assigned' => 'Livreur en route vers vous',
  'picked_up' => 'Récupérée par le livreur',
  'completed' => 'Remise',
  'expired' => 'Expirée',
  'cancelled' => 'Annulée',
  _ => o.status,
};

class _OrderTile extends StatelessWidget {
  const _OrderTile({required this.order});
  final PharmacyOrder order;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final o = order;
    return PCard(
      border: o.status == 'reserved' && o.preparedAt == null ? P.green : null,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => OrderScreen(orderId: o.id)),
      ),
      child: Row(
        children: [
          PIcon(o.delivery ? Icons.delivery_dining : Icons.storefront_outlined),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${o.number} · ${o.buyerFirstName.isEmpty ? 'Patient' : o.buyerFirstName}',
                  style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
                Text(
                  '${o.delivery ? 'Livraison ivia' : 'Retrait sur place'} · ${formatXof(o.itemsXof)}',
                  style: t.bodySmall?.copyWith(color: P.muted),
                ),
                const SizedBox(height: 6),
                PPill(orderStatusLabel(o)),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: P.muted),
        ],
      ),
    );
  }
}

/// Réservation : produits, préparation, remise par code ou au livreur.
class OrderScreen extends ConsumerStatefulWidget {
  const OrderScreen({super.key, required this.orderId});
  final String orderId;

  @override
  ConsumerState<OrderScreen> createState() => _OrderScreenState();
}

class _OrderScreenState extends ConsumerState<OrderScreen> {
  PharmacyOrder? _o;
  final _code = TextEditingController();
  var _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final o = await ref.read(apiClientProvider).pharmacyOrder(widget.orderId);
    if (mounted) setState(() => _o = o);
  }

  Future<void> _do(
    Future<void> Function(IviaApiClient api) a,
    String done,
  ) async {
    setState(() => _busy = true);
    try {
      await a(ref.read(apiClientProvider));
      ref.invalidate(ordersProvider);
      ref.invalidate(earningsProvider);
      await _load();
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(done)));
    } on ApiException catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final o = _o;
    return Scaffold(
      backgroundColor: P.page,
      appBar: AppBar(
        backgroundColor: P.page,
        title: Text(o == null ? 'Réservation' : 'Réservation ${o.number}'),
      ),
      body: o == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(IviaSpacing.screen),
              children: [
                PCard(
                  color: o.active ? P.green : P.navy,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        orderStatusLabel(o),
                        style: t.titleLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        '${o.buyerFirstName.isEmpty ? 'Patient' : o.buyerFirstName} · ${o.delivery ? 'livraison ivia' : 'retrait sur place'}'
                        '${o.expiresAt != null && o.active ? ' · mis de côté jusqu\'à ${hhmm(o.expiresAt!)}' : ''}',
                        style: t.bodyMedium?.copyWith(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                PCard(
                  child: Column(
                    children: [
                      for (final l in o.lines.where((l) => l.available))
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${l.quantity} × ${l.name}${l.prescriptionRequired ? ' · ordonnance' : ''}',
                                  style: t.bodyLarge,
                                ),
                              ),
                              Text(
                                formatXof(l.lineTotalXof),
                                style: t.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      const Divider(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              o.delivery
                                  ? 'Payé par le patient dans l\'app'
                                  : 'À encaisser au comptoir',
                              style: t.titleSmall,
                            ),
                          ),
                          Text(
                            formatXof(o.itemsXof),
                            style: t.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (o.prescriptionRequired) ...[
                  const SizedBox(height: 12),
                  PCard(
                    color: P.softYellow,
                    child: Text(
                      'Ordonnance exigée : vérifiez l\'original à la remise.',
                      style: t.bodyMedium,
                    ),
                  ),
                ],
                if (o.courier case final c?) ...[
                  const SizedBox(height: 12),
                  PCard(
                    child: Row(
                      children: [
                        const PIcon(
                          Icons.two_wheeler,
                          bg: P.softBlue,
                          fg: P.blue,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '${c.firstName} · livreur ivia${c.vehiclePlate.isEmpty ? '' : ' · ${c.vehiclePlate}'}',
                            style: t.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                if (o.active && o.preparedAt == null && o.status != 'picked_up')
                  PButton(
                    label: 'Commande prête',
                    icon: Icons.check,
                    busy: _busy,
                    onTap: () => _do(
                      (api) => api.pharmacyMarkPrepared(o.id),
                      'Le patient est prévenu.',
                    ),
                  ),
                if (o.active && !o.delivery && o.status == 'reserved') ...[
                  const SizedBox(height: 14),
                  PCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Remise au comptoir',
                          style: t.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          'Demandez le code à 4 chiffres affiché dans l\'app du patient.',
                          style: t.bodyMedium?.copyWith(color: P.muted),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _code,
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                          textAlign: TextAlign.center,
                          style: t.headlineMedium?.copyWith(
                            letterSpacing: 12,
                            fontWeight: FontWeight.w800,
                          ),
                          decoration: const InputDecoration(
                            counterText: '',
                            hintText: '• • • •',
                          ),
                        ),
                        const SizedBox(height: 10),
                        PButton(
                          label: 'Valider la remise',
                          color: P.navy,
                          busy: _busy,
                          onTap: () => _do(
                            (api) => api.pharmacyCompletePickup(
                              o.id,
                              _code.text.trim(),
                            ),
                            'Remise enregistrée.',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (o.active && o.status == 'reserved')
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => _do(
                            (api) => api.pharmacyCancelOrder(
                              o.id,
                              'Produit plus disponible',
                            ),
                            'Réservation annulée, patient remboursé.',
                          ),
                    child: const Text('Produit plus disponible : annuler'),
                  ),
              ],
            ),
    );
  }
}

class _OfficeTab extends ConsumerStatefulWidget {
  const _OfficeTab();

  @override
  ConsumerState<_OfficeTab> createState() => _OfficeTabState();
}

class _OfficeTabState extends ConsumerState<_OfficeTab> {
  var _busy = false;

  Future<void> _set(
    PharmacyProfile p, {
    bool? open,
    bool? duty,
    bool? h24,
  }) async {
    setState(() => _busy = true);
    try {
      await ref
          .read(apiClientProvider)
          .setPharmacyStatus(
            isOpen: open ?? p.isOpen,
            onDuty: duty ?? p.onDuty,
            open24h: h24 ?? p.open24h,
          );
      ref.invalidate(pharmacyProfileProvider);
    } on ApiException catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final p = ref.watch(pharmacyProfileProvider).value;
    final shifts = ref.watch(shiftsProvider).value ?? const [];
    if (p == null) return const Center(child: CircularProgressIndicator());
    final open = p.isOpen || p.onDuty || p.open24h;
    Widget toggle(String title, String sub, bool v, void Function(bool) on) =>
        SwitchListTile(
          title: Text(
            title,
            style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          subtitle: Text(sub),
          value: v,
          activeTrackColor: P.green,
          onChanged: _busy ? null : on,
        );
    return ListView(
      padding: const EdgeInsets.all(IviaSpacing.screen),
      children: [
        const PTitle('Mon ', 'officine'),
        const SizedBox(height: 14),
        PCard(
          color: open ? P.green : P.navy,
          child: Row(
            children: [
              Icon(
                open ? Icons.storefront : Icons.no_meeting_room_outlined,
                color: Colors.white,
                size: 34,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.name,
                      style: t.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      p.onDuty
                          ? 'De garde : vous recevez les alertes de nuit'
                          : open
                          ? 'Ouverte : vous recevez les alertes'
                          : 'Fermée : aucune alerte',
                      style: t.bodyMedium?.copyWith(color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        PCard(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            children: [
              toggle(
                'Ouverte',
                p.openingHours.isEmpty ? 'Horaires habituels' : p.openingHours,
                p.isOpen,
                (v) => _set(p, open: v),
              ),
              const Divider(height: 1),
              toggle(
                'De garde',
                'Visible dans « De garde maintenant »',
                p.onDuty,
                (v) => _set(p, duty: v),
              ),
              const Divider(height: 1),
              toggle(
                'Ouverte 24 h/24',
                'Toujours joignable',
                p.open24h,
                (v) => _set(p, h24: v),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'Planning de garde',
          style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        PCard(
          child: shifts.isEmpty
              ? Text(
                  'Aucune garde planifiée par l\'Ordre ou par ivia.',
                  style: t.bodyMedium,
                )
              : Column(
                  children: [
                    for (final s in shifts)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const PIcon(
                          Icons.nightlight_outlined,
                          size: 42,
                        ),
                        title: Text(
                          '${s.startsAt.toLocal().day}/${s.startsAt.toLocal().month} · ${hhmm(s.startsAt)} → ${hhmm(s.endsAt)}',
                        ),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 18),
        PCard(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            children: [
              ListTile(
                leading: const PIcon(Icons.call_outlined, size: 42),
                title: const Text('Téléphone'),
                subtitle: Text(p.phone),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const PIcon(Icons.place_outlined, size: 42),
                title: const Text('Adresse'),
                subtitle: Text(p.addressText),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const PIcon(Icons.devices_outlined, size: 42),
                title: const Text('Appareils connectés'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ConnectedDevicesScreen(),
                  ),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const PIcon(
                  Icons.logout,
                  bg: P.softRed,
                  fg: P.red,
                  size: 42,
                ),
                title: const Text(
                  'Se déconnecter',
                  style: TextStyle(color: P.red, fontWeight: FontWeight.w800),
                ),
                onTap: () =>
                    ref.read(authControllerProvider.notifier).signOut(),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BalanceTab extends ConsumerWidget {
  const _BalanceTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final e = ref.watch(earningsProvider).value;
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(earningsProvider),
      child: ListView(
        padding: const EdgeInsets.all(IviaSpacing.screen),
        children: [
          const PTitle('Mon ', 'solde'),
          const SizedBox(height: 14),
          PCard(
            color: P.navy,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'À recevoir d\'ivia',
                  style: t.bodyMedium?.copyWith(color: Colors.white70),
                ),
                Text(
                  formatXof(e?.balanceXof ?? 0),
                  style: t.displaySmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  'Ventes livrées payées dans l\'app, sans commission.',
                  style: t.bodySmall?.copyWith(color: Colors.white70),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _Num(
                  label: 'Livrées',
                  value: '${e?.deliveredCount ?? 0}',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _Num(label: 'Retraits', value: '${e?.pickupCount ?? 0}'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _Num(
                  label: 'Déjà versé',
                  value: formatXof(e?.paidOutXof ?? 0),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            'Reversements',
            style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          if (e == null || e.payouts.isEmpty)
            PCard(
              child: Text(
                'Aucun reversement pour l\'instant.',
                style: t.bodyMedium,
              ),
            ),
          for (final p
              in e?.payouts ??
                  const <({int amountXof, String reference, DateTime at})>[])
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: PCard(
                child: Row(
                  children: [
                    const PIcon(Icons.payments_outlined),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '${p.at.toLocal().day}/${p.at.toLocal().month} · ${p.reference}',
                        style: t.titleSmall,
                      ),
                    ),
                    Text(
                      '+${formatXof(p.amountXof)}',
                      style: t.titleMedium?.copyWith(
                        color: P.green,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Num extends StatelessWidget {
  const _Num({required this.label, required this.value});
  final String label, value;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return PCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          Text(label, style: t.bodySmall?.copyWith(color: P.muted)),
        ],
      ),
    );
  }
}
