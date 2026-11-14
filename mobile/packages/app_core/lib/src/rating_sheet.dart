import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ivia_ui/ivia_ui.dart';

/// Note saisie dans la feuille d'avis.
typedef RatingResult = ({int stars, List<String> tags, String comment});

/// Étiquettes d'un livreur (codes du serveur, libellés affichés).
const driverPraiseTags = {
  'rapide': 'Rapide',
  'aimable': 'Aimable',
  'soigneux': 'Soigneux',
  'ponctuel': 'Ponctuel',
  'professionnel': 'Professionnel',
};
const driverIssueTags = {
  'en_retard': 'En retard',
  'colis_abime': 'Colis abîmé',
  'impoli': 'Impoli',
  'difficile_a_joindre': 'Difficile à joindre',
};

const _starWords = ['', 'Décevant', 'Bof', 'Correct', 'Très bien', 'Parfait !'];

/// Feuille d'avis : grandes étoiles qui rebondissent, étiquettes adaptées à
/// la note (compliments ou problèmes), commentaire facultatif. [onSubmit]
/// envoie la note et rend un message d'erreur, ou `null` si c'est enregistré.
Future<bool> showRatingSheet(
  BuildContext context, {
  required String title,
  String? subtitle,
  Widget? leading,
  Map<String, String> praiseTags = const {},
  Map<String, String> issueTags = const {},
  String commentHint = 'Un mot de plus (facultatif)',
  required Future<String?> Function(RatingResult) onSubmit,
}) async {
  final done = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _RatingSheet(
      title: title,
      subtitle: subtitle,
      leading: leading,
      praiseTags: praiseTags,
      issueTags: issueTags,
      commentHint: commentHint,
      onSubmit: onSubmit,
    ),
  );
  return done ?? false;
}

class _RatingSheet extends StatefulWidget {
  const _RatingSheet({
    required this.title,
    required this.subtitle,
    required this.leading,
    required this.praiseTags,
    required this.issueTags,
    required this.commentHint,
    required this.onSubmit,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Map<String, String> praiseTags, issueTags;
  final String commentHint;
  final Future<String?> Function(RatingResult) onSubmit;

  @override
  State<_RatingSheet> createState() => _RatingSheetState();
}

class _RatingSheetState extends State<_RatingSheet> {
  var _stars = 0;
  final _tags = <String>{};
  final _comment = TextEditingController();
  var _busy = false;
  var _sent = false;
  String? _error;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await widget.onSubmit((
      stars: _stars,
      tags: _tags.toList(),
      comment: _comment.text.trim(),
    ));
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _busy = false;
        _error = error;
      });
      return;
    }
    setState(() => _sent = true);
    HapticFeedback.mediumImpact();
    await Future<void>.delayed(const Duration(milliseconds: 1300));
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final tags = _stars == 0
        ? const <String, String>{}
        : _stars >= 4
        ? widget.praiseTags
        : widget.issueTags;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        IviaSpacing.screen,
        0,
        IviaSpacing.screen,
        MediaQuery.viewInsetsOf(context).bottom + IviaSpacing.screen,
      ),
      child: AnimatedSize(
        duration: IviaMotion.slow,
        curve: IviaMotion.soft,
        alignment: Alignment.topCenter,
        child: _sent
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: IviaSpacing.xxl),
                child: Column(
                  children: [
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: 1),
                      duration: const Duration(milliseconds: 700),
                      curve: Curves.elasticOut,
                      builder: (_, v, child) =>
                          Transform.scale(scale: v, child: child),
                      child: const CircleAvatar(
                        radius: 36,
                        backgroundColor: IviaColors.successSoft,
                        child: Icon(
                          Icons.favorite_rounded,
                          color: IviaColors.success,
                          size: 38,
                        ),
                      ),
                    ),
                    const SizedBox(height: IviaSpacing.md),
                    Text('Merci pour votre avis !', style: t.titleLarge),
                  ],
                ),
              )
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.leading != null) ...[
                      Center(child: widget.leading),
                      const SizedBox(height: IviaSpacing.md),
                    ],
                    Text(
                      widget.title,
                      textAlign: TextAlign.center,
                      style: t.titleLarge,
                    ),
                    if (widget.subtitle != null) ...[
                      const SizedBox(height: IviaSpacing.xs),
                      Text(
                        widget.subtitle!,
                        textAlign: TextAlign.center,
                        style: t.bodyMedium,
                      ),
                    ],
                    const SizedBox(height: IviaSpacing.lg),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 1; i <= 5; i++)
                          _Star(
                            on: i <= _stars,
                            index: i,
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() {
                                if ((_stars >= 4) != (i >= 4)) _tags.clear();
                                _stars = i;
                              });
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: IviaSpacing.xs),
                    AnimatedSwitcher(
                      duration: IviaMotion.medium,
                      child: Text(
                        _starWords[_stars],
                        key: ValueKey(_stars),
                        textAlign: TextAlign.center,
                        style: t.titleSmall?.copyWith(
                          color: IviaColors.warning,
                        ),
                      ),
                    ),
                    if (tags.isNotEmpty) ...[
                      const SizedBox(height: IviaSpacing.md),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: IviaSpacing.xs,
                        runSpacing: IviaSpacing.xs,
                        children: [
                          for (final MapEntry(:key, :value) in tags.entries)
                            FilterChip(
                              label: Text(value),
                              selected: _tags.contains(key),
                              onSelected: (on) => setState(
                                () => on ? _tags.add(key) : _tags.remove(key),
                              ),
                            ),
                        ],
                      ),
                    ],
                    if (_stars > 0) ...[
                      const SizedBox(height: IviaSpacing.md),
                      TextField(
                        controller: _comment,
                        maxLength: 500,
                        maxLines: 3,
                        minLines: 1,
                        decoration: InputDecoration(
                          hintText: widget.commentHint,
                        ),
                      ),
                    ],
                    if (_error != null)
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: t.bodySmall?.copyWith(color: IviaColors.error),
                      ),
                    const SizedBox(height: IviaSpacing.sm),
                    FilledButton(
                      onPressed: _stars == 0 || _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox.square(
                              dimension: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Envoyer mon avis'),
                    ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => Navigator.pop(context, false),
                      child: const Text('Plus tard'),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

/// Étoile qui rebondit quand elle s'allume.
class _Star extends StatelessWidget {
  const _Star({required this.on, required this.index, required this.onTap});

  final bool on;
  final int index;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: on,
    label: '$index étoile${index > 1 ? 's' : ''}',
    child: GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: TweenAnimationBuilder<double>(
          key: ValueKey(on),
          tween: Tween(begin: on ? 0.6 : 1, end: 1),
          duration: Duration(milliseconds: 450 + index * 40),
          curve: Curves.elasticOut,
          builder: (_, v, child) => Transform.scale(scale: v, child: child),
          child: Icon(
            on ? Icons.star_rounded : Icons.star_outline_rounded,
            size: 46,
            color: on ? const Color(0xFFF5B301) : IviaColors.border,
          ),
        ),
      ),
    ),
  );
}
