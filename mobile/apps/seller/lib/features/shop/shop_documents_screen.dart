import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../app/router.dart';
import '../../app/seller_shop.dart';

/// Pièces demandées au marchand, dans l'ordre d'affichage : (type, libellé,
/// mention, précision).
const _documents = [
  (
    MerchantDocumentKind.idCard,
    "Pièce d'identité",
    'Obligatoire',
    "Carte d'identité, passeport ou carte d'électeur, face avec la photo",
  ),
  (
    MerchantDocumentKind.businessRegistration,
    'Registre du commerce (RCCM)',
    'Facultatif',
    null,
  ),
];

/// « Vérifions votre identité » : pièce d'identité (obligatoire) et RCCM,
/// en photo. Ouvert après la création de la boutique et depuis l'écran
/// « en cours de validation ».
class ShopDocumentsScreen extends ConsumerStatefulWidget {
  const ShopDocumentsScreen({super.key});

  @override
  ConsumerState<ShopDocumentsScreen> createState() =>
      _ShopDocumentsScreenState();
}

class _ShopDocumentsScreenState extends ConsumerState<ShopDocumentsScreen> {
  final _photos = <MerchantDocumentKind, Uint8List>{};

  /// Fichiers déjà envoyés au stockage (clé), et pièces déjà rattachées : un
  /// nouvel essai ne les renvoie pas.
  final _uploadedKeys = <MerchantDocumentKind, String>{};
  final _attached = <MerchantDocumentKind>{};

  String? _error;
  var _busy = false;

  Future<void> _submit() async {
    if (_busy) return;
    final sent = ref.read(sellerShopProvider).value?.merchantDocuments ?? [];
    if (!_photos.containsKey(MerchantDocumentKind.idCard) &&
        !sent.contains(MerchantDocumentKind.idCard)) {
      setState(() => _error = "Ajoutez votre pièce d'identité.");
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final client = ref.read(apiClientProvider);
    final shop = ref.read(sellerShopProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    try {
      // 1. Fichiers vers le compartiment privé (une seule fois chacun).
      for (final MapEntry(key: kind, value: photo) in _photos.entries) {
        if (_uploadedKeys.containsKey(kind)) continue;
        final prepared = await client.prepareUpload(
          purpose: 'merchant_document',
          contentType: 'image/jpeg',
          sizeBytes: photo.length,
        );
        await client.upload(prepared, photo);
        _uploadedKeys[kind] = prepared.objectKey;
      }
      // 2. Rattachement des pièces pas encore rattachées.
      for (final MapEntry(key: kind, value: key) in _uploadedKeys.entries) {
        if (_attached.contains(kind)) continue;
        final kinds = await client.addMerchantDocument(kind, key);
        _attached.add(kind);
        shop.documentsSent(kinds);
      }
      if (_photos.isNotEmpty) {
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('Pièces envoyées.')));
      }
      router.go(Routes.shopPending);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on Exception {
      // Réponse inattendue : message général.
      if (mounted) {
        setState(
          () => _error = 'Une erreur est survenue. Réessayez dans un instant.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Retour : écran « en cours de validation », sans rien envoyer.
  void _back() {
    if (_busy) return;
    context.go(Routes.shopPending);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final sent =
        ref.watch(sellerShopProvider).value?.merchantDocuments ?? const [];
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        body: SafeArea(
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
                      child: IviaPill(label: 'Étape 2 sur 2'),
                    ),
                  ],
                ),
                const SizedBox(height: IviaSpacing.lg),
                Semantics(
                  header: true,
                  child: Text(
                    'Vérifions votre identité',
                    style: textTheme.headlineMedium,
                  ),
                ),
                const SizedBox(height: IviaSpacing.md),
                Text(
                  "L'équipe ivia vérifie votre identité avant de publier "
                  'votre boutique. Vos pièces ne sont vues que par '
                  "l'équipe ivia.",
                  style: textTheme.bodyMedium,
                ),
                const SizedBox(height: IviaSpacing.xl),
                for (final (kind, label, tag, hint) in _documents) ...[
                  DocumentPhotoRow(
                    label: label,
                    tag: tag,
                    hint: hint,
                    pickedLabel: 'Ajoutée',
                    sentLabel: 'Envoyée',
                    photo: _photos[kind],
                    alreadySent: sent.contains(kind),
                    enabled: !_busy,
                    onPicked: (photo) => setState(() {
                      _photos[kind] = photo;
                      // Nouvelle photo : elle sera envoyée et rattachée.
                      _uploadedKeys.remove(kind);
                      _attached.remove(kind);
                      if (kind == MerchantDocumentKind.idCard) _error = null;
                    }),
                  ),
                  const SizedBox(height: IviaSpacing.sm),
                ],
                const SizedBox(height: IviaSpacing.xxl),
                if (_error != null) ...[
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _error!,
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
                      : const Text('Envoyer mes pièces'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
