import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../app/driver_dossier.dart';
import '../../common/formats.dart';
import '../../common/ui.dart';
import '../mission/eta.dart';
import '../profile/settings.dart';
import '../work/work_state.dart';

/// Proposition de mission (D10) : gain indicatif, compte à rebours, trajet,
/// retrait et livraison, « Glisser pour accepter », « Refuser ». Sonnerie et
/// vibration à l'arrivée si elles sont activées (Profil).
class OfferCard extends ConsumerStatefulWidget {
  const OfferCard({super.key, required this.offer});
  final WorkOffer offer;

  @override
  ConsumerState<OfferCard> createState() => _OfferCardState();
}

class _OfferCardState extends ConsumerState<OfferCard> {
  Timer? _tick;
  late final int _total;
  String? _error;
  var _declining = false;

  // Secondes écoulées selon le minuteur ; l'horloge corrige après une mise
  // en arrière-plan (minuteur suspendu).
  var _ticks = 0;

  int get _clockLeft => widget.offer.expiresAt
      .difference(ref.read(apiClientProvider).now())
      .inSeconds;

  int get _left => math.max(0, math.min(_total - _ticks, _clockLeft));

  @override
  void initState() {
    super.initState();
    _total = math.max(_clockLeft, 1);
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      _ticks++;
      if (_left == 0) {
        _drop('Proposition expirée. La recherche continue.');
      } else {
        setState(() {});
      }
    });
    _ringer = ref.read(ringerProvider);
    unawaited(_ring());
  }

  late final IviaRinger _ringer;

  /// Sonnerie jouée une fois à l'arrivée de la proposition, si elle est
  /// activée (Profil) ; la carte reste bien visible jusqu'à la réponse.
  Future<void> _ring() async {
    final on = await ref.read(missionRingProvider.future).catchError((_) {
      return true;
    });
    if (!on || !mounted) return;
    await _ringer.alert();
  }

  @override
  void dispose() {
    _tick?.cancel();
    unawaited(_ringer.stop());
    super.dispose();
  }

  void _drop(String? message) {
    _tick?.cancel();
    unawaited(_ringer.stop());
    if (message != null) announce(context, message);
    ref.read(workProvider.notifier).dropOffer(widget.offer, message: message);
  }

  /// Proposition expirée, prise ou introuvable : retour à la recherche.
  bool _gone(ApiException e) =>
      e.code == 'offer_expired' || e.code == 'offer_not_found';

  Future<void> _accept() async {
    setState(() => _error = null);
    final work = ref.read(workProvider.notifier)..beginAction();
    try {
      await ref.read(apiClientProvider).acceptWorkOffer(widget.offer);
      work.beginAction();
      await work.refresh();
    } on ApiException catch (e) {
      if (!mounted) return;
      if (_gone(e)) {
        _drop(e.message);
      } else {
        setState(() => _error = e.message);
        announce(context, e.message);
      }
    }
  }

  Future<void> _decline() async {
    setState(() {
      _error = null;
      _declining = true;
    });
    try {
      await ref.read(apiClientProvider).declineWorkOffer(widget.offer);
      if (mounted) _drop(null);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (_gone(e)) {
        _drop(null);
      } else {
        setState(() => _error = e.message);
      }
    } finally {
      if (mounted) setState(() => _declining = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.offer;
    final left = _left;
    final vehicle =
        ref.watch(driverDossierProvider).value?.vehicleType ??
        VehicleType.motorbike;
    final total = o.toPickupM + o.tripM;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: MergeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        o.pharmacy ? 'COURSE PHARMACIE' : 'NOUVELLE MISSION',
                        style: DText.overline.copyWith(color: D.red),
                      ),
                    ),
                    Text(
                      formatXof(o.earningXof),
                      style: DText.amount.copyWith(fontSize: 38),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Gain indicatif · payé à la livraison',
                      style: DText.bodyMuted.copyWith(fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            _Countdown(left: left, total: _total),
          ],
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _Chip(Icons.route_rounded, distance(total)),
            _Chip(
              Icons.schedule_rounded,
              '≈ ${duration(travelTime(total, vehicle))}',
            ),
            if (o.parcelSize case final size?)
              _Chip(Icons.inventory_2_rounded, parcelLabel(size))
            else if (o.pharmacy)
              const _Chip(Icons.medication_rounded, 'Médicaments'),
          ],
        ),
        const SizedBox(height: 16),
        _Stop(
          number: 1,
          color: D.night,
          title: o.from.isEmpty ? 'Retrait' : 'Retrait · ${o.from}',
          subtitle: [
            if (o.fromAddress.isNotEmpty) o.fromAddress,
            'à ${distance(o.toPickupM)}',
          ].join(' · '),
          line: true,
        ),
        _Stop(
          number: 2,
          color: D.red,
          title: o.toArea.isEmpty ? 'Livraison' : 'Livraison · ${o.toArea}',
          subtitle: '${distance(o.tripM)} après le retrait',
        ),
        if (_error case final error?) ...[
          const SizedBox(height: 8),
          Text(error, style: DText.body.copyWith(color: IviaColors.error)),
        ],
        const SizedBox(height: 16),
        DSlide(
          label: 'Glisser pour accepter',
          onConfirmed: left == 0 || _declining ? null : _accept,
        ),
        const SizedBox(height: 4),
        TextButton(
          onPressed: _declining ? null : _decline,
          style: TextButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            foregroundColor: D.label,
          ),
          child: Text(
            'Refuser',
            style: DText.button.copyWith(color: D.label, fontSize: 16),
          ),
        ),
      ],
    );
  }
}

