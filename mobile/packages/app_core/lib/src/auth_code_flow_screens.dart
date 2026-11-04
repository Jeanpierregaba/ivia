import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_ui/ivia_ui.dart';

import 'app_identity.dart';
import 'auth_draft.dart';
import 'auth_flow.dart';
import 'auth_page.dart';
import 'auth_routes.dart';
import 'button_progress.dart';
import 'password_field.dart';

/// Chemins d'un parcours avec code.
extension on CodePurpose {
  String get codeRoute => switch (this) {
    CodePurpose.signup => AuthRoutes.signupCode,
    CodePurpose.reset => AuthRoutes.forgotCode,
  };

  String get passwordRoute => switch (this) {
    CodePurpose.signup => AuthRoutes.signupPassword,
    CodePurpose.reset => AuthRoutes.forgotPassword,
  };

  String get emailRoute => switch (this) {
    CodePurpose.signup => AuthRoutes.signup,
    CodePurpose.reset => AuthRoutes.forgot,
  };
}

/// Retour à la connexion : parcours abandonné, adresse gardée.
void _backToLogin(BuildContext context, WidgetRef ref) {
  ref.read(authFlowProvider.notifier).clear();
  context.go(AuthRoutes.login);
}

/// Étape 1 : adresse e-mail, envoi du code (création de compte ou mot de
/// passe oublié).
class AuthEmailScreen extends ConsumerStatefulWidget {
  const AuthEmailScreen({super.key, required this.purpose});

  final CodePurpose purpose;

  @override
  ConsumerState<AuthEmailScreen> createState() => _AuthEmailScreenState();
}

class _AuthEmailScreenState extends ConsumerState<AuthEmailScreen> {
  late final _email = TextEditingController(text: _initialEmail());

  /// Adresse du parcours en cours s'il est du même usage, sinon celle saisie
  /// sur la connexion.
  String _initialEmail() {
    final flow = ref.read(authFlowProvider);
    return flow != null && flow.purpose == widget.purpose
        ? flow.email
        : ref.read(authEmailDraftProvider);
  }

  String? _error;
  var _busy = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final email = _email.text.trim();
    if (!isPlausibleEmail(email)) {
      setState(() => _error = 'Saisissez une adresse e-mail valide.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final router = GoRouter.of(context);
    try {
      ref.read(authEmailDraftProvider.notifier).set(email);
      await ref
          .read(authFlowProvider.notifier)
          .requestCode(widget.purpose, email);
      router.go(widget.purpose.codeRoute);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _error = e.fields['recipient'] ?? e.message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final signup = widget.purpose == CodePurpose.signup;
    return AuthPage(
      title: signup ? 'Créer un compte' : 'Mot de passe oublié',
      intro: Text(
        signup
            ? 'Nous vous envoyons un code à 6 chiffres pour vérifier votre '
                  'adresse, puis vous choisirez votre mot de passe.'
            : 'Nous vous envoyons un code à 6 chiffres pour choisir un '
                  'nouveau mot de passe.',
      ),
      onBack: () => _backToLogin(context, ref),
      backEnabled: !_busy,
      footer: [
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const ButtonProgress()
              : const Text('Recevoir le code'),
        ),
      ],
      children: [
        EmailField(
          controller: _email,
          enabled: !_busy,
          errorText: _error,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
        ),
      ],
    );
  }
}

/// Étape 2 : « Vérifiez vos e-mails », 6 cases, renvoi. Le code est
/// vérifié par le serveur avec le mot de passe, à l'étape 3.
class AuthCodeScreen extends ConsumerStatefulWidget {
  const AuthCodeScreen({super.key, required this.purpose});

  final CodePurpose purpose;

  @override
  ConsumerState<AuthCodeScreen> createState() => _AuthCodeScreenState();
}

class _AuthCodeScreenState extends ConsumerState<AuthCodeScreen> {
  final _code = TextEditingController();
  final _codeFocus = FocusNode();
  Timer? _timer;
  var _remaining = Duration.zero;
  var _attempt = 0;
  String? _error;
  var _busy = false;

