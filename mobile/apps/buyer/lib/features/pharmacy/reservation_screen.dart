import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';
import 'package:flutter/services.dart';

import '../../app/router.dart';
import '../orders/invoice.dart';
import 'alert_screen.dart';
import 'med_ui.dart';
import 'pharmacy_state.dart';

/// Réservation après déblocage : P10 (votre pharmacie, choix du mode), P11
/// (livraison, recherche du livreur puis paiement) ou P12 (suivi).
class ReservationScreen extends ConsumerStatefulWidget {
  const ReservationScreen({super.key, required this.reservationId});
  final String reservationId;

  @override
  ConsumerState<ReservationScreen> createState() => _ReservationScreenState();
}

class _ReservationScreenState extends ConsumerState<ReservationScreen>
    with LivePolling {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    startPolling(
      () => ref.invalidate(medReservationProvider(widget.reservationId)),
    );
    _tick = Timer.periodic(
      const Duration(seconds: 1),
      (_) => mounted ? setState(() {}) : null,
    );
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(medReservationProvider(widget.reservationId));
    final r = async.value;
    if (r == null) {
      return MedScaffold(
        top: const MedTopBar(title: 'Votre pharmacie'),
        body: Center(
          child: async.hasError
              ? const Text('Réservation indisponible.')
              : const CircularProgressIndicator(),
        ),
      );
    }
    if (r.delivery &&
        ['courier_assigned', 'picked_up', 'completed'].contains(r.status)) {
      return _TrackingView(r: r);
    }
    if (r.delivery && r.status != 'cancelled' && r.status != 'expired') {
      return _DeliveryView(r: r);
    }
    return _PharmacyView(r: r);
  }
}

String _countdown(DateTime? until, DateTime now) {
  if (until == null) return '';
  final d = until.difference(now);
  if (d.isNegative) return '00:00';
  return '${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
}

