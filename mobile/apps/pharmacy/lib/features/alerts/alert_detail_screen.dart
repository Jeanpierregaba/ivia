import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../common/providers.dart';
import '../../common/ui.dart';

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
