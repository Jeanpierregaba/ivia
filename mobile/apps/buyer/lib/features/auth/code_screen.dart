import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../app/router.dart';
import 'button_progress.dart';
import 'login_flow.dart';

/// « Vérifiez vos e-mails » : saisie du code à 6 chiffres, renvoi.
class CodeScreen extends ConsumerStatefulWidget {
  const CodeScreen({super.key});

  @override
  ConsumerState<CodeScreen> createState() => _CodeScreenState();
}

class _CodeScreenState extends ConsumerState<CodeScreen> {
  final _code = TextEditingController();
  final _codeFocus = FocusNode();
  Timer? _timer;
  var _remaining = Duration.zero;
  var _attempt = 0;
  String? _error;
  var _busy = false;

  /// Dernière demande connue : gardée pendant la transition vers l'écran
  /// suivant, une fois le code validé.
  LoginFlowState? _flow;

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
    // Le bouton « Vérifier le code » suit le nombre de chiffres saisis.
    if (mounted) setState(() {});
  }

  /// Compte à rebours relancé à chaque nouvelle demande de code.
  void _syncCountdown(LoginFlowState flow) {
    if (flow.attempt == _attempt) return;
    _attempt = flow.attempt;
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
      // Succès : la session ouverte fait changer d'écran.
      await ref.read(loginFlowProvider.notifier).verify(_code.text);
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

  Future<void> _resend(String email) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(loginFlowProvider.notifier).requestCode(email);
      if (!mounted) return;
      _code.clear();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Nouveau code envoyé.')));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _changeEmail() =>
      context.canPop() ? context.pop() : context.go(Routes.login);

  @override
  Widget build(BuildContext context) {
    final flow = _flow = ref.watch(loginFlowProvider) ?? _flow;
    if (flow == null) {
      // Ouvert sans demande de code (code déjà validé, lien direct).
      return const Scaffold(body: SizedBox.shrink());
    }
    _syncCountdown(flow);
    final textTheme = Theme.of(context).textTheme;
    final minutes = flow.expiresIn.inMinutes;
    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.all(IviaSpacing.screen),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: IviaBackButton(onPressed: _changeEmail),
                    ),
                    const SizedBox(height: IviaSpacing.xxl),
                    Semantics(
                      header: true,
                      child: Text(
                        'Vérifiez vos e-mails',
                        style: textTheme.headlineMedium,
                      ),
                    ),
                    const SizedBox(height: IviaSpacing.sm),
                    Text.rich(
                      TextSpan(
                        children: [
                          const TextSpan(
                            text: 'Nous avons envoyé un code à 6 chiffres à ',
                          ),
                          TextSpan(
                            text: flow.email,
                            style: const TextStyle(
                              color: IviaColors.text,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const TextSpan(text: '. '),
                        ],
                      ),
                      style: textTheme.bodyLarge?.copyWith(
                        color: IviaColors.textSecondary,
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: _busy ? null : _changeEmail,
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(48, 40),
                        ),
                        child: const Text("Modifier l'adresse"),
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
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          _error!,
                          style: textTheme.bodyMedium?.copyWith(
                            color: IviaColors.error,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: IviaSpacing.lg),
                    _ResendRow(
                      remaining: _remaining,
                      onResend: _busy ? null : () => _resend(flow.email),
                    ),
                    const SizedBox(height: IviaSpacing.lg),
                    IviaInfoCard(
                      text:
                          'Rien reçu ? Regardez dans les courriers '
                          'indésirables. Le code est valable $minutes minutes.',
                    ),
                    const Spacer(),
                    const SizedBox(height: IviaSpacing.xxl),
                    FilledButton(
                      onPressed: _busy || _code.text.length != 6
                          ? null
                          : _verify,
                      child: _busy
                          ? const ButtonProgress(label: 'Vérification')
                          : const Text('Vérifier le code'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
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
