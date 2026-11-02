import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';

import 'account.dart';

/// Quantité maximale d'un produit dans le panier (limite du serveur).
const cartMaxQuantity = 99;

/// Panier vu par l'app : le dernier panier renvoyé par le serveur, et les
/// quantités voulues encore en cours d'envoi.
class CartState {
  const CartState(this.account, this.cart, [this.pending = const {}]);

  /// Compte à qui est ce panier.
  final String? account;
  final Cart cart;

  /// Quantité voulue par produit, pendant son envoi (0 : retrait).
  final Map<String, int> pending;

  /// Quantité affichée : la voulue pendant l'envoi, sinon l'enregistrée.
  int quantityOf(String productId) =>
      pending[productId] ?? cart.quantityOf(productId);

  bool isSending(String productId) => pending.containsKey(productId);
}

/// Panier du compte connecté, gardé sur le serveur : relu à chaque
/// connexion ; chaque modification renvoie le panier complet, qui remplace
/// l'état (prix, stock et sous-total viennent toujours du serveur).
final cartProvider = AsyncNotifierProvider<CartController, CartState>(
  CartController.new,
  // Pas de nouvel essai automatique : l'écran propose « Réessayer ».
  retry: (_, _) => null,
);

/// Panier à afficher : celui du compte connecté seulement. Pendant la
/// relecture qui suit un changement de compte, `cartProvider` garde l'ancien
/// panier comme valeur précédente : il n'est jamais montré.
final cartViewProvider = Provider<AsyncValue<CartState>>((ref) {
  final account = ref.watch(accountIdProvider);
  final cart = ref.watch(cartProvider);
  if (cart.value case final value? when value.account != account) {
    return cart.hasError && !cart.isLoading
        ? AsyncError(cart.error!, cart.stackTrace ?? StackTrace.current)
        : const AsyncLoading();
  }
  return cart;
});

class CartController extends AsyncNotifier<CartState> {
  /// Refus qui signalent un panier affiché périmé (stock, produit retiré).
  static const _stale = {
    'insufficient_stock',
    'product_unavailable',
    'product_not_found',
  };

  IviaApiClient get _client => ref.read(apiClientProvider);

  /// Change à chaque relecture (autre compte) et à chaque vidage : une
  /// réponse d'avant est ignorée (même instance du notifier).
  var _generation = 0;

  /// Quantité voulue par produit ; une seule requête à la fois par produit,
  /// la dernière quantité voulue est envoyée à la fin de la précédente.
  final _wanted = <String, int>{};
  final _replace = <String>{};
  final _sending = <String, Future<void>>{};

  /// Compte du panier en cours de lecture ou lu.
  String? _account;

  @override
  Future<CartState> build() async {
    final account = _account = ref.watch(accountIdProvider);
    _reset();
    if (account == null) return const CartState(null, Cart.empty);
    return CartState(account, await _client.cart());
  }

  void _reset() {
    _generation++;
    _wanted.clear();
    _replace.clear();
    _sending.clear();
  }

  /// Panier connu ; s'il n'a pas pu être chargé, il est relu (lève son
  /// erreur).
  Future<Cart> _current() async {
    if (state.value case final value?
        when value.account == _account && !state.isLoading) {
      return value.cart;
    }
    if (state.hasError && !state.isLoading) ref.invalidateSelf();
    return (await future).cart;
  }

  void _publish(Cart cart) =>
      state = AsyncData(CartState(_account, cart, Map.unmodifiable(_wanted)));

  /// Relit le panier (prix et stock du moment). Pendant un envoi, le
  /// panier renvoyé par cet envoi fera foi : la relecture est ignorée.
  Future<void> refresh() async {
    final generation = _generation;
    final cart = await _client.cart();
    if (!ref.mounted || generation != _generation || _sending.isNotEmpty) {
      return;
    }
    _publish(cart);
  }

  /// Ajoute [count] exemplaires de [productId] : la quantité envoyée est le
  /// total (déjà au panier + [count]). Lève [ApiException] :
  /// `cart_shop_conflict` (autre boutique, à confirmer puis renvoyer avec
  /// [replaceCart]), `insufficient_stock`, `cart_full`…
  Future<void> add(
    String productId,
    int count, {
    bool replaceCart = false,
  }) async {
    final cart = await _current();
    final current =
        state.value?.quantityOf(productId) ?? cart.quantityOf(productId);
    final total = current + count;
    if (total > cartMaxQuantity) {
      throw ApiException(
        code: 'cart_quantity_max',
        message:
            '$cartMaxQuantity exemplaires au plus par produit : vous les avez '
            'déjà dans le panier.',
      );
    }
    await setQuantity(productId, total, replaceCart: replaceCart);
  }

  /// Fixe la quantité de [productId] (0 : retrait). Affichée tout de suite ;
  /// en cas d'échec, la ligne revient à la quantité enregistrée et
  /// l'erreur est levée.
  Future<void> setQuantity(
    String productId,
    int quantity, {
    bool replaceCart = false,
  }) async {
    final cart = await _current();
    _wanted[productId] = quantity;
    if (replaceCart) _replace.add(productId);
    _publish(cart);
    final sending = _sending[productId] ??= _send(productId, _generation);
    await sending;
  }

  Future<void> _send(String productId, int generation) async {
    try {
      while (true) {
        final quantity = _wanted[productId]!;
        final replace = _replace.remove(productId);
        final cart = await _client.setCartItem(
          productId,
          quantity,
          replaceCart: replace,
        );
        if (!ref.mounted || generation != _generation) return;
        if (_wanted[productId] == quantity) {
          _wanted.remove(productId);
          _publish(cart);
          return;
        }
        // Appuis faits pendant l'envoi : la dernière quantité part ensuite.
        _publish(cart);
      }
    } on ApiException catch (e) {
      if (!ref.mounted || generation != _generation) return;
      _wanted.remove(productId);
      _replace.remove(productId);
      _publish(state.value?.cart ?? Cart.empty);
      // Stock ou produit changé : la ligne montre la raison à jour.
      if (_stale.contains(e.code)) {
        unawaited(refresh().catchError((Object _) {}));
      }
      rethrow;
    } finally {
      if (generation == _generation) _sending.remove(productId);
    }
  }

  /// Vide le panier ; les envois en cours sont oubliés.
  Future<void> clear() async {
    await _client.clearCart();
    if (!ref.mounted) return;
    _reset();
    _publish(Cart.empty);
  }
}
