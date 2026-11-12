import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../app/buyer_area.dart';
import '../../app/router.dart';
import '../home/area_sheet.dart';
import '../payment/payment_providers.dart';
import 'med_draft.dart';
import 'med_ui.dart';
import 'pharmacy_state.dart';

String _kindLabel(String kind) =>
    kind == 'prescription' ? 'Ordonnance' : 'Boîte';

/// P02 : comment indiquer les produits.
class NewAlertScreen extends ConsumerWidget {
  const NewAlertScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final method = ref.watch(medDraftProvider).method;
    Widget option(
      String value,
      IconData icon,
      String title,
      String body, {
      String? badge,
    }) {
      final selected = method == value;
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: MedCard(
          border: selected ? IviaColors.primary : null,
          onTap: () => ref.read(medDraftProvider.notifier).method(value),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MedIconTile(
                icon,
                bg: selected ? Med.softRed : Med.softBlue,
                fg: selected ? IviaColors.primary : Med.navy,
                size: 60,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: t.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (badge != null) ...[
                      const SizedBox(height: 8),
                      MedPill(badge, bg: Med.softBlue, fg: Med.blue),
                    ],
                    const SizedBox(height: 8),
                    Text(body, style: t.bodyMedium?.copyWith(color: Med.muted)),
                  ],
                ),
              ),
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: selected ? IviaColors.primary : const Color(0xFFC9CDD4),
                size: 30,
              ),
            ],
          ),
        ),
      );
    }

    return MedScaffold(
      top: const MedTopBar(
        title: 'Nouvelle alerte',
        trailing: MedPill('Étape 1 sur 3'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: IviaSpacing.screen),
        children: [
          Text(
            'Comment indiquer les produits ?',
            style: t.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            'Vous pourrez combiner les méthodes : une ordonnance et un produit saisi, par exemple.',
            style: t.bodyLarge?.copyWith(color: Med.muted),
          ),
          const SizedBox(height: 20),
          option(
            'prescription',
            Icons.description_outlined,
            'Photo de l\'ordonnance',
            'Le pharmacien lit directement la prescription.',
            badge: 'Le plus rapide',
          ),
          option(
            'box_photo',
            Icons.photo_camera_outlined,
            'Photo de la boîte',
            'Le nom, le dosage et la forme sont visibles sur la boîte.',
          ),
          option(
            'name',
            Icons.edit_note,
            'Saisir le nom',
            'Recherchez le médicament et indiquez la quantité.',
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.lock_outline, size: 20, color: Med.muted),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Vos photos ne sont visibles que par les pharmacies de garde alertées, et sont supprimées 24 h après l\'alerte.',
                  style: t.bodyMedium?.copyWith(color: Med.muted),
                ),
              ),
            ],
          ),
        ],
      ),
      // Grisé tant qu'aucune façon d'indiquer les produits n'est choisie.
      bottom: MedBottomButton(
        label: 'Continuer',
        onTap: switch (method) {
          'name' => () => context.push(Routes.medItems),
          'prescription' ||
          'box_photo' => () => context.push(Routes.medCapture(method)),
          _ => null,
        },
      ),
    );
  }
}

/// P03 : saisir les produits (base de médicaments).
class AlertItemsScreen extends ConsumerStatefulWidget {
  const AlertItemsScreen({super.key});

  @override
  ConsumerState<AlertItemsScreen> createState() => _AlertItemsScreenState();
}

class _AlertItemsScreenState extends ConsumerState<AlertItemsScreen> {
  final _search = TextEditingController();
  var _hits = <MedicineHit>[];
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearch(String q) {
    _debounce?.cancel();
    setState(() {});
    if (q.trim().length < 2) {
      setState(() => _hits = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      try {
        final hits = await ref.read(apiClientProvider).searchMedicines(q);
        if (mounted && _search.text == q) setState(() => _hits = hits);
      } on ApiException {
        // Saisie libre toujours possible.
      }
    });
  }