  @override
  void initState() {
    super.initState();
    _code.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  /// Compte à rebours relancé à chaque nouvelle demande de code.
  void _syncCountdown(AuthFlowState flow) {
    if (flow.attempt == _attempt) return;
    _attempt = flow.attempt;
    // Développement : code de l'API locale saisi tout seul, une fois par
    // envoi (un retour sur les 6 cases laisse voir le message du code).
    if (flow.devCode case final code?) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(authFlowProvider.notifier).devCodeUsed();
        _code.text = code;
        _continue();
      });
    }
    // Temps restant depuis l'envoi : ne repart pas à chaque retour ici.
    final left = flow.resendAfter - DateTime.now().difference(flow.sentAt);
    // Arrondi à la seconde supérieure : « 1:00 » juste après l'envoi.
    _remaining = left.isNegative
        ? Duration.zero
        : Duration(seconds: (left.inMilliseconds / 1000).ceil());
    _timer?.cancel();
    if (_remaining <= Duration.zero) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() => _remaining -= const Duration(seconds: 1));
      if (_remaining <= Duration.zero) timer.cancel();
    });
  }

  void _continue() {
    if (_busy || _code.text.length != 6) return;
    ref.read(authFlowProvider.notifier).codeEntered(_code.text);
    _code.clear();
    context.go(widget.purpose.passwordRoute);
  }

  Future<void> _resend(String email) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(authFlowProvider.notifier)
          .requestCode(widget.purpose, email);
      _code.clear();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Nouveau code envoyé.')));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final flow = ref.watch(authFlowProvider);
    if (flow == null || flow.purpose != widget.purpose) {
      // Ouvert sans demande de code (lien direct, parcours fini).
      return const Scaffold(body: SizedBox.shrink());
    }
    _syncCountdown(flow);
    final error = _error ?? flow.codeError;
    return AuthPage(
      title: 'Vérifiez vos e-mails',
      intro: Text.rich(
        TextSpan(
          children: [
            const TextSpan(text: 'Nous avons envoyé un code à 6 chiffres à '),
            TextSpan(
              text: flow.email,
              style: const TextStyle(
                color: IviaColors.text,
                fontWeight: FontWeight.w700,
              ),
            ),
            const TextSpan(text: '.'),
          ],
        ),
      ),
      onBack: () => context.go(widget.purpose.emailRoute),
      backEnabled: !_busy,
      footer: [
        FilledButton(
          onPressed: _busy || _code.text.length != 6 ? null : _continue,
          child: _busy ? const ButtonProgress() : const Text('Continuer'),
        ),
      ],
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: _busy
                ? null
                : () => context.go(widget.purpose.emailRoute),
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(48, 40),
            ),
            child: const Text("Modifier l'adresse"),
          ),
        ),
        const SizedBox(height: IviaSpacing.md),
        IviaCodeInput(
          controller: _code,
          focusNode: _codeFocus,
          autofocus: true,
          enabled: !_busy,
          hasError: error != null,
          onCompleted: (_) => _continue(),
        ),
        if (error != null) ...[
          const SizedBox(height: IviaSpacing.sm),
          AuthError(error),
        ],
        const SizedBox(height: IviaSpacing.lg),
        _ResendRow(
          remaining: _remaining,
          onResend: _busy ? null : () => _resend(flow.email),
        ),
        const SizedBox(height: IviaSpacing.lg),
        IviaInfoCard(
          text: ref.watch(appIdentityProvider).codeHint(flow.expiresIn),
        ),
      ],
    );
  }
}

/// Étape 3 : mot de passe (création) ou nouveau mot de passe (oublié),
/// envoyé avec le code ; la session ouverte fait changer d'écran.
class NewPasswordScreen extends ConsumerStatefulWidget {
  const NewPasswordScreen({super.key, required this.purpose});

  final CodePurpose purpose;

  @override
  ConsumerState<NewPasswordScreen> createState() => _NewPasswordScreenState();
}

class _NewPasswordScreenState extends ConsumerState<NewPasswordScreen> {
  final _password = TextEditingController();
  AuthFlowState? _last;
  String? _error;
  String? _general;
  var _accountExists = false;
  var _busy = false;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (_password.text.isEmpty) {
      setState(() => _error = 'Choisissez un mot de passe.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _general = null;
      _accountExists = false;
    });
    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(authFlowProvider.notifier).submitPassword(_password.text);
      _password.clear();
      if (widget.purpose == CodePurpose.reset) {
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('Mot de passe changé.')));
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      if (codeErrors.contains(e.code)) {
        // Code refusé : retour aux 6 cases, message affiché là-bas.
        _password.clear();
        router.go(widget.purpose.codeRoute);
        return;
      }
      setState(() {
        if (e.fields['password'] case final field?) {
          _error = field;
        } else {
          _general = e.message;
        }
        _accountExists = e.code == 'account_exists';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Parcours oublié à l'ouverture de la session : l'écran garde son
    // contenu pendant la transition.
    final current = ref.watch(authFlowProvider);
    if (current != null && current.code != null) _last = current;
    final flow = _last;
    if (flow == null || flow.purpose != widget.purpose) {
      // Sans code saisi (lien direct).
      return const Scaffold(body: SizedBox.shrink());
    }
    final signup = widget.purpose == CodePurpose.signup;
    return AutofillGroup(
      child: AuthPage(
        title: signup ? 'Choisissez un mot de passe' : 'Nouveau mot de passe',
        intro: Text('Pour le compte ${flow.email}.'),
        onBack: () => context.go(widget.purpose.codeRoute),
        backEnabled: !_busy,
        footer: [
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const ButtonProgress()
                : Text(signup ? 'Créer mon compte' : 'Changer le mot de passe'),
          ),
        ],
        children: [
          PasswordField(
            controller: _password,
            label: signup ? 'Mot de passe' : 'Nouveau mot de passe',
            newPassword: true,
            autofocus: true,
            enabled: !_busy,
            errorText: _error,
            helperText:
                '10 caractères au moins. Évitez un mot de passe courant ou '
                'proche de votre e-mail.',
            onSubmitted: (_) => _submit(),
          ),
          if (_general case final general?) ...[
            const SizedBox(height: IviaSpacing.md),
            AuthError(general),
          ],
          if (_accountExists)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => _backToLogin(context, ref),
                child: const Text('Se connecter'),
              ),
            ),
        ],
      ),
    );
  }
}

class _ResendRow extends StatelessWidget {
  const _ResendRow({required this.remaining, required this.onResend});

  final Duration remaining;
  final VoidCallback? onResend;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium
        ?.copyWith(color: IviaColors.textSecondary);
    if (remaining > Duration.zero) {
      final seconds = remaining.inSeconds;
      final time =
          '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
      return Text.rich(
        TextSpan(
          children: [
            const TextSpan(text: 'Renvoyer le code dans '),
            TextSpan(
              text: time,
              style: const TextStyle(
                color: IviaColors.text,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        style: style,
      );
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton(
        onPressed: onResend,
        style: TextButton.styleFrom(padding: EdgeInsets.zero),
        child: const Text('Renvoyer le code'),
      ),
    );
  }
}
