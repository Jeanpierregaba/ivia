import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_ui/ivia_ui.dart';

import 'app_identity.dart';
import 'auth_routes.dart';
import 'button_progress.dart';
import 'form_fields.dart';
import 'legal_text.dart';
import 'phone_format.dart';
import 'phone_login_flow.dart';

/// Écrans de la connexion par numéro (spec 001 v2, ADR 0012) : numéro, code
/// reçu par WhatsApp ou SMS, puis « Faisons connaissance » pour un numéro
/// nouveau. Communs aux apps qui choisissent [LoginMethod.phone].

/// Mise en page commune : défilement, marges, contenu étiré.
class _AuthPage extends StatelessWidget {
  const _AuthPage({required this.children, this.canPop = true, this.onBack});

  final List<Widget> children;
  final bool canPop;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) onBack?.call();
      },
      child: Scaffold(
        body: SafeArea(
          child: CustomScrollView(
            slivers: [
              SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: const EdgeInsets.all(IviaSpacing.screen),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: children,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Text(
      message,
      style: Theme.of(context).textTheme.bodyMedium
          ?.copyWith(color: IviaColors.error),
    ),
  );
}

/// Étape 1 : « Votre numéro ».
class PhoneScreen extends ConsumerStatefulWidget {
  const PhoneScreen({super.key});

  @override
  ConsumerState<PhoneScreen> createState() => _PhoneScreenState();
}

class _PhoneScreenState extends ConsumerState<PhoneScreen> {
  final _phone = TextEditingController();
  String? _error;
  OtpChannel? _sending;

  @override
  void initState() {
    super.initState();
    // Retour depuis le code (« Modifier ») : numéro conservé.
    _phone.text = formatTogoPhone(
      ref.read(phoneLoginFlowProvider)?.phone ?? '',
    );
  }

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _submit(OtpChannel channel) async {
    if (_sending != null) return;
    final digits = togoPhoneDigits(_phone.text);
    if (!isTogoMobile(digits)) {
      setState(
        () => _error = 'Numéro mobile togolais attendu : 8 chiffres commençant par 7 ou 9.',
      );
      return;
    }
    setState(() {
      _sending = channel;
      _error = null;
    });
    try {
      await ref
          .read(phoneLoginFlowProvider.notifier)
          .requestCode('+228$digits', channel: channel);
      if (mounted) context.go(AuthRoutes.code);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _sending = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final identity = ref.watch(appIdentityProvider);
    final busy = _sending != null;
    return _AuthPage(
      children: [
        if (identity.authHero case final hero?)
          hero(context)
        else ...[
          const SizedBox(height: IviaSpacing.huge),
          Wrap(
            spacing: IviaSpacing.md,
            runSpacing: IviaSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              IviaLogoTile(size: 76, color: identity.brand.accent),
              if (identity.loginBadge case final badge?)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: identity.brand.accentSoft,
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Text(
                    badge,
                    style: textTheme.labelLarge?.copyWith(
                      color: identity.brand.accent,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: IviaSpacing.xxl),
          Semantics(
            header: true,
            child: Text(identity.loginTitle, style: textTheme.headlineMedium),
          ),
          const SizedBox(height: IviaSpacing.sm),
          Text(
            identity.loginBody,
            style: textTheme.bodyLarge?.copyWith(
              color: IviaColors.textSecondary,
            ),
          ),
        ],
        const SizedBox(height: IviaSpacing.xxxl),
        TogoPhoneField(
          label: 'Numéro de téléphone',
          controller: _phone,
          enabled: !busy,
          errorText: _error,
        ),
        const SizedBox(height: IviaSpacing.xxl),
        FilledButton.icon(
          onPressed: busy ? null : () => _submit(OtpChannel.whatsapp),
          icon: _sending == OtpChannel.whatsapp
              ? const SizedBox.shrink()
              : const Icon(Icons.chat_outlined),
          label: _sending == OtpChannel.whatsapp
              ? const ButtonProgress()
              : const Text('Recevoir le code sur WhatsApp'),
        ),
        const SizedBox(height: IviaSpacing.md),
        OutlinedButton(
          onPressed: busy ? null : () => _submit(OtpChannel.sms),
          child: _sending == OtpChannel.sms
              ? const ButtonProgress()
              : const Text('Recevoir par SMS'),
        ),
        const SizedBox(height: IviaSpacing.lg),
        const IviaInfoCard(
          text:
              'Pas de mot de passe : un code à 6 chiffres vous est envoyé à '
              'chaque connexion. Ne le communiquez à personne.',
        ),
        const Spacer(),
        const SizedBox(height: IviaSpacing.xxl),
        LegalText(
          textAlign: TextAlign.center,
          style: textTheme.bodySmall?.copyWith(color: IviaColors.textSecondary),
          parts: const [
            LegalPart('En continuant, vous acceptez les '),
            LegalPart.link("Conditions d'utilisation"),
            LegalPart(' et la '),
            LegalPart.link('Politique de confidentialité'),
            LegalPart('.'),
          ],
        ),
      ],
    );
  }
}

/// Étape 2 : « Saisissez le code ».
class PhoneCodeScreen extends ConsumerStatefulWidget {
  const PhoneCodeScreen({super.key});

  @override
  ConsumerState<PhoneCodeScreen> createState() => _PhoneCodeScreenState();
}

class _PhoneCodeScreenState extends ConsumerState<PhoneCodeScreen> {
  final _code = TextEditingController();
  final _codeFocus = FocusNode();
  Timer? _timer;
  var _remaining = Duration.zero;
  var _attempt = 0;
  String? _error;
  var _busy = false;

  /// Dernière demande connue, gardée pendant la transition d'écran.
  PhoneLoginState? _flow;

  @override
  void initState() {
    super.initState();
    _code.addListener(_onCodeChanged);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  void _onCodeChanged() {
    if (!mounted) return;
    setState(() {});
    // 6e chiffre saisi ou collé : vérification sans appui supplémentaire.
    if (_code.text.length == 6) unawaited(_verify());
  }

  void _syncCountdown(PhoneLoginState flow) {
    if (flow.attempt == _attempt) return;
    _attempt = flow.attempt;
    if (flow.devCode case final code?) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _code.text = code;
      });
    }
    _remaining = flow.resendAfter;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() => _remaining -= const Duration(seconds: 1));
      if (_remaining <= Duration.zero) timer.cancel();
    });
  }

  Future<void> _verify() async {
    if (_busy || _code.text.length != 6) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final needsSignup = await ref
          .read(phoneLoginFlowProvider.notifier)
          .verify(_code.text);
      // Numéro connu : la session ouverte fait changer d'écran.
      if (needsSignup && mounted) context.go(AuthRoutes.signup);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
      if (!e.isNetwork) {
        _code.clear();
        _codeFocus.requestFocus();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend(PhoneLoginState flow, OtpChannel channel) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(phoneLoginFlowProvider.notifier)
          .requestCode(flow.phone, channel: channel);
      if (!mounted) return;
      _code.clear();
      final sent = ref.read(phoneLoginFlowProvider)?.channel ?? channel;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              sent == OtpChannel.sms
                  ? 'Nouveau code envoyé par SMS.'
                  : 'Nouveau code envoyé sur WhatsApp.',
            ),
          ),
        );
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _changePhone() =>
      context.canPop() ? context.pop() : context.go(AuthRoutes.login);

  @override
  Widget build(BuildContext context) {
    final flow = _flow = ref.watch(phoneLoginFlowProvider) ?? _flow;
    if (flow == null) return const Scaffold(body: SizedBox.shrink());
    _syncCountdown(flow);
    final textTheme = Theme.of(context).textTheme;
    final viaSms = flow.channel == OtpChannel.sms;
    final strong = const TextStyle(
      color: IviaColors.text,
      fontWeight: FontWeight.w700,
    );
    return _AuthPage(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: IviaBackButton(onPressed: _busy ? null : _changePhone),
        ),
        const SizedBox(height: IviaSpacing.xxl),
        Semantics(
          header: true,
          child: Text('Saisissez le code', style: textTheme.headlineMedium),
        ),
        const SizedBox(height: IviaSpacing.sm),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: viaSms
                    ? 'Code à 6 chiffres envoyé par SMS au '
                    : 'Code à 6 chiffres envoyé sur WhatsApp au ',
              ),
              TextSpan(
                text: '+228 ${formatTogoPhone(flow.phone)}',
                style: strong,
              ),
              const TextSpan(text: '.'),
            ],
          ),
          style: textTheme.bodyLarge?.copyWith(color: IviaColors.textSecondary),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: _busy ? null : _changePhone,
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(48, 40),
            ),
            child: const Text('Modifier le numéro'),
          ),
        ),
        const SizedBox(height: IviaSpacing.lg),
        IviaCodeInput(
          controller: _code,
          focusNode: _codeFocus,
          autofocus: true,
          enabled: !_busy,
          hasError: _error != null,
        ),
        if (_error != null) ...[
          const SizedBox(height: IviaSpacing.sm),
          _ErrorText(_error!),
        ],
        const SizedBox(height: IviaSpacing.lg),
        if (_remaining > Duration.zero)
          Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: 'Renvoyer le code dans '),
                TextSpan(
                  text:
                      '${_remaining.inSeconds ~/ 60}:'
                      '${(_remaining.inSeconds % 60).toString().padLeft(2, '0')}',
                  style: strong,
                ),
              ],
            ),
            style: textTheme.bodyMedium?.copyWith(
              color: IviaColors.textSecondary,
            ),
          )
        else
          Wrap(
            spacing: IviaSpacing.lg,
            children: [
              TextButton(
                onPressed: _busy ? null : () => _resend(flow, flow.channel),
                style: TextButton.styleFrom(padding: EdgeInsets.zero),
                child: const Text('Renvoyer le code'),
              ),
              if (!viaSms)
                TextButton(
                  onPressed: _busy ? null : () => _resend(flow, OtpChannel.sms),
                  style: TextButton.styleFrom(padding: EdgeInsets.zero),
                  child: const Text('Recevoir par SMS'),
                ),
            ],
          ),
        const SizedBox(height: IviaSpacing.lg),
        IviaInfoCard(
          text: viaSms
              ? 'Le code est valable ${flow.expiresIn.inMinutes} minutes. '
                    'WhatsApp n\'a pas pu le recevoir : il est parti par SMS.'
              : 'Le code est valable ${flow.expiresIn.inMinutes} minutes. '
                    'Rien reçu ? Vérifiez WhatsApp, ou demandez-le par SMS.',
        ),
        const Spacer(),
        const SizedBox(height: IviaSpacing.xxl),
        FilledButton(
          onPressed: _busy || _code.text.length != 6 ? null : _verify,
          child: _busy
              ? const ButtonProgress(label: 'Vérification')
              : const Text('Vérifier le code'),
        ),
      ],
    );
  }
}