  void _add(String name, {MedicineHit? hit}) {
    if (name.trim().length < 2) return;
    ref
        .read(medDraftProvider.notifier)
        .addItem(
          MedItemDraft(
            name: name.trim(),
            medicineId: hit?.id,
            form: hit?.form ?? '',
          ),
        );
    _search.clear();
    setState(() => _hits = []);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final draft = ref.watch(medDraftProvider);
    final notifier = ref.read(medDraftProvider.notifier);
    final query = _search.text.trim();
    return MedScaffold(
      top: const MedTopBar(
        title: 'Saisir les produits',
        trailing: MedPill('Étape 1 sur 3'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: IviaSpacing.screen),
        children: [
          TextField(
            controller: _search,
            onChanged: _onSearch,
            onSubmitted: _add,
            textInputAction: TextInputAction.done,
            style: t.titleMedium,
            decoration: InputDecoration(
              hintText: 'Rechercher un médicament',
              filled: true,
              fillColor: Colors.white,
              prefixIcon: const Icon(Icons.search, color: IviaColors.primary),
              contentPadding: const EdgeInsets.symmetric(vertical: 22),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(40),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(40),
                borderSide: const BorderSide(
                  color: IviaColors.primary,
                  width: 2,
                ),
              ),
            ),
          ),
          if (query.length >= 2) ...[
            const SizedBox(height: 14),
            MedCard(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
              child: Column(
                children: [
                  for (final (i, h) in _hits.take(5).indexed) ...[
                    if (i > 0) const Divider(height: 1),
                    _ResultRow(
                      title: h.label,
                      subtitle: h.form,
                      onAdd: () => _add(h.label, hit: h),
                    ),
                  ],
                  if (_hits.every(
                    (h) => h.label.toLowerCase() != query.toLowerCase(),
                  )) ...[
                    if (_hits.isNotEmpty) const Divider(height: 1),
                    _ResultRow(
                      title: query,
                      subtitle: 'Ajouter tel quel',
                      onAdd: () => _add(query),
                    ),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Votre liste · ${draft.items.length}',
                  style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              TextButton(
                onPressed: () =>
                    context.push(Routes.medCapture('prescription')),
                child: const Text('+ Photo'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (draft.items.isNotEmpty)
            MedCard(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Column(
                children: [
                  for (final (i, item) in draft.items.indexed) ...[
                    if (i > 0) const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        children: [
                          const MedIconTile(Icons.add_box_outlined, size: 50),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.name,
                                  style: t.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  [
                                    if (item.form.isNotEmpty) item.form,
                                    'boîte',
                                  ].join(' · '),
                                  style: t.bodyMedium?.copyWith(
                                    color: Med.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _QtyButton(
                            icon: Icons.remove,
                            dark: false,
                            onTap: () =>
                                notifier.quantity(i, item.quantity - 1),
                          ),
                          SizedBox(
                            width: 34,
                            child: Text(
                              '${item.quantity}',
                              textAlign: TextAlign.center,
                              style: t.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          _QtyButton(
                            icon: Icons.add,
                            dark: true,
                            onTap: () =>
                                notifier.quantity(i, item.quantity + 1),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          if (draft.photos.isNotEmpty) ...[
            const SizedBox(height: 12),
            MedCard(
              onTap: () => context.push(Routes.medReview),
              child: Row(
                children: [
                  SizedBox.square(
                    dimension: 50,
                    child: MedPhoto(bytes: draft.photos.first.bytes),
                  ),
                  const SizedBox(width: 14),
                  Text(
                    '${draft.photos.length} photo${draft.photos.length > 1 ? 's' : ''} jointe${draft.photos.length > 1 ? 's' : ''}',
                    style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          MedCard(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Générique accepté',
                        style: t.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        'Même molécule et même dosage.',
                        style: t.bodyMedium?.copyWith(color: Med.muted),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: draft.generic,
                  activeTrackColor: Med.blue,
                  onChanged: notifier.generic,
                ),
              ],
            ),
          ),
        ],
      ),
      bottom: MedBottomButton(
        label: 'Continuer',
        onTap: draft.isEmpty ? null : () => context.push(Routes.medLaunch),
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.title,
    required this.subtitle,
    required this.onAdd,
  });
  final String title, subtitle;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    style: t.bodyMedium?.copyWith(color: Med.muted),
                  ),
              ],
            ),
          ),
          _QtyButton(icon: Icons.add, dark: true, onTap: onAdd),
        ],
      ),
    );
  }
}

class _QtyButton extends StatelessWidget {
  const _QtyButton({
    required this.icon,
    required this.dark,
    required this.onTap,
  });
  final IconData icon;
  final bool dark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: dark ? Med.navy : Med.page,
    shape: const CircleBorder(),
    child: InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: SizedBox.square(
        dimension: 44,
        child: Icon(icon, color: dark ? Colors.white : Med.navy),
      ),
    ),
  );
}

/// P04 : prise de vue (ordonnance ou boîte).
class AlertCaptureScreen extends ConsumerStatefulWidget {
  const AlertCaptureScreen({super.key, required this.kind});
  final String kind;

  @override
  ConsumerState<AlertCaptureScreen> createState() => _AlertCaptureScreenState();
}

class _AlertCaptureScreenState extends ConsumerState<AlertCaptureScreen> {
  late var _kind = widget.kind;

  Future<void> _take(PhotoSource source) async {
    final bytes = await ref
        .read(photoPickerProvider)
        .pick(source: source, maxSide: 1600);
    if (bytes == null || !mounted) return;
    ref.read(medDraftProvider.notifier).addPhoto(DraftPhoto(_kind, bytes));
    context.pushReplacement(Routes.medReview);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final photos = ref.watch(medDraftProvider).photos;
    Widget roundDark(IconData icon, VoidCallback onTap) => Material(
      color: const Color(0xFF1E2A44),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox.square(
          dimension: 56,
          child: Icon(icon, color: Colors.white),
        ),
      ),
    );
    return Scaffold(
      backgroundColor: Med.navy,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(IviaSpacing.screen),
              child: Row(
                children: [
                  roundDark(
                    Icons.close,
                    () => (context.canPop()
                        ? context.pop()
                        : context.go('/pharmacy')),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E2A44),
                        borderRadius: BorderRadius.circular(40),
                      ),
                      child: Row(
                        children: [
                          for (final k in ['prescription', 'box_photo'])
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setState(() => _kind = k),
                                child: Container(
                                  height: 46,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: _kind == k
                                        ? Colors.white
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(40),
                                  ),
                                  child: Text(
                                    _kindLabel(k),
                                    style: t.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: _kind == k
                                          ? Med.navy
                                          : Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  roundDark(Icons.flash_on_outlined, () {}),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: IviaSpacing.screen,
                ),
                child: GestureDetector(
                  onTap: () => _take(PhotoSource.camera),
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF17233D),
                      borderRadius: BorderRadius.circular(Med.radius),
                    ),
                    child: Stack(
                      children: [
                        for (final a in [
                          Alignment.topLeft,
                          Alignment.topRight,
                          Alignment.bottomLeft,
                          Alignment.bottomRight,
                        ])
                          Align(
                            alignment: a,
                            child: Padding(
                              padding: const EdgeInsets.all(28),
                              child: _Corner(alignment: a),
                            ),
                          ),
                        const Center(
                          child: Icon(
                            Icons.photo_camera_outlined,
                            color: Color(0xFF51648D),
                            size: 48,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                _kind == 'prescription'
                    ? 'Placez toute l\'ordonnance dans le cadre, bien à plat et éclairée.'
                    : 'Placez la boîte dans le cadre : nom, dosage et forme bien lisibles.',
                textAlign: TextAlign.center,
                style: t.bodyLarge?.copyWith(color: Colors.white),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(36, 0, 36, 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  SizedBox.square(
                    dimension: 56,
                    child: photos.isEmpty
                        ? Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF253350),
                              borderRadius: BorderRadius.circular(14),
                            ),
                          )
                        : MedPhoto(bytes: photos.last.bytes, radius: 14),
                  ),
                  GestureDetector(
                    onTap: () => _take(PhotoSource.camera),
                    child: Container(
                      width: 92,
                      height: 92,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 4),
                      ),
                      padding: const EdgeInsets.all(6),
                      child: const DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                  roundDark(
                    Icons.image_outlined,
                    () => _take(PhotoSource.gallery),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Corner extends StatelessWidget {
  const _Corner({required this.alignment});
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    const side = BorderSide(color: Colors.white, width: 3);
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        border: Border(
          top: alignment.y < 0 ? side : BorderSide.none,
          bottom: alignment.y > 0 ? side : BorderSide.none,
          left: alignment.x < 0 ? side : BorderSide.none,
          right: alignment.x > 0 ? side : BorderSide.none,
        ),
      ),
    );
  }
}

/// P05 : vérifier la photo.
class AlertReviewScreen extends ConsumerStatefulWidget {
  const AlertReviewScreen({super.key});

  @override
  ConsumerState<AlertReviewScreen> createState() => _AlertReviewScreenState();
}

class _AlertReviewScreenState extends ConsumerState<AlertReviewScreen> {
  var _shown = -1;
  late final _note = TextEditingController(
    text: ref.read(medDraftProvider).note,
  );

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final photos = ref.watch(medDraftProvider).photos;
    if (photos.isEmpty) {
      return MedScaffold(
        top: const MedTopBar(title: 'Vérifier la photo'),
        body: Center(
          child: FilledButton(
            onPressed: () =>
                context.pushReplacement(Routes.medCapture('prescription')),
            child: const Text('Prendre une photo'),
          ),
        ),
      );
    }
    final index = _shown < 0 || _shown >= photos.length
        ? photos.length - 1
        : _shown;
    final shown = photos[index];
    final page = photos
        .take(index + 1)
        .where((p) => p.kind == shown.kind)
        .length;
    Widget addTile(String label, String kind) => SizedBox.square(
      dimension: 90,
      child: MedCard(
        padding: EdgeInsets.zero,
        onTap: () => context.push(Routes.medCapture(kind)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.add, color: Med.navy),
            Text(
              label,
              style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
    return MedScaffold(
      top: const MedTopBar(
        title: 'Vérifier la photo',
        trailing: MedPill('Étape 1 sur 3'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: IviaSpacing.screen),
        children: [
          AspectRatio(
            aspectRatio: 1.08,
            child: Stack(
              fit: StackFit.expand,
              children: [
                MedPhoto(bytes: shown.bytes, radius: Med.radius),
                Positioned(
                  left: 16,
                  top: 16,
                  child: MedPill('${_kindLabel(shown.kind)} · page $page'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 90,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final (i, p) in photos.indexed) ...[
                  GestureDetector(
                    onTap: () => setState(() => _shown = i),
                    child: Container(
                      width: 90,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: i == index ? IviaColors.primary : Colors.white,
                          width: 2,
                        ),
                      ),
                      child: MedPhoto(bytes: p.bytes),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                addTile('Page', 'prescription'),
                const SizedBox(width: 12),
                addTile('Boîte', 'box_photo'),
              ],
            ),
          ),
          const SizedBox(height: 14),
          MedCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Le texte est-il lisible ?',
                  style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  'Nom des médicaments, dosage et quantités. Sinon, reprenez la photo.',
                  style: t.bodyMedium?.copyWith(color: Med.muted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Précision pour le pharmacien (facultatif)',
            style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _note,
            maxLength: 300,
            onChanged: ref.read(medDraftProvider.notifier).note,
            decoration: InputDecoration(
              hintText: 'Ex. : le sirop plutôt que les comprimés',
              filled: true,
              fillColor: Colors.white,
              counterText: '',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(Med.radius),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
      bottom: MedBottomButton(
        label: 'Continuer',
        onTap: () => context.push(Routes.medLaunch),
        secondary: MedOutlineButton(
          label: 'Reprendre',
          onTap: () {
            ref.read(medDraftProvider.notifier).removePhoto(index);
            context.pushReplacement(Routes.medCapture(shown.kind));
          },
        ),
      ),
    );
  }
}

/// P06 : lancer l'alerte (résumé, zone et rayon).
class AlertLaunchScreen extends ConsumerStatefulWidget {
  const AlertLaunchScreen({super.key});

  @override
  ConsumerState<AlertLaunchScreen> createState() => _AlertLaunchScreenState();
}

class _AlertLaunchScreenState extends ConsumerState<AlertLaunchScreen> {
  AlertPreview? _preview;
  GeoPoint? _point;
  int? _radius;
  String? _error;
  var _sending = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  /// [ask] : écran d'autorisation s'il le faut (ouverture de l'écran) ;
  /// pas sur un changement de zone, qui suit souvent un refus.
  Future<void> _load({bool ask = true}) async {
    setState(() {
      _error = null;
      _preview = null;
    });
    final p = await alertPosition(context, ref, ask: ask);
    if (!mounted) return;
    if (p == null) {
      setState(
        () => _error =
            'Choisissez votre quartier pour trouver les pharmacies de garde.',
      );
      return;
    }
    try {
      final preview = await ref.read(apiClientProvider).alertPreview(p);
      if (mounted) {
        setState(() {
          _point = p;
          _preview = preview;
          _radius ??= preview.defaultRadiusM;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _send() async {
    final draft = ref.read(medDraftProvider);
    final point = _point, radius = _radius;
    if (point == null || radius == null) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    final api = ref.read(apiClientProvider);
    try {
      final photos = <({String kind, String objectKey})>[];
      for (final p in draft.photos) {
        final prepared = await api.prepareUpload(
          purpose: 'pharmacy_alert_photo',
          contentType: 'image/jpeg',
          sizeBytes: p.bytes.length,
        );
        await api.upload(prepared, p.bytes);
        photos.add((kind: p.kind, objectKey: prepared.objectKey));
      }
      final alert = await api.createAlert(
        items: draft.items,
        photos: photos,
        radiusM: radius,
        location: point,
        genericAccepted: draft.generic,
        note: draft.note.trim(),
      );
      // Démonstration locale sans app pharmacie : les pharmacies de démo
      // répondent d'elles-mêmes quelques secondes plus tard.
      if (ref.read(devPaymentsProvider)) {
        Timer(
          const Duration(seconds: 8),
          () => api.devAutoRespond(alert.id).catchError((_) {}),
        );
      }
      ref
        ..invalidate(myAlertsProvider)
        ..read(medDraftProvider.notifier).reset();
      if (mounted) context.go(Routes.medAlert(alert.id));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final draft = ref.watch(medDraftProvider);
    final preview = _preview;
    final area = ref.watch(buyerAreaProvider);
    ref.listen(buyerAreaProvider, (_, next) {
      // Position en cours de lecture : on attend son résultat.
      if (next is! AreaLocating) _load(ask: false);
    });
    final count =
        preview?.radii
            .where((r) => r.radiusM == _radius)
            .firstOrNull
            ?.pharmacies ??
        0;
    final prescriptions = draft.photos
        .where((p) => p.kind == 'prescription')
        .length;
    final boxes = draft.photos.length - prescriptions;
    return MedScaffold(
      top: const MedTopBar(
        title: 'Lancer l\'alerte',
        trailing: MedPill('Étape 2 sur 3'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: IviaSpacing.screen),
        children: [
          MedCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Produits recherchés',
                  style: t.titleSmall?.copyWith(
                    color: Med.muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (draft.photos.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      SizedBox.square(
                        dimension: 50,
                        child: MedPhoto(bytes: draft.photos.first.bytes),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              [
                                if (prescriptions > 0)
                                  'Ordonnance · $prescriptions page${prescriptions > 1 ? 's' : ''}',
                                if (boxes > 0)
                                  '$boxes boîte${boxes > 1 ? 's' : ''}',
                              ].join(' + '),
                              style: t.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              draft.note.isEmpty
                                  ? 'Sans précision'
                                  : 'Avec une précision',
                              style: t.bodyMedium?.copyWith(color: Med.muted),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
                if (draft.photos.isNotEmpty && draft.items.isNotEmpty)
                  const Divider(height: 28),
                if (draft.photos.isEmpty) const SizedBox(height: 10),
                for (final i in draft.items)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            i.name,
                            style: t.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        Text(
                          '×${i.quantity}',
                          style: t.titleMedium?.copyWith(color: Med.muted),
                        ),
                      ],
                    ),
                  ),
                if (draft.generic) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Générique accepté',
                    style: t.titleSmall?.copyWith(
                      color: Med.blue,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          MedCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Zone de recherche',
                        style: t.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: () => showAreaSheet(context),
                      child: Text(
                        '${area.label} ▾',
                        style: t.titleMedium?.copyWith(
                          color: IviaColors.primary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (preview == null && _error == null)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (preview != null) ...[
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Med.page,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Row(
                      children: [
                        for (final r in preview.radii)
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() => _radius = r.radiusM),
                              child: Container(
                                height: 52,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: _radius == r.radiusM
                                      ? Med.navy
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: Text(
                                  '${r.radiusM ~/ 1000} km',
                                  style: t.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: _radius == r.radiusM
                                        ? Colors.white
                                        : Med.navy,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Icon(Icons.add_box_outlined, color: Med.navy),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text:
                                    '$count pharmacie${count > 1 ? 's' : ''} de garde',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              TextSpan(
                                text: count > 1
                                    ? ' recevront l\'alerte'
                                    : ' recevra l\'alerte',
                              ),
                            ],
                          ),
                          style: t.bodyLarge,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (preview != null)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFFE2EBF8),
                borderRadius: BorderRadius.circular(Med.radius),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline, color: Med.blue),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          const TextSpan(text: 'Lancer l\'alerte est '),
                          const TextSpan(
                            text: 'gratuit',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                          const TextSpan(text: '. Vous payez '),
                          TextSpan(
                            text: formatXof(preview.unlockFeeXof),
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          const TextSpan(
                            text: ' seulement pour débloquer la pharmacie de votre choix parmi celles qui répondent.',
                          ),
                        ],
                      ),
                      style: t.bodyLarge,
                    ),
                  ),
                ],
              ),
            ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Text(
              _error!,
              style: t.bodyMedium?.copyWith(color: IviaColors.error),
            ),
            TextButton(
              onPressed: () => showAreaSheet(context),
              child: const Text('Choisir mon quartier'),
            ),
          ],
        ],
      ),
      bottom: MedBottomButton(
        label: 'Lancer l\'alerte',
        icon: Icons.campaign_outlined,
        busy: _sending,
        onTap: preview == null || count == 0 ? null : _send,
      ),
    );
  }
}
