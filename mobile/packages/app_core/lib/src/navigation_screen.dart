import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_ui/ivia_ui.dart';

import 'ivia_map.dart';
import 'location.dart';
import 'providers.dart';

/// Position reçue pendant la navigation : point et cap (degrés, `null` à
/// l'arrêt).
typedef NavFix = ({GeoPoint point, double? heading});

/// Positions successives du téléphone pendant la navigation (remplacé dans
/// les tests).
final navigationFixesProvider = Provider<Stream<NavFix> Function()>(
  (ref) =>
      () =>
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.bestForNavigation,
              distanceFilter: 4,
            ),
          ).map(
            (p) => (
              point: GeoPoint(lat: p.latitude, lng: p.longitude),
              heading: p.speed > 1 && p.heading >= 0 ? p.heading : null,
            ),
          ),
);

/// Ouvre la navigation dans l'app vers [to] : jamais d'app de cartes externe.
/// Renvoie `true` si la personne a confirmé son arrivée.
Future<bool> openInAppNavigation(
  BuildContext context, {
  required GeoPoint to,
  required String label,
  String profile = 'moto',
}) async =>
    await Navigator.of(context, rootNavigator: true).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            NavigationScreen(to: to, label: label, profile: profile),
      ),
    ) ??
    false;

/// Navigation guidée : carte Google en plein écran, trajet sur les routes
/// (calculé par le serveur), position en direct suivie par la carte, distance
/// et temps restants, nouveau trajet si l'on s'en écarte, arrivée.
class NavigationScreen extends ConsumerStatefulWidget {
  const NavigationScreen({
    super.key,
    required this.to,
    required this.label,
    this.profile = 'moto',
  });

  final GeoPoint to;
  final String label;

  /// `moto` ou `car`.
  final String profile;

