import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'brand.dart';
import 'tokens.dart';

/// Champ de recherche en pilule blanche, avec un bouton pour l'effacer.
class IviaSearchField extends StatefulWidget {
  const IviaSearchField({
    super.key,
    required this.controller,
    required this.hint,
    this.onChanged,
    this.focusNode,
    this.maxLength,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged;
  final FocusNode? focusNode;

  /// Longueur maximale du texte (celle qu'accepte le serveur).
  final int? maxLength;

  @override
  State<IviaSearchField> createState() => _IviaSearchFieldState();
}

class _IviaSearchFieldState extends State<IviaSearchField> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void didUpdateWidget(IviaSearchField old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  void _changed() => setState(() {});

  @override
  Widget build(BuildContext context) {
    const pill = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(IviaRadius.pill)),
      borderSide: BorderSide.none,
    );
    return TextField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      onChanged: widget.onChanged,
      inputFormatters: [
        if (widget.maxLength case final max?)
          LengthLimitingTextInputFormatter(max),
      ],
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: widget.hint,
        filled: true,
        fillColor: IviaColors.surface,
        prefixIcon: const Icon(Icons.search, color: IviaColors.textMuted),
        suffixIcon: widget.controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Effacer la recherche',
                icon: const Icon(Icons.close, color: IviaColors.textMuted),
                onPressed: () {
                  widget.controller.clear();
                  widget.onChanged?.call('');
                },
              ),
        border: pill,
        enabledBorder: pill,
        focusedBorder: pill.copyWith(
          borderSide: BorderSide(
            color: IviaAppBrand.of(context).action,
            width: 2,
          ),
        ),
      ),
    );
  }
}

/// Quantité entière : « − », nombre saisissable, « + », bornée entre
/// [min] et [max].
class IviaQuantityStepper extends StatefulWidget {
  const IviaQuantityStepper({
    super.key,
    required this.value,
    required this.onChanged,
    required this.label,
    this.min = 0,
    this.max = 1000000,
    this.enabled = true,
    this.editable = true,
    this.removeLabel,
    this.addLabel = 'Ajouter 1',
    this.minusLabel = 'Retirer 1',
  });

  final int value;
  final ValueChanged<int> onChanged;

  /// Nom de la quantité, lu par le lecteur d'écran (ex. « Quantité
  /// disponible »).
  final String label;
  final int min;
  final int max;
  final bool enabled;

  /// `false` : nombre affiché seulement, changé par « − » et « + » (une
  /// ligne de panier, où un champ vidé pendant la saisie retirerait le
  /// produit).
  final bool editable;

  /// Libellé du « − » quand il ramène à [min] (« Retirer du panier ») : il
  /// prend alors une corbeille. `null` : « Retirer 1 » partout.
  final String? removeLabel;

  /// Libellés des boutons (« Ajouter un Riz parfumé » sur une ligne de
  /// panier, pour les distinguer d'une ligne à l'autre).
  final String addLabel;
  final String minusLabel;

  @override
  State<IviaQuantityStepper> createState() => _IviaQuantityStepperState();
}

class _IviaQuantityStepperState extends State<IviaQuantityStepper> {
  late final _controller = TextEditingController(text: '${widget.value}');

  @override
  void didUpdateWidget(IviaQuantityStepper old) {
    super.didUpdateWidget(old);
    // Valeur changée par les boutons ou le parent : le champ suit, sauf
    // pendant la saisie d'un champ vide (lu comme le minimum).
    if (int.tryParse(_controller.text) != widget.value &&
        !(_controller.text.isEmpty && widget.value == widget.min)) {
      _controller.text = '${widget.value}';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _set(int value) => widget.onChanged(value.clamp(widget.min, widget.max));

  @override
  Widget build(BuildContext context) {
    final brand = IviaAppBrand.of(context);
    final textTheme = Theme.of(context).textTheme;
    final enabled = widget.enabled;
    final removes =
        widget.removeLabel != null && widget.value == widget.min + 1;
    return Container(
      padding: const EdgeInsets.all(IviaSpacing.xs),
      decoration: const ShapeDecoration(
        color: IviaColors.background,
        shape: StadiumBorder(),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton.filled(
            tooltip: removes ? widget.removeLabel : widget.minusLabel,
            style: IconButton.styleFrom(
              backgroundColor: IviaColors.surface,
              foregroundColor: removes ? IviaColors.error : IviaColors.text,
              disabledBackgroundColor: IviaColors.surface,
            ),
            onPressed: enabled && widget.value > widget.min
                ? () => _set(widget.value - 1)
                : null,
            icon: Icon(removes ? Icons.delete_outline : Icons.remove),
          ),
          if (!widget.editable)
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 40),
              child: Semantics(
                container: true,
                label: widget.label,
                value: '${widget.value}',
                excludeSemantics: true,
                child: Text(
                  '${widget.value}',
                  textAlign: TextAlign.center,
                  style: textTheme.titleMedium,
                ),
              ),
            )
          else
            SizedBox(
              width: 72,
              child: Semantics(
                label: widget.label,
                child: TextField(
                  controller: _controller,
                  enabled: enabled,
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter('${widget.max}'.length),
                  ],
                  style: textTheme.titleMedium,
                  decoration: InputDecoration(
                    isDense: true,
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    hintText: '${widget.min}',
                  ),
                  onChanged: (text) => _set(int.tryParse(text) ?? widget.min),
                ),
              ),
            ),
          IconButton.filled(
            tooltip: widget.addLabel,
            style: IconButton.styleFrom(
              backgroundColor: brand.action,
              foregroundColor: Colors.white,
            ),
            onPressed: enabled && widget.value < widget.max
                ? () => _set(widget.value + 1)
                : null,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}

/// Carte à choisir parmi plusieurs (ex. taille du colis) : bordure de
/// couleur d'action quand elle est choisie.
class IviaChoiceCard extends StatelessWidget {
  const IviaChoiceCard({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.visual,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  /// Illustration au-dessus du libellé.
  final Widget visual;

  @override
  Widget build(BuildContext context) {
    final brand = IviaAppBrand.of(context);
    final radius = BorderRadius.circular(IviaRadius.large);
    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: IviaColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: selected
              ? BorderSide(color: brand.action, width: 2)
              : BorderSide.none,
        ),
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: IviaSpacing.sm,
              vertical: IviaSpacing.lg,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(height: 56, child: Center(child: visual)),
                const SizedBox(height: IviaSpacing.sm),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: selected ? brand.action : IviaColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Ton d'une [IviaStatusPill].
enum IviaPillTone {
  /// Fond bleu pâle, texte Cobalt (ex. « En vente »).
  info,

  /// Fond gris, texte secondaire (ex. une catégorie).
  neutral,
}

/// Pastille d'état ou d'étiquette, sur fond pâle.
class IviaStatusPill extends StatelessWidget {
  const IviaStatusPill({
    super.key,
    required this.label,
    this.tone = IviaPillTone.info,
  });

  final String label;
  final IviaPillTone tone;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (tone) {
      IviaPillTone.info => (IviaColors.secondarySoft, IviaColors.cobaltBlue),
      IviaPillTone.neutral => (IviaColors.background, IviaColors.textSecondary),
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: IviaSpacing.md,
        vertical: IviaSpacing.xs + 2,
      ),
      decoration: ShapeDecoration(
        color: background,
        shape: const StadiumBorder(),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium
            ?.copyWith(color: foreground),
      ),
    );
  }
}
