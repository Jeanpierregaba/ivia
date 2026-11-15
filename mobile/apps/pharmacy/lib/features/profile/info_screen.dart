import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../common/providers.dart';
import '../../common/ui.dart';

/// Informations de la pharmacie validée : téléphone et horaires modifiables,
/// ouverture 24 h/24 et garde en cours, appareils connectés.
class InfoScreen extends ConsumerStatefulWidget {
  const InfoScreen({super.key});

  @override
  ConsumerState<InfoScreen> createState() => _InfoScreenState();
}

class _InfoScreenState extends ConsumerState<InfoScreen> {
  late final PharmacyProfile? _p = ref.read(pharmacyProfileProvider).value;
  late final _phone = TextEditingController(
    text: formatTogoPhone((_p?.phone ?? '').replaceFirst('+228', '')),
  );
  late final _hours = TextEditingController(text: _p?.openingHours);
  var _errors = <String, String>{};
  var _saving = false;
  var _toggling = false;

  @override
  void dispose() {
    _phone.dispose();
    _hours.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _errors = {};
    });
    try {
      await ref
          .read(apiClientProvider)
          .updatePharmacyContact(
            phone: '+228${togoPhoneDigits(_phone.text)}',
            openingHours: _hours.text.trim(),
          );
      ref.invalidate(pharmacyProfileProvider);
      if (mounted) say(context, 'Informations enregistrées.');
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _errors = e.fields);
        if (e.fields.isEmpty) say(context, e.message);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _status(PharmacyProfile p, {bool? h24, bool? duty}) async {
    setState(() => _toggling = true);
    try {
      await ref
          .read(apiClientProvider)
          .setPharmacyStatus(
            isOpen: p.isOpen,
            onDuty: duty ?? p.onDuty,
            open24h: h24 ?? p.open24h,
          );
      ref.invalidate(pharmacyProfileProvider);
    } on ApiException catch (e) {
      if (mounted) say(context, e.message);
    } finally {
      if (mounted) setState(() => _toggling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = ref.watch(pharmacyProfileProvider).value ?? _p;
    if (p == null) return const Scaffold(body: SizedBox.shrink());
    Widget toggle(
      String title,
      String sub,
      bool value,
      ValueChanged<bool> on,
    ) => MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
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
            PSwitch(value: value, onChanged: _toggling ? null : on),
          ],
        ),
      ),
    );
    return Scaffold(
      backgroundColor: P.page,
      body: SafeArea(
        child: Column(
          children: [
            const PHeader(title: 'Informations'),
            Expanded(
              child: PFormTheme(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(P.gutter, 4, P.gutter, 12),
                  children: [
                    PCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p.name,
                            style: PText.cardTitle.copyWith(fontSize: 18),
                          ),
                          const SizedBox(height: 2),
                          Text(p.addressText, style: PText.bodyMuted),
                          Text(
                            "N° d'autorisation : ${p.licenseNumber}",
                            style: PText.bodyMuted,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            "Nom, adresse et autorisation se changent avec "
                            "l'équipe ivia.",
                            style: PText.small,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: TogoPhoneField(
                        label: 'Téléphone de la pharmacie',
                        controller: _phone,
                        enabled: !_saving,
                        errorText: _errors['phone'],
                      ),
                    ),
                    IviaFieldLabel(
                      label: 'Horaires',
                      child: TextField(
                        controller: _hours,
                        enabled: !_saving,
                        decoration: InputDecoration(
                          errorText: _errors['opening_hours'],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    PButton(
                      label: 'Enregistrer',
                      style: PButtonStyle.outline,
                      height: 48,
                      busy: _saving,
                      onTap: _save,
                    ),
                    const SizedBox(height: 16),
                    PCard(
                      child: Column(
                        children: [
                          toggle(
                            'Ouverte 24 h/24',
                            'Vous recevez les alertes jour et nuit',
                            p.open24h,
                            (v) => _status(p, h24: v),
                          ),
                          const Divider(height: 1, color: P.line),
                          toggle(
                            'De garde maintenant',
                            'Hors planning : la nuit, vous recevez les alertes',
                            p.onDuty,
                            (v) => _status(p, duty: v),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    PCard(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const ConnectedDevicesScreen(),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.devices_outlined, color: P.green),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              'Appareils connectés',
                              style: PText.cardTitle,
                            ),
                          ),
                          const Icon(Icons.chevron_right, color: P.muted),
                        ],
                      ),
                    ),
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