  @override
  ConsumerState<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends ConsumerState<NavigationScreen> {
  /// Écart au trajet au-delà duquel il est recalculé.
  static const _offRouteM = 60.0;

  /// Distance à laquelle on considère être arrivé.
  static const _arrivedM = 40.0;

  StreamSubscription<NavFix>? _sub;
  NavFix? _fix;
  double _heading = 0;
  GeoRoute? _route;
  List<GeoPoint> _path = const [];
  DateTime? _lastRouting;
  var _routing = false;
  var _follow = true;
  var _arrivedShown = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final service = ref.read(locationServiceProvider);
    final first = await service.current();
    if (!mounted) return;
    final point = first.point;
    if (point != null) {
      _onFix((point: point, heading: null));
    } else {
      setState(
        () => _error =
            'Position indisponible. Autorisez la localisation pour être guidé.',
      );
    }
    try {
      _sub = ref
          .read(navigationFixesProvider)()
          .listen(_onFix, onError: (_) {});
    } on Object {
      // Pas de suivi en continu : la première position reste affichée.
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _onFix(NavFix fix) {
    if (!mounted) return;
    setState(() {
      _fix = fix;
      _error = null;
      if (fix.heading != null) _heading = fix.heading!;
    });
    final left = _distance(fix.point, widget.to);
    if (left <= _arrivedM && !_arrivedShown) {
      _arrivedShown = true;
      _arrived();
      return;
    }
    if (_path.isEmpty || _offRoute(fix.point) > _offRouteM) _reroute();
  }

  Future<void> _reroute() async {
    final from = _fix?.point;
    final last = _lastRouting;
    if (from == null || _routing) return;
    // Au plus un calcul toutes les 15 s (signal GPS instable).
    if (last != null &&
        DateTime.now().difference(last) < const Duration(seconds: 15)) {
      return;
    }
    _routing = true;
    _lastRouting = DateTime.now();
    try {
      final r = await ref
          .read(apiClientProvider)
          .geoRoute(from, widget.to, profile: widget.profile);
      if (!mounted) return;
      setState(() {
        _route = r;
        _path = r.polyline.isEmpty
            ? [from, widget.to]
            : decodePolyline6(r.polyline);
      });
    } on ApiException {
      if (mounted && _path.isEmpty) setState(() => _path = [from, widget.to]);
    } finally {
      _routing = false;
    }
  }

  /// Distance du point au trajet (au sommet le plus proche).
  double _offRoute(GeoPoint p) =>
      _path.map((q) => _distance(p, q)).fold(double.infinity, math.min);

  /// Distance restante le long du trajet, depuis le sommet le plus proche.
  double _remaining() {
    final here = _fix?.point;
    if (here == null) return 0;
    if (_path.length < 2) return _distance(here, widget.to);
    var best = 0;
    var bestD = double.infinity;
    for (var i = 0; i < _path.length; i++) {
      final d = _distance(here, _path[i]);
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    var total = bestD;
    for (var i = best; i < _path.length - 1; i++) {
      total += _distance(_path[i], _path[i + 1]);
    }
    return total;
  }

  Future<void> _arrived() async {
    final done = await showModalBottomSheet<bool>(
      context: context,
      isDismissible: false,
      backgroundColor: IviaColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => _ArrivedSheet(label: widget.label),
    );
    if (mounted && done == true) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final here = _fix?.point;
    final remaining = _remaining();
    final route = _route;
    // Temps restant proportionnel à la distance restante.
    final seconds = route == null || route.distanceM == 0
        ? null
        : (route.durationS * remaining / route.distanceM).round();
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: IviaMap(
              center: _follow && here != null ? here : (here ?? widget.to),
              zoom: 17,
              bearing: _follow ? _heading : null,
              tilt: _follow ? 45 : 0,
              route: _path,
              markers: [
                if (here != null)
                  IviaMapMarker(
                    id: 'moi',
                    point: here,
                    color: IviaColors.cobaltBlue,
                    icon: Icons.navigation_rounded,
                  ),
                IviaMapMarker(
                  id: 'arrivee',
                  point: widget.to,
                  color: IviaColors.imperialRed,
                  icon: Icons.flag_rounded,
                ),
              ],
              onCameraIdle: (_) {},
            ),
          ),
          // Bandeau du haut : temps et distance restants, destination.
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(IviaSpacing.md),
              child: IviaReveal(
                child: Material(
                  color: IviaColors.berkeleyBlue,
                  borderRadius: BorderRadius.circular(22),
                  elevation: 8,
                  shadowColor: Colors.black38,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 10, 18, 14),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: 'Quitter la navigation',
                          onPressed: () => Navigator.of(context).pop(false),
                          icon: const Icon(
                            Icons.close_rounded,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: IviaSpacing.xs),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AnimatedSwitcher(
                                duration: IviaMotion.medium,
                                child: Text(
                                  here == null
                                      ? 'Recherche de votre position…'
                                      : [
                                          if (seconds != null)
                                            _duration(seconds),
                                          _meters(remaining),
                                        ].join('  ·  '),
                                  key: ValueKey(
                                    '${seconds ?? 0}-${remaining ~/ 50}',
                                  ),
                                  style: t.titleLarge?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Vers ${widget.label}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: t.bodyMedium?.copyWith(
                                  color: Colors.white70,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_routing)
                          const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (route?.approximate ?? false)
            Positioned(
              left: IviaSpacing.md,
              right: IviaSpacing.md,
              top: MediaQuery.paddingOf(context).top + 104,
              child: const IviaReveal(
                index: 1,
                child: _Hint(
                  text: 'Trajet estimé : suivez les routes, le tracé exact arrive bientôt.',
                ),
              ),
            ),
          if (_error != null)
            Positioned(
              left: IviaSpacing.md,
              right: IviaSpacing.md,
              top: MediaQuery.paddingOf(context).top + 104,
              child: _Hint(text: _error!),
            ),
          // Bas : recentrer et arrivée.
          Positioned(
            left: IviaSpacing.md,
            right: IviaSpacing.md,
            bottom: MediaQuery.paddingOf(context).bottom + IviaSpacing.md,
            child: IviaReveal(
              index: 2,
              child: Row(
                children: [
                  AnimatedScale(
                    scale: _follow ? 0 : 1,
                    duration: IviaMotion.medium,
                    curve: Curves.easeOutBack,
                    child: FloatingActionButton(
                      heroTag: 'recentrer',
                      backgroundColor: IviaColors.surface,
                      foregroundColor: IviaColors.cobaltBlue,
                      onPressed: () => setState(() => _follow = true),
                      tooltip: 'Recentrer',
                      child: const Icon(Icons.my_location_rounded),
                    ),
                  ),
                  const SizedBox(width: IviaSpacing.md),
                  Expanded(
                    child: SizedBox(
                      height: 56,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: IviaColors.success,
                          shape: const StadiumBorder(),
                        ),
                        onPressed: _arrived,
                        icon: const Icon(Icons.flag_rounded),
                        label: const Text('Je suis arrivé'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Déplacer la carte à la main arrête le suivi (« Recentrer »).
          if (_follow)
            Positioned.fill(
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerMove: (e) {
                  if (e.delta.distance > 6) setState(() => _follow = false);
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Material(
    color: IviaColors.surface,
    borderRadius: BorderRadius.circular(16),
    elevation: 4,
    child: Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: IviaSpacing.lg,
        vertical: IviaSpacing.md,
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, color: IviaColors.cobaltBlue),
          const SizedBox(width: IviaSpacing.sm),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    ),
  );
}

class _ArrivedSheet extends StatelessWidget {
  const _ArrivedSheet({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          IviaSpacing.screen,
          IviaSpacing.xl,
          IviaSpacing.screen,
          IviaSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.4, end: 1),
              duration: const Duration(milliseconds: 700),
              curve: Curves.elasticOut,
              builder: (_, v, child) => Transform.scale(scale: v, child: child),
              child: Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  color: IviaColors.success.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.flag_rounded,
                  size: 42,
                  color: IviaColors.success,
                ),
              ),
            ),
            const SizedBox(height: IviaSpacing.lg),
            Text(
              'Vous êtes arrivé',
              style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: IviaSpacing.xs),
            Text(
              label,
              textAlign: TextAlign.center,
              style: t.bodyLarge?.copyWith(color: IviaColors.textSecondary),
            ),
            const SizedBox(height: IviaSpacing.xl),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Terminer la navigation'),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Continuer à naviguer'),
            ),
          ],
        ),
      ),
    );
  }
}

double _distance(GeoPoint a, GeoPoint b) {
  const r = 6371000.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(b.lat - a.lat), dLng = rad(b.lng - a.lng);
  final h =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(a.lat)) *
          math.cos(rad(b.lat)) *
          math.pow(math.sin(dLng / 2), 2);
  return 2 * r * math.asin(math.sqrt(h));
}

String _meters(double m) => m >= 1000
    ? '${(m / 1000).toStringAsFixed(m >= 10000 ? 0 : 1).replaceAll('.', ',')} km'
    : '${(m / 10).round() * 10} m';

String _duration(int s) {
  final min = (s / 60).ceil();
  if (min < 60) return '$min min';
  return '${min ~/ 60} h ${(min % 60).toString().padLeft(2, '0')}';
}
