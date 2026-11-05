import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_ui/ivia_ui.dart';

import 'auth_controller.dart';
import 'button_progress.dart';
import 'form_fields.dart';
import 'phone_format.dart';
import 'providers.dart';

/// « Changer de numéro » : code envoyé au nouveau numéro (WhatsApp ou SMS),
/// puis confirmation ; le nouveau numéro devient l'identifiant de connexion.
class ChangePhoneScreen extends ConsumerStatefulWidget {
  const ChangePhoneScreen({super.key});

  @override
  ConsumerState<ChangePhoneScreen> createState() => _ChangePhoneScreenState();
}

class _ChangePhoneScreenState extends ConsumerState<ChangePhoneScreen> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  String? _sentTo;
  OtpChannel? _channel;
  String? _error;
  var _busy = false;

  @override
  void dispose() {
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _send(OtpChannel channel) async {
    final digits = togoPhoneDigits(_phone.text);
    if (!isTogoMobile(digits)) {
      setState(
        () => _error = 'Numéro mobile togolais attendu : 8 chiffres commençant par 7 ou 9.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final otp = await ref
          .read(apiClientProvider)
          .requestPhoneChange('+228$digits', channel: channel);
      setState(() {
        _sentTo = '+228$digits';
        _channel = otp.channel;
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm() async {
    final code = _code.text.replaceAll(RegExp(r'\D'), '');
    if (code.length != 6 || _sentTo == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final user = await ref
          .read(apiClientProvider)
          .confirmPhoneChange(_sentTo!, code);
      await ref.read(authControllerProvider.notifier).profileUpdated(user);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Numéro changé : +228 ${formatTogoPhone(_sentTo!)}.'),
        ),
      );
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final sent = _sentTo != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Changer de numéro')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(IviaSpacing.screen),
          children: [
            Text(
              'Votre numéro sert à vous connecter. Le nouveau numéro doit recevoir un code pour être confirmé.',
              style: t.bodyLarge?.copyWith(color: IviaColors.textSecondary),
            ),
            const SizedBox(height: IviaSpacing.xl),
            TogoPhoneField(
              label: 'Nouveau numéro',
              controller: _phone,
              enabled: !_busy && !sent,
              errorText: sent ? null : _error,
            ),
            const SizedBox(height: IviaSpacing.lg),
            if (!sent) ...[
              FilledButton(
                onPressed: _busy ? null : () => _send(OtpChannel.whatsapp),
                child: _busy
                    ? const ButtonProgress()
                    : const Text('Recevoir le code sur WhatsApp'),
              ),
              const SizedBox(height: IviaSpacing.sm),
              OutlinedButton(
                onPressed: _busy ? null : () => _send(OtpChannel.sms),
                child: const Text('Recevoir par SMS'),
              ),
            ] else ...[
              Text(
                'Code envoyé ${_channel == OtpChannel.sms ? 'par SMS' : 'sur WhatsApp'} au +228 ${formatTogoPhone(_sentTo!)}.',
                style: t.bodyMedium,
              ),
              const SizedBox(height: IviaSpacing.md),
              IviaCodeInput(
                controller: _code,
                autofocus: true,
                enabled: !_busy,
                hasError: _error != null,
              ),
              if (_error != null) ...[
                const SizedBox(height: IviaSpacing.sm),
                Text(
                  _error!,
                  style: t.bodyMedium?.copyWith(color: IviaColors.error),
                ),
              ],
              const SizedBox(height: IviaSpacing.lg),
              FilledButton(
                onPressed: _busy ? null : _confirm,
                child: _busy
                    ? const ButtonProgress()
                    : const Text('Confirmer le nouveau numéro'),
              ),
              TextButton(
                onPressed: _busy ? null : () => setState(() => _sentTo = null),
                child: const Text('Modifier le numéro'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
