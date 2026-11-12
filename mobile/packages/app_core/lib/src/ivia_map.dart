import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as osm;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gm;
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_ui/ivia_ui.dart';
import 'package:latlong2/latlong.dart' as ll;

import 'google_maps_ready.dart'
    if (dart.library.js_interop) 'google_maps_ready_web.dart';
import 'location.dart';
import 'location_prompt.dart';
import 'providers.dart';

/// Google Maps dès que la clé de l'app est configurée (`--dart-define=IVIA_GOOGLE_MAPS=true`).
/// Sinon, tuiles OpenStreetMap : développement seulement, leur serveur public est interdit en
/// production. `IVIA_TILES_URL` permet de pointer vers un fournisseur.
const _googleBuild = bool.fromEnvironment('IVIA_GOOGLE_MAPS');

/// Google Maps demandé au build et réellement chargé (dans le navigateur, le
/// script peut ne pas arriver : la carte reste alors utilisable).
final _useGoogle = _googleBuild && googleMapsLoaded();
const _tilesUrl = String.fromEnvironment(
  'IVIA_TILES_URL',
  defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
);

/// Lomé, sans position connue.
const lome = GeoPoint(lat: 6.1319, lng: 1.2228);

class IviaMapMarker {
  const IviaMapMarker({
    required this.id,
    required this.point,
    this.color = IviaColors.berkeleyBlue,
    this.icon = Icons.place,
  });
  final String id;
  final GeoPoint point;
  final Color color;
  final IconData icon;
}

