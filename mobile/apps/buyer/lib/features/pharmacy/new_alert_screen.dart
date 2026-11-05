import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../app/router.dart';
import 'pharmacy_state.dart';

/// P01 à P03 : « Trouver un médicament ». Produits (base ou saisie libre),
/// photos d'ordonnance ou de boîte, générique accepté, rayon avec le nombre
/// de pharmacies joignables, puis envoi de l'alerte.
class NewAlertScreen extends ConsumerStatefulWidget {
  const NewAlertScreen({super.key});

  @override
  ConsumerState<NewAlertScreen> createState() => _NewAlertScreenState();
}

class _Photo {
  _Photo(this.kind, this.bytes);
  final String kind;
  final Uint8List bytes;
}

class _NewAlertScreenState extends ConsumerState<NewAlertScreen> {
  final _search = TextEditingController();
  final _note = TextEditingController();
  final _items = <MedItemDraft>[];
  final _photos = <_Photo>[];
  var _hits = <MedicineHit>[];
  var _generic = true;
  Timer? _debounce;
  GeoPoint? _point;
  AlertPreview? _preview;
  int? _radius;
  String? _error;
  var _sending = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadPreview());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _loadPreview() async {
    final p = await alertPosition(ref);
    if (!mounted) return;
    if (p == null) {
      setState(
        () => _error =
            'Activez la position ou choisissez votre quartier sur l\'accueil.',
      );
      return;
    }
    try {
      final preview = await ref.read(apiClientProvider).alertPreview(p);
      if (!mounted) return;
      setState(() {
        _point = p;
        _preview = preview;
        _radius = preview.defaultRadiusM;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  void _onSearch(String q) {
    _debounce?.cancel();
    if (q.trim().length < 2) {
      setState(() => _hits = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final hits = await ref.read(apiClientProvider).searchMedicines(q);
        if (mounted && _search.text == q) setState(() => _hits = hits);
      } on ApiException {
        // L'autocomplétion est un confort : la saisie libre reste possible.
      }
    });
  }

  void _add({MedicineHit? hit}) {
    final name = hit?.label ?? _search.text.trim();
    if (name.length < 2) return;
    setState(() {
      _items.add(
        MedItemDraft(name: name, medicineId: hit?.id, form: hit?.form ?? ''),
      );
      _search.clear();
      _hits = [];
    });
  }

  Future<void> _addPhoto(String kind) async {
    final source = await showModalBottomSheet<PhotoSource>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Prendre une photo'),
              onTap: () => Navigator.pop(context, PhotoSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choisir dans la galerie'),
              onTap: () => Navigator.pop(context, PhotoSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    final bytes = await ref
        .read(photoPickerProvider)
        .pick(source: source, maxSide: 1600);
    if (bytes != null && mounted)
      setState(() => _photos.add(_Photo(kind, bytes)));
  }

  Future<void> _send() async {
    if (_items.isEmpty && _photos.isEmpty) {
      setState(
        () => _error =
            'Ajoutez au moins un médicament ou une photo d\'ordonnance.',
      );
      return;
    }
    final point = _point;
    final radius = _radius;
    if (point == null || radius == null) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    final api = ref.read(apiClientProvider);
    try {
      final photos = <({String kind, String objectKey})>[];
      for (final p in _photos) {
        final prepared = await api.prepareUpload(
          purpose: 'pharmacy_alert_photo',
          contentType: 'image/jpeg',
          sizeBytes: p.bytes.length,
        );
        await api.upload(prepared, p.bytes);
        photos.add((kind: p.kind, objectKey: prepared.objectKey));
      }
      final alert = await api.createAlert(
        items: _items,
        photos: photos,
        radiusM: radius,
        location: point,
        genericAccepted: _generic,
        note: _note.text.trim(),
      );
      ref.invalidate(myAlertsProvider);
      if (mounted) context.pushReplacement(Routes.medAlert(alert.id));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final brand = IviaAppBrand.of(context);
    final preview = _preview;
    return Scaffold(
      appBar: AppBar(title: const Text('Trouver un médicament')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(IviaSpacing.screen),
          children: [
            Text.rich(
              TextSpan(
                text: 'Les pharmacies autour de vous\n',
                children: [
                  TextSpan(
                    text: 'vous répondent.',
                    style: TextStyle(color: brand.highlight),
                  ),
                ],
              ),
              style: t.headlineSmall,
            ),
            const SizedBox(height: IviaSpacing.sm),
            Text(
              'Elles indiquent ce qu\'elles ont et à quel prix. Vous ne payez que '
              'pour voir la pharmacie choisie.',
              style: t.bodyMedium?.copyWith(color: IviaColors.textSecondary),
            ),
            const SizedBox(height: IviaSpacing.xl),
            _Label('1. Vos médicaments'),
            TextField(
              controller: _search,
              onChanged: _onSearch,
              onSubmitted: (_) => _add(),
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                hintText: 'Doliprane, amoxicilline…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  tooltip: 'Ajouter',
                  icon: const Icon(Icons.add_circle),
                  onPressed: _add,
                ),
              ),
            ),
            for (final h in _hits.take(6))
              ListTile(
                dense: true,
                leading: const Icon(Icons.medication_outlined),
                title: Text(h.label),
                subtitle: h.form.isEmpty ? null : Text(h.form),
                onTap: () => _add(hit: h),
              ),
            for (final (i, item) in _items.indexed)
              Card(
                margin: const EdgeInsets.only(top: IviaSpacing.sm),
                child: ListTile(
                  leading: const Icon(Icons.medication),
                  title: Text(item.name),
                  subtitle: item.form.isEmpty ? null : Text(item.form),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Moins',
                        icon: const Icon(Icons.remove),
                        onPressed: () => setState(() {
                          if (item.quantity > 1) {
                            item.quantity--;
                          } else {
                            _items.removeAt(i);
                          }
                        }),
                      ),
                      Text('${item.quantity}', style: t.titleMedium),
                      IconButton(
                        tooltip: 'Plus',
                        icon: const Icon(Icons.add),
                        onPressed: item.quantity < 20
                            ? () => setState(() => item.quantity++)
                            : null,
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: IviaSpacing.xl),
            _Label('2. Ordonnance ou boîte (facultatif)'),
            Wrap(
              spacing: IviaSpacing.sm,
              runSpacing: IviaSpacing.sm,
              children: [
                for (final (i, p) in _photos.indexed)
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(IviaRadius.large),
                        child: Image.memory(
                          p.bytes,
                          width: 84,
                          height: 84,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned(
                        right: 0,
                        child: IconButton.filledTonal(
                          iconSize: 16,
                          tooltip: 'Retirer',
                          icon: const Icon(Icons.close),
                          onPressed: () => setState(() => _photos.removeAt(i)),
                        ),
                      ),
                    ],
                  ),
                if (_photos.length < 4) ...[
                  OutlinedButton.icon(
                    onPressed: () => _addPhoto('prescription'),
                    icon: const Icon(Icons.description_outlined),
                    label: const Text('Ordonnance'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _addPhoto('box_photo'),
                    icon: const Icon(Icons.inventory_2_outlined),
                    label: const Text('Boîte'),
                  ),
                ],
              ],
            ),
            if (preview != null)
              Padding(
                padding: const EdgeInsets.only(top: IviaSpacing.sm),
                child: Text(
                  'Photos visibles seulement par les pharmacies sollicitées, '
                  'effacées ${preview.photoRetentionHours} h après l\'alerte.',
                  style: t.bodySmall,
                ),
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _generic,
              onChanged: (v) => setState(() => _generic = v),
              title: const Text('J\'accepte un générique'),
            ),
            TextField(
              controller: _note,
              maxLength: 300,
              decoration: const InputDecoration(
                hintText: 'Précision pour la pharmacie (facultatif)',
              ),
            ),
            const SizedBox(height: IviaSpacing.lg),
            _Label('3. Jusqu\'où chercher ?'),
            if (preview == null && _error == null)
              const Padding(
                padding: EdgeInsets.all(IviaSpacing.lg),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (preview != null)
              Row(
                children: [
                  for (final r in preview.radii)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: _RadiusCard(
                          km: r.radiusM / 1000,
                          pharmacies: r.pharmacies,
                          selected: _radius == r.radiusM,
                          onTap: () => setState(() => _radius = r.radiusM),
                        ),
                      ),
                    ),
                ],
              ),
            if (preview != null) ...[
              const SizedBox(height: IviaSpacing.lg),
              IviaInfoCard(
                text:
                    'Réponses sous ${preview.responseWindowMinutes} min. Pour voir une '
                    'pharmacie : ${formatXof(preview.unlockFeeXof)}, produits mis de côté '
                    '${preview.pickupHoldMinutes} min. Aucune commission ensuite.',
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: IviaSpacing.md),
              Text(
                _error!,
                style: t.bodyMedium?.copyWith(color: IviaColors.error),
              ),
            ],
            const SizedBox(height: IviaSpacing.xl),
            FilledButton(
              onPressed: _sending || preview == null ? null : _send,
              child: _sending
                  ? const ButtonProgress(label: 'Envoi')
                  : const Text('Lancer l\'alerte'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: IviaSpacing.sm),
    child: Text(text, style: Theme.of(context).textTheme.titleMedium),
  );
}

class _RadiusCard extends StatelessWidget {
  const _RadiusCard({
    required this.km,
    required this.pharmacies,
    required this.selected,
    required this.onTap,
  });

  final double km;
  final int pharmacies;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final brand = IviaAppBrand.of(context);
    return Material(
      color: selected ? brand.accent : IviaColors.surface,
      borderRadius: BorderRadius.circular(IviaRadius.large),
      child: InkWell(
        borderRadius: BorderRadius.circular(IviaRadius.large),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: IviaSpacing.lg),
          child: Column(
            children: [
              Text(
                '${km % 1 == 0 ? km.toInt() : km} km',
                style: t.titleLarge?.copyWith(
                  color: selected ? Colors.white : null,
                ),
              ),
              Text(
                '$pharmacies pharmacie${pharmacies > 1 ? 's' : ''}',
                style: t.bodySmall?.copyWith(
                  color: selected ? Colors.white : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
