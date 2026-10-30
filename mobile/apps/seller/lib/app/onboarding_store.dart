import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Mémorise, sur l'appareil, que la présentation a été vue.
class OnboardingStore {
  OnboardingStore._(this._prefs, {required this.seenAtLaunch});

  static const _key = 'onboarding_seen';

  final SharedPreferences? _prefs;

  /// État lu au lancement : décide du premier écran.
  final bool seenAtLaunch;

  /// Stockage illisible : la présentation est montrée, sans bloquer l'app.
  static Future<OnboardingStore> open() async {
    final SharedPreferences prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } on Exception {
      return OnboardingStore._(null, seenAtLaunch: false);
    }
    // Une valeur d'un autre type (donnée corrompue) vaut « pas vue » ;
    // markSeen() la remplacera.
    return OnboardingStore._(prefs, seenAtLaunch: prefs.get(_key) == true);
  }

  /// Un échec d'écriture est ignoré : la présentation reviendra au prochain
  /// lancement.
  Future<void> markSeen() async {
    try {
      await _prefs?.setBool(_key, true);
    } on Exception {
      // Rien à faire : l'utilisateur continue vers la connexion.
    }
  }
}

/// Fourni par `main()` une fois le stockage ouvert.
final onboardingStoreProvider = Provider<OnboardingStore>(
  (ref) => throw UnimplementedError('onboardingStoreProvider non fourni'),
);
