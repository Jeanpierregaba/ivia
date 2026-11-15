import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../common/ui.dart';
import '../security/secure_screen.dart';

/// Photo d'ordonnance : lien signé de 10 minutes. Gardée en mémoire
/// seulement (jamais écrite sur le téléphone) ; un lien expiré relit le
/// détail ([onExpired], une fois).
class PrescriptionImage extends StatefulWidget {
  const PrescriptionImage({
    super.key,
    required this.url,
    this.onExpired,
    this.fit = BoxFit.cover,
    this.dark = false,
  });
  final String? url;
  final VoidCallback? onExpired;
  final BoxFit fit;

  /// Sur le fond bleu nuit de F12 : emplacement sombre.
  final bool dark;

  @override
  State<PrescriptionImage> createState() => _PrescriptionImageState();
}

class _PrescriptionImageState extends State<PrescriptionImage> {
  var _reported = false;

  Widget _missing() => widget.dark
      ? Center(
          child: Text(
            'Photo indisponible',
            style: PText.body.copyWith(color: IviaPharmacyColors.nightMuted),
          ),
        )
      : const IviaImagePlaceholder(radius: 0);

  @override
  Widget build(BuildContext context) {
    final url = widget.url;
    if (url == null) return _missing();
    return Image.network(
      url,
      fit: widget.fit,
      errorBuilder: (_, _, _) {
        if (!_reported) {
          _reported = true;
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => widget.onExpired?.call(),
          );
        }
        return _missing();
      },
    );
  }
}

/// Ordonnance en grand (F12) : pages, zoom au doigt et par boutons, pivot.
/// Sur Android, la capture d'écran est bloquée tant que l'écran est ouvert.
class PrescriptionViewer extends StatefulWidget {
  const PrescriptionViewer({super.key, required this.photos, this.reload});
  final List<InboxPhoto> photos;

  /// Lien expiré (10 minutes) : relit le détail et renvoie les nouvelles
  /// photos.
  final Future<List<InboxPhoto>?> Function()? reload;

  @override
  State<PrescriptionViewer> createState() => _PrescriptionViewerState();
}

class _PrescriptionViewerState extends State<PrescriptionViewer> {
  static const _minScale = 1.0, _maxScale = 4.0, _step = 0.5;

  final _pages = PageController();
  late final _zoom = [
    for (final _ in widget.photos) TransformationController(),
  ];
  late var _photos = widget.photos;
  var _reloading = false;

  Future<void> _refresh() async {
    if (_reloading || widget.reload == null) return;
    _reloading = true;
    final fresh = await widget.reload!();
    if (!mounted) return;
    if (fresh != null && fresh.length == _photos.length) {
      setState(() => _photos = fresh);
    }
    _reloading = false;
  }

  var _page = 0;
  var _turns = 0;
  var _scale = 1.0;

  /// Taille du cadre de la photo : centre du zoom par boutons.
  var _viewport = Size.zero;

  @override
  void initState() {
    super.initState();
    SecureScreen.enable();
    for (final z in _zoom) {
      z.addListener(() {
        final s = z.value.getMaxScaleOnAxis();
        if ((s - _scale).abs() > 0.01) setState(() => _scale = s);
      });
    }
  }

  @override
  void dispose() {
    SecureScreen.disable();
    // Aucune copie de l'ordonnance gardée après la fermeture.
    for (final p in _photos) {
      if (p.url case final url?) NetworkImage(url).evict();
    }
    for (final z in _zoom) {
      z.dispose();
    }
    _pages.dispose();
    super.dispose();
  }

  void _setScale(double scale) {
    final s = scale.clamp(_minScale, _maxScale);
    final z = _zoom[_page];
    // Zoom par boutons : depuis le centre de la photo.
    final c = Offset(_viewport.width / 2, _viewport.height / 2);
    z.value = Matrix4.identity()
      ..translateByDouble(c.dx * (1 - s), c.dy * (1 - s), 0, 1)
      ..scaleByDouble(s, s, 1, 1);
    setState(() => _scale = s);
  }

  Widget _round(IconData icon, String label, VoidCallback? onTap) => Semantics(
    button: true,
    label: label,
    excludeSemantics: true,
    child: SizedBox.square(
      dimension: 48,
      child: Center(
        child: Material(
          color: IviaPharmacyColors.nightButton,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox.square(
              dimension: 44,
              child: Icon(
                icon,
                color: onTap == null ? Colors.white38 : Colors.white,
                size: 22,
              ),
            ),
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final n = _photos.length;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: IviaPharmacyColors.night,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(
                  children: [
                    _round(
                      Icons.close,
                      'Fermer',
                      () => Navigator.of(context).pop(),
                    ),
                    Expanded(
                      child: Semantics(
                        header: true,
                        liveRegion: true,
                        child: Text(
                          'Page ${_page + 1} sur $n',
                          textAlign: TextAlign.center,
                          style: PText.header.copyWith(color: Colors.white),
                        ),
                      ),
                    ),
                    _round(
                      Icons.rotate_right,
                      'Pivoter',
                      () => setState(() => _turns = (_turns + 1) % 4),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: P.gutter),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(P.radius),
                    child: ColoredBox(
                      color: IviaPharmacyColors.nightPanel,
                      child: LayoutBuilder(
                        builder: (context, box) {
                          _viewport = box.biggest;
                          return PageView.builder(
                            controller: _pages,
                            itemCount: n,
                            // Zoomé, le doigt déplace la photo, pas la page.
                            physics: _scale > 1.01
                                ? const NeverScrollableScrollPhysics()
                                : null,
                            onPageChanged: (i) => setState(() {
                              _page = i;
                              _scale = _zoom[i].value.getMaxScaleOnAxis();
                            }),
                            itemBuilder: (_, i) => InteractiveViewer(
                              transformationController: _zoom[i],
                              minScale: _minScale,
                              maxScale: _maxScale,
                              child: Center(
                                child: RotatedBox(
                                  quarterTurns: _turns,
                                  child: Semantics(
                                    image: true,
                                    label: 'Ordonnance, page ${i + 1}',
                                    child: PrescriptionImage(
                                      key: ValueKey(_photos[i].url),
                                      url: _photos[i].url,
                                      fit: BoxFit.contain,
                                      dark: true,
                                      onExpired: _refresh,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _round(
                    Icons.zoom_out,
                    'Réduire',
                    _scale > _minScale + 0.01
                        ? () => _setScale(_scale - _step)
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Container(
                    constraints: const BoxConstraints(minWidth: 80),
                    height: 44,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: const ShapeDecoration(
                      color: IviaPharmacyColors.nightButton,
                      shape: StadiumBorder(),
                    ),
                    child: Text(
                      '${(_scale * 100).round()} %',
                      semanticsLabel:
                          'Zoom ${(_scale * 100).round()} pour cent',
                      style: PText.cardTitle.copyWith(color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 10),
                  _round(
                    Icons.zoom_in,
                    'Agrandir',
                    _scale < _maxScale - 0.01
                        ? () => _setScale(_scale + _step)
                        : null,
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(P.gutter, 12, P.gutter, 12),
                child: Text(
                  [
                    if (SecureScreen.supported) "Capture d'écran désactivée",
                    "photo supprimée 24 h après l'alerte",
                  ].join(' · ').replaceFirstMapped(RegExp('^p'), (_) => 'P'),
                  textAlign: TextAlign.center,
                  style: PText.body.copyWith(
                    color: IviaPharmacyColors.nightMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
