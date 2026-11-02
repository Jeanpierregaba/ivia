import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_ui/ivia_ui.dart';

/// Fiche introuvable (404) ou injoignable : message, retour, nouvel essai ;
/// commune aux fiches et au suivi.
class UnavailableView extends StatelessWidget {
  const UnavailableView({
    super.key,
    required this.error,
    required this.gone,
    required this.onRetry,
  });

  final Object error;
  final String gone;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final notFound =
        error is ApiException && (error as ApiException).statusCode == 404;
    return Padding(
      padding: const EdgeInsets.all(IviaSpacing.screen),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: IviaBackButton(onPressed: () => context.pop()),
          ),
          const Spacer(),
          Text(
            notFound
                ? gone
                : 'Impossible de charger cette page. Vérifiez votre connexion.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          if (!notFound) ...[
            const SizedBox(height: IviaSpacing.lg),
            OutlinedButton(onPressed: onRetry, child: const Text('Réessayer')),
          ],
          const Spacer(),
        ],
      ),
    );
  }
}