/// Étape 3 : « Faisons connaissance » (numéro nouveau). Le compte n'existe
/// qu'après cet écran.
class PhoneSignupScreen extends ConsumerStatefulWidget {
  const PhoneSignupScreen({super.key});

  @override
  ConsumerState<PhoneSignupScreen> createState() => _PhoneSignupScreenState();
}

class _PhoneSignupScreenState extends ConsumerState<PhoneSignupScreen> {
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  var _consent = false;
  var _errors = <String, String>{};
  String? _generalError;
  var _busy = false;

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    super.dispose();
  }

  Map<String, String> _validate() {
    final errors = <String, String>{};
    final first = _firstName.text.trim();
    final last = _lastName.text.trim();
    if (first.isEmpty) errors['first_name'] = 'Saisissez votre prénom.';
    if (first.length > 100) errors['first_name'] = '100 caractères au plus.';
    if (last.isEmpty) errors['last_name'] = 'Saisissez votre nom.';
    if (last.length > 100) errors['last_name'] = '100 caractères au plus.';
    if (!_consent) {
      errors['accept_privacy_policy'] =
          'Cochez la case pour continuer : votre accord est nécessaire.';
    }
    return errors;
  }

  Future<void> _submit() async {
    if (_busy) return;
    final errors = _validate();
    setState(() {
      _errors = errors;
      _generalError = null;
    });
    if (errors.isNotEmpty) return;
    setState(() => _busy = true);
    try {
      // Succès : la session ouverte fait changer d'écran.
      await ref
          .read(phoneLoginFlowProvider.notifier)
          .signup(
            firstName: _firstName.text.trim(),
            lastName: _lastName.text.trim(),
          );
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'signup_expired') {
        _restart(message: e.message);
        return;
      }
      setState(() {
        if (e.fields.isNotEmpty) {
          _errors = e.fields;
        } else {
          _generalError = e.message;
        }
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _restart({String? message}) {
    ref.read(phoneLoginFlowProvider.notifier).reset();
    if (message != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
    context.go(AuthRoutes.login);
  }

  @override
  Widget build(BuildContext context) {
    final flow = ref.watch(phoneLoginFlowProvider);
    if (flow?.signup == null && !_busy) {
      // Ouvert sans code vérifié (lien direct) : retour au numéro.
      return const Scaffold(body: SizedBox.shrink());
    }
    final textTheme = Theme.of(context).textTheme;
    Widget field(
      String key,
      String label,
      TextEditingController c,
      Iterable<String> hints,
    ) => IviaFieldLabel(
      label: label,
      child: TextField(
        controller: c,
        enabled: !_busy,
        textCapitalization: TextCapitalization.words,
        autofillHints: hints,
        textInputAction: TextInputAction.next,
        decoration: InputDecoration(errorText: _errors[key], errorMaxLines: 2),
      ),
    );
    return _AuthPage(
      canPop: false,
      onBack: _busy ? null : _restart,
      children: [
        Row(
          children: [
            IviaBackButton(onPressed: _busy ? null : _restart),
            const Spacer(),
            const IviaPill(label: 'Dernière étape'),
          ],
        ),
        const SizedBox(height: IviaSpacing.lg),
        Semantics(
          header: true,
          child: Text('Faisons connaissance', style: textTheme.headlineMedium),
        ),
        const SizedBox(height: IviaSpacing.sm),
        Text(
          'Votre numéro est confirmé. Comment vous appelez-vous ?',
          style: textTheme.bodyLarge?.copyWith(color: IviaColors.textSecondary),
        ),
        const SizedBox(height: IviaSpacing.xxl),
        field('first_name', 'Prénom', _firstName, const [
          AutofillHints.givenName,
        ]),
        const SizedBox(height: IviaSpacing.lg),
        field('last_name', 'Nom', _lastName, const [AutofillHints.familyName]),
        const SizedBox(height: IviaSpacing.xl),
        ConsentCheckbox(
          value: _consent,
          error: _errors['accept_privacy_policy'],
          onChanged: _busy ? null : (v) => setState(() => _consent = v),
        ),
        const Spacer(),
        const SizedBox(height: IviaSpacing.xxl),
        if (_generalError != null) ...[
          _ErrorText(_generalError!),
          const SizedBox(height: IviaSpacing.md),
        ],
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const ButtonProgress()
              : const Text('Créer mon compte'),
        ),
      ],
    );
  }
}
