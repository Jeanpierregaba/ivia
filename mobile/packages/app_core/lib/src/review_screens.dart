import 'package:flutter/material.dart';
import 'package:ivia_ui/ivia_ui.dart';

/// Écran d'attente d'une validation par l'équipe ivia (boutique, dossier
/// livreur) : anneau, titre, texte, étapes, action. Le statut est relu au
/// retour dans l'app et en tirant vers le bas ; un échec est signalé.
class ReviewPendingView extends StatefulWidget {
  const ReviewPendingView({
    super.key,
    required this.title,
    required this.body,
    required this.steps,
    required this.action,
    required this.onRefresh,
    required this.progressLabel,
  });

  final String title;
  final String body;
  final List<IviaStep> steps;

  /// Annoncé par le lecteur d'écran sur l'anneau (« Validation en cours »).
  final String progressLabel;

  /// Bouton du bas (« Préparer mes produits », « Voir mon dossier »).
  final Widget action;

  /// Relit le statut ; `false` : échec (réseau).
  final Future<bool> Function() onRefresh;

  @override
  State<ReviewPendingView> createState() => _ReviewPendingViewState();
}

class _ReviewPendingViewState extends State<ReviewPendingView> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _refresh);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final ok = await widget.onRefresh();
    if (!ok && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Pas de connexion : statut non actualisé.'),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: const EdgeInsets.all(IviaSpacing.screen),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: IviaSpacing.huge),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          width: 76,
                          height: 76,
                          padding: const EdgeInsets.all(20),
                          decoration: const BoxDecoration(
                            color: IviaColors.surface,
                            shape: BoxShape.circle,
                          ),
                          // Anneau fixe (maquettes) : l'attente se compte
                          // en heures, pas en secondes.
                          child: CircularProgressIndicator(
                            value: 0.75,
                            strokeWidth: 4,
                            color: IviaAppBrand.of(context).action,
                            backgroundColor: IviaColors.border,
                            semanticsLabel: widget.progressLabel,
                          ),
                        ),
                      ),
                      const SizedBox(height: IviaSpacing.xxl),
                      Semantics(
                        header: true,
                        child: Text(
                          widget.title,
                          style: textTheme.headlineMedium,
                        ),
                      ),
                      const SizedBox(height: IviaSpacing.sm),
                      Text(
                        widget.body,
                        style: textTheme.bodyLarge?.copyWith(
                          color: IviaColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: IviaSpacing.xxl),
                      IviaStepList(steps: widget.steps),
                      const Spacer(),
                      const SizedBox(height: IviaSpacing.xxl),
                      widget.action,
                    ],
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

/// Refus ou suspension par l'équipe ivia : titre, motif, actions.
class ReviewBlockedView extends StatelessWidget {
  const ReviewBlockedView({
    super.key,
    required this.title,
    required this.reason,
    required this.actions,
  });

  final String title;

  /// Motif donné par l'admin ; vide : invitation à contacter ivia.
  final String reason;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(IviaSpacing.screen),
          children: [
            const SizedBox(height: IviaSpacing.huge),
            const Icon(
              Icons.report_outlined,
              size: 56,
              color: IviaColors.error,
            ),
            const SizedBox(height: IviaSpacing.xxl),
            Semantics(
              header: true,
              child: Text(title, style: textTheme.headlineMedium),
            ),
            const SizedBox(height: IviaSpacing.sm),
            Text(
              reason.isEmpty
                  ? "Contactez l'équipe ivia pour en savoir plus."
                  : 'Motif : $reason',
              style: textTheme.bodyLarge?.copyWith(
                color: IviaColors.textSecondary,
              ),
            ),
            const SizedBox(height: IviaSpacing.xxxl),
            for (final (i, action) in actions.indexed) ...[
              if (i > 0) const SizedBox(height: IviaSpacing.sm),
              action,
            ],
          ],
        ),
      ),
    );
  }
}

/// Relit un statut et signale un échec (« Actualiser » des écrans de refus).
Future<void> refreshOrWarn(
  BuildContext context,
  Future<bool> Function() refresh,
) async {
  final messenger = ScaffoldMessenger.of(context);
  if (!await refresh()) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Pas de connexion : statut non actualisé.'),
        ),
      );
  }
}
