import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';

/// Photo jointe à l'alerte (ordonnance ou boîte), gardée en mémoire seulement.
class DraftPhoto {
  const DraftPhoto(this.kind, this.bytes);
  final String kind; // prescription | box_photo
  final Uint8List bytes;
}

/// Alerte en préparation (P02 à P06).
class MedDraft {
  const MedDraft({
    this.items = const [],
    this.photos = const [],
    this.generic = true,
    this.note = '',
    this.method = 'prescription',
  });

  final List<MedItemDraft> items;
  final List<DraftPhoto> photos;
  final bool generic;
  final String note;
  final String method; // prescription | box_photo | name

  bool get isEmpty => items.isEmpty && photos.isEmpty;

  MedDraft copyWith({
    List<MedItemDraft>? items,
    List<DraftPhoto>? photos,
    bool? generic,
    String? note,
    String? method,
  }) => MedDraft(
    items: items ?? this.items,
    photos: photos ?? this.photos,
    generic: generic ?? this.generic,
    note: note ?? this.note,
    method: method ?? this.method,
  );
}

final medDraftProvider = NotifierProvider<MedDraftNotifier, MedDraft>(
  MedDraftNotifier.new,
);

class MedDraftNotifier extends Notifier<MedDraft> {
  @override
  MedDraft build() => const MedDraft();

  void reset() => state = const MedDraft();
  void method(String m) => state = state.copyWith(method: m);
  void generic(bool v) => state = state.copyWith(generic: v);
  void note(String v) => state = state.copyWith(note: v);
  void addPhoto(DraftPhoto p) =>
      state = state.copyWith(photos: [...state.photos, p]);
  void removePhoto(int i) =>
      state = state.copyWith(photos: [...state.photos]..removeAt(i));

  void addItem(MedItemDraft item) {
    final i = state.items.indexWhere((x) => x.name == item.name);
    if (i >= 0) return quantity(i, state.items[i].quantity + 1);
    state = state.copyWith(items: [...state.items, item]);
  }

  void quantity(int i, int q) {
    final items = [...state.items];
    if (q <= 0) {
      items.removeAt(i);
    } else {
      items[i].quantity = q.clamp(1, 20);
    }
    state = state.copyWith(items: items);
  }

  /// Produits d'une alerte précédente (relance « Modifier les produits »).
  void fromAlert(MedAlert a) => state = MedDraft(
    items: [
      for (final i in a.items)
        MedItemDraft(name: i.name, form: i.form, quantity: i.quantity),
    ],
    generic: a.genericAccepted,
    note: a.note,
    method: 'name',
  );
}
