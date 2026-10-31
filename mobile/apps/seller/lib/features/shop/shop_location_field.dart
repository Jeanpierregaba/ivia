import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../app/device_services.dart';

/// Centre de Lomé : position de départ de la carte.
const _lome = LatLng(6.1319, 1.2228);

/// Position de la boutique : carte Google Maps (épingle à déplacer, appui
/// pour la placer) quand les clés sont configurées, sinon aperçu ; bouton
/// « Ma position » dans les deux cas.
class ShopLocationField extends ConsumerStatefulWidget {
  const ShopLocationField({
    super.key,
    required this.value,
    required this.onChanged,
    this.errorText,
    this.enabled = true,
  });

  final GeoPoint? value;
  final ValueChanged<GeoPoint> onChanged;
  final String? errorText;
  final bool enabled;

  @override
  ConsumerState<ShopLocationField> createState() => _ShopLocationFieldState();
}

class _ShopLocationFieldState extends ConsumerState<ShopLocationField> {
  GoogleMapController? _map;
  String? _locateError;
  var _locating = false;

  @override
  void dispose() {
    _map?.dispose();
    super.dispose();
  }

  Future<void> _locate() async {
    setState(() {
      _locating = true;
      _locateError = null;
    });
    final result = await ref.read(locationServiceProvider).current();
    if (!mounted) return;
    setState(() {
      _locating = false;
      _locateError = switch (result.failure) {
        null => null,
        LocationFailure.serviceDisabled =>
          'Activez la localisation du téléphone, ou placez la boutique sur '
              'la carte.',
        LocationFailure.denied =>
          'Localisation refusée : placez la boutique sur la carte.',
        LocationFailure.deniedForever =>
          'Localisation désactivée pour ivia : autorisez-la dans les réglages '
              'du téléphone, ou placez la boutique sur la carte.',
        LocationFailure.unavailable =>
          'Position introuvable pour le moment. Réessayez, ou placez la '
              'boutique sur la carte.',
      };
    });
    if (result.point case final point?) {
      widget.onChanged(point);
      await _map?.animateCamera(
        CameraUpdate.newLatLngZoom(LatLng(point.lat, point.lng), 17),
      );
    }
  }

  void _place(LatLng position) {
    if (widget.enabled) {
      widget.onChanged(
        GeoPoint(lat: position.latitude, lng: position.longitude),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final error = widget.errorText ?? _locateError;
    final value = widget.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(IviaRadius.large),
          child: SizedBox(
            height: 180,
            child: ref.watch(mapsEnabledProvider)
                ? _mapView(value)
                : _preview(value),
          ),
        ),
        const SizedBox(height: IviaSpacing.sm),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: widget.enabled && !_locating ? _locate : null,
            icon: _locating
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.my_location),
            label: const Text('Ma position'),
          ),
        ),
        if (error != null)
          Semantics(
            liveRegion: true,
            child: Text(
              error,
              style: textTheme.bodySmall?.copyWith(color: IviaColors.error),
            ),
          ),
      ],
    );
  }

  Widget _mapView(GeoPoint? value) {
    final position = value == null ? null : LatLng(value.lat, value.lng);
    return GoogleMap(
      initialCameraPosition: CameraPosition(
        target: position ?? _lome,
        zoom: position == null ? 12 : 17,
      ),
      onMapCreated: (controller) => _map = controller,
      onTap: _place,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      // La carte prend les gestes, même dans un écran qui défile.
      gestureRecognizers: {
        Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new),
      },
      markers: {
        if (position != null)
          Marker(
            markerId: const MarkerId('boutique'),
            position: position,
            draggable: widget.enabled,
            onDragEnd: _place,
          ),
      },
    );
  }

  /// Sans clé Google Maps (développement) : la position vient de
  /// « Ma position » seulement.
  Widget _preview(GeoPoint? value) {
    final textTheme = Theme.of(context).textTheme;
    return Stack(
      fit: StackFit.expand,
      children: [
        const IviaImagePlaceholder(radius: 0),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.location_on,
                size: 36,
                color: value == null
                    ? IviaColors.textMuted
                    : IviaAppBrand.of(context).action,
              ),
              Text(
                value == null
                    ? 'Aucune position'
                    : '${value.lat.toStringAsFixed(5)}, '
                          '${value.lng.toStringAsFixed(5)}',
                style: textTheme.bodySmall?.copyWith(color: IviaColors.text),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
