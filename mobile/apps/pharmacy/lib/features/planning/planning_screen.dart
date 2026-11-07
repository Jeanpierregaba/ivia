import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../common/providers.dart';
import '../../common/ui.dart';

typedef Shift = ({String id, DateTime startsAt, DateTime endsAt});
typedef NewShift = ({DateTime startsAt, DateTime endsAt});

const _weekdays = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
const _weekdaysLong = [
  'Lundi',
  'Mardi',
  'Mercredi',
  'Jeudi',
  'Vendredi',
  'Samedi',
  'Dimanche',
];
const _months = [
  'janvier',
  'février',
  'mars',
  'avril',
  'mai',
  'juin',
  'juillet',
  'août',
  'septembre',
  'octobre',
  'novembre',
  'décembre',
];

String _two(int n) => n.toString().padLeft(2, '0');

/// Heure de Lomé, soit UTC ; une fin avant le début tombe le lendemain.
NewShift shiftOn(DateTime day, TimeOfDay from, TimeOfDay to) {
  final start = DateTime.utc(
    day.year,
    day.month,
    day.day,
    from.hour,
    from.minute,
  );
  var end = DateTime.utc(day.year, day.month, day.day, to.hour, to.minute);
  if (!end.isAfter(start)) end = end.add(const Duration(days: 1));
  return (startsAt: start, endsAt: end);
}

/// Une garde par ligne : « 08/11/2026 20:00 07:00 ». Renvoie les gardes, ou
/// le numéro de la première ligne illisible.
({List<NewShift> shifts, int? badLine}) parseShiftList(String text) {
  final line = RegExp(
    r'^(\d{1,2})/(\d{1,2})/(\d{4})\s+(\d{1,2})[:h](\d{2})\s+(\d{1,2})[:h](\d{2})$',
  );
  final out = <NewShift>[];
  final lines = text
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();
  for (final (i, l) in lines.indexed) {
    final m = line.firstMatch(l);
    if (m == null) return (shifts: const [], badLine: i + 1);
    int n(int g) => int.parse(m.group(g)!);
    out.add(
      shiftOn(
        DateTime.utc(n(3), n(2), n(1)),
        TimeOfDay(hour: n(4) % 24, minute: n(5) % 60),
        TimeOfDay(hour: n(6) % 24, minute: n(7) % 60),
      ),
    );
  }
  return (shifts: out, badLine: null);
}

/// Planning de garde (F20) : bande des jours, service de jour et gardes du
/// jour choisi, ajout, import, heures de nuit. Dans le dossier ([step]), il
/// se passe : « Passer cette étape » ou « Continuer ».
class PlanningScreen extends ConsumerStatefulWidget {
  const PlanningScreen({super.key, this.step, this.onBack, this.onNext});

  /// Étape du dossier (« 4 sur 5 ») ; `null` hors du dossier.
  final int? step;
  final VoidCallback? onBack;
  final VoidCallback? onNext;

  @override
  ConsumerState<PlanningScreen> createState() => _PlanningScreenState();
}

class _PlanningScreenState extends ConsumerState<PlanningScreen> {
  late DateTime _day = _today();
  var _busy = false;

  /// Jour de Lomé : les gardes sont en heure de Lomé (UTC).
  static DateTime _today() => lomeDay(DateTime.now());

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Gardes qui commencent le jour [d] (heure locale).
  List<Shift> _on(List<Shift> shifts, DateTime d) => [
    for (final s in shifts)
      if (_sameDay(lomeDay(s.startsAt), d)) s,
  ]..sort((a, b) => a.startsAt.compareTo(b.startsAt));

