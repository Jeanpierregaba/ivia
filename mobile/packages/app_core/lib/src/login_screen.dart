import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_ui/ivia_ui.dart';

import 'app_identity.dart';
import 'auth_controller.dart';
import 'auth_draft.dart';
import 'auth_page.dart';
import 'auth_routes.dart';
import 'button_progress.dart';
import 'google_auth.dart';
import 'legal_text.dart';
import 'password_field.dart';
import 'providers.dart';

/// Modes de connexion ouverts par le serveur ; `null` si la lecture échoue
/// (le bouton Google est alors masqué). Relu à chaque ouverture de l'écran :
/// un échec hors ligne n'est pas gardé.
final authProvidersProvider = FutureProvider.autoDispose<AuthProviders?>((
  ref,
) async {
  try {
    return await ref.watch(apiClientProvider).authProviders();
  } on Exception {
    return null;
  }
});

/// « Bienvenue sur ivia » : Google si disponible, e-mail et mot de passe,
/// « Mot de passe oublié ? », « Créer un compte » (ADR 0011).
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  late final _email = TextEditingController(
    text: ref.read(authEmailDraftProvider),
  );
  final _password = TextEditingController();
  String? _emailError;
  String? _error;

  /// Après `invalid_credentials` : un compte de l'ancienne connexion par
  /// code n'a pas encore de mot de passe.
  var _codeHelp = false;
  var _locked = false;
  var _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  /// Adresse reprise par l'écran suivant (création, mot de passe oublié).
  void _go(String location) {
    ref.read(authEmailDraftProvider.notifier).set(_email.text);
    // L'écran reste dessous : le mot de passe n'y est pas gardé.
    _password.clear();
    context.go(location);
  }

  Future<void> _login() async {
    if (_busy) return;
    final email = _email.text.trim();
    if (!isPlausibleEmail(email)) {
      setState(() => _emailError = 'Saisissez une adresse e-mail valide.');
      return;
    }
    if (_password.text.isEmpty) {
      setState(() {
        _emailError = null;
        _error = 'Saisissez votre mot de passe.';
      });
      return;
    }
    setState(() {
      _busy = true;
      _emailError = null;
      _error = null;
      _codeHelp = false;
      _locked = false;
    });
    final auth = ref.read(authControllerProvider.notifier);
    try {
      final session = await ref
          .read(apiClientProvider)
          .login(email, _password.text);
      _password.clear();
      // La session ouverte fait changer d'écran.
      await auth.signedIn(session);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        if (e.code == 'invalid_credentials') {
          _password.clear();
          _codeHelp = true;
        }
        _locked = e.code == 'account_locked';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _google() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final auth = ref.read(authControllerProvider.notifier);
    try {
      final token = await ref.read(googleAuthProvider).signIn();
      // Fenêtre fermée par l'utilisateur : rien à dire.
      if (token == null) return;
      final session = await ref.read(apiClientProvider).signInWithGoogle(token);
      await auth.signedIn(session);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on GoogleAuthException {
      if (mounted) {
        setState(() => _error = 'Connexion avec Google impossible. Réessayez.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final identity = ref.watch(appIdentityProvider);
    // Adresse reprise d'un autre écran (« Se connecter » après
    // « Un compte existe déjà ») : l'écran de connexion reste ouvert dessous.
    ref.listen(authEmailDraftProvider, (_, next) {
      if (next.isNotEmpty && _email.text != next) _email.text = next;
    });
    final google =
        ref.watch(googleAuthProvider).available &&
        (ref.watch(authProvidersProvider).value?.google ?? false);
    final forgot = TextButton(
      onPressed: _busy ? null : () => _go(AuthRoutes.forgot),
      style: TextButton.styleFrom(
        padding: EdgeInsets.zero,
        minimumSize: const Size(48, 40),
      ),
      // Compte bloqué : le lien mis en avant.
      child: Text(
        'Mot de passe oublié ?',
        style: _locked ? const TextStyle(fontWeight: FontWeight.w800) : null,
      ),
    );
    return AutofillGroup(
      child: AuthPage(
        title: identity.loginTitle,
        intro: Text(identity.loginBody),
        header: Padding(
          padding: const EdgeInsets.only(
            top: IviaSpacing.xxl,
            bottom: IviaSpacing.xxl,
          ),
          child: Wrap(
            spacing: IviaSpacing.md,
            runSpacing: IviaSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              IviaLogoTile(size: 76, color: identity.brand.accent),
              if (identity.loginBadge case final badge?)
                _Badge(label: badge, color: identity.brand.accent),
            ],
          ),
        ),
        footer: [
          LegalText(
            textAlign: TextAlign.center,
            style: textTheme.bodySmall?.copyWith(
              color: IviaColors.textSecondary,
            ),
            parts: const [
              LegalPart('En continuant, vous acceptez les '),
              LegalPart.link("Conditions d'utilisation"),
              LegalPart(' et la '),
              LegalPart.link('Politique de confidentialité'),
              LegalPart('.'),
            ],
          ),
        ],
        children: [
          if (google) ...[
            OutlinedButton.icon(
              onPressed: _busy ? null : _google,
              icon: const Icon(Icons.g_mobiledata, size: 28),
              label: const Text('Continuer avec Google'),
            ),
            const SizedBox(height: IviaSpacing.lg),
            const _OrDivider(),
            const SizedBox(height: IviaSpacing.lg),
          ],
          EmailField(
            controller: _email,
            enabled: !_busy,
            errorText: _emailError,
          ),
          const SizedBox(height: IviaSpacing.lg),
          PasswordField(
            controller: _password,
            enabled: !_busy,
            onSubmitted: (_) => _login(),
          ),
          Align(alignment: Alignment.centerRight, child: forgot),
          if (_error case final error?) ...[
            const SizedBox(height: IviaSpacing.sm),
            AuthError(error),
          ],
          if (_codeHelp) ...[
            const SizedBox(height: IviaSpacing.md),
            IviaInfoCard(
              text:
                  'Vous vous connectiez avec un code reçu par e-mail ? '
                  'Créez votre mot de passe.',
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _busy ? null : () => _go(AuthRoutes.emailSignup),
                child: const Text('Créer mon mot de passe'),
              ),
            ),
          ],
          const SizedBox(height: IviaSpacing.xl),
          FilledButton(
            onPressed: _busy ? null : _login,
            child: _busy
                ? const ButtonProgress(label: 'Connexion')
                : const Text('Se connecter'),
          ),
          const SizedBox(height: IviaSpacing.lg),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Pas encore de compte ?', style: textTheme.bodyMedium),
              TextButton(
                onPressed: _busy ? null : () => _go(AuthRoutes.emailSignup),
                child: const Text('Créer un compte'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Expanded(child: Divider()),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: IviaSpacing.md),
        child: Text('ou', style: Theme.of(context).textTheme.bodySmall),
      ),
      const Expanded(child: Divider()),
    ],
  );
}

/// Pastille pleine à côté du logo (« Marchand »).
class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: IviaSpacing.lg,
      vertical: IviaSpacing.sm,
    ),
    decoration: ShapeDecoration(color: color, shape: const StadiumBorder()),
    child: Text(
      label,
      style: Theme.of(context).textTheme.labelLarge
          ?.copyWith(color: Colors.white),
    ),
  );
}
