import 'package:flutter/material.dart';
import 'package:ivia_ui/ivia_ui.dart';

/// Mise en page des écrans de connexion : retour, titre, texte, contenu,
/// puis les boutons en bas (défilement avec une police agrandie).
class AuthPage extends StatelessWidget {
  const AuthPage({
    super.key,
    required this.title,
    required this.children,
    this.intro,
    this.onBack,
    this.header,
    this.footer = const [],
  });

  final String title;
  final Widget? intro;
  final VoidCallback? onBack;

  /// Au-dessus du titre (logo de l'écran de connexion).
  final Widget? header;
  final List<Widget> children;

  /// En bas de l'écran (bouton principal, liens, mentions légales).
  final List<Widget> footer;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
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
                    if (onBack case final back?) ...[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: IviaBackButton(onPressed: back),
                      ),
                      const SizedBox(height: IviaSpacing.xxl),
                    ],
                    ?header,
                    Semantics(
                      header: true,
                      child: Text(title, style: textTheme.headlineMedium),
                    ),
                    if (intro case final i?) ...[
                      const SizedBox(height: IviaSpacing.sm),
                      DefaultTextStyle.merge(
                        style: textTheme.bodyLarge?.copyWith(
                          color: IviaColors.textSecondary,
                        ),
                        child: i,
                      ),
                    ],
                    const SizedBox(height: IviaSpacing.xxl),
                    ...children,
                    const Spacer(),
                    const SizedBox(height: IviaSpacing.xxl),
                    ...footer,
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

/// Message d'erreur annoncé au lecteur d'écran.
class AuthError extends StatelessWidget {
  const AuthError(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Text(
      text,
      style: Theme.of(context).textTheme.bodyMedium
          ?.copyWith(color: IviaColors.error),
    ),
  );
}

/// Champ « Adresse e-mail » des écrans de connexion.
class EmailField extends StatelessWidget {
  const EmailField({
    super.key,
    required this.controller,
    this.errorText,
    this.enabled = true,
    this.textInputAction = TextInputAction.next,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String? errorText;
  final bool enabled;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) => IviaFieldLabel(
    label: 'Adresse e-mail',
    child: TextField(
      controller: controller,
      enabled: enabled,
      keyboardType: TextInputType.emailAddress,
      autofillHints: const [AutofillHints.email],
      autocorrect: false,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        hintText: 'nom@exemple.com',
        errorText: errorText,
        errorMaxLines: 3,
      ),
    ),
  );
}
