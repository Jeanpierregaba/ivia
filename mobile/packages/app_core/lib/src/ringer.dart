import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Sons des apps ivia, app ouverte :
/// - [ring] : sonnerie forte en boucle, avec vibrations, tant qu'une offre
///   attend une réponse (course du livreur, commande du marchand, alerte de
///   la pharmacie) ; [stop] dès qu'elle est acceptée, refusée ou expirée ;
/// - [chime] : son court et doux (notification du client).
///
/// Un son qui ne peut pas jouer (navigateur qui bloque le son avant le
/// premier appui, appareil sans son) ne bloque jamais l'écran.
class IviaRinger {
  /// Tests d'écran : aucun son (pas de lecteur audio sans appareil).
  static bool get _silent => WidgetsBinding.instance is! WidgetsFlutterBinding;

  AudioPlayer? _loop;
  Timer? _buzz;
  Uint8List? _ringBytes, _chimeBytes;

  /// La sonnerie joue-t-elle ?
  bool get ringing => _loop != null;

  Future<Uint8List> _bytes(String name) async =>
      (await rootBundle.load('packages/ivia_app_core/assets/sounds/$name'))
          .buffer
          .asUint8List();

  /// Démarre la sonnerie en boucle (rien si elle joue déjà).
  Future<void> ring() async {
    if (_loop != null || _silent) return;
    final player = AudioPlayer();
    _loop = player;
    _buzz = Timer.periodic(const Duration(milliseconds: 1100), (_) {
      HapticFeedback.heavyImpact();
    });
    try {
      _ringBytes ??= await _bytes('ring.wav');
      if (_loop != player) return; // arrêtée pendant le chargement
      await player.setReleaseMode(ReleaseMode.loop);
      await player.setVolume(1);
      await player.play(BytesSource(_ringBytes!, mimeType: 'audio/wav'));
    } on Object catch (e) {
      debugPrint('Sonnerie impossible : ${e.runtimeType}');
    }
  }

  /// Arrête la sonnerie.
  Future<void> stop() async {
    _buzz?.cancel();
    _buzz = null;
    final player = _loop;
    _loop = null;
    if (player == null) return;
    try {
      await player.stop();
      await player.dispose();
    } on Object {
      // Déjà arrêtée.
    }
  }

  /// Sonnerie jouée une seule fois, avec une vibration forte : une offre à
  /// voir (course du livreur, nouvelle commande du marchand). La boucle
  /// ([ring]) est réservée aux alertes de la pharmacie.
  Future<void> alert() => _once('ring.wav', strong: true);

  /// Son court de notification.
  Future<void> chime() => _once('chime.wav');

  Future<void> _once(String name, {bool strong = false}) async {
    if (_silent) return;
    final player = AudioPlayer();
    try {
      final bytes = name == 'ring.wav'
          ? _ringBytes ??= await _bytes(name)
          : _chimeBytes ??= await _bytes(name);
      await player.play(BytesSource(bytes, mimeType: 'audio/wav'));
      unawaited(
        strong ? HapticFeedback.heavyImpact() : HapticFeedback.lightImpact(),
      );
      // Libéré une fois le son fini.
      unawaited(player.onPlayerComplete.first.then((_) => player.dispose()));
    } on Object {
      await player.dispose();
    }
  }
}

/// Sons de l'app ; remplacé dans les tests (aucun son).
final ringerProvider = Provider<IviaRinger>((ref) {
  final r = IviaRinger();
  ref.onDispose(r.stop);
  return r;
});