/// « Petit colis », « Colis moyen », « Grand colis ».
String parcelLabel(ParcelSize size) => switch (size) {
  ParcelSize.small => 'Petit colis',
  ParcelSize.medium => 'Colis moyen',
  ParcelSize.large => 'Grand colis',
};

class _Chip extends StatelessWidget {
  const _Chip(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: D.page,
      borderRadius: BorderRadius.circular(IviaRadius.pill),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: D.label),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            text,
            style: DText.pill.copyWith(color: D.ink, fontSize: 13),
          ),
        ),
      ],
    ),
  );
}

/// Étape numérotée, reliée à la suivante par un trait.
class _Stop extends StatelessWidget {
  const _Stop({
    required this.number,
    required this.color,
    required this.title,
    required this.subtitle,
    this.line = false,
  });
  final int number;
  final Color color;
  final String title, subtitle;
  final bool line;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 26,
            child: Column(
              children: [
                ExcludeSemantics(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                    child: SizedBox.square(
                      dimension: 26,
                      child: Center(
                        child: MediaQuery.withNoTextScaling(
                          child: Text(
                            '$number',
                            style: DText.pill.copyWith(
                              color: Colors.white,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (line)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      color: D.line,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: line ? 10 : 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: DText.cardTitle.copyWith(fontSize: 15)),
                  Text(subtitle, style: DText.bodyMuted.copyWith(fontSize: 13)),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Compte à rebours : anneau rouge qui se vide, secondes au centre.
class _Countdown extends StatelessWidget {
  const _Countdown({required this.left, required this.total});
  final int left, total;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$left secondes pour accepter',
    excludeSemantics: true,
    child: SizedBox.square(
      dimension: 66,
      child: CustomPaint(
        painter: _CountdownPainter(left / total),
        child: Center(
          child: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.2,
            child: Text('$left', style: DText.amount.copyWith(fontSize: 22)),
          ),
        ),
      ),
    ),
  );
}

class _CountdownPainter extends CustomPainter {
  const _CountdownPainter(this.part);
  final double part;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 7.0;
    final arc = (Offset.zero & size).deflate(stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = D.redSoft;
    canvas.drawArc(arc, 0, 2 * math.pi, false, paint);
    canvas.drawArc(
      arc,
      -math.pi / 2,
      2 * math.pi * part.clamp(0, 1),
      false,
      paint..color = D.red,
    );
  }

  @override
  bool shouldRepaint(_CountdownPainter old) => old.part != part;
}
