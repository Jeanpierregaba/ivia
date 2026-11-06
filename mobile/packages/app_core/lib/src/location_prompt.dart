import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_ui/ivia_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_identity.dart';
import 'location.dart';

/// Textes et icônes de l'écran d'autorisation de la localisation d'une app
/// (maquettes de la spec 030).
class LocationPromptCopy {
  const LocationPromptCopy({
    this.space,
    required this.center,
    required this.satellites,
    required this.title,
    required this.titleAccent,
    required this.body,
  });

  /// Nom de l'espace à côté du logo (« Business ») ; aucun pour l'acheteur.
  final String? space;
  final IconData center;

  /// En haut à gauche, en haut à droite, en bas à gauche, en bas à droite.
  final List<IconData> satellites;

  /// Début du titre, puis sa partie colorée.
  final String title;
  final String titleAccent;
  final String body;
}

/// Mémorise, sur l'appareil, que l'écran du lancement a été passé.
class LocationPromptStore {
  LocationPromptStore._(this._prefs, {required this.doneAtLaunch});

  static const _key = 'location_prompt_done';

  final SharedPreferences? _prefs;

  /// Écran déjà passé, ou position déjà autorisée : pas d'écran au lancement.
  final bool doneAtLaunch;

  /// Stockage illisible : l'écran est montré, sans bloquer l'app. La lecture
  /// de l'autorisation est bornée : le lancement n'attend pas plus de 2 s.
  static Future<LocationPromptStore> open(LocationService service) async {
    SharedPreferences? prefs;
    var done = false;
    try {
      prefs = await SharedPreferences.getInstance();
      done = prefs.get(_key) == true;
    } on Exception {
      prefs = null;
    }
    if (!done) {
      try {
        done =
            await service.access().timeout(const Duration(seconds: 2)) ==
            LocationAccess.granted;
      } on Exception {
        done = false;
      }
    }
    return LocationPromptStore._(prefs, doneAtLaunch: done);
  }

  /// Un échec d'écriture est ignoré : l'écran reviendra au prochain lancement.
  Future<void> markDone() async {
    try {
      await _prefs?.setBool(_key, true);
    } on Exception {
      // Rien à faire : l'utilisateur continue.
    }
  }
}

/// Fourni par `main()` une fois le stockage ouvert.
final locationPromptStoreProvider = Provider<LocationPromptStore>(
  (ref) => throw UnimplementedError('locationPromptStoreProvider non fourni'),
);

/// Écran du lancement passé ; `complete()` le mémorise.
final locationPromptDoneProvider = NotifierProvider<LocationPromptDone, bool>(
  LocationPromptDone.new,
);

class LocationPromptDone extends Notifier<bool> {
  @override
  bool build() => ref.watch(locationPromptStoreProvider).doneAtLaunch;

  Future<void> complete() async {
    await ref.read(locationPromptStoreProvider).markDone();
    state = true;
  }
}

/// Écran d'autorisation de la localisation de l'app. « Autoriser » ouvre la
/// fenêtre du système (les réglages si le refus est définitif) ; dans tous
/// les cas, [onDone] est appelé ensuite, une seule fois.
class LocationPromptScreen extends ConsumerStatefulWidget {
  const LocationPromptScreen({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  ConsumerState<LocationPromptScreen> createState() =>
      _LocationPromptScreenState();
}

class _LocationPromptScreenState extends ConsumerState<LocationPromptScreen> {
  var _busy = false;
  var _done = false;

  void _finish() {
    if (!mounted || _done) return;
    _done = true;
    widget.onDone();
  }

  Future<void> _allow() async {
    if (_busy) return;
    setState(() => _busy = true);
    final service = ref.read(locationServiceProvider);
    try {
      switch (await service.access()) {
        case LocationAccess.askable:
          await service.request();
        case LocationAccess.deniedForever:
          await service.openSettings();
        case LocationAccess.granted:
          break;
      }
    } on Exception {
      // Fenêtre du système en échec : on continue sans position.
    }
    if (!mounted) return;
    setState(() => _busy = false);
    _finish();
  }

  @override
  Widget build(BuildContext context) {
    final identity = ref.watch(appIdentityProvider);
    final copy = identity.locationPrompt;
    return IviaLocationPrompt(
      brand: identity.brand,
      space: copy.space,
      radar: (center: copy.center, satellites: copy.satellites),
      title: copy.title,
      titleAccent: copy.titleAccent,
      body: copy.body,
      busy: _busy,
      onAllow: _allow,
      onRefuse: _finish,
    );
  }
}

/// Écran du lancement : passé, il ne revient plus.
class LaunchLocationPromptScreen extends ConsumerWidget {
  const LaunchLocationPromptScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => LocationPromptScreen(
    onDone: () => ref.read(locationPromptDoneProvider.notifier).complete(),
  );
}

/// Avant une fonctionnalité qui a besoin de la position : sans autorisation,
/// l'écran s'affiche par-dessus tout (barre du bas comprise). Renvoie `true`
/// si la position est autorisée ensuite. Le retour système vaut « Refuser ».
Future<bool> askForLocation(BuildContext context, WidgetRef ref) async {
  final service = ref.read(locationServiceProvider);
  if (await service.access() == LocationAccess.granted) return true;
  if (!context.mounted) return false;
  await Navigator.of(context, rootNavigator: true).push<void>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (route) =>
          LocationPromptScreen(onDone: () => Navigator.of(route).pop()),
    ),
  );
  return await service.access() == LocationAccess.granted;
}
