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
  const CartState(
    this.account,
    this.cart, [
    this.pending = const {},
    this.clearing = false,
  ]);

  /// Compte à qui est ce panier.
  final String? account;
  final Cart cart;

  /// Quantité voulue par produit, pendant son envoi (0 : retrait).
  final Map<String, int> pending;

  /// Vidage en cours : le panier ne se modifie pas.
  final bool clearing;

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

  /// Numéro de la dernière requête partie, et de celle dont le panier est
  /// affiché. Le serveur les traite dans l'ordre d'envoi : une réponse plus
  /// ancienne que le panier affiché (arrivée en retard) n'est pas publiée.
  var _sentSeq = 0;
  var _shownSeq = 0;

  /// Quantité voulue par produit ; une seule requête à la fois par produit,
  /// la dernière quantité voulue est envoyée à la fin de la précédente.
  final _wanted = <String, int>{};
  final _replace = <String>{};
  final _sending = <String, Future<void>>{};

  /// Vidage en cours : les modifications attendent sa fin.
  Future<void>? _clearing;

  /// Compte du panier en cours de lecture ou lu.
  String? _account;

  @override
  Future<CartState> build() async {
    final account = _account = ref.watch(accountIdProvider);
    _reset();
    if (account == null) return const CartState(null, Cart.empty);
    final seq = ++_sentSeq;
    final cart = await _client.cart();
    _shownSeq = seq;
    return CartState(account, cart);
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
    if (_clearing case final clearing?) await clearing;
    if (state.value case final value?
        when value.account == _account && !state.isLoading) {
      return value.cart;
    }
    if (state.hasError && !state.isLoading) ref.invalidateSelf();
    return (await future).cart;
  }

  /// Publie [cart] s'il n'est pas plus ancien que le panier affiché ; sinon
  /// republie l'affiché (les quantités voulues ont pu changer).
  void _publish(Cart cart, {int? seq}) {
    var shown = cart;
    if (seq != null) {
      if (seq < _shownSeq) {
        shown = state.value?.cart ?? cart;
      } else {
        _shownSeq = seq;
      }
    }
    state = AsyncData(
      CartState(_account, shown, Map.unmodifiable(_wanted), _clearing != null),
    );
  }

  /// Relit le panier (prix et stock du moment).
  Future<void> refresh() async {
    final generation = _generation;
    final seq = ++_sentSeq;
    final cart = await _client.cart();
    if (!ref.mounted || generation != _generation) return;
    _publish(cart, seq: seq);
  }

  /// Ajoute [count] exemplaires de [productId] : la quantité envoyée est le
  /// total (déjà au panier + [count]). Lève [ApiException] :
  /// `cart_shop_conflict` (autre boutique, à confirmer puis renvoyer avec
  /// [replaceCart]), `insufficient_stock`, `cart_full`,
  /// `cart_quantity_max`…
  Future<void> add(
    String productId,
    int count, {
    bool replaceCart = false,
  }) async {
    final cart = await _current();
    final current =
        state.value?.quantityOf(productId) ?? cart.quantityOf(productId);
    if (current + count > cartMaxQuantity) {
      throw const ApiException(
        code: 'cart_quantity_max',
        message:
            '$cartMaxQuantity exemplaires au plus par produit : vous les avez '
            'déjà dans le panier.',
      );
    }
    await setQuantity(productId, current + count, replaceCart: replaceCart);
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
        // Vidage ou autre compte depuis le tour précédent : rien ne part.
        if (!ref.mounted || generation != _generation) return;
        final quantity = _wanted[productId]!;
        final replace = _replace.remove(productId);
        final seq = ++_sentSeq;
        final cart = await _client.setCartItem(
          productId,
          quantity,
          replaceCart: replace,
        );
        if (!ref.mounted || generation != _generation) return;
        if (_wanted[productId] == quantity) {
          _wanted.remove(productId);
          _publish(cart, seq: seq);
          return;
        }
        // Appuis faits pendant l'envoi : la dernière quantité part ensuite.
        _publish(cart, seq: seq);
      }
    } catch (e) {
      // Toute erreur, attendue ou non : la ligne revient à la quantité
      // enregistrée, rien ne reste « en cours d'envoi ».
      if (!ref.mounted || generation != _generation) return;
      _wanted.remove(productId);
      _replace.remove(productId);
      _publish(state.value?.cart ?? Cart.empty);
      // Stock ou produit changé : la ligne montre la raison à jour.
      if (e is ApiException && _stale.contains(e.code)) {
        unawaited(refresh().catchError((Object _) {}));
      }
      rethrow;
    } finally {
      if (generation == _generation) _sending.remove(productId);
    }
  }

  /// Vide le panier. Les envois en cours finissent d'abord (sans tour
  /// suivant) pour que le serveur ne recrée pas le panier après le vidage ;
  /// les modifications faites pendant le vidage attendent sa fin.
  Future<void> clear() async {
    if (_clearing case final clearing?) return clearing;
    final done = Completer<void>();
    _clearing = done.future;
    final inFlight = [..._sending.values];
    _reset();
    _publish(state.value?.cart ?? Cart.empty);
    try {
      await Future.wait(inFlight.map((f) => f.catchError((Object _) {})));
      await _client.clearCart();
      if (!ref.mounted) return;
      _sentSeq++;
      _shownSeq = _sentSeq;
      _publish(Cart.empty);
    } catch (e) {
      // Panier du serveur inconnu : relu.
      if (ref.mounted) unawaited(refresh().catchError((Object _) {}));
      rethrow;
    } finally {
      _clearing = null;
      done.complete();
      if (ref.mounted && state.value?.clearing == true) {
        _publish(state.value!.cart);
      }
    }
  }
}
