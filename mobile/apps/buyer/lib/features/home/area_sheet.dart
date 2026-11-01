import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../app/buyer_area.dart';
import '../../app/catalog_data.dart';

/// Choix de la zone : « Utiliser ma position » ou un quartier.
Future<void> showAreaSheet(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (context) => const _AreaSheet(),
);

class _AreaSheet extends ConsumerWidget {
  const _AreaSheet();

  Future<void> _locate(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    final failure = await ref.read(buyerAreaProvider.notifier).locate();
    if (failure != null) {
      messenger.showSnackBar(
        SnackBar(content: Text(locationFailureMessage(failure))),
      );
    }
  }

  Future<void> _choose(
    BuildContext context,
    WidgetRef ref,
    Choice neighborhood,
  ) async {
    Navigator.pop(context);
    await ref.read(buyerAreaProvider.notifier).chooseNeighborhood(neighborhood);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final area = ref.watch(buyerAreaProvider);
    final neighborhoods = ref.watch(neighborhoodsProvider);
    final selectedId = switch (area) {
      AreaNeighborhood(:final id) => id,
      _ => null,
    };
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.8,
      ),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: IviaSpacing.screen),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: IviaSpacing.screen),
            child: Semantics(
              header: true,
              child: Text('Où cherchez-vous ?', style: textTheme.headlineSmall),
            ),
          ),
          const SizedBox(height: IviaSpacing.sm),
          ListTile(
            leading: const Icon(Icons.my_location),
            title: const Text('Utiliser ma position'),
            subtitle: const Text('Boutiques et produits les plus proches'),
            selected: area is AreaPosition,
            trailing: area is AreaPosition ? const Icon(Icons.check) : null,
            onTap: () => _locate(context, ref),
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
                  trailing: n.id == selectedId ? const Icon(Icons.check) : null,
                  onTap: () => _choose(context, ref, n),
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
      ),
    );
  }
}
