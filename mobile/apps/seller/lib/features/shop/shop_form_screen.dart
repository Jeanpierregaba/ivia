import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../app/seller_shop.dart';
import 'shop_location_field.dart';
import 'shop_logo_field.dart';

/// « Créez votre boutique » : envoyée pour validation par l'équipe ivia.
class ShopFormScreen extends ConsumerStatefulWidget {
  const ShopFormScreen({super.key});

  @override
  ConsumerState<ShopFormScreen> createState() => _ShopFormScreenState();
}

class _ShopFormScreenState extends ConsumerState<ShopFormScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  String? _categoryId;
  String? _neighborhoodId;
  GeoPoint? _location;
  Uint8List? _logo;

  /// Clé du logo déjà envoyé : un nouvel essai ne le renvoie pas (tant que
  /// le logo ne change pas).
  String? _logoKey;
  var _consent = false;
  var _errors = <String, String>{};
  String? _generalError;
  var _busy = false;

  /// Le consentement n'est demandé qu'une fois par compte.
  bool get _needsConsent => _user?.privacyConsentAt == null;

  User? get _user => switch (ref.read(authControllerProvider)) {
    AuthSignedIn(:final user) || AuthNeedsProfile(:final user) => user,
    _ => null,
  };

  @override
  void initState() {
    super.initState();
    // Même compte que l'app acheteur : son numéro préremplit la boutique.
    _phone.text = formatTogoPhone(_user?.phone ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    super.dispose();
  }

  /// Vérifications locales ; le serveur valide à nouveau.
  Map<String, String> _validate() {
    final errors = <String, String>{};
    final name = _name.text.trim();
    final address = _address.text.trim();
    if (name.length < 2 || name.length > 100) {
      errors['name'] = 'Le nom compte de 2 à 100 caractères.';
    }
    if (_categoryId == null) {
      errors['category_id'] = 'Choisissez une catégorie.';
    }
    if (!isTogoMobile(togoPhoneDigits(_phone.text))) {
      errors['phone'] =
          'Numéro mobile togolais attendu (8 chiffres commençant par 7 ou 9).';
    }
    if (address.isEmpty || address.length > 300) {
      errors['address_text'] = "Saisissez l'adresse (300 caractères au plus).";
    }
    if (_neighborhoodId == null) {
      errors['neighborhood_id'] = 'Choisissez le quartier.';
    }
    if (_location == null) {
      errors['location'] = 'Placez votre boutique sur la carte.';
    }
    if (_needsConsent && !_consent) {
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
    final client = ref.read(apiClientProvider);
    try {
      if (_needsConsent) {
        final user = await client.updateMe(acceptPrivacyPolicy: true);
        await ref.read(authControllerProvider.notifier).profileUpdated(user);
      }
      final logoKey = _logoKey ??= await _uploadLogo(client);
      if (_logo != null && logoKey == null) return;
      final shop = await client.createShop(
        ShopDraft(
          name: _name.text.trim(),
          categoryId: _categoryId!,
          phone: '+228${togoPhoneDigits(_phone.text)}',
          addressText: _address.text.trim(),
          neighborhoodId: _neighborhoodId,
          location: _location!,
          logoKey: logoKey,
        ),
      );
      // Profil gardé sur le téléphone avec le rôle seller, obtenu avec la
      // boutique : une relance hors ligne ne repropose pas le formulaire.
      await _rememberSellerRole(client);
      // Boutique en attente : le routeur ouvre l'écran de validation.
      ref.read(sellerShopProvider.notifier).created(shop);
    } on ApiException catch (e) {
      if (!mounted) return;
      final fields = {
        for (final MapEntry(:key, :value) in e.fields.entries)
          key.startsWith('location') ? 'location' : key: value,
      };
      setState(() {
        _errors = fields;
        // Erreur sans champ affiché à l'écran : message général.
        if (!fields.keys.any(_shownFields.contains)) _generalError = e.message;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static const _shownFields = {
    'name',
    'category_id',
    'phone',
    'address_text',
    'neighborhood_id',
    'location',
    'logo_key',
    'accept_privacy_policy',
  };

  Future<void> _rememberSellerRole(IviaApiClient client) async {
    try {
      await ref.read(sessionStoreProvider).saveUser(await client.getMe());
    } on ApiException {
      // Sans réseau : le profil sera relu au prochain démarrage.
    }
  }

  /// Retire l'erreur d'un champ dès qu'il change.
  void _clearError(String field) {
    if (_errors.containsKey(field)) {
      setState(() => _errors = {..._errors}..remove(field));
    }
  }

  /// Envoie le logo sur l'URL signée ; `null` si pas de logo ou en cas
  /// d'échec (message sous le logo).
  Future<String?> _uploadLogo(IviaApiClient client) async {
    final logo = _logo;
    if (logo == null) return null;
    try {
      final prepared = await client.prepareUpload(
        purpose: 'shop_logo',
        contentType: 'image/jpeg',
        sizeBytes: logo.length,
      );
      await client.upload(prepared, logo);
      return prepared.objectKey;
    } on ApiException catch (e) {
      if (mounted) {
        setState(
          () => _errors = {
            'logo_key': e.isNetwork
                ? e.message
                : "Le logo n'a pas pu être envoyé. Réessayez, ou retirez-le.",
          },
        );
      }
      return null;
    }
  }

  /// Retour : la création est abandonnée, la session révoquée.
  Future<void> _back() async {
    if (_busy) return;
    await ref.read(authControllerProvider.notifier).signOut();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final choices = ref.watch(shopChoicesProvider);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        body: SafeArea(
          // Formulaire construit d'un bloc (pas de ListView) : la carte et
          // les champs gardent leur état quand ils sortent de l'écran.
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(IviaSpacing.screen),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    IviaBackButton(onPressed: _busy ? null : _back),
                    const SizedBox(width: IviaSpacing.md),
                    const Spacer(),
                    // Souple : la pastille passe sur deux lignes avec une
                    // police très agrandie.
                    const Flexible(
                      flex: 4,
                      child: IviaPill(label: 'Étape 1 sur 2'),
                    ),
                  ],
                ),
                const SizedBox(height: IviaSpacing.lg),
                Semantics(
                  header: true,
                  child: Text(
                    'Créez votre boutique',
                    style: textTheme.headlineMedium,
                  ),
                ),
                const SizedBox(height: IviaSpacing.xl),
                ...switch (choices) {
                  AsyncData(:final value) => _fields(value.$1, value.$2),
                  AsyncError() => [_ChoicesError(onRetry: _retryChoices)],
                  _ => const [
                    Padding(
                      padding: EdgeInsets.all(IviaSpacing.huge),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  ],
                },
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _retryChoices() => ref.invalidate(shopChoicesProvider);

  List<Widget> _fields(List<Choice> categories, List<Choice> neighborhoods) {
    final textTheme = Theme.of(context).textTheme;
    return [
      ShopLogoField(
        value: _logo,
        enabled: !_busy,
        errorText: _errors['logo_key'],
        onChanged: (logo) => setState(() {
          _logo = logo;
          _logoKey = null;
          _errors = {..._errors}..remove('logo_key');
        }),
      ),
      const SizedBox(height: IviaSpacing.xl),
      IviaFieldLabel(
        label: 'Nom de la boutique',
        child: TextField(
          controller: _name,
          enabled: !_busy,
          onChanged: (_) => _clearError('name'),
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            hintText: 'Chez Afi',
            errorText: _errors['name'],
            errorMaxLines: 2,
          ),
        ),
      ),
      const SizedBox(height: IviaSpacing.lg),
      _Select(
        label: 'Catégorie',
        value: _categoryId,
        choices: categories,
        errorText: _errors['category_id'],
        enabled: !_busy,
        onChanged: (id) {
          setState(() => _categoryId = id);
          _clearError('category_id');
        },
      ),
      const SizedBox(height: IviaSpacing.lg),
      TogoPhoneField(
        label: 'Téléphone de la boutique',
        controller: _phone,
        enabled: !_busy,
        helperText: 'Pour que ivia et les livreurs puissent vous joindre.',
        errorText: _errors['phone'],
      ),
      const SizedBox(height: IviaSpacing.lg),
      IviaFieldLabel(
        label: 'Adresse',
        child: TextField(
          controller: _address,
          enabled: !_busy,
          onChanged: (_) => _clearError('address_text'),
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText: 'Rue 248, près du marché',
            errorText: _errors['address_text'],
            errorMaxLines: 2,
          ),
        ),
      ),
      const SizedBox(height: IviaSpacing.lg),
      _Select(
        label: 'Quartier',
        value: _neighborhoodId,
        choices: neighborhoods,
        errorText: _errors['neighborhood_id'],
        enabled: !_busy,
        onChanged: (id) {
          setState(() => _neighborhoodId = id);
          _clearError('neighborhood_id');
        },
      ),
      const SizedBox(height: IviaSpacing.lg),
      IviaFieldLabel(
        label: 'Position sur la carte',
        child: ShopLocationField(
          value: _location,
          enabled: !_busy,
          errorText: _errors['location'],
          onChanged: (point) => setState(() {
            _location = point;
            _errors = {..._errors}..remove('location');
          }),
        ),
      ),
      if (_needsConsent) ...[
        const SizedBox(height: IviaSpacing.lg),
        ConsentCheckbox(
          value: _consent,
          error: _errors['accept_privacy_policy'],
          onChanged: _busy ? null : (v) => setState(() => _consent = v),
        ),
      ],
      const SizedBox(height: IviaSpacing.xxl),
      if (_generalError != null) ...[
        Semantics(
          liveRegion: true,
          child: Text(
            _generalError!,
            style: textTheme.bodyMedium?.copyWith(color: IviaColors.error),
          ),
        ),
        const SizedBox(height: IviaSpacing.md),
      ],
      FilledButton(
        onPressed: _busy ? null : _submit,
        child: _busy
            ? const ButtonProgress()
            : const Text('Envoyer pour validation'),
      ),
    ];
  }
}

/// Liste de choix au style des champs (DropdownButtonFormField de Material).
class _Select extends StatelessWidget {
  const _Select({
    required this.label,
    required this.value,
    required this.choices,
    required this.onChanged,
    required this.enabled,
    this.errorText,
  });

  final String label;
  final String? value;
  final List<Choice> choices;
  final ValueChanged<String?> onChanged;
  final bool enabled;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return IviaFieldLabel(
      label: label,
      child: DropdownButtonFormField<String>(
        initialValue: value,
        isExpanded: true,
        hint: const Text('Choisir'),
        decoration: InputDecoration(errorText: errorText, errorMaxLines: 2),
        items: [
          for (final choice in choices)
            DropdownMenuItem(value: choice.id, child: Text(choice.name)),
        ],
        onChanged: enabled ? onChanged : null,
      ),
    );
  }
}

class _ChoicesError extends StatelessWidget {
  const _ChoicesError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          'Impossible de charger les catégories et les quartiers. Vérifiez '
          'votre connexion.',
          style: Theme.of(context).textTheme.bodyLarge
              ?.copyWith(color: IviaColors.textSecondary),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: IviaSpacing.lg),
        OutlinedButton(onPressed: onRetry, child: const Text('Réessayer')),
      ],
    );
  }
}
