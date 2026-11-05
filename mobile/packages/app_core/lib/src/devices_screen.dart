import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_ui/ivia_ui.dart';

import 'auth_controller.dart';
import 'providers.dart';

/// Sessions actives du compte (`GET /v1/me/sessions`), relues à chaque
/// ouverture de l'écran.
final connectedDevicesProvider = FutureProvider.autoDispose<List<SessionView>>(
  (ref) => ref.read(apiClientProvider).sessions(),
);

/// « Appareils connectés » : chaque appareil où le compte est ouvert, avec
/// « Déconnecter », et la déconnexion de tous les appareils (spec 001 v2).
class ConnectedDevicesScreen extends ConsumerStatefulWidget {
  const ConnectedDevicesScreen({super.key});

  @override
  ConsumerState<ConnectedDevicesScreen> createState() =>
      _ConnectedDevicesScreenState();
}

class _ConnectedDevicesScreenState
    extends ConsumerState<ConnectedDevicesScreen> {
  String? _busy;

  void _message(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  Future<void> _revoke(SessionView s) async {
    setState(() => _busy = s.id);
    try {
      await ref.read(apiClientProvider).revokeSession(s.id);
      ref.invalidate(connectedDevicesProvider);
      final name = s.deviceName.isEmpty ? 'Appareil' : s.deviceName;
      if (mounted) _message('$name déconnecté.');
    } on ApiException catch (e) {
      if (mounted) _message(e.message);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _revokeAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Se déconnecter partout ?'),
        content: const Text(
          'Votre compte sera fermé sur tous vos appareils, celui-ci compris. '
          'Vous vous reconnecterez avec un code.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Tout déconnecter'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = 'all');
    try {
      await ref.read(apiClientProvider).logoutAll();
    } on ApiException catch (e) {
      if (mounted) {
        _message(e.message);
        setState(() => _busy = null);
      }
      return;
    }
    if (mounted) Navigator.of(context).pop();
    // Session révoquée côté serveur : effacée du téléphone.
    await ref.read(authControllerProvider.notifier).signOut();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final devices = ref.watch(connectedDevicesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Appareils connectés')),
      body: SafeArea(
        child: devices.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(IviaSpacing.screen),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    e is ApiException ? e.message : 'Liste indisponible.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: IviaSpacing.lg),
                  OutlinedButton(
                    onPressed: () => ref.invalidate(connectedDevicesProvider),
                    child: const Text('Réessayer'),
                  ),
                ],
              ),
            ),
          ),
          data: (items) => ListView(
            padding: const EdgeInsets.all(IviaSpacing.screen),
            children: [
              Text(
                'Si un appareil ne vous dit rien, déconnectez-le : il devra '
                'recevoir un nouveau code pour rouvrir votre compte.',
                style: textTheme.bodyMedium?.copyWith(
                  color: IviaColors.textSecondary,
                ),
              ),
              const SizedBox(height: IviaSpacing.lg),
              for (final s in items)
                Card(
                  margin: const EdgeInsets.only(bottom: IviaSpacing.md),
                  child: ListTile(
                    leading: Icon(
                      s.current ? Icons.smartphone : Icons.devices_other,
                    ),
                    title: Text(
                      s.deviceName.isEmpty ? 'Appareil' : s.deviceName,
                    ),
                    subtitle: Text(
                      s.current
                          ? 'Cet appareil'
                          : 'Dernière activité : ${_when(s.lastUsedAt)}',
                    ),
                    trailing: s.current
                        ? null
                        : TextButton(
                            onPressed: _busy == null ? () => _revoke(s) : null,
                            child: _busy == s.id
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('Déconnecter'),
                          ),
                  ),
                ),
              const SizedBox(height: IviaSpacing.lg),
              OutlinedButton(
                onPressed: _busy == null ? _revokeAll : null,
                child: const Text('Se déconnecter de tous les appareils'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _when(DateTime at) {
    final d = DateTime.now().difference(at);
    if (d.inMinutes < 2) return "à l'instant";
    if (d.inHours < 1) return 'il y a ${d.inMinutes} min';
    if (d.inDays < 1) return 'il y a ${d.inHours} h';
    return 'il y a ${d.inDays} j';
  }
}
