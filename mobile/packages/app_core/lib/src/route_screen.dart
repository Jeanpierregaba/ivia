import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_ui/ivia_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import 'formats.dart';
import 'ivia_map.dart';
import 'location.dart';
import 'providers.dart';

String _duration(int seconds) {
  final m = (seconds / 60).ceil();
  if (m < 60) return '$m min';
  final rest = m % 60;
  return rest == 0 ? '${m ~/ 60} h' : '${m ~/ 60} h $rest';
}

String _distance(int meters) => meters < 1000
    ? '$meters m'
    : '${(meters / 1000).toStringAsFixed(1).replaceAll('.', ',')} km';

/// Trajet : départ et arrivée, tracé, minutes et distance, prix si la zone a un tarif, puis
/// navigation guidée dans Google Maps ou Waze (pas de guidage dans l'app : ADR 0013).
class RouteScreen extends ConsumerStatefulWidget {
  const RouteScreen({
    super.key,
    this.title = 'Mon trajet',
    this.destination,
    this.destinationLabel,
    this.withPrice = false,
    this.profile = 'moto',
  });
  final String title;
  final GeoPoint? destination;
  final String? destinationLabel;
  final bool withPrice;
  final String profile;

  @override
  ConsumerState<RouteScreen> createState() => _RouteScreenState();
}

class _RouteScreenState extends ConsumerState<RouteScreen> {
  PickedPlace? _from;
  late PickedPlace? _to = widget.destination == null
      ? null
      : PickedPlace(
          point: widget.destination!,
          label: widget.destinationLabel ?? 'Destination',
        );
  late var _profile = widget.profile;
  GeoRoute? _route;
  RideEstimate? _estimate;
  String? _error;
  var _busy = false;

  IviaApiClient get _api => ref.read(apiClientProvider);

  @override
  void initState() {
    super.initState();
    _startFromHere();
  }

  Future<void> _startFromHere() async {
    final p = (await ref.read(locationServiceProvider).current()).point;
    if (!mounted || p == null) return;
    setState(() => _from = PickedPlace(point: p, label: 'Ma position'));
    await _compute();
  }

