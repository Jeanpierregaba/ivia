import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_ui/ivia_ui.dart';

import 'app_identity.dart';
import 'auth_routes.dart';
import 'button_progress.dart';
import 'legal_text.dart';
import 'login_flow.dart';

/// « Bienvenue sur ivia » : saisie de l'e-mail, envoi du code.
class EmailScreen extends ConsumerStatefulWidget {
  const EmailScreen({super.key});

  @override
  ConsumerState<EmailScreen> createState() => _EmailScreenState();
}

class _EmailScreenState extends ConsumerState<EmailScreen> {
  final _email = TextEditingController();
  String? _error;
  var _sending = false;

  @override
  void initState() {
    super.initState();
    // Retour depuis l'écran du code (« Modifier ») : adresse conservée.
    _email.text = ref.read(loginFlowProvider)?.email ?? '';
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_sending) return;
    final email = _email.text;
    if (!isPlausibleEmail(email)) {
      setState(() => _error = 'Saisissez une adresse e-mail valide.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref.read(loginFlowProvider.notifier).requestCode(email);
      if (mounted) context.go(AuthRoutes.code);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final identity = ref.watch(appIdentityProvider);
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
                    const SizedBox(height: IviaSpacing.huge),
                    Row(
                      children: [
                        IviaLogoTile(size: 76, color: identity.brand.accent),
                        if (identity.loginBadge case final badge?) ...[
                          const SizedBox(width: IviaSpacing.md),
                          _Badge(label: badge, color: identity.brand.accent),
                        ],
                      ],
                    ),
                    const SizedBox(height: IviaSpacing.xxl),
                    Semantics(
                      header: true,
                      child: Text(
                        identity.loginTitle,
                        style: textTheme.headlineMedium,
                      ),
                    ),
                    const SizedBox(height: IviaSpacing.sm),
                    Text(
                      identity.loginBody,
                      style: textTheme.bodyLarge?.copyWith(
                        color: IviaColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: IviaSpacing.xxxl),
                    IviaFieldLabel(
                      label: 'Adresse e-mail',
                      child: TextField(
                        controller: _email,
                        enabled: !_sending,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        autocorrect: false,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _submit(),
                        decoration: InputDecoration(
                          hintText: 'nom@exemple.com',
                          errorText: _error,
                          errorMaxLines: 3,
                        ),
                      ),
                    ),
                    const SizedBox(height: IviaSpacing.xxl),
                    FilledButton(
                      onPressed: _sending ? null : _submit,
                      child: _sending
                          ? const ButtonProgress()
                          : const Text('Recevoir le code'),
                    ),
                    const SizedBox(height: IviaSpacing.xxl),
                    const _SoonDivider(),
                    const SizedBox(height: IviaSpacing.lg),
                    // Canal prévu après validation de WhatsApp Business (PRD).
                    OutlinedButton.icon(
                      onPressed: null,
                      icon: const Icon(Icons.chat_outlined),
                      label: const Text('Continuer avec WhatsApp'),
                    ),
                    const Spacer(),
                    const SizedBox(height: IviaSpacing.xxl),
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
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SoonDivider extends StatelessWidget {
  const _SoonDivider();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider()),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: IviaSpacing.md),
          child: Text('bientôt', style: Theme.of(context).textTheme.bodySmall),
        ),
        const Expanded(child: Divider()),
      ],
    );
  }
}

/// Pastille pleine à côté du logo (« Marchand »).
class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
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
}
