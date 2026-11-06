import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../common/providers.dart';
import '../../common/ui.dart';

/// Planning de garde : créneau par créneau, ou import d'une liste.
class PlanningScreen extends ConsumerStatefulWidget {
  const PlanningScreen({super.key});

  @override
  ConsumerState<PlanningScreen> createState() => _PlanningScreenState();
}

class _PlanningScreenState extends ConsumerState<PlanningScreen> {
  DateTime? _day;
  var _from = const TimeOfDay(hour: 20, minute: 0);
  var _to = const TimeOfDay(hour: 7, minute: 0);
  final _import = TextEditingController();
  var _busy = false;

  @override
  void dispose() {
    _import.dispose();
    super.dispose();
  }

  /// Heure de Lomé, soit UTC ; une fin avant le début tombe le lendemain.
  ({DateTime startsAt, DateTime endsAt}) _shift(
    DateTime day,
    TimeOfDay from,
    TimeOfDay to,
  ) {
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

  Future<void> _send(
    List<({DateTime startsAt, DateTime endsAt})> shifts,
  ) async {
    setState(() => _busy = true);
    try {
      await ref.read(apiClientProvider).addPharmacyDutyShifts(shifts);
      ref.invalidate(shiftsProvider);
      _import.clear();
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

  /// Une garde par ligne : 08/11/2026 20:00 07:00
  void _importList() {
    final line = RegExp(
      r'^(\d{1,2})/(\d{1,2})/(\d{4})\s+(\d{1,2})[:h](\d{2})\s+(\d{1,2})[:h](\d{2})$',
    );
    final out = <({DateTime startsAt, DateTime endsAt})>[];
    final lines = _import.text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    for (final (i, l) in lines.indexed) {
      final m = line.firstMatch(l);
      if (m == null) {
        say(
          context,
          'Ligne ${i + 1} illisible. Format : 08/11/2026 20:00 07:00',
        );
        return;
      }
      int n(int g) => int.parse(m.group(g)!);
      out.add(
        _shift(
          DateTime.utc(n(3), n(2), n(1)),
          TimeOfDay(hour: n(4) % 24, minute: n(5) % 60),
          TimeOfDay(hour: n(6) % 24, minute: n(7) % 60),
        ),
      );
    }
    if (out.isNotEmpty) _send(out);
  }

  Future<void> _delete(String id) async {
    try {
      await ref.read(apiClientProvider).deletePharmacyDutyShift(id);
      ref.invalidate(shiftsProvider);
    } on ApiException catch (e) {
      if (mounted) say(context, e.message);
    }
  }

  String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final shifts = ref.watch(shiftsProvider).value ?? const [];
    final day = _day;
    return Scaffold(
      backgroundColor: P.page,
      appBar: AppBar(
        backgroundColor: P.page,
        title: const Text('Planning de garde'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(IviaSpacing.screen),
        children: [
          const _NightHours(),
          const SizedBox(height: 12),
          PCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Ajouter une garde',
                  style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_today_outlined, size: 18),
                  label: Text(day == null ? 'Choisir le jour' : _date(day)),
                  onPressed: () async {
                    final now = DateTime.now();
                    final d = await showDatePicker(
                      context: context,
                      firstDate: now,
                      lastDate: now.add(const Duration(days: 365)),
                      initialDate: day ?? now,
                    );
                    if (d != null) setState(() => _day = d);
                  },
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        child: Text('De ${_from.format(context)}'),
                        onPressed: () async {
                          final v = await showTimePicker(
                            context: context,
                            initialTime: _from,
                          );
                          if (v != null) setState(() => _from = v);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        child: Text('À ${_to.format(context)}'),
                        onPressed: () async {
                          final v = await showTimePicker(
                            context: context,
                            initialTime: _to,
                          );
                          if (v != null) setState(() => _to = v);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                PButton(
                  label: 'Ajouter',
                  busy: _busy,
                  onTap: day == null
                      ? null
                      : () => _send([_shift(day, _from, _to)]),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          PCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Importer une liste',
                  style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  'Une garde par ligne, 60 au plus.',
                  style: t.bodySmall?.copyWith(color: P.muted),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _import,
                  minLines: 3,
                  maxLines: 8,
                  decoration: const InputDecoration(
                    hintText: '08/11/2026 20:00 07:00\n15/11/2026 20:00 07:00',
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton(
                  onPressed: _busy ? null : _importList,
                  child: const Text('Importer'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Gardes à venir',
            style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          if (shifts.isEmpty)
            PCard(child: Text('Aucune garde planifiée.', style: t.bodyMedium)),
          for (final s in shifts)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: PCard(
                padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${_date(s.startsAt.toLocal())} · ${hhmm(s.startsAt)} → ${hhmm(s.endsAt)}',
                        style: t.bodyMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Retirer',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _delete(s.id),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Heures de nuit choisies par la pharmacie.
class _NightHours extends ConsumerStatefulWidget {
  const _NightHours();

  @override
  ConsumerState<_NightHours> createState() => _NightHoursState();
}

class _NightHoursState extends ConsumerState<_NightHours> {
  int? _from, _to;
  var _busy = false;

  Future<void> _save(int from, int to) async {
    setState(() => _busy = true);
    try {
      await ref.read(apiClientProvider).setPharmacyNightHours(from, to);
      ref.invalidate(pharmacyProfileProvider);
      if (mounted) say(context, 'Heures de nuit enregistrées.');
    } on ApiException catch (e) {
      if (mounted) say(context, e.fields.values.firstOrNull ?? e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
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
                DropdownMenuItem(value: h, child: Text('$h h')),
            ],
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final p = ref.watch(pharmacyProfileProvider).value;
    final from = _from ?? p?.nightFromHour ?? 20;
    final to = _to ?? p?.nightToHour ?? 7;
    return PCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Vos heures de nuit',
            style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            'Pendant ces heures, vous ne recevez les alertes que si vous êtes de garde.',
            style: t.bodySmall?.copyWith(color: P.muted),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _hour('De', from, (v) => setState(() => _from = v)),
              const SizedBox(width: 10),
              _hour('À', to, (v) => setState(() => _to = v)),
            ],
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: _busy ? null : () => _save(from, to),
            child: Text(_busy ? 'Patientez…' : 'Enregistrer mes heures'),
          ),
        ],
      ),
    );
  }
}
