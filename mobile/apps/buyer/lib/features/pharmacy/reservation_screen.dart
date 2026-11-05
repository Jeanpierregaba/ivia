import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import 'pay_sheet.dart';
import 'pharmacy_state.dart';

/// P08 à P14 : réservation après le déblocage. Code de remise, mise de côté,
/// pharmacie révélée, choix retrait sur place ou livreur ivia (recherche du
/// livreur puis paiement), suivi jusqu'à la remise.
class ReservationScreen extends ConsumerStatefulWidget {
  const ReservationScreen({super.key, required this.reservationId});

  final String reservationId;

  @override
  ConsumerState<ReservationScreen> createState() => _ReservationScreenState();
}

class _ReservationScreenState extends ConsumerState<ReservationScreen>
    with LivePolling {
  var _busy = false;

  @override
  void initState() {
    super.initState();
    startPolling(
      () => ref.invalidate(medReservationProvider(widget.reservationId)),
    );
  }

  IviaApiClient get _api => ref.read(apiClientProvider);

  void _toast(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      ref.invalidate(medReservationProvider(widget.reservationId));
    } on ApiException catch (e) {
      _toast(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _chooseDelivery(MedReservation r) async {
    final address = await showModalBottomSheet<BuyerAddress>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _AddressSheet(reservationId: r.id),
    );
    if (address == null) return;
    await _run(() => _api.chooseMedDelivery(r.id, address.id));
  }

  Future<void> _pay(MedReservation r) async {
    final paid = await showMedPaySheet(
      context,
      title: 'Médicaments et livraison',
      amountXof: r.totalXof,
      start: (op, phone) =>
          _api.payMedReservation(r.id, operator: op, phone: phone),
    );
    if (paid != null) {
      ref.invalidate(medReservationProvider(widget.reservationId));
      _toast('Paiement reçu : le livreur part chercher votre commande.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(medReservationProvider(widget.reservationId));
    final r = async.value;
    if (r != null && r.finished) stopPolling();
    return Scaffold(
      appBar: AppBar(
        title: Text(r == null ? 'Réservation' : 'Réservation ${r.number}'),
      ),
      body: SafeArea(
        child: r == null
            ? Center(
                child: async.hasError
                    ? Text(
                        async.error is ApiException
                            ? (async.error as ApiException).message
                            : 'Réservation indisponible.',
                      )
                    : const CircularProgressIndicator(),
              )
            : _body(context, r),
      ),
    );
  }

  Widget _body(BuildContext context, MedReservation r) {
    final t = Theme.of(context).textTheme;
    final brand = IviaAppBrand.of(context);
    final left = r.expiresAt?.difference(_api.now());
    final canChoose = r.status == 'reserved';
    return ListView(
      padding: const EdgeInsets.all(IviaSpacing.screen),
      children: [
        // Statut et code de remise.
        Container(
          padding: const EdgeInsets.all(IviaSpacing.lg),
          decoration: BoxDecoration(
            color: r.status == 'cancelled' || r.status == 'expired'
                ? IviaColors.textSecondary
                : brand.accent,
            borderRadius: BorderRadius.circular(IviaRadius.large),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                reservationStatusLabel(r),
                style: t.titleLarge?.copyWith(color: Colors.white),
              ),
              if (left != null &&
                  left > Duration.zero &&
                  !r.finished &&
                  r.paidAt == null)
                Text(
                  'Mis de côté encore ${left.inMinutes + 1} min',
                  style: t.bodyMedium?.copyWith(color: Colors.white70),
                ),
              if (r.handoverCode.isNotEmpty && !r.finished) ...[
                const SizedBox(height: IviaSpacing.lg),
                Text(
                  r.delivery
                      ? 'Code à donner au livreur'
                      : 'Code à donner à la pharmacie',
                  style: t.bodySmall?.copyWith(color: Colors.white70),
                ),
                Text(
                  r.handoverCode.split('').join(' '),
                  style: t.displaySmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
              if (r.status == 'cancelled' && r.cancelReason.isNotEmpty)
                Text(
                  r.cancelReason,
                  style: t.bodyMedium?.copyWith(color: Colors.white),
                ),
            ],
          ),
        ),
        const SizedBox(height: IviaSpacing.lg),
        // Pharmacie révélée.
        Card(
          child: ListTile(
            leading: const Icon(Icons.local_pharmacy),
            title: Text(r.pharmacy.name),
            subtitle: Text(
              [
                r.pharmacy.addressText,
                if (r.distanceM > 0)
                  '${formatDistance(r.distanceM)} · ${r.walkMinutes} min à pied',
              ].where((s) => s.isNotEmpty).join('\n'),
            ),
            isThreeLine: true,
            trailing: r.pharmacy.phone.isEmpty
                ? null
                : IconButton.filled(
                    tooltip: 'Appeler la pharmacie',
                    icon: const Icon(Icons.call),
                    onPressed: () =>
                        launchUrl(Uri.parse('tel:${r.pharmacy.phone}')),
                  ),
          ),
        ),
        const SizedBox(height: IviaSpacing.md),
        // Produits.
        Card(
          child: Padding(
            padding: const EdgeInsets.all(IviaSpacing.lg),
            child: Column(
              children: [
                for (final l in r.lines.where((l) => l.available))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Expanded(child: Text('${l.quantity} × ${l.name}')),
                        Text(formatXof(l.lineTotalXof)),
                      ],
                    ),
                  ),
                if (r.deliveryFeeXof > 0)
                  Row(
                    children: [
                      const Expanded(child: Text('Livraison ivia')),
                      Text(formatXof(r.deliveryFeeXof)),
                    ],
                  ),
                const Divider(),
                Row(
                  children: [
                    Expanded(child: Text('Total', style: t.titleMedium)),
                    Text(formatXof(r.totalXof), style: t.titleMedium),
                  ],
                ),
                if (!r.delivery)
                  Padding(
                    padding: const EdgeInsets.only(top: IviaSpacing.sm),
                    child: Text(
                      'À payer à la pharmacie. Aucune commission ivia.',
                      style: t.bodySmall,
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (r.prescriptionRequired)
          const Padding(
            padding: EdgeInsets.only(top: IviaSpacing.md),
            child: IviaInfoCard(
              text: 'Ordonnance exigée : gardez-la sur vous, elle sera vérifiée à la remise.',
            ),
          ),
        const SizedBox(height: IviaSpacing.xl),
        // Choix du mode (P09) ou suite du parcours.
        if (canChoose) ...[
          Text('Comment récupérer vos médicaments ?', style: t.titleMedium),
          const SizedBox(height: IviaSpacing.md),
          _ModeCard(
            icon: Icons.storefront,
            title: 'Retrait sur place',
            body: 'Allez à la pharmacie, payez sur place et donnez votre code.',
            selected: !r.delivery,
            onTap: _busy || !r.delivery
                ? null
                : () => _run(() => _api.chooseMedPickup(r.id)),
          ),
          const SizedBox(height: IviaSpacing.md),
          _ModeCard(
            icon: Icons.delivery_dining,
            title: 'Livreur ivia',
            body: 'On cherche le livreur le plus proche. Vous payez une fois qu\'il a accepté.',
            selected: r.delivery,
            onTap: _busy ? null : () => _chooseDelivery(r),
          ),
        ],
        if (r.status == 'courier_search') ...[
          const LinearProgressIndicator(),
          const SizedBox(height: IviaSpacing.md),
          Text(
            'Recherche du livreur ivia le plus proche… '
            '${r.courierOffersSent > 0 ? '(${r.courierOffersSent} livreur(s) sollicité(s))' : ''}',
            style: t.bodyLarge,
          ),
          const SizedBox(height: IviaSpacing.sm),
          TextButton(
            onPressed: _busy
                ? null
                : () => _run(() => _api.chooseMedPickup(r.id)),
            child: const Text('Finalement, je passe la récupérer'),
          ),
        ],
        if (r.courier case final c?)
          Card(
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.two_wheeler)),
              title: Text('${c.firstName} · livreur ivia'),
              subtitle: Text(
                [
                  c.vehicleType,
                  c.vehiclePlate,
                ].where((s) => s.isNotEmpty).join(' · '),
              ),
              trailing: c.phone.isEmpty
                  ? null
                  : IconButton.filled(
                      tooltip: 'Appeler le livreur',
                      icon: const Icon(Icons.call),
                      onPressed: () => launchUrl(Uri.parse('tel:${c.phone}')),
                    ),
            ),
          ),
        if (r.status == 'awaiting_payment') ...[
          const SizedBox(height: IviaSpacing.md),
          FilledButton(
            onPressed: _busy ? null : () => _pay(r),
            child: Text('Payer ${formatXof(r.totalXof)}'),
          ),
        ],
        if (r.delivery && r.deliveryAddress.isNotEmpty) ...[
          const SizedBox(height: IviaSpacing.md),
          Text(
            'Livraison : ${r.deliveryAddress}'
            '${r.deliveryEtaMinutes != null ? ' · environ ${r.deliveryEtaMinutes} min' : ''}',
          ),
        ],
        if (r.status == 'reserved' ||
            r.status == 'courier_search' ||
            r.status == 'awaiting_payment') ...[
          const SizedBox(height: IviaSpacing.xl),
          OutlinedButton(
            onPressed: _busy
                ? null
                : () => _run(() => _api.cancelMedReservation(r.id)),
            child: const Text('Annuler la réservation'),
          ),
        ],
      ],
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title, body;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final brand = IviaAppBrand.of(context);
    return Material(
      color: IviaColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(IviaRadius.large),
        side: BorderSide(
          color: selected ? brand.accent : IviaColors.border,
          width: selected ? 2 : 1,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(IviaSpacing.md),
        leading: Icon(icon, color: brand.accent, size: 32),
        title: Text(title, style: Theme.of(context).textTheme.titleMedium),
        subtitle: Text(body),
        trailing: selected
            ? Icon(Icons.check_circle, color: brand.accent)
            : const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

/// Choix de l'adresse de livraison, avec le devis ; ajout d'une adresse à la
/// position actuelle.
class _AddressSheet extends ConsumerStatefulWidget {
  const _AddressSheet({required this.reservationId});
  final String reservationId;

  @override
  ConsumerState<_AddressSheet> createState() => _AddressSheetState();
}

class _AddressSheetState extends ConsumerState<_AddressSheet> {
  List<BuyerAddress>? _addresses;
  BuyerAddress? _selected;
  MedDeliveryQuote? _quote;
  String? _error;
  final _label = TextEditingController(text: 'Maison');
  final _text = TextEditingController();

  IviaApiClient get _api => ref.read(apiClientProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _label.dispose();
    _text.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final list = await _api.addresses();
      if (!mounted) return;
      setState(() => _addresses = list);
      if (list.isNotEmpty) await _pick(list.first);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _pick(BuyerAddress a) async {
    setState(() {
      _selected = a;
      _quote = null;
      _error = null;
    });
    try {
      final q = await _api.medDeliveryQuote(widget.reservationId, a.id);
      if (mounted) setState(() => _quote = q);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _addHere() async {
    final p = await alertPosition(ref);
    if (p == null) {
      setState(
        () => _error = 'Position indisponible : activez la localisation.',
      );
      return;
    }
    try {
      final a = await _api.createAddress(
        label: _label.text.trim().isEmpty ? 'Maison' : _label.text.trim(),
        addressText: _text.text.trim().isEmpty
            ? 'Ma position'
            : _text.text.trim(),
        location: p,
      );
      setState(() => _addresses = [...?_addresses, a]);
      await _pick(a);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final list = _addresses;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        IviaSpacing.screen,
        0,
        IviaSpacing.screen,
        IviaSpacing.screen + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Où livrer ?', style: t.headlineSmall),
            const SizedBox(height: IviaSpacing.md),
            if (list == null && _error == null)
              const Center(child: CircularProgressIndicator()),
            for (final a in list ?? const <BuyerAddress>[])
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  _selected?.id == a.id
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                ),
                title: Text(a.label),
                subtitle: Text(a.addressText),
                onTap: () => _pick(a),
              ),
            if (list != null) ...[
              const SizedBox(height: IviaSpacing.sm),
              Text('Nouvelle adresse à ma position', style: t.titleSmall),
              TextField(
                controller: _label,
                decoration: const InputDecoration(
                  hintText: 'Nom (Maison, Bureau…)',
                ),
              ),
              const SizedBox(height: IviaSpacing.sm),
              TextField(
                controller: _text,
                decoration: const InputDecoration(
                  hintText: 'Repère (rue, portail bleu…)',
                ),
              ),
              TextButton.icon(
                onPressed: _addHere,
                icon: const Icon(Icons.my_location),
                label: const Text('Utiliser ma position'),
              ),
            ],
            if (_quote case final q?)
              IviaInfoCard(
                text:
                    'Livraison ${formatXof(q.deliveryFeeXof)} (${formatDistance(q.distanceM)}, '
                    '~${q.etaMinutes} min). Total ${formatXof(q.totalXof)}, payé une fois le livreur trouvé.',
              ),
            if (_error != null)
              Text(
                _error!,
                style: t.bodyMedium?.copyWith(color: IviaColors.error),
              ),
            const SizedBox(height: IviaSpacing.lg),
            FilledButton(
              onPressed: _quote == null
                  ? null
                  : () => Navigator.pop(context, _selected),
              child: const Text('Chercher un livreur ivia'),
            ),
          ],
        ),
      ),
    );
  }
}
