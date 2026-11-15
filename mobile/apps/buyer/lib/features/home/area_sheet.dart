import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../app/buyer_area.dart';
import '../../app/catalog_data.dart';

/// Choix de la zone : un lieu cherché par son nom (comme sur une carte),
/// « Utiliser ma position », ou un quartier.
Future<void> showAreaSheet(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (context) => const _AreaSheet(),
);

class _AreaSheet extends ConsumerStatefulWidget {
  const _AreaSheet();

  @override
  ConsumerState<_AreaSheet> createState() => _AreaSheetState();
}

class _AreaSheetState extends ConsumerState<_AreaSheet> {
  final _search = TextEditingController();
  final _session = base64Url.encode(
    List.generate(18, (_) => Random.secure().nextInt(256)),
  );
  Timer? _debounce;
  var _results = <GeoSuggestion>[];
  var _searching = false;
  String? _searchError;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onQuery(String q) {
    _debounce?.cancel();
    if (q.trim().length < 3) {
      setState(() {
        _results = [];
        _searching = false;
        _searchError = null;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => _run(q));
  }

  Future<void> _run(String q) async {
    setState(() => _searching = true);
    try {
      final items = await ref
          .read(apiClientProvider)
          .geoAutocomplete(
            q.trim(),
            near: ref.read(buyerAreaProvider).point ?? lome,
            session: _session,
          );
      if (!mounted || _search.text != q) return;
      setState(() {
        _results = items;
        _searchError = items.isEmpty ? 'Aucun lieu trouvé.' : null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _searchError = e.message);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _pick(GeoSuggestion s) async {
    var point = s.point;
    final messenger = ScaffoldMessenger.of(context);
    if (point == null) {
      try {
        point =
            (await ref
                    .read(apiClientProvider)
                    .geoPlace(s.id, session: _session))
                .point;
      } on ApiException catch (e) {
        if (mounted) setState(() => _searchError = e.message);
        return;
      }
    }
    if (!mounted) return;
    Navigator.pop(context);
    await ref.read(buyerAreaProvider.notifier).choosePlace(point, s.name);
    showMessage(messenger, 'Zone : ${s.name}');
  }

  Future<void> _locate() async {
    final messenger = ScaffoldMessenger.of(context);
    // Écran d'autorisation au-dessus de la feuille ; refusé, la lecture
    // échoue avec le message habituel.
    await askForLocation(context, ref);
    if (!mounted) return;
    final area = ref.read(buyerAreaProvider.notifier);
    Navigator.pop(context);
    final failure = await area.locate();
    if (failure != null) {
      messenger.showSnackBar(
        SnackBar(content: Text(locationFailureMessage(failure))),
      );
    }
  }

  Future<void> _choose(Choice neighborhood) async {
    Navigator.pop(context);
    await ref.read(buyerAreaProvider.notifier).chooseNeighborhood(neighborhood);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final area = ref.watch(buyerAreaProvider);
    final neighborhoods = ref.watch(neighborhoodsProvider);
    final selectedId = switch (area) {
      AreaNeighborhood(:final id) => id,
      _ => null,
    };
    final searching = _search.text.trim().length >= 3;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      child: ListView(
        shrinkWrap: true,
        padding: EdgeInsets.only(
          bottom: IviaSpacing.screen + MediaQuery.viewInsetsOf(context).bottom,
        ),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: IviaSpacing.screen),
            child: Semantics(
              header: true,
              child: Text('Où cherchez-vous ?', style: textTheme.headlineSmall),
            ),
          ),
          const SizedBox(height: IviaSpacing.md),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: IviaSpacing.screen),
            child: TextField(
              controller: _search,
              onChanged: _onQuery,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Un lieu : Grand Marché, Université de Lomé…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searching
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : null,
              ),
            ),
          ),
          if (searching) ...[
            if (_searchError case final e?)
              Padding(
                padding: const EdgeInsets.all(IviaSpacing.screen),
                child: Text(e, style: textTheme.bodyMedium),
              ),
            for (final s in _results)
              ListTile(
                leading: const Icon(Icons.place_outlined),
                title: Text(s.name),
                subtitle: s.address.isEmpty ? null : Text(s.address),
                onTap: () => _pick(s),
              ),
          ] else ...[
            const SizedBox(height: IviaSpacing.sm),
            ListTile(
              leading: const Icon(Icons.my_location),
              title: const Text('Utiliser ma position'),
              subtitle: const Text('Boutiques et produits les plus proches'),
              selected: area is AreaPosition && area is! AreaPlace,
              trailing: area is AreaPosition && area is! AreaPlace
                  ? const Icon(Icons.check)
                  : null,
              onTap: _locate,
            ),
            if (area case AreaPlace(:final name))
              ListTile(
                leading: const Icon(Icons.place),
                title: Text(name),
                subtitle: const Text('Lieu choisi'),
                selected: true,
                trailing: const Icon(Icons.check),
                onTap: () => Navigator.pop(context),
              ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                IviaSpacing.screen,
                IviaSpacing.md,
                IviaSpacing.screen,
                IviaSpacing.xs,
              ),
              child: Text(
                'Ou choisissez un quartier',
                style: textTheme.labelLarge,
              ),
            ),
            ...switch (neighborhoods) {
              AsyncData(value: final all) => [
                for (final n in all)
                  ListTile(
                    title: Text(n.name),
                    selected: n.id == selectedId,
                    trailing: n.id == selectedId
                        ? const Icon(Icons.check)
                        : null,
                    onTap: () => _choose(n),
                  ),
              ],
              AsyncError() => [
                Padding(
                  padding: const EdgeInsets.all(IviaSpacing.screen),
                  child: OutlinedButton(
                    onPressed: () => ref.invalidate(neighborhoodsProvider),
                    child: const Text('Quartiers : réessayer'),
                  ),
                ),
              ],
              _ => const [
                Padding(
                  padding: EdgeInsets.all(IviaSpacing.xl),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ],
            },
          ],
        ],
      ),
    );
  }
}
