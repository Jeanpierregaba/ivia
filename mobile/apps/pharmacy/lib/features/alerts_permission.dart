import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_ui/ivia_ui.dart';
import 'package:permission_handler/permission_handler.dart';

import 'ui.dart';

/// Autorisations du téléphone accordées ? Sans objet sur le web.
final alertsReadyProvider = FutureProvider<bool>((ref) async {
  if (kIsWeb) return true;
  return await Permission.notification.isGranted &&
      (defaultTargetPlatform != TargetPlatform.android ||
          await Permission.ignoreBatteryOptimizations.isGranted);
});

/// « Plus tard » : la question revient à la prochaine ouverture de l'app.
final alertsPromptSkippedProvider = NotifierProvider<_Skipped, bool>(
  _Skipped.new,
);

class _Skipped extends Notifier<bool> {
  @override
  bool build() => false;

  void skip() => state = true;
}

/// Demande les autorisations qui permettent de ne manquer aucune alerte.
class AlertsPermissionScreen extends ConsumerStatefulWidget {
  const AlertsPermissionScreen({super.key});

  @override
  ConsumerState<AlertsPermissionScreen> createState() =>
      _AlertsPermissionScreenState();
}

class _AlertsPermissionScreenState
    extends ConsumerState<AlertsPermissionScreen> {
  var _busy = false;

  Future<void> _allow() async {
    setState(() => _busy = true);
    await Permission.notification.request();
    if (defaultTargetPlatform == TargetPlatform.android) {
      await Permission.ignoreBatteryOptimizations.request();
    }
    ref.invalidate(alertsReadyProvider);
    // Un refus ne bloque pas l'app : la question revient à la prochaine ouverture.
    ref.read(alertsPromptSkippedProvider.notifier).skip();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    Widget row(IconData icon, String title, String body) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: PCard(
        child: Row(
          children: [
            PIcon(icon),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  Text(body, style: t.bodySmall?.copyWith(color: P.muted)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    return Scaffold(
      backgroundColor: P.page,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(IviaSpacing.screen),
          children: [
            const PTitle('Ne manquez aucune ', 'alerte'),
            const SizedBox(height: 8),
            Text(
              'Un patient attend votre réponse : autorisez ivia Pharmacie à vous prévenir, même téléphone verrouillé.',
              style: t.bodyLarge?.copyWith(color: P.muted),
            ),
            const SizedBox(height: 20),
            row(
              Icons.notifications_active_outlined,
              'Alertes',
              'Pour recevoir les demandes des patients.',
            ),
            row(
              Icons.fullscreen,
              'Plein écran',
              'Pour que l\'alerte s\'affiche par-dessus l\'écran verrouillé.',
            ),
            row(
              Icons.battery_charging_full_outlined,
              'Arrière-plan',
              'Pour que le téléphone ne coupe pas l\'application.',
            ),
            const SizedBox(height: 12),
            PButton(label: 'Autoriser', busy: _busy, onTap: _allow),
            TextButton(
              onPressed: _busy
                  ? null
                  : ref.read(alertsPromptSkippedProvider.notifier).skip,
              child: const Text('Plus tard'),
            ),
          ],
        ),
      ),
    );
  }
}
