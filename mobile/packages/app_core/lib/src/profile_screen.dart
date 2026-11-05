import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_ui/ivia_ui.dart';

import 'auth_controller.dart';
import 'providers.dart';
import 'button_progress.dart';
import 'form_fields.dart';
import 'phone_format.dart';

/// « Faisons connaissance » : prénom, nom, téléphone et consentement,
/// demandés tant que le profil est incomplet.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _phone = TextEditingController();
  var _consent = false;
  var _isNewAccount = true;

  /// Numéro vérifié par un code (connexion par numéro) : il n'est ni
  /// redemandé ni modifiable ici.
  var _phoneVerified = false;
  var _errors = <String, String>{};
  String? _generalError;
  var _busy = false;

  @override
  void initState() {
    super.initState();
    if (ref.read(authControllerProvider) case AuthNeedsProfile(:final user)) {
      _firstName.text = user.firstName;
      _lastName.text = user.lastName;
      _phone.text = formatTogoPhone(user.phone ?? '');
      _isNewAccount = user.firstName.isEmpty;
      _phoneVerified = user.phoneVerified;
    }
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _phone.dispose();
    super.dispose();
  }

  /// Vérifications locales ; le serveur valide à nouveau.
  Map<String, String> _validate() {
    final errors = <String, String>{};
    final first = _firstName.text.trim();
    final last = _lastName.text.trim();
    if (first.isEmpty) errors['first_name'] = 'Saisissez votre prénom.';
    if (first.length > 100) errors['first_name'] = '100 caractères au plus.';
    if (last.isEmpty) errors['last_name'] = 'Saisissez votre nom.';
    if (last.length > 100) errors['last_name'] = '100 caractères au plus.';
    if (!_phoneVerified && !isTogoMobile(togoPhoneDigits(_phone.text))) {
      errors['phone'] =
          'Numéro mobile togolais attendu (8 chiffres commençant par 7 ou 9).';
    }
    if (!_consent) {
      errors['accept_privacy_policy'] =
          'Cochez la case pour continuer : votre accord est nécessaire.';
    }
    return errors;
  }

  Future<void> _submit() async {
    if (_busy) return;
    final errors = _validate();
    setState(() {
      _errors = errors;
      _generalError = null;
    });
    if (errors.isNotEmpty) return;
    setState(() => _busy = true);
    try {
      final user = await ref
          .read(apiClientProvider)
          .updateMe(
            firstName: _firstName.text.trim(),
            lastName: _lastName.text.trim(),
            phone: _phoneVerified
                ? null
                : '+228${togoPhoneDigits(_phone.text)}',
            acceptPrivacyPolicy: true,
          );
      // Profil complet : le routeur ouvre l'accueil.
      await ref.read(authControllerProvider.notifier).profileUpdated(user);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        if (e.code == 'phone_taken') {
          _errors = {'phone': e.message};
        } else if (e.fields.isNotEmpty) {
          _errors = e.fields;
        } else {
          _generalError = e.message;
        }
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Retour : la connexion est abandonnée, la session révoquée. Bloqué
  /// pendant l'envoi du profil.
  Future<void> _back() async {
    if (_busy) return;
    await ref.read(authControllerProvider.notifier).signOut();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final names = [
      IviaFieldLabel(
        label: 'Prénom',
        child: TextField(
          controller: _firstName,
          enabled: !_busy,
          textCapitalization: TextCapitalization.words,
          autofillHints: const [AutofillHints.givenName],
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            errorText: _errors['first_name'],
            errorMaxLines: 2,
          ),
        ),
      ),
      IviaFieldLabel(
        label: 'Nom',
        child: TextField(
          controller: _lastName,
          enabled: !_busy,
          textCapitalization: TextCapitalization.words,
          autofillHints: const [AutofillHints.familyName],
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            errorText: _errors['last_name'],
            errorMaxLines: 2,
          ),
        ),
      ),
    ];
    // Prénom et nom côte à côte si la place le permet, sinon l'un sous
    // l'autre (petit écran, police agrandie).
    final width = MediaQuery.sizeOf(context).width - 2 * IviaSpacing.screen;
    final sideBySide = width / MediaQuery.textScalerOf(context).scale(1) >= 300;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        body: SafeArea(
          child: CustomScrollView(
            slivers: [
              SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: const EdgeInsets.all(IviaSpacing.screen),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          IviaBackButton(onPressed: _busy ? null : _back),
                          const Spacer(),
                          if (_isNewAccount)
                            const IviaPill(label: 'Dernière étape'),
                        ],
                      ),
                      const SizedBox(height: IviaSpacing.lg),
                      Semantics(
                        header: true,
                        child: Text(
                          'Faisons connaissance',
                          style: textTheme.headlineMedium,
                        ),
                      ),
                      const SizedBox(height: IviaSpacing.sm),
                      Text(
                        'Ces informations servent à préparer vos commandes.',
                        style: textTheme.bodyLarge?.copyWith(
                          color: IviaColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: IviaSpacing.xxl),
                      if (sideBySide)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: names[0]),
                            const SizedBox(width: IviaSpacing.md),
                            Expanded(child: names[1]),
                          ],
                        )
                      else ...[
                        names[0],
                        const SizedBox(height: IviaSpacing.lg),
                        names[1],
                      ],
                      if (!_phoneVerified) ...[
                        const SizedBox(height: IviaSpacing.lg),
                        TogoPhoneField(
                          label: 'Téléphone',
                          controller: _phone,
                          enabled: !_busy,
                          helperText:
                              'Visible par le livreur uniquement pendant une '
                              'livraison.',
                          errorText: _errors['phone'],
                        ),
                      ],
                      const SizedBox(height: IviaSpacing.xl),
                      ConsentCheckbox(
                        value: _consent,
                        error: _errors['accept_privacy_policy'],
                        onChanged: _busy
                            ? null
                            : (v) => setState(() => _consent = v),
                      ),
                      const Spacer(),
                      const SizedBox(height: IviaSpacing.xxl),
                      if (_generalError != null) ...[
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            _generalError!,
                            style: textTheme.bodyMedium?.copyWith(
                              color: IviaColors.error,
                            ),
                          ),
                        ),
                        const SizedBox(height: IviaSpacing.md),
                      ],
                      FilledButton(
                        onPressed: _busy ? null : _submit,
                        child: _busy
                            ? const ButtonProgress()
                            : Text(
                                _isNewAccount
                                    ? 'Créer mon compte'
                                    : 'Continuer',
                              ),
                      ),
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
