import 'package:flutter/material.dart';
import 'package:ivia_ui/ivia_ui.dart';

/// Écran provisoire, remplacé par la connexion par OTP (fonctionnalité 001).
class LoginPlaceholderScreen extends StatelessWidget {
  const LoginPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(IviaSpacing.screen),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IviaLogo(color: IviaAppBrand.driver.logoOnLight),
              const SizedBox(height: IviaSpacing.xxxl),
              Text('Connexion', style: textTheme.headlineMedium),
              const SizedBox(height: IviaSpacing.sm),
              Text('Écran à venir.', style: textTheme.bodyLarge),
            ],
          ),
        ),
      ),
    );
  }
}
