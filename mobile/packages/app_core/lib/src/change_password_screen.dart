import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_ui/ivia_ui.dart';

import 'auth_page.dart';
import 'button_progress.dart';
import 'messages.dart';
import 'password_field.dart';
import 'providers.dart';

/// Le compte a-t-il déjà un mot de passe (un compte créé avec Google n'en a
/// pas) ; `null` si la lecture échoue (le champ « actuel » est alors
/// affiché, le serveur tranche).
final hasPasswordProvider = FutureProvider.autoDispose<bool?>((ref) async {
  try {
    return (await ref.watch(apiClientProvider).sessionInfo()).hasPassword;
  } on Exception {
    return null;
  }
});

/// « Mot de passe » de l'écran Compte : actuel (si le compte en a un),
/// nouveau ; les autres appareils sont déconnectés.
class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() =>
      _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  String? _currentError;
  String? _nextError;
  String? _general;
  var _busy = false;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    super.dispose();
  }

  Future<void> _submit(bool askCurrent) async {
    if (_busy) return;
    setState(() {
      _currentError = askCurrent && _current.text.isEmpty
          ? 'Saisissez votre mot de passe actuel.'
          : null;
      _nextError = _next.text.isEmpty ? 'Choisissez un mot de passe.' : null;
      _general = null;
    });
    if (_currentError != null || _nextError != null) return;
    setState(() => _busy = true);
    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(apiClientProvider)
          .changePassword(
            current: askCurrent ? _current.text : null,
            next: _next.text,
          );
      _current.clear();
      _next.clear();
      showMessage(
        messenger,
        'Mot de passe changé. Vos autres appareils sont déconnectés.',
      );
      if (router.canPop()) router.pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        // Erreur sur l'actuel alors que le champ n'est pas affiché : message
        // général.
        _currentError = askCurrent ? e.fields['current_password'] : null;
        _nextError = e.fields['new_password'] ?? e.fields['password'];
        if (_currentError == null && _nextError == null) {
          _general = e.fields['current_password'] ?? e.message;
        }
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasPassword = ref.watch(hasPasswordProvider);
    if (hasPassword.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    // Lecture en échec : champ affiché (le serveur tranche).
    final askCurrent = hasPassword.value ?? true;
    return AutofillGroup(
      child: AuthPage(
        title: askCurrent
            ? 'Changer le mot de passe'
            : 'Choisir un mot de passe',
        intro: Text(
          askCurrent
              ? 'Vos autres appareils seront déconnectés.'
              : 'Votre compte a été créé avec Google : ajoutez un mot de '
                    'passe pour vous connecter aussi avec votre e-mail.',
        ),
        onBack: () => context.pop(),
        backEnabled: !_busy,
        footer: [
          FilledButton(
            onPressed: _busy ? null : () => _submit(askCurrent),
            child: _busy ? const ButtonProgress() : const Text('Enregistrer'),
          ),
        ],
        children: [
          if (askCurrent) ...[
            PasswordField(
              controller: _current,
              label: 'Mot de passe actuel',
              enabled: !_busy,
              errorText: _currentError,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: IviaSpacing.lg),
          ],
          PasswordField(
            controller: _next,
            label: 'Nouveau mot de passe',
            newPassword: true,
            enabled: !_busy,
            errorText: _nextError,
            helperText:
                '10 caractères au moins. Évitez un mot de passe courant ou '
                'proche de votre e-mail.',
            onSubmitted: (_) => _submit(askCurrent),
          ),
          if (_general case final general?) ...[
            const SizedBox(height: IviaSpacing.md),
            AuthError(general),
          ],
        ],
      ),
    );
  }
}