  Future<void> _pick({required bool origin}) async {
    final picked = await Navigator.of(context).push<PickedPlace>(
      MaterialPageRoute(
        builder: (_) => PlacePickerScreen(
          initial: (origin ? _from : _to)?.point,
          title: origin ? 'Point de départ' : 'Destination',
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => origin ? _from = picked : _to = picked);
    await _compute();
  }

  Future<void> _compute() async {
    final from = _from, to = _to;
    if (from == null || to == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final route = await _api.geoRoute(
        from.point,
        to.point,
        profile: _profile,
      );
      RideEstimate? estimate;
      if (widget.withPrice) {
        try {
          estimate = await _api.rideEstimate(
            from.point,
            to.point,
            vehicle: _profile,
          );
        } on ApiException {
          // Pas de tarif sur ce départ : le trajet reste affiché, sans prix.
        }
      }
      if (mounted) {
        setState(() {
          _route = route;
          _estimate = estimate;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _start() async {
    final from = _from?.point, to = _to?.point;
    if (to == null) return;
    await launchUrl(
      Uri.https('www.google.com', '/maps/dir/', {
        'api': '1',
        if (from != null) 'origin': '${from.lat},${from.lng}',
        'destination': '${to.lat},${to.lng}',
        'travelmode': _profile == 'moto' ? 'two-wheeler' : 'driving',
        'dir_action': 'navigate',
      }),
      mode: LaunchMode.externalApplication,
    );
  }

  /// Centre et niveau de zoom pour voir tout le trajet.
  (GeoPoint, double) _view() {
    final from = _from?.point, to = _to?.point;
    final points = [
      ?from,
      ?to,
      if (_route != null && _route!.polyline.isNotEmpty)
        ...decodePolyline6(_route!.polyline),
    ];
    if (points.isEmpty) return (lome, 13);
    if (points.length == 1) return (points.first, 15);
    final lats = points.map((p) => p.lat), lngs = points.map((p) => p.lng);
    final minLat = lats.reduce(min), maxLat = lats.reduce(max);
    final minLng = lngs.reduce(min), maxLng = lngs.reduce(max);
    final span = max(maxLat - minLat, maxLng - minLng);
    final zoom = span <= 0
        ? 15.0
        : (log(360 * 1.2 / span) / ln2 - 0.6).clamp(3.0, 16.0);
    return (
      GeoPoint(lat: (minLat + maxLat) / 2, lng: (minLng + maxLng) / 2),
      zoom,
    );
  }

  Widget _place(
    IconData icon,
    Color color,
    String hint,
    PickedPlace? p,
    VoidCallback onTap,
  ) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              p == null || p.label.isEmpty ? hint : p.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: p == null ? FontWeight.w400 : FontWeight.w700,
                color: p == null ? IviaColors.textMuted : IviaColors.text,
              ),
            ),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final route = _route;
    final (center, zoom) = _view();
    final polyline = route == null
        ? const <GeoPoint>[]
        : decodePolyline6(route.polyline);
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Stack(
        children: [
          Positioned.fill(
            child: IviaMap(
              // Nouveau trajet : la carte se recadre dessus.
              key: ValueKey(
                '${_from?.point.lat}|${_to?.point.lat}|${route?.distanceM}',
              ),
              center: center,
              zoom: zoom,
              route: polyline,
              markers: [
                if (_from != null)
                  IviaMapMarker(
                    id: 'from',
                    point: _from!.point,
                    color: IviaColors.cobaltBlue,
                    icon: Icons.trip_origin,
                  ),
                if (_to != null)
                  IviaMapMarker(
                    id: 'to',
                    point: _to!.point,
                    color: IviaColors.primary,
                    icon: Icons.place,
                  ),
              ],
            ),
          ),
          Positioned(
            top: 10,
            left: 12,
            right: 12,
            child: Material(
              elevation: 3,
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _place(
                    Icons.trip_origin,
                    IviaColors.cobaltBlue,
                    'Point de départ',
                    _from,
                    () => _pick(origin: true),
                  ),
                  const Divider(height: 1),
                  _place(
                    Icons.place,
                    IviaColors.primary,
                    'Où allez-vous ?',
                    _to,
                    () => _pick(origin: false),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: Material(
        elevation: 8,
        color: Colors.white,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'moto',
                      label: Text('Moto'),
                      icon: Icon(Icons.two_wheeler),
                    ),
                    ButtonSegment(
                      value: 'car',
                      label: Text('Voiture'),
                      icon: Icon(Icons.directions_car_outlined),
                    ),
                  ],
                  selected: {_profile},
                  onSelectionChanged: (v) {
                    setState(() => _profile = v.first);
                    _compute();
                  },
                ),
                const SizedBox(height: 12),
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: LinearProgressIndicator(),
                  )
                else if (_error != null)
                  Text(
                    _error!,
                    style: const TextStyle(color: IviaColors.imperialRed),
                  )
                else if (route != null) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _duration(route.durationS),
                        style: t.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          _distance(route.distanceM),
                          style: t.titleMedium?.copyWith(
                            color: IviaColors.textMuted,
                          ),
                        ),
                      ),
                      const Spacer(),
                      if (_estimate != null)
                        Text(
                          formatXof(_estimate!.priceXof),
                          style: t.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                    ],
                  ),
                  if (route.approximate)
                    Text(
                      'Estimation à vol d\'oiseau : le calcul d\'itinéraire n\'est pas disponible.',
                      style: t.bodySmall?.copyWith(color: IviaColors.warning),
                    ),
                ] else
                  Text(
                    'Choisissez une destination pour voir le temps de trajet.',
                    style: t.bodyMedium?.copyWith(color: IviaColors.textMuted),
                  ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _to == null ? null : _start,
                  icon: const Icon(Icons.navigation_outlined),
                  label: const Text('Démarrer l\'itinéraire'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
