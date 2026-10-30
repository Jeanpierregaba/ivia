import 'package:flutter/material.dart';
import 'package:ivia_ui/ivia_ui.dart';

void main() {
  runApp(const DriverApp());
}

class DriverApp extends StatelessWidget {
  const DriverApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ivia Livreur',
      theme: IviaTheme.light(),
      home: const _HomePlaceholder(),
    );
  }
}

/// Écran provisoire, remplacé par la connexion (fonctionnalité 001).
class _HomePlaceholder extends StatelessWidget {
  const _HomePlaceholder();

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
              Text(
                'LIVREUR',
                style: textTheme.labelSmall?.copyWith(
                  color: IviaColors.primaryStrong,
                ),
              ),
              const SizedBox(height: IviaSpacing.xs),
              Text('ivia', style: textTheme.displaySmall),
            ],
          ),
        ),
      ),
    );
  }
}