class _Lines extends StatelessWidget {
  const _Lines({required this.r, this.withDelivery = false});
  final MedReservation r;
  final bool withDelivery;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return MedCard(
      child: Column(
        children: [
          if (withDelivery) ...[
            _row(t, 'Produits', formatXof(r.itemsXof)),
            _row(
              t,
              'Livraison · moto${r.distanceM > 0 ? ', ${formatDistance(r.distanceM)}' : ''}',
              formatXof(r.deliveryFeeXof),
            ),
          ] else
            for (final l in r.lines.where((l) => l.available))
              _row(t, '${l.name} ×${l.quantity}', formatXof(l.lineTotalXof)),
          const Divider(height: 28),
          Row(
            children: [
              Expanded(
                child: Text(
                  withDelivery ? 'Total' : 'Total produits',
                  style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                formatXof(withDelivery ? r.totalXof : r.itemsXof),
                style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static Widget _row(TextTheme t, String a, String b) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Expanded(child: Text(a, style: t.bodyLarge)),
        Text(b, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
      ],
    ),
  );
}

/// P10 : votre pharmacie (débloquée), choix du mode.
class _PharmacyView extends ConsumerStatefulWidget {
  const _PharmacyView({required this.r});
  final MedReservation r;

  @override
  ConsumerState<_PharmacyView> createState() => _PharmacyViewState();
}

class _PharmacyViewState extends ConsumerState<_PharmacyView> {
  BuyerAddress? _address;
  MedDeliveryQuote? _quote;
  var _busy = false;

  @override
  void initState() {
    super.initState();
    _loadQuote();
  }

  Future<void> _loadQuote() async {
    try {
      final api = ref.read(apiClientProvider);
      final list = await api.addresses();
      if (list.isEmpty) return;
      final q = await api.medDeliveryQuote(widget.r.id, list.first.id);
      if (mounted) {
        setState(() {
          _address = list.first;
          _quote = q;
        });
      }
    } on ApiException {
      // Devis indisponible : « Me faire livrer » reste proposé.
    }
  }

  Future<void> _deliver() async {
    var address = _address;
    address ??= await pickDeliveryAddress(context, ref, widget.r.id);
    if (address == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(apiClientProvider)
          .chooseMedDelivery(widget.r.id, address.id);
      ref.invalidate(medReservationProvider(widget.r.id));
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.r;
    final t = Theme.of(context).textTheme;
    final now = ref.read(apiClientProvider).now();
    final ended =
        r.status == 'cancelled' ||
        r.status == 'expired' ||
        r.status == 'completed';
    final loc = r.pharmacy.location;
    return MedScaffold(
      top: MedTopBar(
        title: 'Votre pharmacie',
        centered: true,
        trailing: MedRoundButton(
          icon: Icons.share_outlined,
          tooltip: 'Partager',
          onTap: () async {
            await Clipboard.setData(
              ClipboardData(
                text:
                    '${r.pharmacy.name}\n${r.pharmacy.addressText}\n${r.pharmacy.phone}',
              ),
            );
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Adresse de la pharmacie copiée.'),
                ),
              );
            }
          },
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          IviaSpacing.screen,
          0,
          IviaSpacing.screen,
          IviaSpacing.xxl,
        ),
        children: [
          SizedBox(
            height: 170,
            child: Stack(
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(Med.radius),
                    child: loc == null
                        ? Container(color: const Color(0xFFE3E5E9))
                        : MedMap(center: loc, markers: [loc]),
                  ),
                ),
                const Positioned(
                  left: 14,
                  top: 14,
                  child: MedPill('🔓 Débloquée'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          MedCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.pharmacy.name,
                  style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    r.pharmacy.addressText,
                    if (r.distanceM > 0) formatDistance(r.distanceM),
                  ].join(' · '),
                  style: t.bodyLarge?.copyWith(color: Med.muted),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    const MedPill(
                      'De garde',
                      bg: Color(0xFFDDE7F7),
                      fg: Med.blue,
                    ),
                    if (!ended && r.expiresAt != null)
                      MedPill(
                        'Mis de côté — ${_countdown(r.expiresAt, now)}',
                        bg: Med.softRed,
                        fg: IviaColors.primary,
                      ),
                    if (ended)
                      MedPill(
                        reservationStatusLabel(r),
                        bg: Med.page,
                        fg: Med.muted,
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _GreyButton(
                        icon: Icons.call_outlined,
                        label: 'Appeler',
                        onTap: () => callNumber(r.pharmacy.phone),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _GreyButton(
                        icon: Icons.directions_outlined,
                        label: 'Itinéraire',
                        onTap: loc == null ? null : () => openDirections(loc),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _Lines(r: r),
          if (!ended) ...[
            const SizedBox(height: 22),
            Text(
              'Comment récupérer vos produits ?',
              style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _ModeCard(
                    icon: Icons.delivery_dining,
                    red: true,
                    title: 'Me faire livrer',
                    subtitle: _quote == null
                        ? 'Livreur ivia'
                        : '≈ ${_quote!.etaMinutes} min · ${formatXof(_quote!.deliveryFeeXof)}',
                    selected: true,
                    onTap: _busy ? null : _deliver,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ModeCard(
                    icon: Icons.directions_walk,
                    title: 'J\'y vais',
                    subtitle: r.walkMinutes > 0
                        ? '${r.walkMinutes} min à pied'
                        : 'Retrait sur place',
                    selected: false,
                    onTap: () => context.push(Routes.medPickup(r.id)),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _GreyButton extends StatelessWidget {
  const _GreyButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 60,
    child: FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: Med.page,
        foregroundColor: Med.navy,
        shape: const StadiumBorder(),
      ),
      onPressed: onTap,
      icon: Icon(icon),
      label: Text(
        label,
        style: Theme.of(context).textTheme.titleMedium
            ?.copyWith(fontWeight: FontWeight.w800),
      ),
    ),
  );
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    this.red = false,
  });

  final IconData icon;
  final String title, subtitle;
  final bool selected, red;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return MedCard(
      border: selected ? IviaColors.primary : null,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MedIconTile(
            icon,
            bg: red ? Med.softRed : Med.softBlue,
            fg: red ? IviaColors.primary : Med.navy,
          ),
          const SizedBox(height: 30),
          Text(
            title,
            style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          Text(subtitle, style: t.bodyMedium?.copyWith(color: Med.muted)),
        ],
      ),
    );
  }
}

/// Choix (ou création à la position actuelle) d'une adresse de livraison.
Future<BuyerAddress?> pickDeliveryAddress(
  BuildContext context,
  WidgetRef ref,
  String reservationId,
) => showModalBottomSheet<BuyerAddress>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _AddressSheet(reservationId: reservationId),
);

class _AddressSheet extends ConsumerStatefulWidget {
  const _AddressSheet({required this.reservationId});
  final String reservationId;

  @override
  ConsumerState<_AddressSheet> createState() => _AddressSheetState();
}

class _AddressSheetState extends ConsumerState<_AddressSheet> {
  List<BuyerAddress>? _list;
  final _label = TextEditingController(text: 'Maison');
  final _text = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    ref.read(apiClientProvider).addresses().then((l) {
      if (mounted) setState(() => _list = l);
    }, onError: (_) => mounted ? setState(() => _list = []) : null);
  }

  @override
  void dispose() {
    _label.dispose();
    _text.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final p = await alertPosition(context, ref);
    if (p == null) {
      setState(
        () => _error =
            'Position indisponible : choisissez votre quartier sur l\'accueil.',
      );
      return;
    }
    try {
      final a = await ref
          .read(apiClientProvider)
          .createAddress(
            label: _label.text.trim().isEmpty ? 'Maison' : _label.text.trim(),
            addressText: _text.text.trim().isEmpty
                ? 'Ma position'
                : _text.text.trim(),
            location: p,
          );
      if (mounted) Navigator.pop(context, a);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Livrer à',
              style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            if (_list == null) const Center(child: CircularProgressIndicator()),
            for (final a in _list ?? const <BuyerAddress>[])
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const MedIconTile(
                  Icons.place_outlined,
                  bg: Med.softRed,
                  fg: IviaColors.primary,
                ),
                title: Text(
                  a.label,
                  style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(a.addressText),
                onTap: () => Navigator.pop(context, a),
              ),
            const SizedBox(height: 10),
            Text(
              'Nouvelle adresse à ma position',
              style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _label,
              decoration: const InputDecoration(
                hintText: 'Nom (Maison, Bureau…)',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _text,
              decoration: const InputDecoration(
                hintText: 'Repère (rue, portail vert…)',
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: const TextStyle(color: IviaColors.error),
                ),
              ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _create,
              icon: const Icon(Icons.my_location),
              label: const Text('Utiliser ma position'),
            ),
          ],
        ),
      ),
    );
  }
}

/// P11 : livraison (adresse, pharmacie, total) ; recherche du livreur puis
/// paiement une fois le livreur trouvé.
class _DeliveryView extends ConsumerStatefulWidget {
  const _DeliveryView({required this.r});
  final MedReservation r;

  @override
  ConsumerState<_DeliveryView> createState() => _DeliveryViewState();
}

class _DeliveryViewState extends ConsumerState<_DeliveryView> {
  var _busy = false;

  Future<void> _change() async {
    final a = await pickDeliveryAddress(context, ref, widget.r.id);
    if (a == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final api = ref.read(apiClientProvider);
      await api.chooseMedPickup(widget.r.id);
      await api.chooseMedDelivery(widget.r.id, a.id);
      ref.invalidate(medReservationProvider(widget.r.id));
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.r;
    final t = Theme.of(context).textTheme;
    final searching = r.status == 'courier_search' || r.status == 'reserved';
    final found = r.status == 'awaiting_payment';
    return MedScaffold(
      top: const MedTopBar(title: 'Livraison', centered: true),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: IviaSpacing.screen),
        children: [
          MedCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Livrer à',
                        style: t.titleSmall?.copyWith(
                          color: Med.muted,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (!found)
                      TextButton(
                        onPressed: _busy ? null : _change,
                        child: const Text('Changer'),
                      ),
                  ],
                ),
                Row(
                  children: [
                    const MedIconTile(
                      Icons.place_outlined,
                      bg: Med.softRed,
                      fg: IviaColors.primary,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        r.deliveryAddress.isEmpty
                            ? 'Adresse de livraison'
                            : r.deliveryAddress,
                        style: t.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          MedCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Depuis',
                  style: t.titleSmall?.copyWith(
                    color: Med.muted,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const MedIconTile(Icons.add_box_outlined),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            r.pharmacy.name,
                            style: t.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            'Moto${r.deliveryEtaMinutes != null ? ' · ≈ ${r.deliveryEtaMinutes} min' : ''}',
                            style: t.bodyMedium?.copyWith(color: Med.muted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (r.prescriptionRequired) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Med.softYellow,
                borderRadius: BorderRadius.circular(Med.radius),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.description_outlined, color: Med.yellow),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text.rich(
                      const TextSpan(
                        children: [
                          TextSpan(text: 'Médicament sur ordonnance : '),
                          TextSpan(
                            text: 'montrez l\'original au livreur',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                          TextSpan(text: ' à la remise, avec votre code.'),
                        ],
                      ),
                      style: t.bodyLarge,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          _Lines(r: r, withDelivery: true),
          const SizedBox(height: 16),
          if (searching)
            MedCard(
              child: Row(
                children: [
                  const SizedBox.square(
                    dimension: 26,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: IviaColors.primary,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Recherche du livreur ivia le plus proche',
                          style: t.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          'Vous payez dès qu\'un livreur accepte la course.',
                          style: t.bodyMedium?.copyWith(color: Med.muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          if (found && r.courier != null)
            MedCard(
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 26,
                    backgroundColor: Med.page,
                    child: Icon(Icons.two_wheeler, color: Med.navy),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      '${r.courier!.firstName} a accepté la course',
                      style: t.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (searching)
            TextButton(
              onPressed: _busy
                  ? null
                  : () async {
                      await ref.read(apiClientProvider).chooseMedPickup(r.id);
                      ref.invalidate(medReservationProvider(r.id));
                    },
              child: const Text('Finalement, j\'y vais moi-même'),
            ),
        ],
      ),
      bottom: MedBottomButton(
        label: found
            ? 'Payer ${formatXof(r.totalXof)}'
            : 'En attente d\'un livreur…',
        onTap: found
            ? () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => MedPaymentPage(
                    title: 'Payer la livraison',
                    header: _Lines(r: r, withDelivery: true),
                    amountXof: r.totalXof,
                    start: (op, phone) async => (
                      await ref
                          .read(apiClientProvider)
                          .payMedReservation(r.id, operator: op, phone: phone),
                      r.id,
                    ),
                    onPaid: (_) async {
                      ref.invalidate(medReservationProvider(r.id));
                      if (context.mounted) Navigator.of(context).pop();
                    },
                  ),
                ),
              )
            : null,
      ),
    );
  }
}

/// P12 : suivi de la livraison.
class _TrackingView extends ConsumerWidget {
  const _TrackingView({required this.r});
  final MedReservation r;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final done = r.status == 'completed';
    final eta = r.deliveryEtaMinutes;
    final arrival = eta == null
        ? null
        : (r.pickedUpAt ?? r.paidAt ?? DateTime.now()).add(
            Duration(minutes: eta),
          );
    final steps = [
      ('Paiement reçu', r.paidAt),
      ('Préparée par la pharmacie', r.preparedAt),
      ('Récupérée par le livreur', r.pickedUpAt),
      ('Livrée', r.deliveredAt),
    ];
    final current = steps.lastIndexWhere((s) => s.$2 != null);
    return MedScaffold(
      top: MedTopBar(title: 'Livraison #${r.number}', centered: true),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: IviaSpacing.screen),
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: done ? Med.navy : IviaColors.primary,
              borderRadius: BorderRadius.circular(Med.radius),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        done
                            ? 'Livrée'
                            : (r.status == 'picked_up'
                                  ? 'Livreur en route'
                                  : 'Le livreur va à la pharmacie'),
                        style: t.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const MedPill('Moto', fg: IviaColors.primary),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  done
                      ? 'Remise à ${hhmm(r.deliveredAt ?? DateTime.now())}'
                      : arrival == null
                      ? 'Arrivée bientôt'
                      : 'Arrivée vers ${hhmm(arrival)}',
                  style: t.headlineMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (!done && r.handoverCode.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text(
                    'Votre code de remise',
                    style: t.bodyLarge?.copyWith(color: Colors.white),
                  ),
                  const SizedBox(height: 12),
                  MedCodeBoxes(r.handoverCode, color: IviaColors.primary),
                ],
              ],
            ),
          ),
          if (r.courier case final c?) ...[
            const SizedBox(height: 14),
            MedCard(
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 30,
                    backgroundColor: Med.page,
                    child: Icon(Icons.person, color: Med.muted),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          c.firstName,
                          style: t.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          [
                            'Livreur ivia',
                            if (c.vehiclePlate.isNotEmpty) c.vehiclePlate,
                          ].join(' · '),
                          style: t.bodyMedium?.copyWith(color: Med.muted),
                        ),
                      ],
                    ),
                  ),
                  if (c.phone.isNotEmpty)
                    Material(
                      color: Med.navy,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => callNumber(c.phone),
                        child: const SizedBox.square(
                          dimension: 56,
                          child: Icon(Icons.call_outlined, color: Colors.white),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          MedCard(
            child: Column(
              children: [
                for (final (i, (label, at)) in steps.indexed)
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: 28,
                          child: Column(
                            children: [
                              Container(
                                width: 22,
                                height: 22,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: at != null && i < current
                                      ? IviaColors.primary
                                      : Colors.white,
                                  border: Border.all(
                                    color: at != null
                                        ? IviaColors.primary
                                        : const Color(0xFFC9CDD4),
                                    width: i == current ? 5 : 2,
                                  ),
                                ),
                              ),
                              if (i < steps.length - 1)
                                Expanded(
                                  child: Container(
                                    width: 4,
                                    color: i < current
                                        ? IviaColors.primary
                                        : const Color(0xFFE3E5E9),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 26),
                            child: Text(
                              label,
                              style: t.titleMedium?.copyWith(
                                fontWeight: at != null
                                    ? FontWeight.w800
                                    : FontWeight.w400,
                                color: at != null ? Med.navy : Med.muted,
                              ),
                            ),
                          ),
                        ),
                        if (at != null)
                          Text(
                            hhmm(at),
                            style: t.bodyMedium?.copyWith(color: Med.muted),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          if (r.paidAt != null) _InvoiceButton(r: r),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

/// P13 : retrait sur place (carte, code, itinéraire).
class PickupScreen extends ConsumerStatefulWidget {
  const PickupScreen({super.key, required this.reservationId});
  final String reservationId;

  @override
  ConsumerState<PickupScreen> createState() => _PickupScreenState();
}

class _PickupScreenState extends ConsumerState<PickupScreen> with LivePolling {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    startPolling(
      () => ref.invalidate(medReservationProvider(widget.reservationId)),
    );
    _tick = Timer.periodic(
      const Duration(seconds: 1),
      (_) => mounted ? setState(() {}) : null,
    );
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final r = ref.watch(medReservationProvider(widget.reservationId)).value;
    if (r == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final loc = r.pharmacy.location;
    final now = ref.read(apiClientProvider).now();
    return Scaffold(
      backgroundColor: Med.page,
      body: Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: MediaQuery.sizeOf(context).height * .42,
            child: loc == null
                ? Container(color: const Color(0xFFE3E5E9))
                : MedMap(center: loc, markers: [loc], zoom: 15.5),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(IviaSpacing.screen),
              child: Row(
                children: [
                  MedRoundButton(
                    icon: Icons.arrow_back,
                    onTap: () => (context.canPop()
                        ? context.pop()
                        : context.go('/pharmacy')),
                  ),
                  const Spacer(),
                  MedRoundButton(
                    icon: Icons.call_outlined,
                    onTap: () => callNumber(r.pharmacy.phone),
                  ),
                ],
              ),
            ),
          ),
          Positioned.fill(
            top: MediaQuery.sizeOf(context).height * .38,
            child: Container(
              decoration: const BoxDecoration(
                color: Med.page,
                borderRadius: BorderRadius.vertical(top: Radius.circular(36)),
              ),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  IviaSpacing.screen,
                  28,
                  IviaSpacing.screen,
                  120,
                ),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          r.pharmacy.name,
                          style: t.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (r.expiresAt != null && r.status == 'reserved')
                        MedPill(
                          '— ${_countdown(r.expiresAt, now)}',
                          bg: Med.softRed,
                          fg: IviaColors.primary,
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    [
                      if (r.distanceM > 0) formatDistance(r.distanceM),
                      if (r.walkMinutes > 0) '${r.walkMinutes} min à pied',
                    ].join(' · '),
                    style: t.bodyLarge?.copyWith(color: Med.muted),
                  ),
                  const SizedBox(height: 18),
                  if (r.status == 'completed')
                    MedCard(
                      child: Text(
                        'Produits remis. Merci !',
                        style: t.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE6E8EC),
                        borderRadius: BorderRadius.circular(Med.radius),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Code de retrait à montrer',
                            style: t.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 14),
                          MedCodeBoxes(r.handoverCode),
                        ],
                      ),
                    ),
                  if (r.status == 'completed') _InvoiceButton(r: r),
                  const SizedBox(height: 18),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.payments_outlined, color: Med.blue),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            children: [
                              const TextSpan(
                                text: 'Vous payez les produits sur place : ',
                              ),
                              TextSpan(
                                text: formatXof(r.itemsXof),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              TextSpan(
                                text: r.prescriptionRequired
                                    ? '. Apportez l\'original de l\'ordonnance.'
                                    : '.',
                              ),
                            ],
                          ),
                          style: t.bodyLarge,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: MedBottomButton(
        label: 'Ouvrir l\'itinéraire',
        icon: Icons.directions_outlined,
        onTap: loc == null ? null : () => openDirections(loc),
      ),
    );
  }
}

/// « Télécharger la facture » d'une réservation réglée.
class _InvoiceButton extends ConsumerWidget {
  const _InvoiceButton({required this.r});
  final MedReservation r;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
    padding: const EdgeInsets.only(top: 14),
    child: OutlinedButton.icon(
      onPressed: () {
        final me = switch (ref.read(authControllerProvider)) {
          AuthSignedIn(:final user) => user,
          _ => null,
        };
        Invoice.fromReservation(r, me).download();
      },
      icon: const Icon(Icons.receipt_long_outlined),
      label: const Text('Télécharger la facture'),
    ),
  );
}
