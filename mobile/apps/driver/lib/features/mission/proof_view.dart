import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../common/ui.dart';
import '../earnings/earnings.dart';
import '../work/work_state.dart';
import 'mission_ui.dart';

/// Preuve de remise (D14) : code à 4 chiffres du client, case « J'ai vu
/// l'original de l'ordonnance » si elle est exigée, « Confirmer la
/// livraison ». Un code faux affiche le refus du serveur et efface le code.
/// La photo du colis est masquée (pas de serveur, spec 033).
class ProofView extends ConsumerStatefulWidget {
  const ProofView({super.key, required this.mission});
  final WorkMission mission;

  @override
  ConsumerState<ProofView> createState() => _ProofViewState();
}

class _ProofViewState extends ConsumerState<ProofView> {
  static const _length = 4;
  final _code = TextEditingController();
  final _focus = FocusNode();
  var _prescription = false, _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _code.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _code.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _ready =>
      _code.text.length == _length &&
      (!widget.mission.prescriptionCheck || _prescription);

  Future<void> _confirm() async {
    final m = widget.mission;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(apiClientProvider)
          .deliverMission(m, _code.text, prescriptionChecked: _prescription);
      ref.invalidate(missionHistoryProvider);
      ref.read(workProvider.notifier).markDelivered(m);
    } on ApiException catch (e) {
      if (!mounted) return;
      final message = e.fields['code'] ?? e.message;
      _code.clear();
      setState(() => _error = message);
      announce(context, message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Livraison impossible (dialogue existant, remplacé par D16 à la
  /// tâche 16).
  Future<void> _fail(WorkMission m) async {
    final reason = TextEditingController();
    var calls = 2;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('Livraison impossible'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: reason,
                decoration: const InputDecoration(
                  labelText: 'Motif (client absent, adresse introuvable…)',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Expanded(child: Text('Appels au client')),
                  IconButton(
                    onPressed: calls > 0 ? () => set(() => calls--) : null,
                    icon: const Icon(Icons.remove),
                  ),
                  Text('$calls'),
                  IconButton(
                    onPressed: () => set(() => calls++),
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Confirmer'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      final error = await ref
          .read(workProvider.notifier)
          .run((api) => api.failMission(m, reason.text.trim(), calls));
      if (error != null && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.mission;
    final client = m.client?.name ?? '';
    final ref0 = m.reference.isEmpty ? '' : shortRef(m.reference);
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(D.gutter, 12, D.gutter, 16),
              children: [
                const StepHeader(title: 'Preuve de remise', step: '2 sur 2'),
                const SizedBox(height: 16),
                DCard(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const DIconTile(
                        Icons.inventory_2_rounded,
                        bg: D.blueSoft,
                        fg: D.blue,
                        size: 44,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: MergeSemantics(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                [
                                  ref0,
                                  client,
                                ].where((s) => s.isNotEmpty).join(' · '),
                                style: DText.cardTitle.copyWith(fontSize: 17),
                              ),
                              Text(
                                [
                                  m.pickup.name,
                                  if (m.itemsCount > 0)
                                    m.pharmacy
                                        ? '${m.itemsCount} ${m.itemsCount > 1 ? 'produits' : 'produit'}'
                                        : '${m.itemsCount} ${m.itemsCount > 1 ? 'articles' : 'article'}',
                                ].join(' · '),
                                style: DText.bodyMuted.copyWith(fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const MTag('Payée', bg: D.greenSoft, fg: D.green),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Semantics(
                  header: true,
                  child: Text(
                    'Code du client',
                    style: DText.cardTitle.copyWith(fontSize: 20),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Demandez le code à 4 chiffres au client.',
                  style: DText.bodyMuted.copyWith(fontSize: 14),
                ),
                const SizedBox(height: 12),
                _CodeField(controller: _code, focus: _focus),
                if (_error case final error?) ...[
                  const SizedBox(height: 8),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      error,
                      style: DText.body.copyWith(color: IviaColors.error),
                    ),
                  ),
                ],
                if (m.prescriptionCheck) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
                    decoration: BoxDecoration(
                      color: IviaDriverColors.warningSoft,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.assignment_rounded,
                              color: IviaDriverColors.warning,
                              size: 22,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Médicament sur ordonnance',
                                style: DText.cardTitle.copyWith(fontSize: 16),
                              ),
                            ),
                          ],
                        ),
                        CheckRow(
                          label: "J'ai vu l'original de l'ordonnance",
                          value: _prescription,
                          onChanged: (v) => setState(() => _prescription = v),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              D.gutter,
              8,
              D.gutter,
              MediaQuery.paddingOf(context).bottom + 12,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DButton(
                  label: 'Confirmer la livraison',
                  icon: Icons.check_rounded,
                  busy: _busy,
                  onTap: _ready ? _confirm : null,
                ),
                if (!m.pharmacy)
                  TextButton(
                    onPressed: _busy ? null : () => _fail(m),
                    style: TextButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: Text(
                      'Livraison impossible',
                      style: DText.button.copyWith(
                        color: D.label,
                        fontSize: 15,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Code en 4 cases ; un champ invisible reçoit la saisie (clavier
/// numérique, collage, remplissage automatique).
class _CodeField extends StatelessWidget {
  const _CodeField({required this.controller, required this.focus});
  final TextEditingController controller;
  final FocusNode focus;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      ExcludeSemantics(child: DCodeBoxes(controller.text)),
      Positioned.fill(
        child: Semantics(
          label: 'Code du client, 4 chiffres',
          child: TextField(
            controller: controller,
            focusNode: focus,
            keyboardType: TextInputType.number,
            autofillHints: const [AutofillHints.oneTimeCode],
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(4),
            ],
            showCursor: false,
            enableInteractiveSelection: false,
            style: const TextStyle(color: Colors.transparent, fontSize: 1),
            decoration: const InputDecoration(
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              filled: false,
              counterText: '',
            ),
          ),
        ),
      ),
    ],
  );
}