  Future<void> _send(List<NewShift> shifts) async {
    setState(() => _busy = true);
    try {
      await ref.read(apiClientProvider).addPharmacyDutyShifts(shifts);
      ref.invalidate(shiftsProvider);
      if (mounted) {
        say(
          context,
          shifts.length > 1
              ? '${shifts.length} gardes ajoutées.'
              : 'Garde ajoutée.',
        );
      }
    } on ApiException catch (e) {
      if (mounted) say(context, e.fields.values.firstOrNull ?? e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(Shift s) async {
    try {
      await ref.read(apiClientProvider).deletePharmacyDutyShift(s.id);
      ref.invalidate(shiftsProvider);
      if (mounted) say(context, 'Garde retirée.');
    } on ApiException catch (e) {
      if (mounted) say(context, e.message);
    }
  }

  Future<void> _add() async {
    final shift = await showModalBottomSheet<NewShift>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (_) => _AddShiftSheet(day: _day),
    );
    if (shift != null) await _send([shift]);
  }

  Future<void> _import() async {
    final shifts = await showModalBottomSheet<List<NewShift>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (_) => const _ImportSheet(),
    );
    if (shifts != null && shifts.isNotEmpty) await _send(shifts);
  }

  Future<void> _nightHours(PharmacyProfile? p) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (_) => _NightHoursSheet(
        from: p?.nightFromHour ?? 20,
        to: p?.nightToHour ?? 8,
      ),
    );
    if (saved == true) ref.invalidate(pharmacyProfileProvider);
  }

  Widget _days(List<Shift> shifts) {
    final monday = _today().subtract(Duration(days: _today().weekday - 1));
    return SizedBox(
      height: 72,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: P.gutter),
        itemCount: 28,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final d = monday.add(Duration(days: i));
          final selected = _sameDay(d, _day);
          final duty = _on(shifts, d).isNotEmpty;
          final fg = selected ? Colors.white : P.ink;
          return Semantics(
            button: true,
            selected: selected,
            label:
                '${_weekdaysLong[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}'
                '${duty ? ', de garde' : ''}',
            excludeSemantics: true,
            child: Material(
              color: selected ? P.green : Colors.white,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => setState(() => _day = d),
                child: SizedBox(
                  width: 49,
                  child: MediaQuery.withClampedTextScaling(
                    maxScaleFactor: 1.2,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _weekdays[d.weekday - 1],
                          style: PText.body.copyWith(
                            fontSize: 13,
                            color: selected ? Colors.white : P.muted,
                          ),
                        ),
                        Text(
                          '${d.day}',
                          style: PText.cardTitle.copyWith(color: fg),
                        ),
                        const SizedBox(height: 2),
                        Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: !duty
                                ? Colors.transparent
                                : selected
                                ? Colors.white
                                : P.green,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _row(String title, String sub, Widget pill, {Widget? action}) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: PText.cardTitle),
                  Text(sub, style: PText.bodyMuted),
                ],
              ),
            ),
            PTrailing(child: pill),
            ?action,
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final step = widget.step;
    final next = widget.onNext;
    final shifts = ref.watch(shiftsProvider).value ?? const <Shift>[];
    final p = ref.watch(pharmacyProfileProvider).value;
    final nightFrom = p?.nightFromHour ?? 20;
    final nightTo = p?.nightToHour ?? 8;
    final today = _on(shifts, _day);
    return Scaffold(
      backgroundColor: P.page,
      body: SafeArea(
        child: Column(
          children: [
            PHeader(
              title: step == null ? 'Planning' : 'Planning de garde',
              trailing: step == null
                  ? Semantics(
                      button: true,
                      label: 'Ajouter une garde',
                      excludeSemantics: true,
                      child: SizedBox.square(
                        dimension: 48,
                        child: Center(
                          child: Material(
                            color: Colors.white,
                            shape: const CircleBorder(),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: _busy ? null : _add,
                              child: const SizedBox.square(
                                dimension: 44,
                                child: Icon(Icons.add, color: P.ink),
                              ),
                            ),
                          ),
                        ),
                      ),
                    )
                  : PStepPill(step: step, of: 5),
              onBack: widget.onBack,
            ),
            const SizedBox(height: 4),
            _days(shifts),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(P.gutter, 12, P.gutter, 16),
                children: [
                  PCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                          child: Semantics(
                            header: true,
                            child: Text(
                              '${_weekdaysLong[_day.weekday - 1]} ${_day.day} '
                              '${_months[_day.month - 1]}',
                              style: PText.label,
                            ),
                          ),
                        ),
                        const Divider(height: 1, color: P.line),
                        _row(
                          'Service de jour',
                          '${_two(nightTo)}:00 → ${_two(nightFrom)}:00',
                          const PPill('En service', bg: P.page, fg: P.label),
                        ),
                        for (final s in today) ...[
                          const Divider(height: 1, color: P.line),
                          _row(
                            'Garde de nuit',
                            '${hhmm(s.startsAt)} → ${hhmm(s.endsAt)}',
                            const PPill('De garde'),
                            action: IconButton(
                              tooltip: 'Retirer cette garde',
                              onPressed: () => _delete(s),
                              icon: const Icon(
                                Icons.close,
                                color: P.muted,
                                size: 20,
                              ),
                            ),
                          ),
                        ],
                        if (step != null) ...[
                          const Divider(height: 1, color: P.line),
                          InkWell(
                            onTap: _busy ? null : _add,
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Row(
                                children: [
                                  const Icon(Icons.add, color: P.green),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'Ajouter une garde',
                                      style: PText.button.copyWith(
                                        fontSize: 15,
                                        color: P.green,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  PCard(
                    onTap: _busy ? null : _import,
                    child: Row(
                      children: [
                        const PIcon(Icons.download, size: 40),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Importer une liste',
                                style: PText.cardTitle,
                              ),
                              Text(
                                'Le planning officiel : une garde par ligne',
                                style: PText.bodyMuted,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  PCard(
                    onTap: () => _nightHours(p),
                    child: Row(
                      children: [
                        const PIcon(Icons.nightlight_outlined, size: 40),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Heures de nuit', style: PText.cardTitle),
                              Text(
                                'De ${_two(nightFrom)}:00 à ${_two(nightTo)}:00',
                                style: PText.bodyMuted,
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right, color: P.muted),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  PCard(
                    color: P.softBlue,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const ExcludeSemantics(
                          child: Icon(Icons.info, color: P.blue, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'En journée, les alertes vont à toutes les '
                            'pharmacies en service. La nuit, uniquement aux '
                            'pharmacies de garde.',
                            style: PText.body.copyWith(color: P.ink),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (next != null)
              PBottomBar(
                children: [
                  PButton(
                    label: shifts.isEmpty ? 'Passer cette étape' : 'Continuer',
                    style: shifts.isEmpty
                        ? PButtonStyle.outline
                        : PButtonStyle.filled,
                    onTap: next,
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Ajout d'une garde : jour, début, fin.
class _AddShiftSheet extends StatefulWidget {
  const _AddShiftSheet({required this.day});
  final DateTime day;

  @override
  State<_AddShiftSheet> createState() => _AddShiftSheetState();
}

class _AddShiftSheetState extends State<_AddShiftSheet> {
  late var _day = widget.day;
  var _from = const TimeOfDay(hour: 20, minute: 0);
  var _to = const TimeOfDay(hour: 8, minute: 0);

  @override
  Widget build(BuildContext context) {
    Widget choice(String label, String value, VoidCallback onTap) => Expanded(
      child: PCard(
        color: P.page,
        onTap: onTap,
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: PText.small),
            Text(value, style: PText.cardTitle),
          ],
        ),
      ),
    );
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(P.gutter, 0, P.gutter, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Ajouter une garde',
              style: PText.heading.copyWith(fontSize: 24),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                choice(
                  'Jour',
                  '${_two(_day.day)}/${_two(_day.month)}/${_day.year}',
                  () async {
                    final now = DateTime.now();
                    final d = await showDatePicker(
                      context: context,
                      firstDate: DateTime(now.year, now.month, now.day),
                      lastDate: now.add(const Duration(days: 365)),
                      initialDate: _day.isBefore(now) ? now : _day,
                    );
                    if (d != null) setState(() => _day = d);
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                choice('De', _from.format(context), () async {
                  final v = await showTimePicker(
                    context: context,
                    initialTime: _from,
                  );
                  if (v != null) setState(() => _from = v);
                }),
                const SizedBox(width: 8),
                choice('À', _to.format(context), () async {
                  final v = await showTimePicker(
                    context: context,
                    initialTime: _to,
                  );
                  if (v != null) setState(() => _to = v);
                }),
              ],
            ),
            const SizedBox(height: 16),
            PButton(
              label: 'Ajouter',
              onTap: () => Navigator.of(context).pop(shiftOn(_day, _from, _to)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Import d'une liste de gardes collée.
class _ImportSheet extends StatefulWidget {
  const _ImportSheet();

  @override
  State<_ImportSheet> createState() => _ImportSheetState();
}

class _ImportSheetState extends State<_ImportSheet> {
  final _text = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    final r = parseShiftList(_text.text);
    if (r.badLine case final line?) {
      setState(
        () => _error = 'Ligne $line illisible. Format : 08/11/2026 20:00 07:00',
      );
      return;
    }
    Navigator.of(context).pop(r.shifts);
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(P.gutter, 0, P.gutter, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Importer une liste',
              style: PText.heading.copyWith(fontSize: 24),
            ),
            const SizedBox(height: 6),
            Text('Une garde par ligne, 60 au plus.', style: PText.bodyMuted),
            const SizedBox(height: 12),
            TextField(
              controller: _text,
              minLines: 3,
              maxLines: 8,
              decoration: InputDecoration(
                hintText: '08/11/2026 20:00 07:00\n15/11/2026 20:00 07:00',
                errorText: _error,
                errorMaxLines: 2,
              ),
            ),
            const SizedBox(height: 14),
            PButton(label: 'Importer', onTap: _submit),
          ],
        ),
      ),
    ),
  );
}

/// Heures de nuit : seules les pharmacies de garde sont alertées.
class _NightHoursSheet extends ConsumerStatefulWidget {
  const _NightHoursSheet({required this.from, required this.to});
  final int from, to;

  @override
  ConsumerState<_NightHoursSheet> createState() => _NightHoursSheetState();
}

class _NightHoursSheetState extends ConsumerState<_NightHoursSheet> {
  late var _from = widget.from;
  late var _to = widget.to;
  var _busy = false;

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await ref.read(apiClientProvider).setPharmacyNightHours(_from, _to);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        say(context, e.fields.values.firstOrNull ?? e.message);
      }
    }
  }

  Widget _hour(String label, int value, ValueChanged<int> onChanged) =>
      Expanded(
        child: IviaFieldLabel(
          label: label,
          child: DropdownButtonFormField<int>(
            initialValue: value,
            items: [
              for (var h = 0; h < 24; h++)
                DropdownMenuItem(value: h, child: Text('${_two(h)}:00')),
            ],
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(P.gutter, 0, P.gutter, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Heures de nuit', style: PText.heading.copyWith(fontSize: 24)),
          const SizedBox(height: 6),
          Text(
            'Pendant ces heures, vous ne recevez les alertes que si vous êtes '
            'de garde.',
            style: PText.bodyMuted,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _hour('De', _from, (v) => setState(() => _from = v)),
              const SizedBox(width: 10),
              _hour('À', _to, (v) => setState(() => _to = v)),
            ],
          ),
          const SizedBox(height: 16),
          PButton(label: 'Enregistrer', busy: _busy, onTap: _save),
        ],
      ),
    ),
  );
}