/// Décode une polyline6 d'OSRM.
List<GeoPoint> decodePolyline6(String encoded) {
  final out = <GeoPoint>[];
  var i = 0, lat = 0, lng = 0;
  int next() {
    var result = 0, shift = 0, b = 0;
    do {
      b = encoded.codeUnitAt(i++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    return (result & 1) != 0 ? ~(result >> 1) : result >> 1;
  }

  while (i < encoded.length) {
    lat += next();
    lng += next();
    out.add(GeoPoint(lat: lat / 1e6, lng: lng / 1e6));
  }
  return out;
}

/// Carte commune aux apps.
class IviaMap extends StatefulWidget {
  const IviaMap({
    super.key,
    required this.center,
    this.zoom = 14.5,
    this.markers = const [],
    this.route = const [],
    this.interactive = true,
    this.onCameraIdle,
  });

  final GeoPoint center;
  final double zoom;
  final List<IviaMapMarker> markers;
  final List<GeoPoint> route;
  final bool interactive;

  /// Centre de la carte à l'arrêt du mouvement, jamais pendant.
  final ValueChanged<GeoPoint>? onCameraIdle;

  @override
  State<IviaMap> createState() => _IviaMapState();
}

class _IviaMapState extends State<IviaMap> {
  final _osm = osm.MapController();
  gm.GoogleMapController? _google;
  late GeoPoint _last = widget.center;
  Timer? _idle;

  @override
  void didUpdateWidget(IviaMap old) {
    super.didUpdateWidget(old);
    // Un nouveau centre voulu par l'écran (recherche, ma position) déplace la carte.
    final c = widget.center;
    if (c.lat == old.center.lat && c.lng == old.center.lng) return;
    _last = c;
    if (_useGoogle) {
      _google?.animateCamera(
        gm.CameraUpdate.newLatLng(gm.LatLng(c.lat, c.lng)),
      );
    } else {
      _osm.move(ll.LatLng(c.lat, c.lng), _osm.camera.zoom);
    }
  }

  @override
  void dispose() {
    _idle?.cancel();
    _osm.dispose();
    _google?.dispose();
    super.dispose();
  }

  double _hue(Color c) => HSVColor.fromColor(c).hue;

  @override
  Widget build(BuildContext context) {
    final w = widget;
    if (_useGoogle) {
      return gm.GoogleMap(
        initialCameraPosition: gm.CameraPosition(
          target: gm.LatLng(w.center.lat, w.center.lng),
          zoom: w.zoom,
        ),
        onMapCreated: (c) => _google = c,
        zoomControlsEnabled: false,
        mapToolbarEnabled: false,
        myLocationButtonEnabled: false,
        scrollGesturesEnabled: w.interactive,
        zoomGesturesEnabled: w.interactive,
        rotateGesturesEnabled: false,
        tiltGesturesEnabled: false,
        onCameraMove: (p) =>
            _last = GeoPoint(lat: p.target.latitude, lng: p.target.longitude),
        onCameraIdle: () => w.onCameraIdle?.call(_last),
        markers: {
          for (final m in w.markers)
            gm.Marker(
              markerId: gm.MarkerId(m.id),
              position: gm.LatLng(m.point.lat, m.point.lng),
              icon: gm.BitmapDescriptor.defaultMarkerWithHue(_hue(m.color)),
            ),
        },
        polylines: {
          if (w.route.isNotEmpty)
            gm.Polyline(
              polylineId: const gm.PolylineId('route'),
              color: IviaColors.cobaltBlue,
              width: 5,
              points: [for (final p in w.route) gm.LatLng(p.lat, p.lng)],
            ),
        },
      );
    }
    return osm.FlutterMap(
      mapController: _osm,
      options: osm.MapOptions(
        initialCenter: ll.LatLng(w.center.lat, w.center.lng),
        initialZoom: w.zoom,
        interactionOptions: osm.InteractionOptions(
          flags: w.interactive
              ? osm.InteractiveFlag.drag |
                    osm.InteractiveFlag.pinchZoom |
                    osm.InteractiveFlag.scrollWheelZoom
              : osm.InteractiveFlag.none,
        ),
        onPositionChanged: (p, _) {
          _last = GeoPoint(lat: p.center.latitude, lng: p.center.longitude);
          _idle?.cancel();
          _idle = Timer(
            const Duration(milliseconds: 400),
            () => w.onCameraIdle?.call(_last),
          );
        },
      ),
      children: [
        osm.TileLayer(
          urlTemplate: _tilesUrl,
          userAgentPackageName: 'tg.ivia.app',
        ),
        if (w.route.isNotEmpty)
          osm.PolylineLayer(
            polylines: [
              osm.Polyline(
                points: [for (final p in w.route) ll.LatLng(p.lat, p.lng)],
                strokeWidth: 5,
                color: IviaColors.cobaltBlue,
              ),
            ],
          ),
        osm.MarkerLayer(
          markers: [
            for (final m in w.markers)
              osm.Marker(
                point: ll.LatLng(m.point.lat, m.point.lng),
                width: 40,
                height: 40,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: m.color,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(m.icon, color: Colors.white, size: 20),
                ),
              ),
          ],
        ),
        const Align(
          alignment: Alignment.bottomRight,
          child: ColoredBox(
            color: Color(0xCCFFFFFF),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                '© OpenStreetMap contributors',
                style: TextStyle(fontSize: 10),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Lieu choisi : position et libellé.
class PickedPlace {
  const PickedPlace({required this.point, required this.label});
  final GeoPoint point;
  final String label;
}

String _sessionToken() {
  final r = Random.secure();
  return base64Url.encode(List.generate(18, (_) => r.nextInt(256)));
}

/// Choix d'un lieu : recherche (3 caractères, après une pause de frappe) ou épingle déplacée.
/// L'adresse se lit à l'arrêt de la carte. Renvoie un [PickedPlace].
class PlacePickerScreen extends ConsumerStatefulWidget {
  const PlacePickerScreen({
    super.key,
    this.initial,
    this.title = 'Choisir le lieu',
    this.hint = 'Déplacez la carte pour mettre le repère au bon endroit.',
    this.confirmLabel = 'Confirmer ce lieu',
  });
  final GeoPoint? initial;
  final String title, hint, confirmLabel;

  @override
  ConsumerState<PlacePickerScreen> createState() => _PlacePickerScreenState();
}

class _PlacePickerScreenState extends ConsumerState<PlacePickerScreen> {
  final _search = TextEditingController();
  final _session = _sessionToken();
  late GeoPoint _target = widget.initial ?? lome;
  late GeoPoint _center = _target;
  var _label = '';
  var _results = <GeoSuggestion>[];
  var _mine = <UserPlace>[];
  var _searching = false;
  Timer? _debounce;

  IviaApiClient get _api => ref.read(apiClientProvider);

  @override
  void initState() {
    super.initState();
    _reverse(_center);
    _loadMine();
    // Ouvert par l'utilisateur (ajout d'une adresse, dossier pharmacie) :
    // sans autorisation, l'écran de la 030 s'affiche avant la lecture.
    if (widget.initial == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await askForLocation(context, ref);
        if (mounted) await _locate();
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadMine() async {
    try {
      final mine = await _api.geoMyPlaces();
      if (mounted) setState(() => _mine = mine);
    } on ApiException {
      // Le raccourci manque, la recherche reste possible.
    }
  }

  Future<void> _locate() async {
    final p = (await ref.read(locationServiceProvider).current()).point;
    if (p != null && mounted) setState(() => _target = p);
  }

  Future<void> _reverse(GeoPoint p) async {
    try {
      final label = await _api.geoReverse(p);
      if (mounted) setState(() => _label = label);
    } on ApiException {
      if (mounted) setState(() => _label = '');
    }
  }

  void _onSearch(String text) {
    _debounce?.cancel();
    if (text.trim().length < 3) {
      setState(() => _results = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      setState(() => _searching = true);
      try {
        final items = await _api.geoAutocomplete(
          text.trim(),
          near: _center,
          session: _session,
        );
        if (mounted) setState(() => _results = items);
      } on ApiException {
        if (mounted) setState(() => _results = []);
      } finally {
        if (mounted) setState(() => _searching = false);
      }
    });
  }

  Future<void> _choose(GeoSuggestion s) async {
    FocusScope.of(context).unfocus();
    try {
      final point =
          s.point ?? (await _api.geoPlace(s.id, session: _session)).point;
      if (!mounted) return;
      setState(() {
        _target = point;
        _center = point;
        _label = s.address.isEmpty ? s.name : '${s.name}, ${s.address}';
        _results = [];
        _search.clear();
      });
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Stack(
        children: [
          Positioned.fill(
            child: Stack(
              alignment: Alignment.center,
              children: [
                IviaMap(
                  center: _target,
                  zoom: 16,
                  onCameraIdle: (p) {
                    _center = p;
                    _reverse(p);
                  },
                ),
                // La pointe du repère désigne le centre de la carte.
                const IgnorePointer(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: 44),
                    child: Icon(
                      Icons.location_on,
                      size: 44,
                      color: IviaColors.primary,
                    ),
                  ),
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
              borderRadius: BorderRadius.circular(14),
              color: Colors.white,
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _search,
                    onChanged: _onSearch,
                    decoration: InputDecoration(
                      hintText: 'Rechercher un lieu',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searching
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : null,
                      filled: true,
                      fillColor: Colors.white,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                    ),
                  ),
                  if (_results.isEmpty &&
                      _search.text.isEmpty &&
                      _mine.isNotEmpty)
                    SizedBox(
                      height: 46,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        children: [
                          for (final m in _mine.take(6))
                            Padding(
                              padding: const EdgeInsets.only(
                                right: 6,
                                bottom: 6,
                              ),
                              child: ActionChip(
                                avatar: Icon(
                                  m.type == 'home'
                                      ? Icons.home_outlined
                                      : m.type == 'work'
                                      ? Icons.work_outline
                                      : Icons.history,
                                  size: 16,
                                ),
                                label: Text(m.label),
                                onPressed: () => setState(() {
                                  _target = m.point;
                                  _center = m.point;
                                  _label = m.address;
                                }),
                              ),
                            ),
                        ],
                      ),
                    ),
                  if (_results.isNotEmpty)
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 260),
                      child: ListView(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        children: [
                          for (final s in _results)
                            ListTile(
                              dense: true,
                              leading: Icon(
                                s.source == 'personal'
                                    ? Icons.star_outline
                                    : Icons.place_outlined,
                              ),
                              title: Text(s.name),
                              subtitle: s.address.isEmpty
                                  ? null
                                  : Text(
                                      s.address,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                              onTap: () => _choose(s),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: Material(
        elevation: 6,
        color: Colors.white,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.hint,
                  style: t.bodySmall?.copyWith(color: IviaColors.textMuted),
                ),
                const SizedBox(height: 4),
                Text(
                  _label.isEmpty ? 'Recherche de l\'adresse…' : _label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                FilledButton(
                  onPressed: () =>
                      Navigator.of(context)
                          .pop(PickedPlace(point: _center, label: _label)),
                  child: Text(widget.confirmLabel),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Suivi d'une livraison : marqueur du livreur, déplacé en douceur entre deux positions. Rien tant
/// qu'aucune position n'est reçue (ou dans un navigateur, sans temps réel).
class LiveTrackingMap extends ConsumerStatefulWidget {
  const LiveTrackingMap({super.key, required this.orderId, this.height = 200});
  final String orderId;
  final double height;

  @override
  ConsumerState<LiveTrackingMap> createState() => _LiveTrackingMapState();
}

class _LiveTrackingMapState extends ConsumerState<LiveTrackingMap> {
  StreamSubscription<dynamic>? _sub;
  GeoPoint? _position;
  Timer? _retry;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  void _connect() {
    final socket = ref
        .read(apiClientProvider)
        .openSocket('/v1/ws/orders/${widget.orderId}/tracking');
    if (socket == null) return;
    _sub = socket.stream.listen(
      (raw) {
        final j = jsonDecode(raw as String) as Map<String, dynamic>;
        if (mounted) {
          setState(
            () => _position = GeoPoint(
              lat: (j['lat'] as num).toDouble(),
              lng: (j['lng'] as num).toDouble(),
            ),
          );
        }
      },
      onError: (_) => _later(),
      onDone: _later,
      cancelOnError: true,
    );
  }

  void _later() {
    if (mounted) _retry = Timer(const Duration(seconds: 10), _connect);
  }

  @override
  void dispose() {
    _retry?.cancel();
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = _position;
    if (p == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: SizedBox(
          height: widget.height,
          child: TweenAnimationBuilder<Offset>(
            tween: Tween(end: Offset(p.lat, p.lng)),
            duration: const Duration(seconds: 2),
            builder: (_, v, _) {
              final at = GeoPoint(lat: v.dx, lng: v.dy);
              return IviaMap(
                center: at,
                interactive: false,
                markers: [
                  IviaMapMarker(
                    id: 'driver',
                    point: at,
                    color: IviaColors.cobaltBlue,
                    icon: Icons.two_wheeler,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
